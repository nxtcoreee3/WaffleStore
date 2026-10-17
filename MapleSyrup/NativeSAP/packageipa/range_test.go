package packageipa

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestRangeRequiresExact206AndLength(t *testing.T) {
	for _, bad := range []string{"", "status", "range", "truncated"} {
		t.Run(bad, func(t *testing.T) {
			s := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.Header.Get("Cookie") != "" || r.Header.Get("X-Token") != "" {
					t.Error("credentials leaked")
				}
				if bad == "status" {
					w.WriteHeader(200)
					fmt.Fprint(w, "abcd")
					return
				}
				value := "bytes 0-3/10"
				if bad == "range" {
					value = "bytes 1-4/10"
				}
				w.Header().Set("Content-Range", value)
				w.WriteHeader(206)
				if bad == "truncated" {
					fmt.Fprint(w, "ab")
				} else {
					fmt.Fprint(w, "abcd")
				}
			}))
			defer s.Close()
			r := rangeReader{ctx: context.Background(), client: s.Client(), url: s.URL, budget: 1024}
			data, size, e := r.fetch(0, 3)
			if bad == "" {
				if e != nil || string(data) != "abcd" || size != 10 {
					t.Fatalf("valid range rejected: %v", e)
				}
			} else if e == nil {
				t.Fatal("bad range accepted")
			}
		})
	}
}
func TestRemoteRejectsUntrustedURL(t *testing.T) {
	if _, e := InspectRemote("http://apple.com.evil.test/a", "test.app"); e == nil {
		t.Fatal("untrusted URL accepted")
	}
}
