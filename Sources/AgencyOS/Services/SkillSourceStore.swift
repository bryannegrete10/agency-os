import Foundation

// Owns the skill provenance manifest at ~/.agency-os/skills.json: for each
// installed skill folder, where it came from and how to update it. Update
// commands live ONLY here (seeded by the known registry below or recorded by our
// own installer) and never come from scanned skill content; SkillUpdater also
// whitelists the executable. This is the registry the update-checker consumes.
//
// PUBLIC build note: the registry() seed is Bryan's personal CLI-installed picks.
// Mirror the LibraryStore.seedItems() / DivisionParser.mapURL divergence -- the
// public build should ship an empty registry().
enum SkillSourceStore {
    static var dirURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agency-os")
    }
    static var fileURL: URL { dirURL.appendingPathComponent("skills.json") }

    // Public build ships an empty registry: known-source entries are personal
    // picks. Users add their own provenance to ~/.agency-os/skills.json. (The
    // private build seeds this with vetted vendor-CLI skills.)
    static func registry() -> [SkillSource] { [] }

    // Loads the manifest keyed by folder, merging in any registry seeds that are
    // not already recorded (never clobbering an existing/user record).
    static func load() -> [String: SkillSource] {
        var map: [String: SkillSource] = [:]
        if let data = try? Data(contentsOf: fileURL),
           let items = try? JSONDecoder().decode([SkillSource].self, from: data) {
            for item in items { map[item.folder] = item }
        }
        var changed = false
        for seed in registry() where map[seed.folder] == nil {
            map[seed.folder] = seed
            changed = true
        }
        if changed { save(Array(map.values)) }
        return map
    }

    static func save(_ items: [SkillSource]) {
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        let sorted = items.sorted { $0.folder.localizedCaseInsensitiveCompare($1.folder) == .orderedAscending }
        if let data = try? JSONEncoder().encode(sorted) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    static func upsert(_ source: SkillSource) {
        var map = load()
        map[source.folder] = source
        save(Array(map.values))
    }

    static func setInstalledVersion(folder: String, version: String) {
        var map = load()
        guard var source = map[folder] else { return }
        source.installedVersion = version
        map[folder] = source
        save(Array(map.values))
    }
}
