import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Fixed fields only. Never retain body text, URLs, arbitrary headers or messages.
public enum ResponseDiagnostic {
    public static func response(_ data: Data, status: Int, scope: String, attempt: Int, secrets: [String] = []) -> String {
        let root = try? ApplePlist.dictionary(data)
        let format: String
        if data.isEmpty { format = "empty" }
        else if root != nil { format = "plist" }
        else if String(decoding: data.prefix(128), as: UTF8.self).lowercased().contains("<html") { format = "html" }
        else { format = "other" }
        let raw = (root?["failureType"] as? String) ?? (root?["failureType"] as? NSNumber)?.stringValue ?? ""
        let number = raw.hasPrefix("-") ? String(raw.dropFirst()) : raw
        let failure: String
        if raw.isEmpty { failure = "absent" }
        else if !number.isEmpty, number.count <= 8, number.allSatisfy({ $0.isASCII && $0.isNumber }), !secrets.contains(raw) { failure = raw }
        else { failure = "present-withheld" }
        // scope comes from an internal switch, not a URL or Apple string.
        return "scope=\(scope); attempt=\(attempt); HTTP=\(status); body=\(format); apple-failure=\(failure)"
    }
    public static func category(_ error: Error) -> String {
        if let error = error as? StoreError {
            switch error {
            case .sessionExpired: return "Apple-sign-in-required"
            case .http(let status): return "HTTP-\(status)"
            case .native(let stage): return "native-stage-\(stage)"
            case .licenseRequired: return "license-required"
            case .paidPurchase: return "automatic-purchase-refused"
            case .unavailable: return "app-version-unavailable"
            case .versionMismatch: return "app-version-mismatch"
            case .apple: return "Apple-Store-response"
            case .retryLater: return "retry-after-over-budget"
            default: return "Store-protocol"
            }
        }
        if let error = error as? SAPError, case .nativeRuntime(let stage) = error { return "SAP-native-stage-\(stage)" }
        if error is CancellationError { return "cancelled" }
        return "operation-\((error as NSError).code)"
    }
}
