//
//  NavigationButtons.swift
//  WaffleStore
//
//  Created by lunginspector on 2/24/26.
//

import SwiftUI
import PartyUI
import UIKit

struct NavigationButtons: View {
    @EnvironmentObject var appData: AppData
    @StateObject private var installer = OTAInstaller()

    private var primaryActionTitle: String {
        guard let record = appData.downloadReady else { return "Downgrade App".localized }
        guard appData.signingCertificate != nil else { return "Export IPA" }
        return record.filename.hasPrefix("Signed-") ? "Install" : "Sign & Install"
    }

    private var primaryActionIcon: String {
        guard let record = appData.downloadReady else { return "square.and.arrow.down" }
        guard appData.signingCertificate != nil else { return "arrow.up.doc" }
        return record.filename.hasPrefix("Signed-") ? "arrow.down.app" : "signature"
    }
    
    var body: some View {
        VStack {
            if !appData.isAuthenticated {
                Button(action: {
                    Haptic.shared.play(.soft)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        if appData.appleId.isEmpty || appData.password.isEmpty {
                            Alertinator.shared.alert(title: "No Apple ID details were input!".localized, body: "Login prompt description".localized)
                        } else {
                            appData.startAppleLogin()
                        }
                    }
                }) {
                    if appData.hasSent2FACode {
                        ButtonLabel(text: "Log In".localized, icon: "arrow.right")
                    } else {
                        ButtonLabel(text: "Send 2FA Code".localized, icon: "key")
                    }
                }
                .buttonStyle(FancyButtonStyle())
                .disabled(appData.appleId.isEmpty || appData.password.isEmpty)
                .disabled(appData.hasSent2FACode ? appData.code.isEmpty : false)
            } else {
                if appData.isDowngrading {
                    Button(action: {
                        Haptic.shared.play(.soft)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
#if canImport(UIKit)
    if let url = URL(string: "wafflestore://open") {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    } else if let appStoreURL = URL(string: "itms-apps://itunes.apple.com/app/id") {
        UIApplication.shared.open(appStoreURL, options: [:], completionHandler: nil)
    }
#endif
                        }
                    }) {
                        ButtonLabel(text: "Open App".localized, icon: "arrow.up.forward.app")
                    }
                    .buttonStyle(FancyButtonStyle(color: .blue))
                    .disabled(!appData.hasAppBeenServed)
                    
                    Button(action: {
                        Haptic.shared.play(.heavy)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            exitinator()
                        }
                    }) {
                        ButtonLabel(text: "Go to Home Screen".localized, icon: "house")
                    }
                    .buttonStyle(FancyButtonStyle())
                    .disabled(!appData.hasAppBeenServed)
                } else {
                    Button(action: runPrimaryAction) {
                        ButtonLabel(text: primaryActionTitle, icon: primaryActionIcon)
                    }
                    .buttonStyle(FancyButtonStyle())
                    .disabled(appData.downloadReady == nil && appData.appLink.isEmpty)
                    
                    let currentAppId = extractAppId(from: appData.appLink)
                    let existingFav = appData.favourites.first { extractAppId(from: $0.appLink) == currentAppId }
                    let isFavourited = existingFav != nil

                    Button(action: {
                        Haptic.shared.play(.soft)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            if appData.appLink.isEmpty {
                                Alertinator.shared.alert(title: "Cannot Add to Favourites".localized, body: "Please enter an app link first.".localized)
                                return
                            }
                            
                            if isFavourited {
                                if let fav = existingFav {
                                    appData.favourites = FavouritesStore.remove(fav)
                                    Haptic.shared.play(.soft)
                                    Alertinator.shared.alert(title: "Removed from Favourites".localized, body: "This app has been removed from your favourites.".localized)
                                }
                            } else {
                                let currentLink = appData.appLink
                                fetchAppNameAndBundleId(forLink: currentLink) { trackName, bundleId in
                                    DispatchQueue.main.async {
                                        let resolvedName = trackName.isEmpty ? (bundleId.isEmpty ? "App Store Link" : bundleId) : trackName
                                        let resolvedBundle = bundleId.isEmpty ? appData.appBundleID : bundleId
                                        let favourite = FavouriteApp(
                                            appLink: currentLink,
                                            bundleId: resolvedBundle,
                                            appName: resolvedName
                                        )
                                        appData.favourites = FavouritesStore.add(favourite)
                                        Haptic.shared.play(.soft)
                                        Alertinator.shared.alert(title: "Added to Favourites".localized, body: "This app has been added to your favourites for quick access.".localized)
                                    }
                                }
                            }
                        }
                    }) {
                        ButtonLabel(text: isFavourited ? "Remove from Favourites".localized : "Add to Favourites".localized, icon: isFavourited ? "star.fill" : "star")
                    }
                    .buttonStyle(FancyButtonStyle(color: .mint))
                    .disabled(appData.appLink.isEmpty)
                    

                }
            }
        }
    }

    private func runPrimaryAction() {
        Haptic.shared.play(.soft)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if let record = appData.downloadReady {
                handleDownload(record)
            } else {
                startDowngrade()
            }
        }
    }

    private func handleDownload(_ record: DownloadRecord) {
        guard let fileURL = record.fileURL else { return }
        guard appData.signingCertificate != nil else {
            presentShareSheet(with: fileURL)
            return
        }

        if record.filename.hasPrefix("Signed-") {
            do {
                try installer.start(record)
                if let pageURL = installer.pageURL {
                    UIApplication.shared.open(pageURL)
                }
            } catch {
                Alertinator.shared.alert(title: "Installation failed", body: error.localizedDescription)
            }
        } else {
            appData.signDownloadedIPA(record)
        }
    }

    private func startDowngrade() {
        guard !appData.appLink.isEmpty, let ipaTool = appData.ipaTool else { return }
        let appID = extractAppId(from: appData.appLink)
        guard !appID.isEmpty else { return }
        print("App ID: \(appID)")
        appData.isDowngrading = true
        appData.hasAppBeenServed = false
        downgradeApp(appId: appID, ipaTool: ipaTool)
    }
}

func extractAppId(from link: String) -> String {
    var parsed = link.components(separatedBy: "id").last ?? ""
    for char in parsed {
        if !char.isNumber {
            if let index = parsed.firstIndex(of: char) {
                parsed = String(parsed.prefix(upTo: index))
            }
            break
        }
    }
    return parsed
}

func fetchAppNameAndBundleId(forLink: String, completion: @escaping (String, String) -> Void) {
    let parsedAppId = extractAppId(from: forLink)
    guard !parsedAppId.isEmpty, let url = URL(string: "https://itunes.apple.com/lookup?id=\(parsedAppId)") else {
        completion("", "")
        return
    }
    
    URLSession.shared.dataTask(with: url) { data, response, error in
        guard let data = data, error == nil else {
            completion("", "")
            return
        }
        do {
            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let results = json["results"] as? [[String: Any]],
               let firstResult = results.first {
                let trackName = firstResult["trackName"] as? String ?? ""
                let bundleId = firstResult["bundleId"] as? String ?? ""
                completion(trackName, bundleId)
            } else {
                completion("", "")
            }
        } catch {
            completion("", "")
        }
    }.resume()
}
