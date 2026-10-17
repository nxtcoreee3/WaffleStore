package packageipa

import (
	"archive/zip"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

// Isolated unauthenticated range transport. A server that ignores Range must
// not trigger a multi-gigabyte metadata download.
func trustedCDN(u *url.URL) bool {
	h := strings.ToLower(u.Hostname())
	return u.Scheme == "https" && u.User == nil && u.Fragment == "" && (u.Port() == "" || u.Port() == "443") && (strings.HasSuffix(h, ".apple.com") || strings.HasSuffix(h, ".mzstatic.com") || strings.HasSuffix(h, ".cdn-apple.com"))
}

type rangeReader struct {
	ctx    context.Context
	client *http.Client
	url    string
	size   int64
	budget int64
}

func (r *rangeReader) fetch(start, end int64) ([]byte, int64, error) {
	length := end - start + 1
	if start < 0 || length <= 0 || length > 1<<20 || r.budget < length {
		return nil, 0, errors.New("range budget exceeded")
	}
	r.budget -= length
	req, e := http.NewRequestWithContext(r.ctx, "GET", r.url, nil)
	if e != nil {
		return nil, 0, e
	}
	req.Header.Set("Range", fmt.Sprintf("bytes=%d-%d", start, end))
	req.Header.Set("Accept-Encoding", "identity")
	resp, e := r.client.Do(req)
	if e != nil {
		return nil, 0, errors.New("range request failed")
	}
	defer resp.Body.Close()
	if resp.StatusCode != 206 {
		return nil, 0, errors.New("CDN does not support ranges")
	}
	var gotStart, gotEnd, total int64
	if _, e = fmt.Sscanf(resp.Header.Get("Content-Range"), "bytes %d-%d/%d", &gotStart, &gotEnd, &total); e != nil || gotStart != start || gotEnd != end || total <= end || total > 8<<30 || (r.size > 0 && r.size != total) {
		return nil, 0, errors.New("invalid Content-Range")
	}
	if resp.Header.Get("Content-Encoding") != "" && resp.Header.Get("Content-Encoding") != "identity" {
		return nil, 0, errors.New("encoded range")
	}
	if text := resp.Header.Get("Content-Length"); text != "" {
		v, e := strconv.ParseInt(text, 10, 64)
		if e != nil || v != length {
			return nil, 0, errors.New("range size mismatch")
		}
	}
	data, e := io.ReadAll(io.LimitReader(resp.Body, length+1))
	if e != nil || int64(len(data)) != length {
		return nil, 0, errors.New("truncated range")
	}
	return data, total, nil
}
func (r *rangeReader) ReadAt(p []byte, off int64) (int, error) {
	if len(p) == 0 {
		return 0, nil
	}
	if off < 0 || off >= r.size {
		return 0, io.EOF
	}
	length := int64(len(p))
	if off+length > r.size {
		length = r.size - off
	}
	data, _, e := r.fetch(off, off+length-1)
	if e != nil {
		return 0, e
	}
	n := copy(p, data)
	if n < len(p) {
		return n, io.EOF
	}
	return n, nil
}
func InspectRemote(text, bundle string) ([]byte, error) {
	u, e := url.Parse(text)
	if e != nil || !trustedCDN(u) {
		return nil, errors.New("untrusted CDN")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	client := &http.Client{Timeout: 10 * time.Second, CheckRedirect: func(req *http.Request, via []*http.Request) error {
		if len(via) >= 8 || !trustedCDN(req.URL) {
			return errors.New("redirect rejected")
		}
		req.Header.Del("Authorization")
		req.Header.Del("Cookie")
		return nil
	}}
	reader := &rangeReader{ctx: ctx, client: client, url: text, budget: 8 << 20}
	_, size, e := reader.fetch(0, 0)
	if e != nil {
		return nil, e
	}
	reader.size = size
	z, e := zip.NewReader(reader, size)
	if e != nil {
		return nil, e
	}
	info, _, e := inspect(z, bundle)
	if e != nil {
		return nil, e
	}
	return json.Marshal(info)
}
