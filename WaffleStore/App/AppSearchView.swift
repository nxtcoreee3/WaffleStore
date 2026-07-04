import SwiftUI
import PartyUI

struct ITunesSearchResponse: Codable {
    let resultCount: Int
    let results: [ITunesApp]
}

struct ITunesApp: Codable, Identifiable {
    var id: Int { trackId }
    let trackId: Int
    let trackName: String
    let trackViewUrl: String
    let artworkUrl100: String
    let artistName: String
    let primaryGenreName: String?
}

struct AppSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appData: AppData
    
    @State private var query: String = ""
    @State private var results: [ITunesApp] = []
    @State private var isSearching: Bool = false
    @State private var searchTask: Task<Void, Never>? = nil
    
    var body: some View {
        NavigationStack {
            VStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search apps...".localized, text: $query)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: query) { newValue in
                            triggerSearch(for: newValue)
                        }
                    if !query.isEmpty {
                        Button(action: { query = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .modifier(TextFieldBackground())
                .padding(.horizontal)
                .padding(.top)
                
                if isSearching {
                    Spacer()
                    ProgressView("Searching App Store...".localized)
                    Spacer()
                } else if results.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: query.isEmpty ? "sparkles" : "exclamationmark.magnifyingglass")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text(query.isEmpty ? "Type to search apps".localized : "No apps found".localized)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    List(results) { app in
                        Button(action: {
                            appData.appLink = app.trackViewUrl
                            Haptic.shared.play(.light)
                            dismiss()
                        }) {
                            HStack(spacing: 12) {
                                AsyncImage(url: URL(string: app.artworkUrl100)) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                } placeholder: {
                                    Color.gray.opacity(0.2)
                                }
                                .frame(width: 50, height: 50)
                                .cornerRadius(10)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(app.trackName)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Text(app.artistName)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                    if let genre = app.primaryGenreName {
                                        Text(genre)
                                            .font(.caption)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.secondary.opacity(0.15))
                                            .cornerRadius(4)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .font(.title3)
                                    .foregroundColor(.accentColor)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Search App Store".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel".localized) {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func triggerSearch(for term: String) {
        searchTask?.cancel()
        
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            return
        }
        
        isSearching = true
        
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            
            guard let encodedTerm = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "https://itunes.apple.com/search?term=\(encodedTerm)&entity=software&limit=25") else {
                isSearching = false
                return
            }
            
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if Task.isCancelled { return }
                
                let response = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
                
                await MainActor.run {
                    self.results = response.results
                    self.isSearching = false
                }
            } catch {
                print("Search error: \(error)")
                await MainActor.run {
                    self.isSearching = false
                }
            }
        }
    }
}
