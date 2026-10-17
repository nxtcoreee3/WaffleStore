import SwiftUI
import PartyUI
import UIKit

struct ContentView: View {
    @State private var hasShownWelcome: Bool = false
    @State private var showLogs: Bool = true
    @State private var showSettingsView: Bool = false
    @State private var showSearchView: Bool = false
    @State private var showHistoryView: Bool = false
    @State private var showFavouritesView: Bool = false
    
    @EnvironmentObject var appData: AppData
    @StateObject private var localizationManager = LocalizationManager.shared
    
    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad {
                NavigationSplitView(sidebar: {
                    List {
                        LogsSection
                        NavigationButtons()
                    }
                    .navigationTitle("WaffleStore")
                }) {
                    List {
                        if !appData.isAuthenticated {
                            LoginSection
                        } else {
                            if appData.isDowngrading {
                                AppInfoSection
                            } else {
                                InputAppSection
                            }
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            AppMenu(showHistoryView: $showHistoryView, showFavouritesView: $showFavouritesView)
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(action: {
                                showSettingsView.toggle()
                            }) {
                                Image(systemName: "gear")
                            }
                        }
                    }
                }
            } else {
                NavigationStack {
                    List {
                        LogsSection
                        if !appData.isAuthenticated {
                            LoginSection
                        } else {
                            if appData.isDowngrading {
                                AppInfoSection
                            } else {
                                InputAppSection
                            }
                        }
                    }
                    .navigationTitle("WaffleStore")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            AppMenu(showHistoryView: $showHistoryView, showFavouritesView: $showFavouritesView)
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(action: {
                                showSettingsView.toggle()
                            }) {
                                Image(systemName: "gear")
                            }
                        }
                    }
                    .safeAreaInset(edge: .bottom) {
                        NavigationButtons()
                            .modifier(OverlayBackground())
                    }
                }
            }
        }
        .sheet(isPresented: $showSettingsView) {
            SettingsView()
        }
        .sheet(isPresented: $showSearchView) {
            AppSearchView()
        }
        .sheet(isPresented: $showHistoryView) {
            DowngradeHistoryView()
        }
        .sheet(isPresented: $showFavouritesView) {
            FavouritesView()
        }
        .onAppear {
            appData.restoreStoreAccount()
        }
    }
    
    private var LogsSection: some View {
        Section(header: HeaderLabel(text: "Logs".localized, icon: "terminal"), footer: Text("Originally created by mineek and jailbreak.party. Further improvements and maintenance by nxtcoreee3. Backend powered by ipatool.".localized)) {
            VStack {
                TerminalHeader(text: appData.applicationStatus, icon: "checkmark.circle.fill", color: .green)
                if appData.showsDowngradeProgress {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: appData.downgradeProgress)
                        HStack {
                            Text(appData.downgradeProgressDetail)
                            Spacer()
                            Text("\(Int(appData.downgradeProgress * 100))%")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 2)
                }
                LogView()
                    .modifier(TerminalPlatter())
            }
        }
    }
    
    private var LoginSection: some View {
        Group {
            Section(header: HeaderLabel(text: "Login".localized, icon: "icloud"), footer: Text("")) {
                VStack {
                    TextField("Apple ID".localized, text: $appData.appleId)
                        .modifier(TextFieldBackground())
                        .disabled(appData.hasSent2FACode)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    
                    HStack {
                        if appData.showPassword {
                            TextField("Password".localized, text: $appData.password)
                                .modifier(TextFieldBackground())
                                .disabled(appData.hasSent2FACode)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        } else {
                            SecureField("Password".localized, text: $appData.password)
                                .modifier(TextFieldBackground())
                                .disabled(appData.hasSent2FACode)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        
                        Button(action: {
                            appData.showPassword.toggle()
                        }) {
                            Image(systemName: appData.showPassword ? "eye" : "eye.slash")
                                .frame(width: 22, height: 22, alignment: .center)
                        }
                        .buttonStyle(TranslucentButtonStyle(useFullWidth: false))
                    }
                }
            }
            
            if appData.hasSent2FACode {
                Section(header: HeaderLabel(text: "Verification Code".localized, icon: "key.viewfinder")) {
                    TextField("2FA Code".localized, text: $appData.code)
                        .modifier(TextFieldBackground())
                        .keyboardType(.numberPad)
                }
            }
        }
    }
    
    private var InputAppSection: some View {
        Section(header: HeaderLabel(text: "Downgrade App".localized, icon: "arrow.down.app"), footer: Text("To downgrade an app, it must have been purchased on your account at some point in the past (when the app has a cloud icon next to it). The apps now need some sort of signing to work. Either export the IPAs and sign it yourself or import your signing certificates in Settings.".localized)) {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    TextField("App Store Link".localized, text: $appData.appLink)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if !appData.appLink.isEmpty {
                        Button {
                            appData.appLink = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Clear app link")
                    }
                }
                .modifier(TextFieldBackground())

                Button(action: {
                    Haptic.shared.play(.soft)
                    showSearchView.toggle()
                }) {
                    ButtonLabel(text: "Search App Store".localized, icon: "magnifyingglass")
                }
                .buttonStyle(TranslucentButtonStyle())
            }
        }
    }
    
    private var AppInfoSection: some View {
        Section(header: HeaderLabel(text: "App Info".localized, icon: "info.circle")) {
            ItemInfoCell(label: "App Link".localized, icon: "link", text: appData.appLink)
            ItemInfoCell(label: "App Bundle ID".localized, icon: "shippingbox", text: appData.appBundleID)

            ItemInfoCell(label: "Target App Version".localized, icon: "arrow.down.app", text: appData.appVersion)
        }
    }
    
}

struct AppMenu: View {
    @EnvironmentObject var appData: AppData
    @Binding var showHistoryView: Bool
    @Binding var showFavouritesView: Bool
    
    var body: some View {
        Menu {
            Button(action: {
                showFavouritesView.toggle()
            }) {
                Label("Favourites".localized, systemImage: "star.fill")
            }
            .disabled(!appData.isAuthenticated)
            
            Button(action: {
                showHistoryView.toggle()
            }) {
                Label("Downgrade History".localized, systemImage: "clock.arrow.circlepath")
            }
            .disabled(!appData.isAuthenticated)
            
            Button(action: {
                let tempDir = FileManager.default.temporaryDirectory
                let tempIPAURL = tempDir.appendingPathComponent("app.ipa")
                presentShareSheet(with: appData.downloadedIPAURL ?? tempIPAURL)
            }) {
                Label("Export IPA".localized, systemImage: "arrow.up.doc")
            }
            .disabled(!appData.hasAppBeenServed)
            
            Button(action: {
                Haptic.shared.play(.heavy)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    appData.logoutStoreAccount()
                }
            }) {
                ButtonLabel(text: "Log Out".localized, icon: "arrow.right")
            }
            .disabled(!appData.isAuthenticated)
        } label: {
            Image(systemName: "line.horizontal.3")
        }
    }
}

struct DowngradeHistoryView: View {
    @EnvironmentObject var appData: AppData
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: HeaderLabel(text: "Downgrade History".localized, icon: "clock.arrow.circlepath")) {
                    if appData.downgradeHistory.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No Downgrades Yet".localized)
                                .font(.headline)
                            Text("No Downgrades Description".localized)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(appData.downgradeHistory) { entry in
                            DowngradeHistoryCell(entry: entry)
                        }
                    }
                }
            }
            .navigationTitle("History".localized)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }
}

struct DowngradeHistoryCell: View {
    let entry: DowngradeHistoryEntry
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: "arrow.down.app")
                    .frame(width: 22, height: 22, alignment: .center)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.bundleId)
                        .font(.headline)
                    Text("Version \(entry.installedVersion)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(Self.dateFormatter.string(from: entry.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(entry.dataNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct ItemInfoCell: View {
    var label: String
    var icon: String
    var text: String
    
    var body: some View {
        LabeledContent {
            if text.isEmpty {
                ProgressView()
            } else {
                Text(text)
            }
        } label: {
            HStack {
                Image(systemName: icon)
                    .frame(width: 22, height: 22, alignment: .center)
                Text(label)
            }
        }
        .contextMenu {
            Button(action: {
                UIPasteboard.general.string = text
            }) {
                Label("Copy Value".localized, systemImage: "character.cursor.ibeam")
            }
        }
    }
}

struct SidebarToggleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content
                .toolbar(removing: .sidebarToggle)
        } else {
            content
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppData.shared)
}
