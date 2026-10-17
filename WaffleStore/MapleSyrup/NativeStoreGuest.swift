import Foundation
import MapleSAP

nonisolated final class NativeKBSyncGenerator: KBSyncGenerator {
    func generate(identity: MachineIdentity, dsid: UInt64) throws -> Data {
        let cache = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true).appendingPathComponent("MapleSAP", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        var output: UnsafeMutablePointer<UInt8>?
        var length = 0
        let status = cache.path.withCString { path in
            identity.hardwareID.withUnsafeBytes { bytes in
                WaffleSAPKBSync(UnsafeMutablePointer(mutating: path),
                    UnsafeMutablePointer(mutating: bytes.bindMemory(to: UInt8.self).baseAddress),
                    identity.hardwareID.count, dsid, &output, &length)
            }
        }
        defer { WaffleSAPFree(output, length) }
        guard status == 0 else { throw StoreError.native(Int32(status)) }
        guard let output = output, length > 0, length <= 16 << 20 else { throw StoreError.native(8) }
        return Data(bytes: output, count: length)
    }
}
nonisolated enum NativePackage {
    struct Parameters: Encodable {
        let appID: String
        let bundleID: String
        let externalVersionID: String
        let md5: String
        let metadata: Data
        let sinfs: [Data]
    }
    struct Info: Codable, Sendable { let bundleID: String; let version: String; let build: String? }
    static func inspect(url: URL, bundle: String) throws -> Info {
        var output: UnsafeMutablePointer<UInt8>?
        var length = 0
        let status = url.absoluteString.withCString { url in
            bundle.withCString { bundle in
                WaffleInspectIPA(UnsafeMutablePointer(mutating: url), UnsafeMutablePointer(mutating: bundle), &output, &length)
            }
        }
        defer { WaffleSAPFree(output, length) }
        guard status == 0 else { throw StoreError.native(Int32(status)) }
        guard let output = output, length > 0, length < 4096 else { throw StoreError.packageInvalid }
        return try JSONDecoder().decode(Info.self, from: Data(bytes: output, count: length))
    }
    static func prepare(source: URL, destination: URL, app: StoreApp, descriptor: StoreDownload) throws -> Info {
        let input = try JSONEncoder().encode(Parameters(appID: app.id, bundleID: app.bundleID,
            externalVersionID: descriptor.externalVersionID, md5: descriptor.md5,
            metadata: descriptor.metadata, sinfs: descriptor.sinfs))
        var output: UnsafeMutablePointer<UInt8>?
        var length = 0
        let status = source.path.withCString { source in
            destination.path.withCString { destination in
                input.withUnsafeBytes { bytes in
                    WafflePrepareIPA(UnsafeMutablePointer(mutating: source), UnsafeMutablePointer(mutating: destination),
                        UnsafeMutablePointer(mutating: bytes.bindMemory(to: UInt8.self).baseAddress), input.count, &output, &length)
                }
            }
        }
        defer { WaffleSAPFree(output, length) }
        guard status == 0 else { throw StoreError.native(Int32(status)) }
        guard let output = output, length > 0, length < 4096 else { throw StoreError.packageInvalid }
        return try JSONDecoder().decode(Info.self, from: Data(bytes: output, count: length))
    }
}
