//
//  Favourites.swift
//  WaffleStore
//
//  Created by nxtcoreee3 on 6/27/26.
//

import Foundation

struct FavouriteApp: Identifiable, Codable, Equatable {
    let id: UUID
    let appLink: String
    let bundleId: String
    let appName: String
    let dateAdded: Date
    
    init(appLink: String, bundleId: String, appName: String) {
        self.id = UUID()
        self.appLink = appLink
        self.bundleId = bundleId
        self.appName = appName
        self.dateAdded = Date()
    }
}

enum FavouritesStore {
    private static let storageKey = "favouriteApps"
    
    static func load() -> [FavouriteApp] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return []
        }
        
        do {
            return try JSONDecoder().decode([FavouriteApp].self, from: data)
                .sorted { $0.dateAdded > $1.dateAdded }
        } catch {
            print("Failed to load favourites: \(error)")
            return []
        }
    }
    
    static func add(_ app: FavouriteApp) -> [FavouriteApp] {
        var favourites = load()
        if !favourites.contains(where: { $0.bundleId == app.bundleId }) {
            favourites.insert(app, at: 0)
            save(favourites)
        }
        return favourites
    }
    
    static func remove(_ app: FavouriteApp) -> [FavouriteApp] {
        var favourites = load()
        favourites.removeAll { $0.id == app.id }
        save(favourites)
        return favourites
    }
    
    static func isFavourited(bundleId: String) -> Bool {
        let favourites = load()
        return favourites.contains { $0.bundleId == bundleId }
    }
    
    private static func save(_ favourites: [FavouriteApp]) {
        do {
            let data = try JSONEncoder().encode(favourites)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("Failed to save favourites: \(error)")
        }
    }
}
