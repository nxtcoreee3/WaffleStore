import SwiftUI
import PartyUI

struct FavouritesView: View {
    @EnvironmentObject var appData: AppData
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: HeaderLabel(text: "Favourites".localized, icon: "star.fill")) {
                    if appData.favourites.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No Favourites Yet".localized)
                                .font(.headline)
                            Text("No Favourites Description".localized)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(appData.favourites) { favourite in
                            FavouriteAppCell(favourite: favourite)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    Haptic.shared.play(.soft)
                                    appData.appLink = favourite.appLink
                                    dismiss()
                                }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let favourite = appData.favourites[index]
                                appData.favourites = FavouritesStore.remove(favourite)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Favourites".localized)
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

struct FavouriteAppCell: View {
    let favourite: FavouriteApp
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: "star.fill")
                    .frame(width: 22, height: 22, alignment: .center)
                    .foregroundStyle(.mint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(favourite.appName)
                        .font(.headline)
                    Text(favourite.bundleId)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(Self.dateFormatter.string(from: favourite.dateAdded))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    FavouritesView()
        .environmentObject(AppData.shared)
}
