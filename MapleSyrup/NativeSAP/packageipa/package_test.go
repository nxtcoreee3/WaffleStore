package packageipa

import (
	"archive/zip"
	"bytes"
	"crypto/md5"
	"encoding/hex"
	"howett.net/plist"
	"io"
	"os"
	"path/filepath"
	"testing"
)

func fixture(t *testing.T, dir string, malformed bool) (string, Input) {
	t.Helper()
	source := filepath.Join(dir, "source.ipa")
	f, e := os.Create(source)
	if e != nil {
		t.Fatal(e)
	}
	z := zip.NewWriter(f)
	info, _ := plist.Marshal(Info{Build: "12345", BundleID: "test.app", Version: "1.2.3", Executable: "Test", Platforms: []string{"iPhoneOS"}}, plist.BinaryFormat)
	entries := map[string][]byte{"Payload/Test.app/Info.plist": info, "Payload/Test.app/Test": bytes.Repeat([]byte{42}, 4096), "Payload/Test.app/SC_Info/Test.sinf": []byte("old")}
	if malformed {
		entries["../bad"] = []byte("bad")
	}
	for name, b := range entries {
		w, e := z.Create(name)
		if e != nil {
			t.Fatal(e)
		}
		if _, e = w.Write(b); e != nil {
			t.Fatal(e)
		}
	}
	if e = z.Close(); e != nil {
		t.Fatal(e)
	}
	f.Close()
	metadata, _ := plist.Marshal(map[string]interface{}{"itemId": uint64(123), "softwareVersionExternalIdentifier": uint64(999), "softwareVersionBundleId": "test.app"}, plist.XMLFormat)
	return source, Input{AppID: "123", BundleID: "test.app", ExternalVersionID: "999", Metadata: metadata, Sinfs: [][]byte{[]byte("new-license")}}
}
func TestPreparePreservesPayloadAndReplacesLicense(t *testing.T) {
	dir := t.TempDir()
	source, input := fixture(t, dir, false)
	dest := filepath.Join(dir, "out.ipa")
	result, e := Prepare(source, dest, input)
	if e != nil {
		t.Fatal(e)
	}
	if !bytes.Contains(result, []byte("1.2.3")) || !bytes.Contains(result, []byte("12345")) {
		t.Fatal("version not verified")
	}
	z, e := zip.OpenReader(dest)
	if e != nil {
		t.Fatal(e)
	}
	defer z.Close()
	counts := map[string]int{}
	for _, f := range z.File {
		counts[f.Name]++
		r, e := f.Open()
		if e != nil {
			t.Fatal(e)
		}
		b, e := io.ReadAll(r)
		r.Close()
		if e != nil {
			t.Fatal(e)
		}
		if f.Name == "Payload/Test.app/SC_Info/Test.sinf" && !bytes.Equal(b, []byte("new-license")) {
			t.Fatal("license not replaced")
		}
	}
	for _, n := range counts {
		if n != 1 {
			t.Fatal("duplicate entry")
		}
	}
}
func TestRejectWrongIdentityAndUnsafePaths(t *testing.T) {
	for _, kind := range []string{"bundle", "path", "version", "checksum"} {
		t.Run(kind, func(t *testing.T) {
			dir := t.TempDir()
			source, input := fixture(t, dir, kind == "path")
			switch kind {
			case "bundle":
				input.BundleID = "wrong"
			case "version":
				input.ExternalVersionID = "1"
			case "checksum":
				input.MD5 = hex.EncodeToString(md5.New().Sum(nil))
			}
			dest := filepath.Join(dir, "out.ipa")
			if _, e := Prepare(source, dest, input); e == nil {
				t.Fatal("invalid package accepted")
			}
			if _, e := os.Stat(dest); !os.IsNotExist(e) {
				t.Fatal("invalid output retained")
			}
		})
	}
}
func TestNoSinfsIsSupported(t *testing.T) {
	dir := t.TempDir()
	source, input := fixture(t, dir, false)
	input.Sinfs = nil
	if _, e := Prepare(source, filepath.Join(dir, "out.ipa"), input); e != nil {
		t.Fatal(e)
	}
}
