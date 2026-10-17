package ranger

import (
	"errors"
	"testing"
)

type fetcherFailsToGetBlocks struct{}

func (b *fetcherFailsToGetBlocks) FetchRanges([]ByteRange) ([]Block, error) {
	return []Block{}, nil
}

func (b *fetcherFailsToGetBlocks) ExpectedLength() (int64, error) {
	return 1024, nil
}

type fetcherFailsToInitialize struct{}

func (b *fetcherFailsToInitialize) FetchRanges([]ByteRange) ([]Block, error) {
	panic(errors.New("should never hit this"))
}

func (b *fetcherFailsToInitialize) ExpectedLength() (int64, error) {
	return 1024, errors.New("failed to fetch info about thing")
}

func TestReaderWithBadRangers(t *testing.T) {
	subtest(t, "FailsToGetBlocks", func(t *testing.T) {
		r, err := NewReader(&fetcherFailsToGetBlocks{})
		if err != nil {
			t.Fatal(err)
		}

		b := make([]byte, 100)
		n, err := r.ReadAt(b, 100)
		if err == nil {
			t.Fatalf("read %d bytes", n)
		} else {
			t.Log(err)
		}
	})

	subtest(t, "FailsToInitialize", func(t *testing.T) {
		_, err := NewReader(&fetcherFailsToInitialize{})
		if err == nil {
			t.Fail()
		} else {
			t.Log(err)
		}
	})

	subtest(t, "FailsToInitializeLate", func(t *testing.T) {
		r := &Reader{Fetcher: &fetcherFailsToInitialize{}}
		_, err := r.ReadAt(nil, 10)
		if err == nil {
			t.Fail()
		} else {
			t.Log(err)
		}
	})

	subtest(t, "FailsToInitializeLate", func(t *testing.T) {
		r := &Reader{Fetcher: &fetcherFailsToInitialize{}}
		_, err := r.Read(nil)
		if err == nil {
			t.Fail()
		} else {
			t.Log(err)
		}
	})

	subtest(t, "FailsToInitializeLate", func(t *testing.T) {
		r := &Reader{Fetcher: &fetcherFailsToInitialize{}}
		_, err := r.Length()
		if err == nil {
			t.Fail()
		} else {
			t.Log(err)
		}
	})

	subtest(t, "FailsToInitializeLate", func(t *testing.T) {
		r := &Reader{Fetcher: &fetcherFailsToInitialize{}}
		_, err := r.Seek(0, 0)
		if err == nil {
			t.Fail()
		} else {
			t.Log(err)
		}
	})

}
