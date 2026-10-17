import XCTest
@testable import MapleSAP
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Tests the real URLSession transport with local URLProtocol responses, not Apple.
final class AuthenticationTransportTests: XCTestCase {
    func testChallengeCookiesSurviveIsolatedRequestSessions() async throws {
        let cookie = HTTPCookie(properties: [.name: "initial", .value: "fixture-initial", .domain: ".itunes.apple.com", .path: "/", .secure: "TRUE"])!
        let transport = AppleAuthenticationTransport(cookies: [StoreCookie(cookie)], isolatedConnections: true,
            protocolClasses: [ChallengeProtocol.self])
        defer { transport.close() }
        let request = URLRequest(url: URL(string: "https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate")!)
        let (_, initialResponse) = try await transport.send(request)
        XCTAssertEqual(initialResponse.statusCode, 200)
        let verification = URLRequest(url: URL(string: "https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate?verify=1")!)
        let (_, verificationResponse) = try await transport.send(verification)
        XCTAssertEqual(verificationResponse.statusCode, 200)
        let cookies = await transport.cookies()
        XCTAssertTrue(cookies.contains { $0.name == "initial" && $0.value == "fixture-initial" })
        XCTAssertTrue(cookies.contains { $0.name == "challenge" && $0.value == "fixture-challenge" })
    }
    func testClosedTransportCannotStartAnotherLoginRequest() async throws {
        let transport = AppleAuthenticationTransport(isolatedConnections: true)
        transport.close()
        do { _ = try await transport.send(URLRequest(url: URL(string: "https://buy.itunes.apple.com/")!)); XCTFail("request started after close") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    func testRestoredCookiesRespectDestinationDomainPathAndSecure() async throws {
        let cookie = HTTPCookie(properties: [.name: "scoped", .value: "fixture-scoped", .domain: "p42-buy.itunes.apple.com", .path: "/WebObjects/", .secure: "TRUE"])!
        let parent = HTTPCookie(properties: [.name: "parent", .value: "fixture-parent", .domain: ".apple.com", .path: "/", .secure: "TRUE"])!
        let transport = AppleAuthenticationTransport(cookies: [StoreCookie(cookie), StoreCookie(parent)])
        defer { transport.close() }
        let snapshot = await transport.cookies()
        XCTAssertEqual(snapshot.count, 2)
        let pod = await transport.cookieDiagnostic(for: URL(string: "https://p42-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct")!)
        XCTAssertEqual(pod, "cookie-jar-count=2; request-cookie-count=2")
        let dispatch = await transport.cookieDiagnostic(for: URL(string: "https://downloaddispatch.itunes.apple.com/r/redownload")!)
        XCTAssertEqual(dispatch, "cookie-jar-count=2; request-cookie-count=1")
        let insecure = await transport.cookieDiagnostic(for: URL(string: "http://p42-buy.itunes.apple.com/WebObjects/test")!)
        XCTAssertEqual(insecure, "cookie-jar-count=2; request-cookie-count=0")
        XCTAssertNil(StoreCookie(HTTPCookie(properties: [.name: "evil", .value: "fixture", .domain: ".evil.test", .path: "/"])!).cookie())
    }
}
private final class ChallengeProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let headers = ["Content-Type": "application/x-apple-plist",
                       "Set-Cookie": "challenge=fixture-challenge; Domain=.itunes.apple.com; Path=/; Secure"]
        let cookie = request.value(forHTTPHeaderField: "Cookie") ?? ""
        let valid = cookie.contains("initial=fixture-initial") && (request.url?.query != "verify=1" || cookie.contains("challenge=fixture-challenge"))
        let response = HTTPURLResponse(url: request.url!, statusCode: valid ? 200 : 401, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("<plist version=\"1.0\"><dict/></plist>".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
