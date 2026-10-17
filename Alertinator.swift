import Foundation

public extension Notification.Name {
    static let AlertinatorDidPostAlert = Notification.Name("AlertinatorDidPostAlert")
}

public struct AlertPayload: Sendable {
    public let title: String
    public let body: String
}

public final class Alertinator: @unchecked Sendable {
    public static let shared = Alertinator()
    private init() {}

    public func alert(title: String, body: String) {
        let payload = AlertPayload(title: title, body: body)
        if Thread.isMainThread {
            NotificationCenter.default.post(name: .AlertinatorDidPostAlert, object: payload)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .AlertinatorDidPostAlert, object: payload)
            }
        }
    }
}
