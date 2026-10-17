import XCTest
@testable import MapleSAP
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class SAPTests: XCTestCase {
    private func plist(_ value: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
    }
    private func bag(_ overrides: [String: Any] = [:]) throws -> Data {
        var values: [String: Any] = ["authenticateAccount": "https://auth.itunes.apple.com/auth/v1/native/",
            "sign-sap-setup": "https://play.itunes.apple.com/setup",
            "sign-sap-setup-cert": "https://play.itunes.apple.com/cert", "sign-sap-version": "200"]
        values.merge(overrides) { _, new in new }
        return try plist(["urlBag": values])
    }

    func testBagUsesDynamicEndpointsAndRejectsUnknownVersion() throws {
        let configuration = try SAPConfiguration.parse(bag: bag())
        XCTAssertEqual(configuration.version, 200)
        XCTAssertEqual(configuration.setupURL.path, "/setup")
        XCTAssertEqual(try SAPConfiguration.parse(bag: bag(["sign-sap-setup-cert": "https://s.mzstatic.com/sap/setupCert.plist"])).certificateURL.host, "s.mzstatic.com")
        XCTAssertThrowsError(try SAPConfiguration.parse(bag: bag(["sign-sap-version": "201"]))) {
            XCTAssertEqual($0 as? SAPError, .unsupportedVersion)
        }
        XCTAssertThrowsError(try SAPConfiguration.parse(bag: plist(["urlBag": [:]])))
    }

    func testEndpointsCannotLeakSetupToUntrustedHosts() throws {
        for value in ["http://play.itunes.apple.com/setup", "https://apple.com.evil.test/setup",
                      "https://user:secret@play.itunes.apple.com/setup", "https://play.itunes.apple.com:444/setup"] {
            XCTAssertThrowsError(try SAPConfiguration.parse(bag: bag(["sign-sap-setup": value])))
        }
        XCTAssertThrowsError(try SAPConfiguration.parse(bag: bag(["authenticateAccount": "https://apple.com/other"])))
    }

    func testIdentityBytesAndGUIDAreTheSameStableIdentity() throws {
        let identity = try MachineIdentity(hardwareID: Data([2, 1, 2, 3, 4, 255]))
        XCTAssertEqual(identity.guid, "0201020304FF")
        XCTAssertThrowsError(try MachineIdentity(hardwareID: Data()))
    }

    func testAppleDocumentEnvelopeIsParsedWithoutChangingBagFields() throws {
        let original = try bag()
        let xml = String(data: original, encoding: .utf8)!
        let start = xml.range(of: "<plist")!.lowerBound
        let end = xml.range(of: "</plist>")!.upperBound
        let wrapped = Data(("<?xml version=\"1.0\"?><Document><Protocol>" + xml[start..<end] + "</Protocol></Document>").utf8)
        XCTAssertEqual(try SAPConfiguration.parse(bag: wrapped), try SAPConfiguration.parse(bag: original))
        let bareDict = Data("<Document><key>value</key><string>test</string></Document>".utf8)
        XCTAssertThrowsError(try SAPConfiguration.parse(bag: bareDict))
    }

    func testHandshakeSignsExactBodyOnlyAfterSuccessfulSetup() async throws {
        let configuration = try SAPConfiguration.parse(bag: bag())
        let transport = FakeTransport(responses: [try plist(["sign-sap-setup-cert": Data([1])]),
                                                 try plist(["sign-sap-setup-buffer": Data([2])])])
        let guest = FakeGuest()
        let session = try SAPSession(guest: guest, transport: transport)
        do { _ = try await session.actionSignature(body: Data()); XCTFail("Signed before setup") }
        catch { XCTAssertEqual(error as? SAPError, .invalidState) }
        try await session.initialize(configuration: configuration,
                                     identity: MachineIdentity(hardwareID: Data([2, 1, 2, 3, 4, 5])))
        let body = Data("exact serialized authentication bytes".utf8)
        let signature = try await session.actionSignature(body: body)
        // Fixture bytes test transport/state only; NEVER an Apple-valid signature.
        XCTAssertEqual(signature, Data([3, 4]).base64EncodedString())
        XCTAssertEqual(guest.lastBody, body)
        XCTAssertEqual(guest.inputs, [Data([1]), Data([2])])
        let requests = await transport.requests
        XCTAssertEqual(requests[1].httpMethod, "POST")
        let envelope = try PropertyListSerialization.propertyList(from: requests[1].httpBody!, format: nil) as! [String: Data]
        XCTAssertEqual(envelope["sign-sap-setup-buffer"], Data([9]))
        await session.close()
        await session.close()
        XCTAssertEqual(guest.closeCount, 1)
    }

    func testGuestFailureClosesSessionAndNeverSigns() async throws {
        let transport = FakeTransport(responses: [try plist(["wrong-key": Data([1])])])
        let guest = FakeGuest()
        let session = try SAPSession(guest: guest, transport: transport)
        do {
            try await session.initialize(configuration: SAPConfiguration.parse(bag: bag()),
                                         identity: MachineIdentity(hardwareID: Data(repeating: 2, count: 6)))
            XCTFail("Accepted missing certificate")
        } catch { XCTAssertEqual(error as? SAPError, .invalidCertificate) }
        XCTAssertEqual(guest.closeCount, 1)
        do { _ = try await session.actionSignature(body: Data()); XCTFail("Signed after failure") }
        catch { XCTAssertEqual(error as? SAPError, .invalidState) }
    }

    func testRejectsJITAndEmptySignature() async throws {
        let jit = FakeGuest(); jit.executionMode = .dynamicExecutableMemory
        XCTAssertThrowsError(try SAPSession(guest: jit, transport: FakeTransport(responses: []))) {
            XCTAssertEqual($0 as? SAPError, .executableRuntimeRejected)
        }
        let guest = FakeGuest(); guest.signature = Data()
        let session = try SAPSession(guest: guest, transport: FakeTransport(responses: [
            try plist(["sign-sap-setup-cert": Data([1])]), try plist(["sign-sap-setup-buffer": Data([2])])]))
        try await session.initialize(configuration: SAPConfiguration.parse(bag: bag()),
                                     identity: MachineIdentity(hardwareID: Data(repeating: 2, count: 6)))
        do { _ = try await session.actionSignature(body: Data()); XCTFail("Accepted empty signature") }
        catch { XCTAssertEqual(error as? SAPError, .emptySignature) }
        await session.close()
    }

    func testHTTPAndOversizedResponsesAreNotParsedAsSuccess() async throws {
        for status in [204, 403, 404, 429, 500, 503] {
            let apple = SAPProtocol(transport: FakeTransport(responses: [Data()], status: status))
            do { _ = try await apple.bag(identity: MachineIdentity(hardwareID: Data(repeating: 2, count: 6))); XCTFail("Accepted HTTP \(status)") }
            catch { XCTAssertEqual(error as? SAPError, .http(status)) }
        }
        let apple = SAPProtocol(transport: FakeTransport(responses: [Data(repeating: 0, count: SAPProtocol.maximumBodySize + 1)]))
        do { _ = try await apple.bag(identity: MachineIdentity(hardwareID: Data(repeating: 2, count: 6))); XCTFail("Accepted oversized response") }
        catch { XCTAssertEqual(error as? SAPError, .oversizedResponse) }
    }

    func testNativeProbeControlAndReportContainNoAddressesOrSecrets() {
        let capability = MemoryCapability.probe()
        XCTAssertEqual(capability.signedTextControl, 42)
        XCTAssertEqual(capability.rwAllocationErrno, 0)
        XCTAssertTrue(capability.sanitizedReport.contains("unsigned-code-execution=not-attempted"))
    }
}

private actor FakeTransport: SAPTransport {
    var responses: [Data]
    var requests: [URLRequest] = []
    let status: Int
    init(responses: [Data], status: Int = 200) { self.responses = responses; self.status = status }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !responses.isEmpty else { throw SAPError.invalidState }
        return (responses.removeFirst(), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

private final class FakeGuest: AppleSAPGuest {
    var executionMode = SAPExecutionMode.interpreted
    var inputs: [Data] = []
    var lastBody: Data?
    var closeCount = 0
    var signature = Data([3, 4])
    func initialize(hardwareID: Data) throws {}
    func exchange(version: UInt32, hardwareID: Data, input: Data) throws -> (output: Data, state: Int32) {
        inputs.append(input)
        return inputs.count == 1 ? (Data([9]), 1) : (Data(), 0)
    }
    func sign(body: Data) throws -> Data { lastBody = body; return signature }
    func close() { closeCount += 1 }
}
