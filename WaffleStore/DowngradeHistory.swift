//
//  DowngradeHistory.swift
//  WaffleStore
//
//  Created by nxtcoreee3 on 6/20/26.
//

import Foundation

struct DowngradeHistoryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let appId: String
    let appLink: String
    let bundleId: String
    let installedVersion: String
    let externalVersionId: String
    let date: Date
    let keptAppData: Bool
    
    var dataNote: String {
        keptAppData ? "App data kept".localized : "App data cleaned".localized
    }
}

enum DowngradeHistoryStore {
    private static let storageKey = "downgradeHistory"
    
    static func load() -> [DowngradeHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return []
        }
        
        do {
            return try JSONDecoder().decode([DowngradeHistoryEntry].self, from: data)
                .sorted { $0.date > $1.date }
        } catch {
            print("Failed to load downgrade history: \(error)")
            return []
        }
    }
    
    static func append(_ entry: DowngradeHistoryEntry) -> [DowngradeHistoryEntry] {
        var history = load()
        history.insert(entry, at: 0)
        save(history)
        return history
    }
    
    private static func save(_ history: [DowngradeHistoryEntry]) {
        do {
            let data = try JSONEncoder().encode(history)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("Failed to save downgrade history: \(error)")
        }
    }
    
    static func exportToJSON() -> URL? {
        let history = load()
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(history)
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("downgrade_history.json")
            try data.write(to: tempURL)
            return tempURL
        } catch {
            print("Failed to export history: \(error)")
            return nil
        }
    }
    
    static func importFromJSON(at url: URL) -> [DowngradeHistoryEntry]? {
        do {
            let data = try Data(contentsOf: url)
            let history = try JSONDecoder().decode([DowngradeHistoryEntry].self, from: data)
            save(history)
            return history
        } catch {
            print("Failed to import history: \(error)")
            return nil
        }
    }
    
    static var keepsAppDataForNextInstall: Bool {
        if UserDefaults.standard.object(forKey: "autoCleanApp") == nil {
            return false
        }
        
        return !UserDefaults.standard.bool(forKey: "autoCleanApp")
    }
}
