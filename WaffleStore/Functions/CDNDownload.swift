import Foundation
import MapleSAP

// A completely separate session. Account cookies and authentication headers
// are NEVER attached to CDN requests, including redirects.
nonisolated final class CDNDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let progress: @Sendable (Double, Int64, Int64) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var task: URLSessionDownloadTask?
    private var cancelled = false
    private var redirects = 0
    private var result: Result<URL, Error>?
    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil; c.httpShouldSetCookies = false; c.urlCache = nil
        c.timeoutIntervalForRequest = 60; c.timeoutIntervalForResource = 3600
        return URLSession(configuration: c, delegate: self, delegateQueue: nil)
    }()
    init(destination: URL, progress: @escaping @Sendable (Double, Int64, Int64) -> Void) {
        self.destination = destination; self.progress = progress
    }
    func run(_ url: URL) async throws -> URL {
        _ = try CDNPolicy.validate(url.absoluteString)
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if cancelled { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
                self.continuation = continuation
                var request = URLRequest(url: url)
                request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                let download = session.downloadTask(with: request)
                task = download
                lock.unlock()
                download.resume()
            }
        }, onCancel: { self.cancel() })
    }
    private func cancel() {
        lock.lock(); cancelled = true; let task = task; lock.unlock(); task?.cancel()
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > 8 << 30 { downloadTask.cancel(); return }
        progress(totalBytesExpectedToWrite > 0 ? min(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 1) : 0,
                 totalBytesWritten, totalBytesExpectedToWrite)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        redirects += 1
        guard redirects <= 8, let url = request.url, (try? CDNPolicy.validate(url.absoluteString)) != nil else {
            completionHandler(nil); return
        }
        // Rebuild rather than trusting headers propagated by URLSession.
        var clean = URLRequest(url: url); clean.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        completionHandler(clean)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard let response = downloadTask.response as? HTTPURLResponse else { throw StoreError.invalidResponse }
            guard response.statusCode == 200 else { throw CDNHTTPFailure(status: response.statusCode, retryAfter: response.value(forHTTPHeaderField: "Retry-After")) }
            let size = try location.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= 8 << 30,
                  response.expectedContentLength < 0 || response.expectedContentLength == Int64(size) else { throw StoreError.packageInvalid }
            try FileManager.default.moveItem(at: location, to: destination)
            result = .success(destination)
        } catch { result = .failure(error) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let continuation = self.continuation; self.continuation = nil
        let wasCancelled = cancelled
        lock.unlock()
        if wasCancelled {
            try? FileManager.default.removeItem(at: destination)
            continuation?.resume(throwing: CancellationError())
        } else if let error = error { continuation?.resume(throwing: error) }
        else { continuation?.resume(with: result ?? .failure(StoreError.invalidResponse)) }
        session.finishTasksAndInvalidate()
    }
}
