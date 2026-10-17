// xcode: set sdk=iOS

//
//  AppData.swift
//  WaffleStore
//
//  Created by lunginspector on 2/25/26.
//

import SwiftUI
import Combine
import MapleSAP

enum AppTab: Hashable { case search, downloads, favourites, account, settings }

@MainActor
final class AppData: ObservableObject {
    static let shared = AppData()
    @Published var selectedTab: AppTab = .search
    var openVersionsAfterLogin = false
    var selectedCatalogCountry: String?
    @Published var catalogRegion: String = UserDefaults.standard.string(forKey: "catalogRegion") ?? "" {
        didSet { UserDefaults.standard.set(catalogRegion, forKey: "catalogRegion") }
    }
    var accountCountry: String {
        guard let account = ipaTool?.account else { return "us" }
        return (try? Storefront.country(account.storefront)) ?? "us"
    }
    var catalogCountry: String {
        Storefront.catalogCountries.contains(catalogRegion) ? catalogRegion : accountCountry
    }
    func openAppSelection(_ input: String, country: String? = nil) {
        guard !isDowngrading, storeRequestCount == 0, !showStoreVersions else { return }
        appLink = input
        selectedCatalogCountry = country ?? catalogCountry
        if isAuthenticated {
            selectedTab = .search
            showStoreVersions = true
        } else {
            openVersionsAfterLogin = true
            selectedTab = .account
        }
    }

    
    @Published var applicationIcon: String = "xmark.circle.fill"
    @Published var applicationIconColor: Color = .secondary
    @Published var applicationStatus: String = "Not logged in!".localized
    @Published var downgradeProgress: Double = 0
    @Published var downgradeProgressDetail: String = ""
    @Published var activeDownloadName = ""
    var downloadPhaseLabel: String {
        switch applicationStatus {
        case "Downloading IPA from CDN": return "Downloading"
        case "Validating ZIP, app identity and purchase data": return "Checking download"
        case "Requesting selected externalVersionId": return "Preparing download"
        case "Retrying CDN download": return "Reconnecting"
        default: return "Preparing download"
        }
    }
    var downloadProgressText: String {
        if applicationStatus == "Downloading IPA from CDN" { return downgradeProgressDetail }
        if applicationStatus == "Validating ZIP, app identity and purchase data" { return "Verifying the selected version" }
        return "Getting the app ready"
    }
    @Published var showsDowngradeProgress: Bool = false
    
    @Published var appBundleID: String = ""
    @Published var appVersion: String = ""
    
    @Published var hasAppBeenServed: Bool = false
    
    @Published var ipaTool: IPATool?
    
    @Published var appleId: String = ""
    @Published var password: String = ""
    @Published var code: String = ""
    
    @Published var isAuthenticated: Bool = false
    @Published var isAuthenticating: Bool = false
    @Published var authenticationError: String = ""
    @Published var authenticationRecovery: String = ""
    var authenticationTask: Task<Void, Never>?
    var didRestoreStoreAccount = false
    var pendingAuthenticationCookies: [StoreCookie] = []
    var preparedAppleLogin: PreparedAppleLogin?
    var loginPreparationExpiry: Task<Void, Never>?
    @Published var showStoreVersions = false
    @Published var downloadedIPAURL: URL?
    @Published var downloadReady: DownloadRecord?
    @Published var installationRequest: DownloadRecord?
    @Published var completedDownloads: [DownloadRecord] = []
    @Published var signingCertificates: [SigningCertificate] = SigningCertificateStore.load()
    @Published var activeSigningCertificateID: UUID? = UUID(uuidString: UserDefaults.standard.string(forKey: "activeSigningCertificateID") ?? "") {
        didSet {
            UserDefaults.standard.set(activeSigningCertificateID?.uuidString, forKey: "activeSigningCertificateID")
        }
    }
    @Published var riskyOptionsEnabled: Bool = UserDefaults.standard.bool(forKey: "riskyOptionsEnabled") {
        didSet {
            UserDefaults.standard.set(riskyOptionsEnabled, forKey: "riskyOptionsEnabled")
            if !riskyOptionsEnabled {
                allowSigningProfileMismatch = false
                allowEncryptedIPASigning = false
            }
        }
    }
    @Published var allowSigningProfileMismatch: Bool = UserDefaults.standard.bool(forKey: "allowSigningProfileMismatch") {
        didSet { UserDefaults.standard.set(allowSigningProfileMismatch, forKey: "allowSigningProfileMismatch") }
    }
    @Published var allowEncryptedIPASigning: Bool = UserDefaults.standard.bool(forKey: "allowEncryptedIPASigning") {
        didSet { UserDefaults.standard.set(allowEncryptedIPASigning, forKey: "allowEncryptedIPASigning") }
    }
    @Published var storeError = ""
    @Published var storeRequestCount = 0
    var storeTask: Task<Void, Never>?
    @Published var isDowngrading: Bool = false
    
    @Published var appLink: String = ""
    
    @Published var hasSent2FACode: Bool = false
    
    @Published var showPassword: Bool = false
    
    @Published var showFavouritesView: Bool = false
    
    @Published var downgradeHistory: [DowngradeHistoryEntry] = DowngradeHistoryStore.load()
    @Published var favourites: [FavouriteApp] = FavouritesStore.load()
}
