import MemoryProbe

public struct MemoryCapability {
    public let signedTextControl: Int32
    public let rwAllocationErrno: Int32
    public let rwToRXErrno: Int32
    public let rwxAllocationErrno: Int32
    public static func probe() -> MemoryCapability {
        let result = waffle_probe_memory()
        return MemoryCapability(signedTextControl: result.signed_text_result,
            rwAllocationErrno: result.rw_allocation_errno, rwToRXErrno: result.rw_to_rx_errno,
            rwxAllocationErrno: result.rwx_allocation_errno)
    }
    public var sanitizedReport: String {
        "signed-text-control=\(signedTextControl)\nrw-allocation-errno=\(rwAllocationErrno)\nrw-to-rx-errno=\(rwToRXErrno)\nrwx-allocation-errno=\(rwxAllocationErrno)\nunsigned-code-execution=not-attempted"
    }
}
