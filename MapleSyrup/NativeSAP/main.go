// Isolated guest ABI bridge derived from majd/ipatool's MIT SAP machine.
// No CLI, login, purchase or Go appstore backend is linked.
package main

/*
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
*/
import "C"
import (
	"context"
	"encoding/json"
	"github.com/majd/ipatool/v2/internal/sap/assets"
	"github.com/majd/ipatool/v2/internal/sap/machine"
	"github.com/majd/ipatool/v2/wafflebridge/packageipa"
	"sync"
	"time"
	"unsafe"
)

type guest struct {
	machine  *machine.Machine
	context  uint64
	hardware []byte
}

var mutex sync.Mutex
var guests = map[uint64]*guest{}
var nextHandle uint64

// Statuses deliberately expose stages, never guest buffers, tokens or URLs.
// 1 arguments; 2 assets; 3 emulator; 4 init; 5 exchange; 6 sign; 7 handle.
//
//export WaffleSAPOpen
func WaffleSAPOpen(cache *C.char, hardware *C.uchar, length C.size_t, handle *C.uint64_t) C.int {
	mutex.Lock()
	defer mutex.Unlock()
	if cache == nil || hardware == nil || length != 6 || handle == nil {
		return 1
	}
	directory := C.GoString(cache)
	if directory == "" {
		return 1
	}
	assets.CacheRoot = directory // Explicit app sandbox path; no home/system fallback.
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	bundle, err := assets.Load(ctx)
	if err != nil {
		return 2
	}
	m, err := machine.Open(ctx, bundle)
	if err != nil {
		return 3
	}
	id := C.GoBytes(unsafe.Pointer(hardware), 6)
	session, err := m.Initialize(id)
	if err != nil {
		m.Close()
		return 4
	}
	nextHandle++
	if nextHandle == 0 {
		m.Teardown(session)
		m.Close()
		return 7
	}
	guests[nextHandle] = &guest{m, session, id}
	*handle = C.uint64_t(nextHandle)
	return 0
}

//export WaffleSAPExchange
func WaffleSAPExchange(handle C.uint64_t, version C.uint32_t, input *C.uchar, length C.size_t,
	output **C.uchar, outputLength *C.size_t, state *C.int32_t) C.int {
	mutex.Lock()
	defer mutex.Unlock()
	g := guests[uint64(handle)]
	if g == nil {
		return 7
	}
	if version != 200 || input == nil || length == 0 || length > 1<<20 || output == nil || outputLength == nil || state == nil {
		return 1
	}
	data, result, err := g.machine.Exchange(uint32(version), g.hardware, g.context, C.GoBytes(unsafe.Pointer(input), C.int(length)))
	if err != nil {
		return 5
	}
	*output = nil
	*outputLength = 0
	*state = C.int32_t(result)
	if len(data) > 0 {
		*output = (*C.uchar)(C.CBytes(data))
		*outputLength = C.size_t(len(data))
	}
	return 0
}

//export WaffleSAPSign
func WaffleSAPSign(handle C.uint64_t, input *C.uchar, length C.size_t, output **C.uchar, outputLength *C.size_t) C.int {
	mutex.Lock()
	defer mutex.Unlock()
	g := guests[uint64(handle)]
	if g == nil {
		return 7
	}
	if input == nil || length == 0 || length > 1<<20 || output == nil || outputLength == nil {
		return 1
	}
	data, err := g.machine.Sign(g.context, C.GoBytes(unsafe.Pointer(input), C.int(length)))
	if err != nil || len(data) == 0 {
		return 6
	}
	*output = (*C.uchar)(C.CBytes(data))
	*outputLength = C.size_t(len(data))
	return 0
}

//export WaffleSAPKBSync
func WaffleSAPKBSync(cache *C.char, hardware *C.uchar, length C.size_t, dsid C.uint64_t, output **C.uchar, outputLength *C.size_t) C.int {
	mutex.Lock()
	defer mutex.Unlock()
	if cache == nil || hardware == nil || length != 6 || dsid == 0 || output == nil || outputLength == nil {
		return 1
	}
	assets.CacheRoot = C.GoString(cache)
	if assets.CacheRoot == "" {
		return 1
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	bundle, err := assets.Load(ctx)
	if err != nil {
		return 2
	}
	data, err := machine.GenerateKBSync(ctx, bundle, C.GoBytes(unsafe.Pointer(hardware), 6), uint64(dsid))
	if err != nil || len(data) == 0 || len(data) > 16<<20 {
		return 8
	}
	*output = (*C.uchar)(C.CBytes(data))
	*outputLength = C.size_t(len(data))
	return 0
}

//export WafflePrepareIPA
func WafflePrepareIPA(source *C.char, destination *C.char, input *C.uchar, length C.size_t, output **C.uchar, outputLength *C.size_t) C.int {
	if source == nil || destination == nil || input == nil || length == 0 || length > 16<<20 || output == nil || outputLength == nil {
		return 1
	}
	var parameters packageipa.Input
	if json.Unmarshal(C.GoBytes(unsafe.Pointer(input), C.int(length)), &parameters) != nil {
		return 20
	}
	data, err := packageipa.Prepare(C.GoString(source), C.GoString(destination), parameters)
	if err != nil {
		return C.int(packageipa.FailureCode(err))
	}
	*output = (*C.uchar)(C.CBytes(data))
	*outputLength = C.size_t(len(data))
	return 0
}

//export WaffleInspectIPA
func WaffleInspectIPA(url *C.char, bundle *C.char, output **C.uchar, outputLength *C.size_t) C.int {
	if url == nil || bundle == nil || output == nil || outputLength == nil {
		return 1
	}
	data, err := packageipa.InspectRemote(C.GoString(url), C.GoString(bundle))
	if err != nil {
		return 22
	}
	*output = (*C.uchar)(C.CBytes(data))
	*outputLength = C.size_t(len(data))
	return 0
}

//export WaffleSAPClose
func WaffleSAPClose(handle C.uint64_t) {
	mutex.Lock()
	defer mutex.Unlock()
	g := guests[uint64(handle)]
	if g == nil {
		return
	}
	delete(guests, uint64(handle))
	g.machine.Teardown(g.context)
	g.machine.Close()
	for i := range g.hardware {
		g.hardware[i] = 0
	}
}

//export WaffleSAPFree
func WaffleSAPFree(pointer *C.uchar, length C.size_t) {
	if pointer != nil {
		C.memset(unsafe.Pointer(pointer), 0, length)
		C.free(unsafe.Pointer(pointer))
	}
}
func main() {}
