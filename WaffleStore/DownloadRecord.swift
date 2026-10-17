import Foundation

// Local download history, separate from the original installation history.
// No account ID, signed URL, cookies or kbsync are serialized.
struct DownloadRecord: Codable, Identifiable {
    var id: String { filename }
    let filename: String
    let appID: String
    let appName: String
    let bundleID: String
    let version: String
    let build: String?
    let externalVersionID: String
    let date: Date
    var fileURL: URL? {
        guard filename == URL(fileURLWithPath: filename).lastPathComponent,
              filename.hasSuffix(".ipa"), !filename.contains(".."),
              let docs = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else { return nil }
        let url = docs.appendingPathComponent("Downloads").appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    // Delete only the IPA and matching nonsecret sidecar in Downloads. A stale
    // record is safe to remove even if Files already deleted its IPA.
    func deleteFiles(in directory: URL? = nil) throws {
        guard filename == URL(fileURLWithPath: filename).lastPathComponent,
              filename.hasSuffix(".ipa"), !filename.contains("..") else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        let fm = FileManager.default
        let root: URL
        if let directory { root = directory }
        else {
            root = try fm.url(for: .documentDirectory, in: .userDomainMask,
                appropriateFor: nil, create: false).appendingPathComponent("Downloads")
        }
        let ipa = root.appendingPathComponent(filename)
        for file in [ipa, ipa.deletingPathExtension().appendingPathExtension("json")] {
            if fm.fileExists(atPath: file.path) { try fm.removeItem(at: file) }
        }
    }
    // Clean downloaded IPAs and their sidecars, including IPAs without records.
    // Preserve unrelated documents and never follow a substituted Downloads directory.
    static func deleteAllFiles(in directory: URL? = nil) throws {
        let fm = FileManager.default
        let root = try directory ?? fm.url(for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false).appendingPathComponent("Downloads")
        guard fm.fileExists(atPath: root.path) else { return }
        let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        let files = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])
        for file in files where file.pathExtension == "ipa" {
            guard try file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory != true else { continue }
            let record = DownloadRecord(filename: file.lastPathComponent, appID: "", appName: "",
                bundleID: "", version: "", build: nil, externalVersionID: "", date: .distantPast)
            try record.deleteFiles(in: root)
        }
        // A sidecar may remain after the IPA was deleted in Files.
        for file in files where file.pathExtension == "json" && fm.fileExists(atPath: file.path) {
            guard let data = try? Data(contentsOf: file), data.count < 65536,
                  let record = try? JSONDecoder().decode(DownloadRecord.self, from: data),
                  file.lastPathComponent == URL(fileURLWithPath: record.filename)
                    .deletingPathExtension().appendingPathExtension("json").lastPathComponent else { continue }
            try record.deleteFiles(in: root)
        }
    }
    static func load() -> [DownloadRecord] {
        let fm = FileManager.default
        guard let docs = try? fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false),
              let files = try? fm.contentsOfDirectory(at: docs.appendingPathComponent("Downloads"), includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "json" }.compactMap { file in
            guard let data = try? Data(contentsOf: file), data.count < 65536,
                  let record = try? JSONDecoder().decode(DownloadRecord.self, from: data), record.fileURL != nil else { return nil }
            return record
        }.sorted { $0.date > $1.date }
    }
}
