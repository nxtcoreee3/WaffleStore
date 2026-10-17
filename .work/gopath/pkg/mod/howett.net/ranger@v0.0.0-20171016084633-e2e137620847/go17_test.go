// +build go1.7

package ranger

import "testing"

func subtest(t *testing.T, name string, f func(t *testing.T)) {
	t.Run(name, f)
}
