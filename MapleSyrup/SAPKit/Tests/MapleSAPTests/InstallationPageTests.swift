import XCTest
@testable import MapleSAP

final class InstallationPageTests: XCTestCase {
    func testMetadataEscapedAndOriginalInstallTargetPreserved() throws {
        let target = URL(string: "itms-services://?action=download-manifest&url=https%3A%2F%2Fapi.palera.in%2FgenPlist%3Fname%3DTest")!
        let page = try InstallationPage.html(name: "Test <script>alert('x')</script> & App", version: "1.0 <b>", target: target)
        XCTAssertTrue(page.contains("Test &lt;script&gt;alert(&#39;x&#39;)&lt;/script&gt; &amp; App"))
        XCTAssertTrue(page.contains("Version 1.0 &lt;b&gt;"))
        XCTAssertFalse(page.contains("<script>alert("))
        let script = page.components(separatedBy: "const target=")[1].components(separatedBy: ";document")[0]
        let decoded = try JSONSerialization.jsonObject(with: Data(script.utf8), options: .fragmentsAllowed) as? String
        XCTAssertEqual(decoded, target.absoluteString)
        XCTAssertTrue(page.contains("location.href=target"))
    }
    func testExecutableTargetRefused() {
        XCTAssertThrowsError(try InstallationPage.html(name: "Test", version: "1", target: URL(string: "javascript:alert(1)")!))
    }
}
