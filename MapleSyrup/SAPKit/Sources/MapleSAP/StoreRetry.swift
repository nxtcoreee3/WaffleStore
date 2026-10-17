import Foundation

public enum StoreRetry {
    // Bounded waits preserve Apple's Retry-After; never cap a longer server
    // deadline into an earlier request. attempt is zero-based.
    public static func delay(_ header: String?, attempt: Int, now: Date = Date()) throws -> TimeInterval {
        let fallback = Double((attempt + 1) * 5)
        guard let header = header?.trimmingCharacters(in: .whitespacesAndNewlines), !header.isEmpty else { return fallback }
        if header.allSatisfy({ $0.isASCII && $0.isNumber }) {
            guard let seconds = UInt64(header), seconds <= 30 else { throw StoreError.retryLater }
            return max(1, Double(seconds))
        }
        for format in ["EEE, dd MMM yyyy HH:mm:ss z", "EEEE, dd-MMM-yy HH:mm:ss z", "EEE MMM d HH:mm:ss yyyy"] {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = format
            if let date = formatter.date(from: header) {
                let value = max(0, date.timeIntervalSince(now))
                guard value <= 30 else { throw StoreError.retryLater }
                return max(1, value)
            }
        }
        return fallback
    }
}
public struct CDNHTTPFailure: Error, Sendable {
    public let status: Int
    public let retryAfter: String?
    public init(status: Int, retryAfter: String?) { self.status = status; self.retryAfter = retryAfter }
}
