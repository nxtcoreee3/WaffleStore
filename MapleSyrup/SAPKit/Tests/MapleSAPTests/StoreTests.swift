import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MapleSAP

final class StoreTests: XCTestCase {
    func testStorefrontUsesAccountCountry() throws {
        XCTAssertEqual(try Storefront.country("143505-1,29"), "ar")
        XCTAssertEqual(try Storefront.country("143441-1,29"), "us")
        XCTAssertThrowsError(try Storefront.country("unknown"))
    }
    func testIdentifiersRejectBooleansAndFractions() {
        XCTAssertNil(StoreParsing.identifier(true))
        XCTAssertNil(StoreParsing.identifier(1.5))
        XCTAssertNil(StoreParsing.identifier("123&evil=1"))
        XCTAssertEqual(StoreParsing.identifier(NSNumber(value: UInt64.max)), String(UInt64.max))
    }
    func testResponseMustMatchSelectedExternalVersion() throws {
        let app = StoreApp(id: "123", bundleID: "test.app", name: "Test", price: 0)
        let root: [String: Any] = ["songList": [["URL": "https://iosapps.itunes.apple.com/test.ipa?token=withheld",
            "metadata": ["itemId": 123, "softwareVersionExternalIdentifier": "999", "softwareVersionBundleId": "test.app",
                         "softwareVersionExternalIdentifiers": ["999", 888]], "sinfs": []]]]
        let download = try StoreParsing.download(root, app: app, version: "999", email: "test@example.invalid")
        XCTAssertEqual(download.availableVersionIDs, ["999", "888"])
        XCTAssertThrowsError(try StoreParsing.download(root, app: app, version: "888", email: "test@example.invalid"))
    }
    func testCDNRejectsInsecureAndLookalikeHosts() throws {
        for url in ["http://iosapps.itunes.apple.com/a", "https://apple.com.evil.test/a", "https://user@iosapps.itunes.apple.com/a"] {
            XCTAssertThrowsError(try CDNPolicy.validate(url))
        }
        XCTAssertNoThrow(try CDNPolicy.validate("https://iosapps.itunes.apple.com/a"))
    }
    func testLicenseAndSessionErrorsRemainSpecific() {
        XCTAssertThrowsError(try StoreParsing.failure(["failureType": "9610"])) { XCTAssertEqual($0 as? StoreError, .licenseRequired) }
        XCTAssertThrowsError(try StoreParsing.failure(["failureType": "2034"])) { XCTAssertEqual($0 as? StoreError, .sessionExpired) }
    }
}

private actor StoreFixtureTransport: AuthenticationTransport {
    struct Reply { let status: Int; let data: Data }
    var replies: [Reply]
    var requests: [URLRequest] = []
    init(_ replies: [Reply]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw StoreError.invalidResponse }
        let reply = replies.removeFirst()
        return (reply.data, HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: nil)!)
    }
    func cookies() async -> [StoreCookie] { [] }
}
private final class StoreFixtureGenerator: KBSyncGenerator {
    var calls = 0
    func generate(identity: MachineIdentity, dsid: UInt64) throws -> Data { calls += 1; return Data("fresh-fixture-blob".utf8) }
}
private final class StoreFixtureCache: KBSyncPersistence {
    var data: Data?; var clears = 0; var saves = 0
    init(_ data: Data? = nil) { self.data = data }
    func load(dsid: String, guid: String) throws -> Data? { data }
    func save(_ data: Data, dsid: String, guid: String) throws { self.data = data; saves += 1 }
    func clear() throws { data = nil; clears += 1 }
}
extension StoreTests {
    private func plist(_ root: [String: Any]) throws -> Data { try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0) }
    private var app: StoreApp { StoreApp(id: "123", bundleID: "test.app", name: "Test", price: nil) }
    private func reply(version: String = "999") throws -> Data {
        try plist(["songList": [["URL": "https://iosapps.itunes.apple.com/a.ipa", "metadata": ["itemId": "123", "softwareVersionExternalIdentifier": version,
            "softwareVersionBundleId": "test.app", "softwareVersionExternalIdentifiers": ["999", "888"]]]]])
    }
    private func bag() throws -> Data { try plist(["urlBag": ["volumeStoreDownloadProduct": "https://downloaddispatch.itunes.apple.com/WebObjects/DownloadDispatch.woa/wa/ent/download",
        "redownloadProduct": "https://downloaddispatch.itunes.apple.com/r/redownload", "updateProduct": "https://downloaddispatch.itunes.apple.com/up/updateProduct",
        "buyProduct": "https://buy.itunes.apple.com/WebObjects/MZBuy.woa/wa/buyProduct"]]) }
    private func session(_ transport: StoreFixtureTransport, cache: StoreFixtureCache = StoreFixtureCache(), generator: StoreFixtureGenerator = StoreFixtureGenerator(), diagnostic: @escaping (String) async -> Void = { _ in }) throws -> StoreSession {
        let identity = try MachineIdentity(hardwareID: Data([2, 1, 2, 3, 4, 5]))
        let account = StoreAccount(email: "fixture@example.invalid", name: "Test", dsid: "12345", passwordToken: "fixture-token", storefront: "143505-1,29", pod: "42", guid: identity.guid,
            authenticationURL: URL(string: "https://p42-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate")!)
        return try StoreSession(account: account, identity: identity, transport: transport, generator: generator, persistence: cache, diagnostic: diagnostic)
    }
    func testEntUsesSameIdentityAndCachesOnlyAcceptedBlob() async throws {
        let cache = StoreFixtureCache(); let generator = StoreFixtureGenerator()
        let transport = StoreFixtureTransport([.init(status: 200, data: try bag()), .init(status: 200, data: try reply())])
        _ = try await session(transport, cache: cache, generator: generator).descriptor(app: app, externalVersionID: "999")
        let requests = await transport.requests
        let request = requests[1]
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Token"), "fixture-token")
        let body = try PropertyListSerialization.propertyList(from: request.httpBody!, format: nil) as! [String: Any]
        XCTAssertEqual(body["externalVersionId"] as? String, "999")
        XCTAssertEqual(body["guid"] as? String, "020102030405")
        // Independent fixture from ipatool hardwareID[2:], four GUID bytes.
        XCTAssertEqual(Data(base64Encoded: body["serialNumber"] as! String), Data([0x54, 0xc8, 0xb0, 0xa9, 0x88, 2, 3, 4, 5]))
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Configurator/2.18 (Macintosh; OS X 15.3.2; 24D81) AppleWebKit/0620.2.4.11.6")
        XCTAssertEqual(body["kbsync"] as? String, Data("fresh-fixture-blob".utf8).base64EncodedString())
        XCTAssertEqual(cache.saves, 1); XCTAssertEqual(generator.calls, 1)
    }
    func testRejectedCachedKBSyncRegeneratesOnce() async throws {
        let cache = StoreFixtureCache(Data("stale".utf8)); let generator = StoreFixtureGenerator()
        let transport = StoreFixtureTransport([.init(status: 200, data: try bag()), .init(status: 403, data: Data()), .init(status: 200, data: try reply())])
        _ = try await session(transport, cache: cache, generator: generator).descriptor(app: app, externalVersionID: "999")
        XCTAssertEqual(cache.clears, 1); XCTAssertEqual(cache.saves, 1); XCTAssertEqual(generator.calls, 1)
    }
    func testPinnedRedownloadEmpty500UsesBagUpdateAndRetainsID() async throws {
        let empty = try plist([:])
        let transport = StoreFixtureTransport([.init(status: 200, data: try bag()), .init(status: 200, data: empty), .init(status: 200, data: empty),
            .init(status: 500, data: Data()), .init(status: 200, data: try reply(version: "888"))])
        _ = try await session(transport).descriptor(app: app, externalVersionID: "888")
        let requests = await transport.requests
        XCTAssertEqual(requests.last?.url?.path, "/up/updateProduct")
        let root = try PropertyListSerialization.propertyList(from: requests.last!.httpBody!, format: nil) as! [String: Any]
        XCTAssertEqual(root["appExtVrsId"] as? String, "888")
        XCTAssertNil(requests.last?.value(forHTTPHeaderField: "X-Token"))
    }
    func testMissingFreeLicenseUsesFinancePurchaseWithoutQueryAndKeepsOldID() async throws {
        let transport = StoreFixtureTransport([.init(status: 200, data: try bag()),
            .init(status: 200, data: try plist(["failureType": "9610"])),
            .init(status: 200, data: try plist(["jingleDocType": "purchaseSuccess", "status": 0])),
            .init(status: 200, data: try reply(version: "888"))])
        let free = StoreApp(id: app.id, bundleID: app.bundleID, name: app.name, price: 0)
        let result = try await session(transport).descriptor(app: free, externalVersionID: "888")
        XCTAssertEqual(result.externalVersionID, "888")
        let requests = await transport.requests
        XCTAssertEqual(requests[1].url?.path, "/WebObjects/DownloadDispatch.woa/wa/ent/download")
        XCTAssertEqual(requests[2].url?.path, "/WebObjects/MZFinance.woa/wa/buyProduct")
        XCTAssertEqual(requests[2].url?.host, "p42-buy.itunes.apple.com")
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "User-Agent"), SAPProtocol.userAgent)
        XCTAssertNil(requests[2].url?.query)
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "X-Token"), "fixture-token")
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "X-Apple-Store-Front"), "143505-1,29")
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Content-Type"), "application/x-apple-plist")
        let root = try PropertyListSerialization.propertyList(from: requests[2].httpBody!, format: nil) as! [String: Any]
        XCTAssertEqual(root["price"] as? String, "0")
        XCTAssertEqual(root["pricingParameters"] as? String, "STDQ")
        XCTAssertEqual(root["appExtVrsId"] as? String, "0")
        XCTAssertEqual(root["guid"] as? String, "020102030405")
        for request in [requests[1], requests[3]] {
            let download = try PropertyListSerialization.propertyList(from: request.httpBody!, format: nil) as! [String: Any]
            XCTAssertEqual(download["externalVersionId"] as? String, "888")
        }
    }
    func testAlreadyOwnedFreeAppDoesNotAcquireAtAll() async throws {
        let transport = StoreFixtureTransport([.init(status: 200, data: try bag()),
            .init(status: 200, data: try reply()), .init(status: 200, data: try reply(version: "888"))])
        let store = try session(transport)
        let free = StoreApp(id: app.id, bundleID: app.bundleID, name: app.name, price: 0)
        _ = try await store.descriptor(app: free, externalVersionID: "999")
        _ = try await store.descriptor(app: free, externalVersionID: "888")
        let requests = await transport.requests
        XCTAssertFalse(requests.contains { $0.url?.path.hasSuffix("buyProduct") == true })
        XCTAssertEqual(requests.count, 3)
    }
    func testPurchaseAlreadyOwnedReplyStillRequiresValidDownload() async throws {
        let transport = StoreFixtureTransport([.init(status: 200, data: try bag()),
            .init(status: 200, data: try plist(["failureType": "9610"])),
            .init(status: 200, data: try plist(["failureType": "5002"])),
            .init(status: 200, data: try reply(version: "888"))])
        let free = StoreApp(id: app.id, bundleID: app.bundleID, name: app.name, price: 0)
        let result = try await session(transport).descriptor(app: free, externalVersionID: "888")
        XCTAssertEqual(result.externalVersionID, "888")
        let requests = await transport.requests; XCTAssertEqual(requests.count, 4)
    }
    func testEntLicenseErrorIsNotLostInFallbackAndHonorsOptOut() async throws {
        let transport = StoreFixtureTransport([.init(status: 200, data: try bag()),
            .init(status: 200, data: try plist(["failureType": "9610"]))])
        do {
            _ = try await session(transport).descriptor(app: app, externalVersionID: "888", acquireFreeLicense: false)
            XCTFail("missing license accepted")
        } catch { XCTAssertEqual(error as? StoreError, .licenseRequired) }
        let requests = await transport.requests; XCTAssertEqual(requests.count, 2)
    }
    func testPurchaseFailureIsNotReplayedAndNextOperationChecksAccessFirst() async throws {
        let transport = StoreFixtureTransport([.init(status: 200, data: try bag()),
            .init(status: 200, data: try plist(["failureType": "9610"])),
            .init(status: 200, data: try plist(["failureType": "2058", "customerMessage": "Requires App Store interaction"])),
            .init(status: 200, data: try reply())])
        let store = try session(transport)
        let free = StoreApp(id: app.id, bundleID: app.bundleID, name: app.name, price: 0)
        do { _ = try await store.descriptor(app: free, externalVersionID: "999"); XCTFail("unconfirmed license") }
        catch { XCTAssertEqual(error as? StoreError, .apple("2058", "Requires App Store interaction")) }
        var requests = await transport.requests; XCTAssertEqual(requests.count, 3)
        _ = try await store.descriptor(app: free, externalVersionID: "999")
        requests = await transport.requests
        XCTAssertEqual(requests[3].url?.path, "/WebObjects/DownloadDispatch.woa/wa/ent/download")
        XCTAssertEqual(requests.filter { $0.url?.path.hasSuffix("buyProduct") == true }.count, 1)
    }
    func testMissingLicenseAfterPurchaseIsNotPurchasedInLoop() async throws {
        let transport = StoreFixtureTransport([.init(status: 200, data: try bag()),
            .init(status: 200, data: try plist(["failureType": "9610"])),
            .init(status: 200, data: try plist(["jingleDocType": "purchaseSuccess", "status": 0])),
            .init(status: 200, data: try plist(["failureType": "9610"]))])
        let free = StoreApp(id: app.id, bundleID: app.bundleID, name: app.name, price: 0)
        do { _ = try await session(transport).descriptor(app: free, externalVersionID: "888"); XCTFail("license rejection") }
        catch { XCTAssertEqual(error as? StoreError, .licenseRequired) }
        let requests = await transport.requests; XCTAssertEqual(requests.count, 4)
    }
    func testAmbiguousPurchase500VerifiesAccessInsteadOfAssumingOwnership() async throws {
        let transport = StoreFixtureTransport([.init(status: 200, data: try bag()),
            .init(status: 200, data: try plist(["failureType": "9610"])),
            .init(status: 500, data: Data()), .init(status: 200, data: try reply(version: "888"))])
        let free = StoreApp(id: app.id, bundleID: app.bundleID, name: app.name, price: 0)
        let result = try await session(transport).descriptor(app: free, externalVersionID: "888")
        XCTAssertEqual(result.externalVersionID, "888")
        let requests = await transport.requests
        XCTAssertEqual(requests.filter { $0.url?.path.hasSuffix("buyProduct") == true }.count, 1)
        XCTAssertEqual(requests.count, 4)
    }
    func testAmbiguousPurchase500CannotFabricateLicenseOrReplayPurchase() async throws {
        let transport = StoreFixtureTransport([.init(status: 200, data: try bag()),
            .init(status: 200, data: try plist(["failureType": "9610"])),
            .init(status: 500, data: Data()), .init(status: 200, data: try plist(["failureType": "9610"]))])
        let free = StoreApp(id: app.id, bundleID: app.bundleID, name: app.name, price: 0)
        do { _ = try await session(transport).descriptor(app: free, externalVersionID: "888"); XCTFail("unverified access") }
        catch { XCTAssertEqual(error as? StoreError, .http(500)) }
        let requests = await transport.requests; XCTAssertEqual(requests.count, 4)
    }
    func testUnavailableFreeAppGetsOneLicenseAttemptThenSelectedVersion() async throws {
        let empty = try plist([:])
        let transport = StoreFixtureTransport([.init(status: 200, data: try bag()),
            .init(status: 200, data: empty), .init(status: 200, data: empty),
            .init(status: 200, data: empty), .init(status: 200, data: empty),
            .init(status: 200, data: try plist(["jingleDocType": "purchaseSuccess", "status": 0])),
            .init(status: 200, data: try reply(version: "888"))])
        let free = StoreApp(id: app.id, bundleID: app.bundleID, name: app.name, price: 0)
        let result = try await session(transport).descriptor(app: free, externalVersionID: "888")
        XCTAssertEqual(result.externalVersionID, "888")
        let requests = await transport.requests
        XCTAssertEqual(requests.filter { $0.url?.path.hasSuffix("buyProduct") == true }.count, 1)
        XCTAssertEqual(requests.count, 7)
    }
    func testCachedKBSyncLicenseDenialDoesNotRegenerateOrClear() async throws {
        let cache = StoreFixtureCache(Data("accepted-account-fixture".utf8))
        let generator = StoreFixtureGenerator()
        let transport = StoreFixtureTransport([.init(status: 200, data: try bag()),
            .init(status: 200, data: try plist(["failureType": "9610"]))])
        do {
            _ = try await session(transport, cache: cache, generator: generator).descriptor(app: app, externalVersionID: "888", acquireFreeLicense: false)
            XCTFail("license denial accepted")
        } catch { XCTAssertEqual(error as? StoreError, .licenseRequired) }
        XCTAssertEqual(cache.clears, 0); XCTAssertEqual(generator.calls, 0)
        let requests = await transport.requests; XCTAssertEqual(requests.count, 2)
    }
    func testOwnedPaidAppCanDownloadWithoutAcquisition() async throws {
        let transport = StoreFixtureTransport([.init(status: 200, data: try bag()), .init(status: 200, data: try reply(version: "888"))])
        let paid = StoreApp(id: app.id, bundleID: app.bundleID, name: app.name, price: 2)
        let result = try await session(transport).descriptor(app: paid, externalVersionID: "888")
        XCTAssertEqual(result.externalVersionID, "888")
        let requests = await transport.requests; XCTAssertEqual(requests.count, 2)
    }
    func testPaidAppCannotBePurchasedAutomatically() async throws {
        let transport = StoreFixtureTransport([.init(status: 200, data: try bag()), .init(status: 200, data: try plist(["failureType": "9610"]))])
        do { _ = try await session(transport).descriptor(app: StoreApp(id: "123", bundleID: "test.app", name: "Paid", price: 2), externalVersionID: "999"); XCTFail("paid acquisition") }
        catch { XCTAssertEqual(error as? StoreError, .paidPurchase) }
        let requests = await transport.requests; XCTAssertEqual(requests.count, 2)
    }
}
extension StoreTests {
    func testRetryAfterRejectsOverBudgetAndHonorsHTTPDate() throws {
        XCTAssertEqual(try StoreRetry.delay("7", attempt: 0), 7)
        XCTAssertThrowsError(try StoreRetry.delay("31", attempt: 0))
        let date = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(try StoreRetry.delay("Thu, 01 Jan 1970 00:00:10 GMT", attempt: 0, now: date), 10)
        XCTAssertEqual(try StoreRetry.delay(nil, attempt: 1), 10)
    }
}
#if canImport(Security)
extension StoreTests {
    func testAcceptedKBSyncKeychainIsBoundToAccountAndIdentity() throws {
        let cache = KeychainKBSync(service: "com.wafflestore.tests.kbsync." + UUID().uuidString)
        defer { try? cache.clear() }
        XCTAssertNil(try cache.load(dsid: "1", guid: "020000000001"))
        try cache.save(Data("fixture".utf8), dsid: "1", guid: "020000000001")
        XCTAssertEqual(try cache.load(dsid: "1", guid: "020000000001"), Data("fixture".utf8))
        XCTAssertNil(try cache.load(dsid: "2", guid: "020000000001"))
        XCTAssertNil(try cache.load(dsid: "1", guid: "020000000002"))
        try cache.save(Data("updated".utf8), dsid: "1", guid: "020000000001")
        XCTAssertEqual(try cache.load(dsid: "1", guid: "020000000001"), Data("updated".utf8))
        try cache.clear(); try cache.clear()
        XCTAssertNil(try cache.load(dsid: "1", guid: "020000000001"))
    }
}
#endif

private actor StoreDiagnosticEvents {
    var values: [String] = []
    func record(_ value: String) { values.append(value) }
}
extension StoreTests {
    func testEnt401FallsBackWithoutDeclaringSessionExpired() async throws {
        let events = StoreDiagnosticEvents(); let cache = StoreFixtureCache()
        let transport = StoreFixtureTransport([.init(status: 200, data: try bag()),
            .init(status: 401, data: Data()), .init(status: 200, data: try reply())])
        let descriptor = try await session(transport, cache: cache, diagnostic: { await events.record($0) })
            .descriptor(app: app, externalVersionID: "999")
        XCTAssertEqual(descriptor.externalVersionID, "999")
        let requests = await transport.requests
        XCTAssertEqual(requests.last?.url?.host, "p42-buy.itunes.apple.com")
        XCTAssertEqual(cache.saves, 0)
        let diagnostics = await events.values
        XCTAssertTrue(diagnostics.contains { $0.contains("scope=ent") && $0.contains("HTTP=401") })
        XCTAssertTrue(diagnostics.contains { $0.contains("recovery=ent-to-pod") })
    }
    func testPreferredAppleTokenRejectionCanStillUsePodSession() async throws {
        let transport = StoreFixtureTransport([.init(status: 200, data: try bag()),
            .init(status: 401, data: try plist(["failureType": "2034", "customerMessage": "token rejected"])),
            .init(status: 200, data: try reply())])
        let result = try await session(transport).descriptor(app: app, externalVersionID: "999")
        XCTAssertEqual(result.externalVersionID, "999")
    }
    func testPodStructuredTokenRejectionRemainsSpecific() async throws {
        let transport = StoreFixtureTransport([.init(status: 200, data: try bag()),
            .init(status: 401, data: Data()), .init(status: 401, data: try plist(["failureType": "2034"]))])
        do { _ = try await session(transport).descriptor(app: app, externalVersionID: "999"); XCTFail("expired pod accepted") }
        catch { XCTAssertEqual(error as? StoreError, .sessionExpired) }
    }
    func testBarePod401DoesNotProveExpiredToken() async throws {
        let transport = StoreFixtureTransport([.init(status: 200, data: try bag()),
            .init(status: 401, data: Data()), .init(status: 401, data: Data())])
        do { _ = try await session(transport).descriptor(app: app, externalVersionID: "999"); XCTFail("empty unauthorized reply accepted") }
        catch { XCTAssertEqual(error as? StoreError, .http(401)) }
    }
    func testDiagnosticsNeverIncludeResponseSecretsMessagesOrURLs() throws {
        let body = try plist(["failureType": "2034", "customerMessage": "fixture-token https://secret.invalid/?token=private", "passwordToken": "fixture-token"])
        let diagnostic = ResponseDiagnostic.response(body, status: 401, scope: "ent", attempt: 1, secrets: ["fixture-token"])
        XCTAssertTrue(diagnostic.contains("apple-failure=2034"))
        XCTAssertFalse(diagnostic.contains("fixture-token")); XCTAssertFalse(diagnostic.contains("https://"))
        XCTAssertFalse(diagnostic.contains("private"))
        XCTAssertEqual(ResponseDiagnostic.category(StoreError.sessionExpired), "Apple-sign-in-required")
    }
}

extension StoreTests {
    func testForeignCatalogResolutionReachesDownloadWithoutChangingAccountAuthentication() async throws {
        let lookup = try JSONSerialization.data(withJSONObject: ["results": [["trackId": 123, "bundleId": "test.app", "trackName": "Test", "price": 0]]])
        let version = try JSONSerialization.data(withJSONObject: ["results": ["123": ["bundleId": "test.app", "offers": [["version": ["externalId": "888"]]]]]])
        let transport = StoreFixtureTransport([.init(status: 200, data: lookup), .init(status: 200, data: try bag()),
            .init(status: 200, data: version), .init(status: 200, data: try reply(version: "888"))])
        let store = try session(transport)
        let app = try await store.lookup("123", country: "US")
        XCTAssertEqual(app.catalogCountry, "us")
        let result = try await store.descriptor(app: app)
        XCTAssertEqual(result.externalVersionID, "888")
        let requests = await transport.requests
        XCTAssertEqual(URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "country" }?.value, "us")
        XCTAssertEqual(URLComponents(url: requests[2].url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "cc" }?.value, "us")
        XCTAssertEqual(requests[3].value(forHTTPHeaderField: "X-Apple-Store-Front"), "143505-1,29")
        XCTAssertEqual(requests[3].value(forHTTPHeaderField: "X-Token"), "fixture-token")
        XCTAssertFalse(requests.contains { $0.url?.path.hasSuffix("buyProduct") == true })
    }
    func testForeignCatalogFreeLicenseStillUsesAccountStorefrontAndSelectedVersion() async throws {
        let transport = StoreFixtureTransport([.init(status: 200, data: try bag()), .init(status: 200, data: try plist(["failureType": "9610"])),
            .init(status: 200, data: try plist(["jingleDocType": "purchaseSuccess", "status": 0])), .init(status: 200, data: try reply(version: "888"))])
        let app = StoreApp(id: "123", bundleID: "test.app", name: "Test", price: 0, catalogCountry: "us")
        let result = try await session(transport).descriptor(app: app, externalVersionID: "888")
        XCTAssertEqual(result.externalVersionID, "888")
        let requests = await transport.requests
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "X-Apple-Store-Front"), "143505-1,29")
        XCTAssertEqual(requests[2].url?.host, "p42-buy.itunes.apple.com")
        XCTAssertEqual(requests.filter { $0.url?.path.hasSuffix("buyProduct") == true }.count, 1)
    }
    func testInvalidCatalogCountryRejectedBeforeNetwork() async throws {
        let transport = StoreFixtureTransport([])
        do { _ = try await session(transport).lookup("123", country: "us&evil=1"); XCTFail("Invalid country accepted") }
        catch { XCTAssertEqual(error as? StoreError, .unsupportedStorefront) }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }
}

extension StoreTests {
    func testPurchase2059UsesOneGAMEAlternateAndKeepsRegionalAppAndOldVersion() async throws {
        let transport = StoreFixtureTransport([.init(status: 200, data: try bag()),
            .init(status: 200, data: try plist(["failureType": "9610"])),
            .init(status: 200, data: try plist(["failureType": "2059", "customerMessage": "Purchase could not be completed."])),
            .init(status: 200, data: try plist(["jingleDocType": "purchaseSuccess", "status": 0])),
            .init(status: 200, data: try reply(version: "888"))])
        let regional = StoreApp(id: "123", bundleID: "test.app", name: "Test", price: 0, catalogCountry: "us")
        let result = try await session(transport).descriptor(app: regional, externalVersionID: "888")
        XCTAssertEqual(result.externalVersionID, "888")
        let requests = await transport.requests
        let purchases = requests.filter { $0.url?.path.hasSuffix("buyProduct") == true }
        XCTAssertEqual(purchases.count, 2)
        var pricing: [String] = []
        for request in purchases {
            let body = try PropertyListSerialization.propertyList(from: request.httpBody!, format: nil) as! [String: Any]
            pricing.append(body["pricingParameters"] as! String)
            XCTAssertEqual(body["price"] as? String, "0")
            XCTAssertEqual(StoreParsing.identifier(body["salableAdamId"]), "123")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Apple-Store-Front"), "143505-1,29")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Token"), "fixture-token")
        }
        for request in purchases {
            let body = try PropertyListSerialization.propertyList(from: request.httpBody!, format: nil) as! [String: Any]
            XCTAssertEqual(body["salableAdamId"] as? String, "123")
            XCTAssertEqual(Set(body.keys), Set(["appExtVrsId", "hasAskedToFulfillPreorder", "buyWithoutAuthorization", "hasDoneAgeCheck", "guid", "price", "pricingParameters", "productType", "salableAdamId"]))
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Configurator/2.20 (Macintosh; OS X 26.5.1; 25F80) AppleWebKit/1624.2.5.11.4")
        }
        XCTAssertEqual(pricing, ["STDQ", "GAME"])
    }
    func testRepeated2059StopsAfterTwoPricingRequestsAndPreservesAppleMessage() async throws {
        let denial = try plist(["failureType": "2059", "customerMessage": "Purchase could not be completed."])
        let transport = StoreFixtureTransport([.init(status: 200, data: try bag()), .init(status: 200, data: try plist(["failureType": "9610"])),
            .init(status: 200, data: denial), .init(status: 200, data: denial)])
        let free = StoreApp(id: "123", bundleID: "test.app", name: "Test", price: 0)
        do { _ = try await session(transport).descriptor(app: free, externalVersionID: "888"); XCTFail("Rejected acquisition accepted") }
        catch { XCTAssertEqual(error as? StoreError, .apple("2059", "Purchase could not be completed.")) }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(requests.filter { $0.url?.path.hasSuffix("buyProduct") == true }.count, 2)
    }
    func testGAMEAlternateDoesNotIgnoreSubscriptionRejection() async throws {
        let transport = StoreFixtureTransport([.init(status: 200, data: try bag()), .init(status: 200, data: try plist(["failureType": "9610"])),
            .init(status: 200, data: try plist(["failureType": "2059"])),
            .init(status: 200, data: try plist(["customerMessage": "Subscription required"]))])
        let free = StoreApp(id: "123", bundleID: "test.app", name: "Test", price: 0)
        do { _ = try await session(transport).descriptor(app: free, externalVersionID: "888"); XCTFail("Subscription denial accepted") }
        catch { XCTAssertEqual(error as? StoreError, .apple("", "Subscription required")) }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 4)
    }
}
