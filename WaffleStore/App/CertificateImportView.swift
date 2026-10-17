import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CertificateImportView: View {
    @EnvironmentObject private var appData: AppData
    @Environment(\.dismiss) private var dismiss

    @State private var p12URL: URL?
    @State private var provisionURL: URL?
    @State private var password = ""
    @State private var name = ""
    @State private var icon = "signature"
    @State private var importKind: ImportKind = .p12
    @State private var showImporter = false
    @State private var errorMessage: String?

    private enum ImportKind {
        case p12
        case provision
    }

    private var canSave: Bool {
        p12URL != nil && provisionURL != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Name", text: $name)
                    iconPicker
                }

                Section {
                    fileButton("Choose signing certificate (.p12)", selected: p12URL != nil) {
                        importKind = .p12
                        showImporter = true
                    }
                    fileButton("Choose provisioning profile", selected: provisionURL != nil) {
                        importKind = .provision
                        showImporter = true
                    }
                } header: {
                    Text("Signing files")
                } footer: {
                    Text("Import the .p12 certificate and matching .mobileprovision profile used to sign downloaded IPAs.")
                }

                Section("Certificate password") {
                    SecureField("Password (leave blank if none)", text: $password)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Import Signing Certificate")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showImporter) {
                DocumentPicker {
                    if importKind == .p12 {
                        p12URL = $0
                    } else {
                        provisionURL = $0
                    }
                    showImporter = false
                } onCancel: {
                    showImporter = false
                }
            }
        }
    }

    private var iconPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(SigningProfileIcons.all, id: \.self) { candidate in
                    Button {
                        icon = candidate
                    } label: {
                        Image(systemName: candidate)
                            .font(.title2)
                            .frame(width: 42, height: 42)
                            .foregroundStyle(icon == candidate ? Color.accentColor : Color.secondary)
                            .background(icon == candidate ? Color.accentColor.opacity(0.14) : .clear, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func fileButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: selected ? "checkmark.circle.fill" : "doc.badge.plus")
        }
    }

    private func save() {
        guard let p12URL, let provisionURL else { return }
        do {
            try appData.addSigningCertificate(
                p12: p12URL,
                provision: provisionURL,
                password: password,
                name: name,
                icon: icon
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let parent: DocumentPicker

        init(_ parent: DocumentPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                parent.onCancel()
                return
            }
            print("Selected signing file: \(url.lastPathComponent)")
            parent.onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel()
        }
    }
}
