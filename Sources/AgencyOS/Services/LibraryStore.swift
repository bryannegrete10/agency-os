import Foundation

// Owns the install-later library: a JSON file the app reads and writes at
// ~/.agency-os/library.json. Starts empty; add your own source repos from the
// Library tab.
enum LibraryStore {
    static var dirURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agency-os")
    }
    static var fileURL: URL { dirURL.appendingPathComponent("library.json") }

    static func load() -> [LibraryItem] {
        guard let data = try? Data(contentsOf: fileURL),
              let items = try? JSONDecoder().decode([LibraryItem].self, from: data),
              !items.isEmpty else {
            let seed = seedItems()
            save(seed)
            return seed
        }
        return items
    }

    static func save(_ items: [LibraryItem]) {
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // No bundled picks: the public build starts with an empty library so users
    // curate their own. (The private RA build seeds its vetted repos here.)
    private static func seedItems() -> [LibraryItem] { [] }
}
