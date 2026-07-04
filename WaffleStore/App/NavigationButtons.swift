//
//  NavigationButtons.swift
//  WaffleStore
//
//  Created by lunginspector on 2/24/26.
//

import SwiftUI
import PartyUI

struct NavigationButtons: View {
    @EnvironmentObject var appData: AppData
    
    var body: some View {
        VStack {
            // i hate this.
            if !appData.isAuthenticated {
                Button(action: {
                    Haptic.shared.play(.soft)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        if appData.appleId.isEmpty || appData.password.isEmpty {
                            Alertinator.shared.alert(title: "No Apple ID details were input!".localized, body: "Login prompt description".localized)
                        } else {
                            if appData.code.isEmpty {
                                appData.ipaTool = IPATool(appleId: appData.appleId, password: appData.password)
                                appData.ipaTool?.authenticate(requestCode: true)
                                //appData.hasSent2FACode = true
                                return
                            }
                            let finalPassword = appData.password + appData.code
                            appData.ipaTool = IPATool(appleId: appData.appleId, password: finalPassword)
                            let ret = appData.ipaTool?.authenticate()
                            appData.isAuthenticated = ret ?? false
                            
                            if appData.isAuthenticated {
                                appData.applicationStatus = "Ready to Downgrade!".localized
                                appData.applicationIcon = "checkmark.circle.fill"
                                appData.applicationIconColor = .secondary
                            }
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
                            _ = LSApplicationWorkspace.default()?.openApplication(withBundleID: "com.nxtcoreee3.WaffleStore")
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
                    Button(action: {
                        Haptic.shared.play(.soft)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            if appData.appLink.isEmpty {
                                return
                            }
                            var appLinkParsed = appData.appLink
                            appLinkParsed = appLinkParsed.components(separatedBy: "id").last ?? ""
                            for char in appLinkParsed {
                                if !char.isNumber {
                                    appLinkParsed = String(appLinkParsed.prefix(upTo: appLinkParsed.firstIndex(of: char)!))
                                    break
                                }
                            }
                            print("App ID: \(appLinkParsed)")
                            appData.isDowngrading = true
                            appData.hasAppBeenServed = false
                            downgradeApp(appId: appLinkParsed, ipaTool: appData.ipaTool!)
                        }
                    }) {
                        ButtonLabel(text: "Downgrade App".localized, icon: "square.and.arrow.down")
                    }
                    .buttonStyle(FancyButtonStyle())
                    .disabled(appData.appLink.isEmpty)
                    
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
                    .buttonStyle(FancyButtonStyle(color: .yellow))
                    .disabled(appData.appLink.isEmpty)
                    
                    /*
                    Button(action: {
                        Haptic.shared.play(.heavy)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            appData.isAuthenticated = false
                            EncryptedKeychainWrapper.nuke()
                            EncryptedKeychainWrapper.generateAndStoreKey()
                            sleep(3)
                            exitinator()
                        }
                    }) {
                        ButtonLabel(text: "Log Out & Exit", icon: "xmark")
                    }
                    .buttonStyle(FancyButtonStyle(color: .red))
                     */
                }
            }
        }
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

