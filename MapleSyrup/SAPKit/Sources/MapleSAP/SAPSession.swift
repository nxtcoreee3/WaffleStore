// SAP v200 envelope and state flow adapted from majd/ipatool (MIT).
// See THIRD_PARTY_NOTICES.md and docs/IPATOOL_AUDIT.md for the pinned source.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol SAPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

// A future interpreter or AOT runtime must implement the SAME guest ABI.
// Guest RX permission describes emulated memory; it must never become host RX.
public enum SAPExecutionMode { case interpreted, aheadOfTime, dynamicExecutableMemory }
public protocol AppleSAPGuest: AnyObject {
    var executionMode: SAPExecutionMode { get }
    func initialize(hardwareID: Data) throws
    func exchange(version: UInt32, hardwareID: Data, input: Data) throws -> (output: Data, state: Int32)
    func sign(body: Data) throws -> Data
    func close()
}

public final class AppleSAPTransport: NSObject, SAPTransport, URLSessionTaskDelegate {
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        // Download to a temporary file so an oversized response is not loaded into RAM.
        let (file, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: file) }
        guard let http = response as? HTTPURLResponse else { throw SAPError.invalidBag }
        guard http.statusCode == 200 else { throw SAPError.http(http.statusCode) }
        let length = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard length <= SAPProtocol.maximumBodySize else { throw SAPError.oversizedResponse }
        return (try Data(contentsOf: file), http)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask,
                           willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest,
                           completionHandler: @escaping (URLRequest?) -> Void) {
        // Bag/certificate/setup redirects are not silently followed. Authentication
        // needs a separate, bounded redirect policy preserving the signed body.
        completionHandler(nil)
    }

    public func close() { session.invalidateAndCancel() }
}

public struct SAPProtocol {
    public static let maximumBodySize = 1 << 20
    public static let userAgent = "Configurator/2.17 (Macintosh; OS X 15.2; 24C5089c) AppleWebKit/0620.1.16.11.6"
    private let transport: SAPTransport
    public init(transport: SAPTransport) { self.transport = transport }

    public func bag(identity: MachineIdentity) async throws -> SAPConfiguration {
        // The Bag discovery URL is the sole bootstrap URL. All SAP/auth URLs
        // come from the returned Bag; there is no unsigned auth fallback.
        let url = URL(string: "https://init.itunes.apple.com/bag.xml?guid=\(identity.guid)")!
        var request = URLRequest(url: url)
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        let body = try await send(request)
        return try SAPConfiguration.parse(bag: body)
    }

    public func certificate(configuration: SAPConfiguration) async throws -> Data {
        let body = try await send(URLRequest(url: configuration.certificateURL))
        return try plistData(body, key: "sign-sap-setup-cert", error: .invalidCertificate)
    }

    public func exchange(configuration: SAPConfiguration, input: Data) async throws -> Data {
        guard !input.isEmpty, input.count <= Self.maximumBodySize else { throw SAPError.invalidExchange }
        var request = URLRequest(url: configuration.setupURL)
        request.httpMethod = "POST"
        request.setValue("application/x-plist", forHTTPHeaderField: "Content-Type")
        request.httpBody = try PropertyListSerialization.data(fromPropertyList: ["sign-sap-setup-buffer": input], format: .xml, options: 0)
        let body = try await send(request)
        return try plistData(body, key: "sign-sap-setup-buffer", error: .invalidExchange)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        var request = request
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await transport.send(request)
        guard response.statusCode == 200 else { throw SAPError.http(response.statusCode) }
        guard data.count <= Self.maximumBodySize else { throw SAPError.oversizedResponse }
        return data
    }

    private func plistData(_ data: Data, key: String, error: SAPError) throws -> Data {
        guard let plist = try ApplePlist.dictionary(data),
              let value = plist[key] as? Data, !value.isEmpty else { throw error }
        return value
    }
}

public actor SAPSession {
    private enum State { case idle, initializing, ready, closed }
    private var state = State.idle
    private let guest: AppleSAPGuest
    private let apple: SAPProtocol
    public init(guest: AppleSAPGuest, transport: SAPTransport) throws {
        guard guest.executionMode != .dynamicExecutableMemory else { throw SAPError.executableRuntimeRejected }
        self.guest = guest
        self.apple = SAPProtocol(transport: transport)
    }

    public func initialize(configuration: SAPConfiguration, identity: MachineIdentity) async throws {
        guard state == .idle else { throw SAPError.invalidState }
        state = .initializing
        do {
            try guest.initialize(hardwareID: identity.hardwareID)
            let certificate = try await apple.certificate(configuration: configuration)
            guard state == .initializing else { throw SAPError.invalidState }
            let first = try guest.exchange(version: configuration.version, hardwareID: identity.hardwareID, input: certificate)
            guard first.state == 1, !first.output.isEmpty else { throw SAPError.invalidExchange }
            let reply = try await apple.exchange(configuration: configuration, input: first.output)
            guard state == .initializing else { throw SAPError.invalidState }
            let final = try guest.exchange(version: configuration.version, hardwareID: identity.hardwareID, input: reply)
            guard final.state == 0 else { throw SAPError.invalidExchange }
            state = .ready
        } catch {
            if state != .closed { guest.close() }
            state = .closed
            throw error
        }
    }

    public func actionSignature(body: Data) throws -> String {
        guard state == .ready else { throw SAPError.invalidState }
        let signature = try guest.sign(body: body)
        guard !signature.isEmpty else { throw SAPError.emptySignature }
        return signature.base64EncodedString()
    }

    public func close() {
        if state != .closed { guest.close() }
        state = .closed
    }
}
