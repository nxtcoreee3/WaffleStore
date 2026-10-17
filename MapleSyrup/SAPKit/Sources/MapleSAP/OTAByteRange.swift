import Foundation

// Single byte ranges for the original local OTA transport. Reject malformed
// or multipart ranges rather than serving the wrong portion of an IPA.
public enum OTAByteRange {
    public static func resolve(_ header: String?, size: Int) throws -> Range<Int> {
        guard size > 0 else { throw StoreError.packageInvalid }
        guard let header else { return 0..<size }
        guard header.hasPrefix("bytes="), !header.contains(",") else { throw StoreError.invalidResponse }
        let parts = header.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 else { throw StoreError.invalidResponse }
        func number(_ value: Substring) -> Int? {
            guard !value.isEmpty, value.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return Int(value)
        }
        if parts[0].isEmpty {
            guard let suffix = number(parts[1]), suffix > 0 else { throw StoreError.invalidResponse }
            return max(0, size - min(suffix, size))..<size
        }
        guard let start = number(parts[0]), start < size else { throw StoreError.invalidResponse }
        if parts[1].isEmpty { return start..<size }
        guard let end = number(parts[1]), end >= start else { throw StoreError.invalidResponse }
        return start..<(min(end, size - 1) + 1)
    }
}
