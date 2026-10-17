import Foundation
import Security
import Zip
import ZsignSwift

enum IPAEncryptionStatus {
    case encrypted
    case decrypted
    case unknown
}

enum IPAEncryptionDetector {
    static func status(for ipaURL: URL) -> IPAEncryptionStatus {
        let fileManager = FileManager.default
        let work = fileManager.temporaryDirectory.appendingPathComponent("WaffleStoreInspect-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: work) }
        do {
            try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
            try Zip.unzipFile(ipaURL, destination: work, overwrite: true, password: nil, progress: nil)
            guard let appURL = fileManager.enumerator(at: work, includingPropertiesForKeys: [.isDirectoryKey])?
                .compactMap({ $0 as? URL }).first(where: { $0.pathExtension == "app" }),
                  let info = NSDictionary(contentsOf: appURL.appendingPathComponent("Info.plist")) as? [String: Any],
                  let executable = info["CFBundleExecutable"] as? String else { return .unknown }
            return encryptionStatus(for: appURL.appendingPathComponent(executable))
        } catch {
            print("[diagnostic] Could not inspect IPA encryption state: \(error.localizedDescription)")
            return .unknown
        }
    }

    private static func encryptionStatus(for executableURL: URL) -> IPAEncryptionStatus {
        guard let data = try? Data(contentsOf: executableURL), data.count >= 32 else { return .unknown }
        let magic = data.uint32(at: 0, endian: .little)
        let is64 = magic == 0xfeedfacf
        let is32 = magic == 0xfeedface
        guard is64 || is32 else { return .unknown }
        let commandOffset = is64 ? 32 : 28
        let commandCount = Int(data.uint32(at: 16, endian: .little))
        var offset = commandOffset
        for _ in 0..<commandCount {
            guard offset + 8 <= data.count else { return .unknown }
            let command = data.uint32(at: offset, endian: .little)
            let size = Int(data.uint32(at: offset + 4, endian: .little))
            guard size >= 8, offset + size <= data.count else { return .unknown }
            if command == 0x21 || command == 0x2c {
                guard offset + 20 <= data.count else { return .unknown }
                let cryptID = data.uint32(at: offset + 16, endian: .little)
                return cryptID == 0 ? .decrypted : .encrypted
            }
            offset += size
        }
        return .decrypted
    }
}

private extension Data {
    enum ByteOrder { case little, big }
    func uint32(at offset: Int, endian: ByteOrder) -> UInt32 {
        let bytes = self[offset..<(offset + 4)]
        let values = bytes.map(UInt32.init)
        if endian == .little {
            return values[0] | values[1] << 8 | values[2] << 16 | values[3] << 24
        }
        return values[3] | values[2] << 8 | values[1] << 16 | values[0] << 24
    }
}

struct SigningCertificate: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var icon: String
    let p12Filename: String
    let provisionFilename: String
    let password: String

    var p12URL: URL {
        SigningCertificateStore.directoryURL.appendingPathComponent(p12Filename)
    }

    var provisionURL: URL {
        SigningCertificateStore.directoryURL.appendingPathComponent(provisionFilename)
    }
}

enum SigningProfileIcons {
    static let all = [
        "signature", "checkmark.seal.fill", "shield.lefthalf.filled", "lock.shield.fill",
        "key.fill", "person.crop.circle", "person.crop.circle.fill", "star.fill",
        "bolt.fill", "flame.fill", "crown.fill", "globe", "cloud.fill",
        "folder.fill", "wrench.and.screwdriver.fill", "gearshape.fill", "app.badge.fill",
        "terminal.fill", "pencil.and.outline", "circle.hexagongrid.fill"
    ]
}

enum CertificateValidator {
    enum ValidationError: LocalizedError {
        case invalidPassword
        case invalidProfile
        case expiredProfile
        case missingIdentity
        case profileMismatch(profileIdentifier: String, bundleIdentifier: String)

        var errorDescription: String? {
            switch self {
            case .invalidPassword: return "The .p12 password is incorrect or the certificate is invalid."
            case .invalidProfile: return "The provisioning profile could not be read."
            case .expiredProfile: return "The provisioning profile has expired."
            case .missingIdentity: return "The .p12 file does not contain a signing identity."
            case .profileMismatch(let profileIdentifier, let bundleIdentifier):
                return "Provisioning profile targets \(profileIdentifier), but this IPA uses \(bundleIdentifier). Import a profile created for the downloaded app."
            }
        }
    }

    static func validate(p12: URL, provision: URL, password: String) throws {
        let p12Data = try Data(contentsOf: p12)
        var imported: CFArray?
        let options = [kSecImportExportPassphrase as String: password]
        let status = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &imported)
        guard status == errSecSuccess else { throw ValidationError.invalidPassword }
        guard let imported, CFArrayGetCount(imported) > 0 else { throw ValidationError.missingIdentity }

        let profile = try provisioningProfile(from: provision)
        guard let expiration = profile["ExpirationDate"] as? Date else {
            throw ValidationError.invalidProfile
        }
        guard expiration > Date() else { throw ValidationError.expiredProfile }
    }

    static func validate(p12: URL, provision: URL, password: String, bundleURL: URL) throws {
        try validate(p12: p12, provision: provision, password: password)

        let profile = try provisioningProfile(from: provision)
        guard let info = NSDictionary(contentsOf: bundleURL.appendingPathComponent("Info.plist")) as? [String: Any],
              let bundleIdentifier = info["CFBundleIdentifier"] as? String,
              let entitlements = profile["Entitlements"] as? [String: Any],
              let applicationIdentifier = entitlements["application-identifier"] as? String else {
            throw ValidationError.invalidProfile
        }

        guard profileAllows(applicationIdentifier: applicationIdentifier, bundleIdentifier: bundleIdentifier) else {
            throw ValidationError.profileMismatch(profileIdentifier: applicationIdentifier, bundleIdentifier: bundleIdentifier)
        }
    }

    private static func provisioningProfile(from url: URL) throws -> [String: Any] {
        let profileData = try Data(contentsOf: url)
        guard let xmlStart = profileData.range(of: Data("<?xml".utf8)) else {
            throw ValidationError.invalidProfile
        }
        let plistData = profileData.subdata(in: xmlStart.lowerBound..<profileData.endIndex)
        guard let profile = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            throw ValidationError.invalidProfile
        }
        return profile
    }

    private static func profileAllows(applicationIdentifier: String, bundleIdentifier: String) -> Bool {
        let identifierPattern = applicationIdentifier.split(separator: ".", maxSplits: 1).dropFirst().first.map(String.init)
        guard let identifierPattern else { return false }
        if identifierPattern == bundleIdentifier || identifierPattern == "*" { return true }
        if identifierPattern.hasSuffix(".*") {
            let prefix = String(identifierPattern.dropLast(2))
            return bundleIdentifier == prefix || bundleIdentifier.hasPrefix(prefix + ".")
        }
        return false
    }
}

enum SigningCertificateStore {
    private static let folderName = "SigningCertificate"
    private static let metadataFilename = "certificates.json"

    static var directoryURL: URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return applicationSupport.appendingPathComponent(folderName, isDirectory: true)
    }

    static func load() -> [SigningCertificate] {
        let metadataURL = directoryURL.appendingPathComponent(metadataFilename)
        if let data = try? Data(contentsOf: metadataURL),
           let certificates = try? JSONDecoder().decode([SigningCertificate].self, from: data) {
            return certificates.filter { filesExist(for: $0) && isValid($0) }
        }

        return loadLegacyCertificate().map { [$0] } ?? []
    }

    static func add(p12: URL, provision: URL, password: String, name: String, icon: String) throws -> SigningCertificate {
        try CertificateValidator.validate(p12: p12, provision: provision, password: password)
        let id = UUID()
        let folder = directoryURL.appendingPathComponent(id.uuidString, isDirectory: true)
        let p12URL = folder.appendingPathComponent("signing.p12")
        let provisionURL = folder.appendingPathComponent("signing.mobileprovision")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        do {
            try copy(p12, to: p12URL)
            try copy(provision, to: provisionURL)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }

        let certificate = SigningCertificate(
            id: id,
            name: name.isEmpty ? "Signing Certificate" : name,
            icon: icon,
            p12Filename: "\(id.uuidString)/signing.p12",
            provisionFilename: "\(id.uuidString)/signing.mobileprovision",
            password: password
        )
        var certificates = load()
        certificates.append(certificate)
        try saveMetadata(certificates)
        return certificate
    }

    static func update(_ certificate: SigningCertificate, in certificates: [SigningCertificate]) throws {
        try saveMetadata(certificates.map { $0.id == certificate.id ? certificate : $0 })
    }

    static func remove(_ certificate: SigningCertificate) {
        let folder = directoryURL.appendingPathComponent(certificate.id.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try? saveMetadata(load().filter { $0.id != certificate.id })
    }

    private static func saveMetadata(_ certificates: [SigningCertificate]) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let metadataURL = directoryURL.appendingPathComponent(metadataFilename)
        try JSONEncoder().encode(certificates).write(to: metadataURL, options: .atomic)
    }

    private static func filesExist(for certificate: SigningCertificate) -> Bool {
        FileManager.default.fileExists(atPath: certificate.p12URL.path)
            && FileManager.default.fileExists(atPath: certificate.provisionURL.path)
    }

    private static func isValid(_ certificate: SigningCertificate) -> Bool {
        (try? CertificateValidator.validate(p12: certificate.p12URL, provision: certificate.provisionURL, password: certificate.password)) != nil
    }

    private static func loadLegacyCertificate() -> SigningCertificate? {
        struct LegacyCertificate: Codable {
            let p12Filename: String
            let provisionFilename: String
            let password: String
        }
        let url = directoryURL.appendingPathComponent("certificate.json")
        guard let data = try? Data(contentsOf: url),
              let old = try? JSONDecoder().decode(LegacyCertificate.self, from: data) else { return nil }
        let certificate = SigningCertificate(
            id: UUID(),
            name: "Signing Certificate",
            icon: "signature",
            p12Filename: old.p12Filename,
            provisionFilename: old.provisionFilename,
            password: old.password
        )
        return filesExist(for: certificate) && isValid(certificate) ? certificate : nil
    }

    private static func copy(_ source: URL, to destination: URL) throws {
        let hasSecurityScope = source.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope { source.stopAccessingSecurityScopedResource() }
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }
}

enum IPAResigner {
    private final class ErrorBox: @unchecked Sendable {
        var value: Swift.Error?
    }

    enum SigningError: Swift.Error, LocalizedError {
        case invalidIPA
        case failed(String)
        case outputMissing

        var errorDescription: String? {
            switch self {
            case .invalidIPA: return "The downloaded IPA could not be opened for signing."
            case .failed(let message): return message
            case .outputMissing: return "The signed IPA was not created."
            }
        }
    }

    static func sign(input: URL, output: URL, certificate: SigningCertificate, allowProfileMismatch: Bool = false) throws {
        let fileManager = FileManager.default
        print("[sign] Starting IPA signing")
        print("[sign] Input: \(input.lastPathComponent)")
        print("[sign] Certificate: \(certificate.name)")
        print("[sign] Checking certificate files")
        try CertificateValidator.validate(p12: certificate.p12URL, provision: certificate.provisionURL, password: certificate.password)
        print("[sign] Certificate and provisioning profile are valid")
        Zip.addCustomFileExtension("ipa")
        print("[sign] Registered .ipa archive extension")

        let workDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("WaffleStoreSigning-\(UUID().uuidString)", isDirectory: true)
        let payloadDirectory = workDirectory.appendingPathComponent("Payload", isDirectory: true)
        defer { try? fileManager.removeItem(at: workDirectory) }

        try fileManager.createDirectory(at: payloadDirectory, withIntermediateDirectories: true)
        print("[sign] Extracting IPA")
        try Zip.unzipFile(input, destination: workDirectory, overwrite: true, password: nil, progress: nil)
        guard let appURL = try? fileManager.contentsOfDirectory(at: payloadDirectory, includingPropertiesForKeys: [.isDirectoryKey]).first(where: { $0.pathExtension == "app" }) else {
            print("[sign] Failed: no .app bundle was found in Payload")
            throw SigningError.invalidIPA
        }
        print("[sign] App bundle: \(appURL.lastPathComponent)")

        do {
            try CertificateValidator.validate(
                p12: certificate.p12URL,
                provision: certificate.provisionURL,
                password: certificate.password,
                bundleURL: appURL
            )
            print("[sign] Certificate matches the app bundle")
        } catch let error as CertificateValidator.ValidationError
                    where allowProfileMismatch && {
                        if case .profileMismatch = error { return true }
                        return false
                    }() {
            print("[sign] WARNING: proceeding with confirmed provisioning-profile bundle-ID mismatch")
        }

        try? fileManager.removeItem(at: appURL.appendingPathComponent("_CodeSignature", isDirectory: true))
        try? fileManager.removeItem(at: appURL.appendingPathComponent("embedded.mobileprovision"))
        try normalizePermissions(in: appURL)

        print("[sign] Running Zsign")
        let errorBox = ErrorBox()
        let signed = Zsign.sign(
            appPath: appURL.path,
            provisionPath: certificate.provisionURL.path,
            p12Path: certificate.p12URL.path,
            p12Password: certificate.password,
            // This Zsign fork uses the flag the same way Ksign does:
            // true keeps embedded.mobileprovision in the signed bundle.
            removeProvision: true,
            completion: { _, error in errorBox.value = error }
        )
        if let error = errorBox.value {
            print("[sign] Zsign error: \(error.localizedDescription)")
            throw error
        }
        guard signed else {
            print("[sign] Zsign returned failure without an error")
            throw SigningError.failed("Zsign could not sign this IPA with the selected certificate.")
        }
        print("[sign] Zsign completed")

        try? fileManager.removeItem(at: output)
        print("[sign] Repackaging signed IPA")
        try Zip.zipFiles(paths: [payloadDirectory], zipFilePath: output, password: nil, progress: nil)
        guard fileManager.fileExists(atPath: output.path) else {
            print("[sign] Failed: signed output could not be packaged")
            throw SigningError.outputMissing
        }
        print("[sign] Finished: \(output.lastPathComponent)")
    }

    private static func normalizePermissions(in appURL: URL) throws {
        let fileManager = FileManager.default
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: appURL.path)
        guard let enumerator = fileManager.enumerator(at: appURL, includingPropertiesForKeys: nil) else { return }
        for case let itemURL as URL in enumerator {
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: itemURL.path)
        }
    }
}

@MainActor
extension AppData {
    var signingCertificate: SigningCertificate? {
        if let activeSigningCertificateID,
           let selected = signingCertificates.first(where: { $0.id == activeSigningCertificateID }) {
            return selected
        }
        return signingCertificates.first
    }

    func addSigningCertificate(p12: URL, provision: URL, password: String, name: String, icon: String) throws {
        let certificate = try SigningCertificateStore.add(p12: p12, provision: provision, password: password, name: name, icon: icon)
        signingCertificates.append(certificate)
        if activeSigningCertificateID == nil { activeSigningCertificateID = certificate.id }
    }

    func updateSigningCertificate(_ certificate: SigningCertificate) throws {
        try SigningCertificateStore.update(certificate, in: signingCertificates)
        if let index = signingCertificates.firstIndex(where: { $0.id == certificate.id }) {
            signingCertificates[index] = certificate
        }
    }

    func removeSigningCertificate(_ certificate: SigningCertificate) {
        SigningCertificateStore.remove(certificate)
        signingCertificates.removeAll { $0.id == certificate.id }
        if activeSigningCertificateID == certificate.id {
            activeSigningCertificateID = signingCertificates.first?.id
        }
    }

    func selectSigningCertificate(_ certificate: SigningCertificate) {
        activeSigningCertificateID = certificate.id
    }

    func signDownloadedIPA(_ record: DownloadRecord) {
        guard let certificate = signingCertificate,
              let sourceURL = record.fileURL,
              storeTask == nil else { return }
        guard let downloadsURL = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Downloads", isDirectory: true) else { return }

        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: downloadsURL, withIntermediateDirectories: true)
        let filename = record.filename.hasPrefix("Signed-") ? record.filename : "Signed-\(record.filename)"
        let outputURL = downloadsURL.appendingPathComponent(filename)
        let signedRecord = DownloadRecord(filename: filename, appID: record.appID, appName: record.appName, bundleID: record.bundleID, version: record.version, build: record.build, externalVersionID: record.externalVersionID, date: Date())

        isDowngrading = true
        showsDowngradeProgress = true
        downgradeProgress = 0.05
        applicationStatus = "Signing IPA…"
        print("[sign] Queued signing for \(record.filename)")
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try await IPAResigner.sign(input: sourceURL, output: outputURL, certificate: certificate,
                                         allowProfileMismatch: self.allowSigningProfileMismatch)
                }.value
                let metadataURL = outputURL.deletingPathExtension().appendingPathExtension("json")
                try JSONEncoder().encode(signedRecord).write(to: metadataURL, options: .atomic)
                completedDownloads = DownloadRecord.load()
                downloadReady = signedRecord
                downloadedIPAURL = outputURL
                downgradeProgress = 1
                applicationStatus = "IPA signed and ready to install."
                applicationIcon = "checkmark.circle.fill"
            } catch {
                print("[sign] Signing failed: \(error.localizedDescription)")
                applicationStatus = "IPA signing failed."
                applicationIcon = "xmark.circle.fill"
                Alertinator.shared.alert(title: "Signing failed", body: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
            isDowngrading = false
            showsDowngradeProgress = false
        }
    }
}
