package ranger

import (
	"crypto/md5"
	"fmt"
	"io"
	"testing"
)

type TestCase interface {
	Name() string
	RunTest(*testing.T, *Reader)
}

type ReadAtTestCase struct {
	Offset int64
	Size   int
	MD5    string
}

func (tc *ReadAtTestCase) Name() string {
	return fmt.Sprintf("%d_at_%d", tc.Size, tc.Offset)
}

func (tc *ReadAtTestCase) RunTest(t *testing.T, hpr *Reader) {
	bytes := make([]byte, tc.Size)
	nbytes, err := hpr.ReadAt(bytes, tc.Offset)
	if err != nil && err != io.EOF {
		t.Error(err)
		return
	}
	t.Logf("Read %d bytes from off %d.", nbytes, tc.Offset)
	s := md5Sum(bytes)
	if s != tc.MD5 {
		t.Errorf("Mismatch: Expected %s, got %s", tc.MD5, s)
	}
}

type SeekTestCase struct {
	Offset int64
	Whence int
	Size   int
	MD5    string
}

func (tc *SeekTestCase) Name() string {
	return fmt.Sprintf("%d_at_%d_whence_%d", tc.Size, tc.Offset, tc.Whence)
}

func (tc *SeekTestCase) RunTest(t *testing.T, hpr *Reader) {
	bytes := make([]byte, tc.Size)
	o, _ := hpr.Seek(tc.Offset, tc.Whence)
	nbytes, err := hpr.Read(bytes)
	if err != nil && err != io.EOF {
		t.Error(err)
		return
	}
	t.Logf("Read %d bytes from off %d.", nbytes, o)
	s := md5Sum(bytes)
	if s != tc.MD5 {
		t.Errorf("Mismatch: Expected %s, got %s", tc.MD5, s)
	}
}

type SequentialTestCase struct {
	Size int
	MD5  string
}

func (tc *SequentialTestCase) Name() string {
	return fmt.Sprintf("%d", tc.Size)
}

func (tc *SequentialTestCase) RunTest(t *testing.T, hpr *Reader) {
	bytes := make([]byte, tc.Size)
	nbytes, err := hpr.Read(bytes)
	if err != nil && err != io.EOF {
		t.Error(err)
		return
	}
	t.Logf("Read %d bytes.", nbytes)
	s := md5Sum(bytes)
	if s != tc.MD5 {
		t.Errorf("Mismatch: Expected %s, got %s", tc.MD5, s)
	}
}

// md5Sum returns the md5 of a slice in lowercase hex
func md5Sum(b []byte) string {
	sum := md5.Sum(b)
	return fmt.Sprintf("%02x", sum)
}
