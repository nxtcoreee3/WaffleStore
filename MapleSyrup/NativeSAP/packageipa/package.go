// Streaming iOS package preparation, adapted from ipatool (MIT).
// No extraction, decryption, signing or installation.
package packageipa

import (
	"archive/zip"
	"crypto/md5"
	"encoding/hex"
	"encoding/json"
	"errors"
	"howett.net/plist"
	"io"
	"os"
	"path"
	"strings"
)

type Input struct {
	AppID             string   `json:"appID"`
	BundleID          string   `json:"bundleID"`
	ExternalVersionID string   `json:"externalVersionID"`
	MD5               string   `json:"md5"`
	Metadata          []byte   `json:"metadata"`
	Sinfs             [][]byte `json:"sinfs"`
}
type Info struct {
	Build      string   `json:"build,omitempty" plist:"CFBundleVersion"`
	BundleID   string   `json:"bundleID" plist:"CFBundleIdentifier"`
	Version    string   `json:"version" plist:"CFBundleShortVersionString"`
	Executable string   `json:"-" plist:"CFBundleExecutable"`
	Platforms  []string `json:"-" plist:"CFBundleSupportedPlatforms"`
}

func safeName(name string) bool {
	return name != "" && !strings.Contains(name, "\\") && !strings.HasPrefix(name, "/") && path.Clean(strings.TrimSuffix(name, "/")) == strings.TrimSuffix(name, "/") && name != ".." && !strings.HasPrefix(name, "../")
}
func readSmall(f *zip.File) ([]byte, error) {
	if f.UncompressedSize64 > 1<<20 {
		return nil, errors.New("oversized plist")
	}
	r, e := f.Open()
	if e != nil {
		return nil, e
	}
	defer r.Close()
	b, e := io.ReadAll(io.LimitReader(r, (1<<20)+1))
	if len(b) > 1<<20 {
		return nil, errors.New("oversized plist")
	}
	return b, e
}
func inspect(z *zip.Reader, bundle string) (Info, string, error) {
	var info Info
	var root string
	seen := map[string]bool{}
	if len(z.File) > 200000 {
		return info, root, errors.New("too many entries")
	}
	for _, f := range z.File {
		if !safeName(f.Name) || seen[f.Name] {
			return info, root, errors.New("invalid or duplicate ZIP path")
		}
		seen[f.Name] = true
		parts := strings.Split(f.Name, "/")
		if len(parts) == 3 && parts[0] == "Payload" && strings.HasSuffix(parts[1], ".app") && parts[2] == "Info.plist" {
			if root != "" {
				return info, root, errors.New("multiple apps")
			}
			b, e := readSmall(f)
			if e != nil {
				return info, root, e
			}
			if _, e = plist.Unmarshal(b, &info); e != nil {
				return info, root, e
			}
			root = "Payload/" + parts[1] + "/"
		}
	}
	if root == "" || info.BundleID != bundle || info.Version == "" || info.Executable == "" {
		return info, root, errors.New("package identity mismatch")
	}
	ios := false
	for _, p := range info.Platforms {
		if p == "iPhoneOS" {
			ios = true
		}
	}
	if !ios {
		return info, root, errors.New("not an iOS device package")
	}
	return info, root, nil
}
func Prepare(source, destination string, input Input) (result []byte, err error) {
	if source == destination || input.AppID == "" || input.ExternalVersionID == "" {
		return nil, errors.New("invalid arguments")
	}
	file, e := os.Open(source)
	if e != nil {
		return nil, e
	}
	defer file.Close()
	stat, e := file.Stat()
	if e != nil {
		return nil, e
	}
	if stat.Size() > 8<<30 {
		return nil, errors.New("package too large")
	}
	if input.MD5 != "" {
		h := md5.New()
		if _, e = io.Copy(h, file); e != nil {
			return nil, e
		}
		if !strings.EqualFold(hex.EncodeToString(h.Sum(nil)), input.MD5) {
			return nil, errors.New("checksum mismatch")
		}
	}
	z, e := zip.NewReader(file, stat.Size())
	if e != nil {
		return nil, e
	}
	info, root, e := inspect(z, input.BundleID)
	if e != nil {
		return nil, e
	}
	var metadata map[string]interface{}
	if _, e = plist.Unmarshal(input.Metadata, &metadata); e != nil {
		return nil, e
	}
	number := func(v interface{}) string {
		switch v := v.(type) {
		case string:
			return v
		default:
			b, _ := json.Marshal(v)
			return string(b)
		}
	}
	if number(metadata["itemId"]) != input.AppID || number(metadata["softwareVersionExternalIdentifier"]) != input.ExternalVersionID || metadata["softwareVersionBundleId"] != input.BundleID {
		return nil, errors.New("metadata mismatch")
	}
	replacements := map[string][]byte{"iTunesMetadata.plist": input.Metadata}
	if len(input.Sinfs) > 0 {
		var manifest struct {
			SinfPaths []string `plist:"SinfPaths"`
		}
		found := false
		for _, f := range z.File {
			if f.Name == root+"SC_Info/Manifest.plist" {
				b, e := readSmall(f)
				if e != nil {
					return nil, e
				}
				if _, e = plist.Unmarshal(b, &manifest); e != nil {
					return nil, e
				}
				found = true
			}
		}
		if !found {
			manifest.SinfPaths = []string{"SC_Info/" + info.Executable + ".sinf"}
		}
		if len(manifest.SinfPaths) != len(input.Sinfs) {
			return nil, errors.New("SINF count mismatch")
		}
		for i, p := range manifest.SinfPaths {
			if !safeName(p) || !strings.HasPrefix(p, "SC_Info/") || len(input.Sinfs[i]) == 0 || len(input.Sinfs[i]) > 1<<20 {
				return nil, errors.New("invalid SINF")
			}
			if _, ok := replacements[root+p]; ok {
				return nil, errors.New("duplicate SINF")
			}
			replacements[root+p] = input.Sinfs[i]
		}
	}
	var total uint64
	for _, f := range z.File {
		if f.UncompressedSize64 > 32<<30-total {
			return nil, errors.New("expanded package too large")
		}
		total += f.UncompressedSize64
		r, e := f.Open()
		if e != nil {
			return nil, e
		}
		_, e = io.Copy(io.Discard, r)
		ce := r.Close()
		if e != nil {
			return nil, e
		}
		if ce != nil {
			return nil, ce
		}
	}
	headers, e := newZIPLocalHeaders(file, stat.Size())
	if e != nil {
		return nil, e
	}
	out, e := os.OpenFile(destination, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if e != nil {
		return nil, e
	}
	defer func() {
		if err != nil {
			out.Close()
			os.Remove(destination)
		}
	}()
	writer := zip.NewWriter(out)
	for _, f := range z.File {
		extra, e := headers.extra(f)
		if e != nil {
			return nil, e
		}
		if _, replace := replacements[f.Name]; replace {
			continue
		}
		header := f.FileHeader
		header.Extra = zipStoredExtra(&header, extra)
		if header.Method == zip.Store || f.FileInfo().IsDir() {
			header.Flags &^= 0x8
		} else {
			header.Flags |= 0x8
		}
		target, e := writer.CreateRaw(&header)
		if e != nil {
			return nil, e
		}
		header.Extra = zipExtraWithoutZIP64(f.Extra)
		raw, e := f.OpenRaw()
		if e != nil {
			return nil, e
		}
		if _, e = io.Copy(target, raw); e != nil {
			return nil, e
		}
	}
	for name, data := range replacements {
		w, e := writer.Create(name)
		if e != nil {
			return nil, e
		}
		if _, e = w.Write(data); e != nil {
			return nil, e
		}
	}
	if e = writer.Close(); e != nil {
		return nil, e
	}
	if e = out.Sync(); e != nil {
		return nil, e
	}
	if e = out.Close(); e != nil {
		return nil, e
	}
	return json.Marshal(info)
}

// Fixed diagnostic codes for the C ABI; never expose raw error strings.
func FailureCode(err error) int {
	if err == nil {
		return 0
	}
	switch err.Error() {
	case "checksum mismatch":
		return 32
	case "package identity mismatch", "not an iOS device package", "multiple apps":
		return 33
	case "metadata mismatch":
		return 34
	case "SINF count mismatch", "invalid SINF", "duplicate SINF":
		return 35
	case "invalid or duplicate ZIP path", "too many entries", "expanded package too large", "package too large", "oversized plist":
		return 31
	}
	if errors.Is(err, zip.ErrChecksum) {
		return 36
	}
	if errors.Is(err, zip.ErrFormat) {
		return 31
	}
	var fileError *os.PathError
	if errors.As(err, &fileError) {
		return 37
	}
	return 21
}
