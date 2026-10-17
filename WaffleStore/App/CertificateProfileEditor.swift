import SwiftUI

struct CertificateProfileEditor: View {
    @EnvironmentObject private var appData: AppData
    @Environment(\.dismiss) private var dismiss

    let certificate: SigningCertificate
    @State private var name: String
    @State private var icon: String
    @State private var errorMessage: String?

    init(certificate: SigningCertificate) {
        self.certificate = certificate
        _name = State(initialValue: certificate.name)
        _icon = State(initialValue: certificate.icon)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Name", text: $name)
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

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit Certificate")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
        }
    }

    private func save() {
        var updated = certificate
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Signing Certificate" : name
        updated.icon = icon
        do {
            try appData.updateSigningCertificate(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
