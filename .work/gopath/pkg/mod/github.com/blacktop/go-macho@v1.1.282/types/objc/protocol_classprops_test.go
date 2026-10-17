package objc

import (
	"strings"
	"testing"
)

func TestProtocolDump_ClassProperties(t *testing.T) {
	p := &Protocol{
		Name: "P",
		ClassProperties: []Property{
			// required class property
			{
				PropertyT:         PropertyT{},
				Name:              "classProp",
				EncodedAttributes: "T@,N", // id, nonatomic
			},
			// optional class property
			{
				PropertyT:         PropertyT{},
				Name:              "optProp",
				EncodedAttributes: "Tq,N,?", // long long, nonatomic, optional
			},
		},
	}

	out := p.Verbose()

	// Required class property should appear under @required and be marked as class
	reqIdx := strings.Index(out, "@required")
	if reqIdx < 0 {
		t.Fatalf("expected @required section in protocol dump:\n%s", out)
	}
	wantReq := "@property (class, nonatomic) id classProp;"
	if !strings.Contains(out[reqIdx:], wantReq) {
		t.Fatalf("expected required class property in @required section:\nwant: %q\nhave:\n%s", wantReq, out[reqIdx:])
	}

	// Optional class property should appear under @optional and be marked as class
	optIdx := strings.Index(out, "@optional")
	if optIdx < 0 {
		t.Fatalf("expected @optional section in protocol dump:\n%s", out)
	}
	wantOpt := "@property (class, nonatomic) long long optProp;"
	if !strings.Contains(out[optIdx:], wantOpt) {
		t.Fatalf("expected optional class property in @optional section:\nwant: %q\nhave:\n%s", wantOpt, out[optIdx:])
	}
}
