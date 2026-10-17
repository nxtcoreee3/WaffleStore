import XCTest
@testable import MapleSAP
final class OTARangeTests: XCTestCase {
    func testFullOpenEndedSuffixAndClampedRanges() throws {
        XCTAssertEqual(try OTAByteRange.resolve(nil, size: 100), 0..<100)
        XCTAssertEqual(try OTAByteRange.resolve("bytes=0-9", size: 100), 0..<10)
        XCTAssertEqual(try OTAByteRange.resolve("bytes=90-", size: 100), 90..<100)
        XCTAssertEqual(try OTAByteRange.resolve("bytes=-10", size: 100), 90..<100)
        XCTAssertEqual(try OTAByteRange.resolve("bytes=-200", size: 100), 0..<100)
        XCTAssertEqual(try OTAByteRange.resolve("bytes=90-200", size: 100), 90..<100)
    }
    func testInvalidRangesDoNotServeDifferentIPABytes() {
        for header in ["bytes=100-", "bytes=8-2", "bytes=-0", "bytes=-", "bytes=1-2,8-9", "bytes=999999999999999999999999-", "bytes=+1-2", "bytes=0--1", "items=0-9"] {
            XCTAssertThrowsError(try OTAByteRange.resolve(header, size: 100))
        }
        XCTAssertThrowsError(try OTAByteRange.resolve(nil, size: 0))
    }
}
