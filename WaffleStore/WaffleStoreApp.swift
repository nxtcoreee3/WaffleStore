//
//  WaffleStoreApp.swift
//  WaffleStore
//
//  Created by nxtcoreee3 on 6/20/26.
//

import SwiftUI
import UniformTypeIdentifiers

var pipe = Pipe()
var sema = DispatchSemaphore(value: 0)
var weOnADebugBuild: Bool = false

@main
struct WaffleStoreApp: App {
    @StateObject private var appData = AppData.shared
    @StateObject private var localizationManager = LocalizationManager.shared
    
    @AppStorage("autoCleanApp") var autoCleanApp: Bool = true
    
    init() {
        setvbuf(stdout, nil, _IONBF, 0)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        #if DEBUG
        weOnADebugBuild = true
        #else
        weOnADebugBuild = false
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appData)
                .environment(\.locale, .init(identifier: localizationManager.currentLanguage.rawValue))
                .onAppear {
                    if autoCleanApp {
                        cleanUp()
                    }
                }
                .onOpenURL { schemedURL in
                    let rawURL = schemedURL.absoluteString.replacingOccurrences(of: "wafflestore:", with: "")
                    if let appLink = rawURL.removingPercentEncoding {
                        appData.appLink = appLink
                        print("Successfully received app link! \(appLink)")
                    }
                }
        }
    }
}

extension String: @retroactive Error {}
