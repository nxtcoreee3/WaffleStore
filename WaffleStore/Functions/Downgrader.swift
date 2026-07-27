//
//  Downgrader.swift
//  PancakeStore
//
//  Created by Mineek on 19/10/2024.
//

import Foundation
import UIKit
import Telegraph
import Zip
import SwiftUI
import SafariServices
import PartyUI

struct SafariWebView: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> SFSafariViewController {
        return SFSafariViewController(url: url)
    }
    
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
    }
}

func installAppVersion(appId: String, versionId: String, ipaTool: IPATool, recordsHistory: Bool) {
    let appData = AppData.shared
    
    setDowngradeProgress(0.02, detail: "Starting downgrade".localized)
    let path = ipaTool.downloadIPAForVersion(appId: appId, appVerId: versionId) { progress, detail in
        setDowngradeProgress(progress, detail: detail)
    }
    print("IPA downloaded to \(path)")
    setDowngradeProgress(0.92, detail: "Packing installable IPA".localized)
    
    let tempDir = FileManager.default.temporaryDirectory
    var contents = try! FileManager.default.contentsOfDirectory(atPath: path)
    print("Contents: \(contents)")
    // also delete this; i wanna see both the app's directory and the temp ipa GONE.
    let destinationUrl = tempDir.appendingPathComponent("app.ipa")
    try! Zip.zipFiles(paths: contents.map { URL(fileURLWithPath: path).appendingPathComponent($0) }, zipFilePath: destinationUrl, password: nil, progress: nil)
    print("IPA zipped to \(destinationUrl)")
    let path2 = URL(fileURLWithPath: path)
    var appDir = path2.appendingPathComponent("Payload")
    for file in try! FileManager.default.contentsOfDirectory(atPath: appDir.path) {
        if file.hasSuffix(".app") {
            print("Found app: \(file)")
            // i assume we delete this? idk how to though
            appDir = appDir.appendingPathComponent(file)
            break
        }
    }
    let infoPlistPath = appDir.appendingPathComponent("Info.plist")
    let infoPlist = NSDictionary(contentsOf: infoPlistPath)!
    let appBundleId = infoPlist["CFBundleIdentifier"] as! String
    let appVersion = infoPlist["CFBundleShortVersionString"] as! String
    print("appBundleId: \(appBundleId)")
    print("appVersion: \(appVersion)")

    appData.appBundleID = appBundleId
    appData.appVersion = appVersion
    setDowngradeProgress(0.95, detail: "Preparing install manifest".localized)
    
    if recordsHistory {
        let entry = DowngradeHistoryEntry(
            id: UUID(),
            appId: appId,
            appLink: appData.appLink,
            bundleId: appBundleId,
            installedVersion: appVersion,
            externalVersionId: versionId,
            date: Date(),
            keptAppData: DowngradeHistoryStore.keepsAppDataForNextInstall
        )
        DispatchQueue.main.async {
            appData.downgradeHistory = DowngradeHistoryStore.append(entry)
        }
    }
    
    let finalURL = "https://api.palera.in/genPlist?bundleid=\(appBundleId)&name=\(appBundleId)&version=\(appVersion)&fetchurl=http://127.0.0.1:9090/signed.ipa"
    let installURL = "itms-services://?action=download-manifest&url=" + finalURL.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
    
    DispatchQueue.global(qos: .background).async {
        let server = Server()

        server.route(.GET, "signed.ipa", { _ in
            print("Serving signed.ipa")
            let signedIPAData = try Data(contentsOf: destinationUrl)
            return HTTPResponse(body: signedIPAData)
        })

        server.route(.GET, "install", { _ in
            print("Serving install page")
            appData.hasAppBeenServed = true
            appData.applicationStatus = "Downgrade successful!".localized
            appData.applicationIcon = "checkmark.circle.fill"
            appData.applicationIconColor = .green
            appData.downgradeProgress = 1
            appData.downgradeProgressDetail = "Ready to install".localized
            appData.showsDowngradeProgress = false
            let installPage = """
            <script type="text/javascript">
                window.location = "\(installURL)"
            </script>
            """
            return HTTPResponse(.ok, headers: ["Content-Type": "text/html"], content: installPage)
        })
        
        try! server.start(port: 9090)
        print("Server has started listening")
        
        DispatchQueue.main.async {
            print("Requesting app install")
            
            // having it built-in no matter the version sounds more enjoyable, if you're already taking all the damn effort to do this bullshit then why not have this pop up on 17.x too?
            let safariView = SafariWebView(url: URL(string: "http://127.0.0.1:9090/install")!)
            UIApplication.shared.windows.first?.rootViewController?.present(UIHostingController(rootView: safariView), animated: true, completion: nil)
            /*
            let majoriOSVersion = Int(UIDevice.current.systemVersion.components(separatedBy: ".").first!)!
            if majoriOSVersion >= 18 {
                // iOS 18+ ( idk why this is needed but it seems to fix it for some people )
                let safariView = SafariWebView(url: URL(string: "http://127.0.0.1:9090/install")!)
                UIApplication.shared.windows.first?.rootViewController?.present(UIHostingController(rootView: safariView), animated: true, completion: { cleanUp() })
            } else {
                // iOS 17-
                UIApplication.shared.open(URL(string: installURL)!)
            }
             */
        }
        
        while server.isRunning {
            sleep(1)
        }
        print("Server has stopped")
    }
}

func downgradeAppToVersion(appId: String, versionId: String, ipaTool: IPATool) {
    installAppVersion(appId: appId, versionId: versionId, ipaTool: ipaTool, recordsHistory: true)
}

func restoreLatestAppVersion(appId: String, ipaTool: IPATool) {
    installAppVersion(appId: appId, versionId: "", ipaTool: ipaTool, recordsHistory: false)
}

func promptForVersionId(appId: String, versionIds: [String], ipaTool: IPATool) {
    let isiPad = UIDevice.current.userInterfaceIdiom == .pad
    let alert = UIAlertController(title: "Enter version ID".localized, message: "Select a version to downgrade to".localized, preferredStyle: isiPad ? .alert : .actionSheet)
    for versionId in versionIds {
        alert.addAction(UIAlertAction(title: versionId, style: .default, handler: { _ in
            setDowngradeProgress(0.01, detail: String(format: "Selected version %@".localized, versionId))
            downgradeAppToVersion(appId: appId, versionId: versionId, ipaTool: ipaTool)
        }))
    }
    alert.addAction(UIAlertAction(title: "Cancel".localized, style: .cancel, handler: { _ in
        resetDowngradeProgress()
    }))
    UIApplication.shared.windows.first?.rootViewController?.present(alert, animated: true, completion: nil)
}

func showAlert(title: String, message: String) {
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
    UIApplication.shared.windows.first?.rootViewController?.present(alert, animated: true, completion: nil)
}

func getAllAppVersionIdsFromServer(appId: String, ipaTool: IPATool) {
    let serverURL = "https://apis.bilin.eu.org/history/"
    let url = URL(string: "\(serverURL)\(appId)")!
    let request = URLRequest(url: url)
    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            DispatchQueue.main.async {
                showAlert(title: "Error".localized, message: error.localizedDescription)
                resetDowngradeProgress()
            }
            return
        }
        let json = try! JSONSerialization.jsonObject(with: data!) as! [String: Any]
        let versionIds = json["data"] as! [Dictionary<String, Any>]
        if versionIds.count == 0 {
            DispatchQueue.main.async {
                showAlert(title: "Error".localized, message: "No version IDs error".localized)
                resetDowngradeProgress()
            }
            return
        }
        DispatchQueue.main.async {
            let isiPad = UIDevice.current.userInterfaceIdiom == .pad
            let alert = UIAlertController(title: "Select a version".localized, message: "Select a version to downgrade to".localized, preferredStyle: isiPad ? .alert : .actionSheet)
            for versionId in versionIds {
                alert.addAction(UIAlertAction(title: "\(versionId["bundle_version"]!)", style: .default, handler: { _ in
                    let externalVersionId = "\(versionId["external_identifier"]!)"
                    setDowngradeProgress(0.01, detail: String(format: "Selected version %@".localized, "\(versionId["bundle_version"]!)"))
                    downgradeAppToVersion(appId: appId, versionId: externalVersionId, ipaTool: ipaTool)
                }))
            }
            alert.addAction(UIAlertAction(title: "Cancel".localized, style: .cancel, handler: { _ in
                resetDowngradeProgress()
            }))
            UIApplication.shared.windows.first?.rootViewController?.present(alert, animated: true, completion: nil)
        }
    }
    task.resume()
}

func downgradeApp(appId: String, ipaTool: IPATool) {
    let appData = AppData.shared
    
    setDowngradeProgress(0.01, detail: "Checking available versions".localized)
    let versionIds = ipaTool.getVersionIDList(appId: appId)
    if versionIds.isEmpty {
        print("No version ids were found, aborting...")
        DispatchQueue.main.async {
            Alertinator.shared.alert(title: "Failed to downgrade app!".localized, body: "Downgrade error description".localized)
            appData.isDowngrading = false
            appData.appLink = ""
            appData.applicationStatus = "Ready to Downgrade!".localized
            appData.applicationIcon = "checkmark.circle.fill"
            appData.showsDowngradeProgress = false
        }
        return
    }
    setDowngradeProgress(0.04, detail: "Choose a version".localized)
    
    let isiPad = UIDevice.current.userInterfaceIdiom == .pad
    
    let alert = UIAlertController(title: "Version ID".localized, message: "Manual or Server Description".localized, preferredStyle: isiPad ? .alert : .actionSheet)
    alert.addAction(UIAlertAction(title: "Manual".localized, style: .default, handler: { _ in
        promptForVersionId(appId: appId, versionIds: versionIds, ipaTool: ipaTool)
    }))
    alert.addAction(UIAlertAction(title: "Server".localized, style: .default, handler: { _ in
        getAllAppVersionIdsFromServer(appId: appId, ipaTool: ipaTool)
    }))
    alert.addAction(UIAlertAction(title: "Cancel".localized, style: .cancel, handler: { _ in
        resetDowngradeProgress()
    }))
    UIApplication.shared.windows.first?.rootViewController?.present(alert, animated: true, completion: nil)
}

func setDowngradeProgress(_ progress: Double, detail: String) {
    DispatchQueue.main.async {
        let appData = AppData.shared
        appData.downgradeProgress = min(max(progress, 0), 1)
        appData.downgradeProgressDetail = detail
        appData.showsDowngradeProgress = true
        appData.applicationStatus = detail
        appData.applicationIcon = "showMeProgressPlease"
        appData.applicationIconColor = .secondary
    }
}

func resetDowngradeProgress() {
    DispatchQueue.main.async {
        let appData = AppData.shared
        appData.isDowngrading = false
        appData.downgradeProgress = 0
        appData.downgradeProgressDetail = ""
        appData.showsDowngradeProgress = false
        appData.applicationStatus = "Ready to Downgrade!".localized
        appData.applicationIcon = "checkmark.circle.fill"
        appData.applicationIconColor = .secondary
    }
}

func cleanUp() {
    do {
        // first, delete the temporary ipa file.
        let tempDir = FileManager.default.temporaryDirectory
        let tempIPA = tempDir.appendingPathComponent("app.ipa")
        
        try FileManager.default.removeItem(at: tempIPA)
        // then, nuke the app directory.
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let appFolder = docsURL.appendingPathComponent("app")
        
        try FileManager.default.removeItem(at: appFolder)
    } catch {
        
    }
}
