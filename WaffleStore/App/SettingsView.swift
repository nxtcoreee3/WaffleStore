import SwiftUI
import PartyUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var appData: AppData
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    
    @AppStorage("autoCleanApp") var autoCleanApp: Bool = true
    @AppStorage("allowEncryptedIPAs") private var allowEncryptedIPAs: Bool = false
    @StateObject private var localizationManager = LocalizationManager.shared
    @State private var showFileImporter = false
    @State private var showCertificateImport = false
    @State private var editingCertificate: SigningCertificate?
    @State private var showRiskyOptionsAlert = false
    
    private var appVersionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: HeaderLabel(text: "About".localized, icon: "info.circle")) {
                    VStack(alignment: .leading, spacing: 10) {
                        AppInfoCell()
                        HStack {
                            Button(action: {
                                openURL(URL(string: "https://discord.com/invite/tweakbreak-1443331342799601666")!)
                            }) {
                                ButtonLabel(text: "Discord".localized, icon: "discord", useImage: true)
                            }
                            .buttonStyle(TranslucentButtonStyle(color: .discord))
                            Button(action: {
                                openURL(URL(string: "https://github.com/nxtcoreee3/WaffleStore")!)
                            }) {
                                ButtonLabel(text: "GitHub".localized, icon: "github", useImage: true)
                            }
                            .buttonStyle(TranslucentButtonStyle(color: .github))
                        }
                        Button(action: {
                            openURL(URL(string: "https://nxtcoreee3.github.io/WaffleStore/")!)
                        }) {
                            ButtonLabel(text: "Website".localized, icon: "globe")
                        }
                        .buttonStyle(TranslucentButtonStyle())
                    }
                }
                
                Section(header: HeaderLabel(text: "Settings".localized, icon: "gearshape")) {
                    Toggle(isOn: $autoCleanApp) {
                        Text("Auto-Clean App".localized)
                        Text("Auto-Clean Description".localized)
                    }
                }

                Section(header: HeaderLabel(text: "Risky options", icon: "exclamationmark.triangle"), footer: Text("These options can produce unusable or unsafe IPAs. Enable only if you understand the consequences.")) {
                    Toggle("Enable Risky Options", isOn: Binding(
                        get: { appData.riskyOptionsEnabled },
                        set: { enabled in
                            if enabled {
                                showRiskyOptionsAlert = true
                            } else {
                                appData.riskyOptionsEnabled = false
                            }
                        }
                    ))
                }

                if appData.riskyOptionsEnabled {
                Section(header: HeaderLabel(text: "Signing", icon: "signature"), footer: Text("Import a matching .p12 certificate and provisioning profile to sign downloaded IPAs and install them.")) {
                    ForEach(appData.signingCertificates) { certificate in
                        HStack(spacing: 10) {
                            Button {
                                appData.selectSigningCertificate(certificate)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: certificate.icon)
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(certificate.name)
                                        if appData.signingCertificate?.id == certificate.id {
                                            Text("Active")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if appData.signingCertificate?.id == certificate.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            Button {
                                editingCertificate = certificate
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                appData.removeSigningCertificate(certificate)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }

                    Button {
                        showCertificateImport = true
                    } label: {
                        Label("Import signing certificate", systemImage: "plus.circle")
                    }
                }

                Section(header: HeaderLabel(text: "Signing overrides", icon: "signature"), footer: Text("A mismatched profile can make an app fail to launch or break extensions, VPNs, keychain access, or app groups.")) {
                    Toggle("Allow mismatched App IDs", isOn: Binding(
                        get: { appData.allowSigningProfileMismatch },
                        set: { enabled in
                            appData.allowSigningProfileMismatch = enabled
                        }
                    ))
                    Text("Use only when you understand the signing risks. Strict validation remains enabled by default.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(header: HeaderLabel(text: "Encrypted downloads", icon: "lock.trianglebadge.exclamationmark"), footer: Text("Encrypted IPAs are retained without decryption. They may not launch and signing them does not decrypt them.")) {
                    Toggle("Keep encrypted IPAs", isOn: $allowEncryptedIPAs)
                }
                }
                
                Section(header: HeaderLabel(text: "Language".localized, icon: "globe"), footer:
                    Button(action: {
                        openURL(URL(string: "https://poeditor.com/join/project/Ofr2qvyudt")!)
                    }) {
                        Text("Translation Thank You".localized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                ) {
                    Picker("Language".localized, selection: $localizationManager.currentLanguage) {
                        ForEach(Language.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                Section(header: HeaderLabel(text: "Data".localized, icon: "loupe"), footer: Text("Storage Warning".localized)) {
                    VStack {
                        Button(action: {
                            cleanUp()
                        }) {
                            ButtonLabel(text: "Clean Documents".localized, icon: "trash")
                        }
                        .buttonStyle(TranslucentButtonStyle())
                        
                        HStack {
                            Button(action: {
                                if let url = DowngradeHistoryStore.exportToJSON() {
                                    presentShareSheet(with: url)
                                }
                            }) {
                                ButtonLabel(text: "Export History".localized, icon: "square.and.arrow.up")
                            }
                            .buttonStyle(TranslucentButtonStyle())
                            
                            Button(action: {
                                showFileImporter = true
                            }) {
                                ButtonLabel(text: "Import History".localized, icon: "square.and.arrow.down")
                            }
                            .buttonStyle(TranslucentButtonStyle())
                        }
                    }
                }
                .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.json]) { result in
                    switch result {
                    case .success(let url):
                        if url.startAccessingSecurityScopedResource() {
                            defer { url.stopAccessingSecurityScopedResource() }
                            if let importedHistory = DowngradeHistoryStore.importFromJSON(at: url) {
                                appData.downgradeHistory = importedHistory
                            }
                        }
                    case .failure(let error):
                        print("Failed to import history: \(error)")
                    }
                }
                Section(header: HeaderLabel(text: "Credits".localized, icon: "star")) {
                    LinkCreditCell(image: Image("nxtcoreee3"), name: "nxtcoreee3", description: "Developer of WaffleStore.".localized, url: "https://github.com/nxtcoreee3")
                    LinkCreditCell(image: Image("mineek"), name: "mineek", description: "Original creator of MuffinStore Jailed.".localized, url: "https://github.com/mineek")
                    LinkCreditCell(image: Image("lunginspector"), name: "lunginspector", description: "Original creator of PancakeStore.".localized, url: "https://github.com/lunginspector")
                    LinkCreditCell(image: Image("skadz"), name: "skadz", description: "Original creator of PancakeStore.".localized, url: "https://github.com/skadz108")
                    LinkCreditCell(image: Image("Majd"), name: "Majd Alfhaily", description: "backend fix via ipatool", url: "https://github.com/majd/ipatool")
                    LinkCreditCell(image: Image("zhlynn"), name: "zhlynn", description: "Zsign signing backend", url: "https://github.com/zhlynn/zsign")
                }
            }
            .navigationTitle("Settings".localized)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                    }
                }
            }
            .sheet(isPresented: $showCertificateImport) {
                CertificateImportView()
                    .environmentObject(appData)
            }
            .sheet(item: $editingCertificate) { certificate in
                CertificateProfileEditor(certificate: certificate)
                    .environmentObject(appData)
            }
            .alert("Risky options", isPresented: $showRiskyOptionsAlert) {
                Button("Proceed", role: .destructive) {
                    appData.riskyOptionsEnabled = true
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("These options can keep encrypted IPAs or sign an app with a mismatched profile. The result may not install, launch, or preserve VPN, extension, keychain, or app-group functionality. Are you sure you want to continue?")
            }
        }
    }
}
