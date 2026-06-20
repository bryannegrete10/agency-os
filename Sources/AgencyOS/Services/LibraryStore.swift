import Foundation

// Owns the install-later library: a JSON file the app reads and writes at
// ~/.agency-os/library.json. Seeds from the design-skill repos we vetted and
// installed, plus one wishlist example, on first run.
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

    private static func seedItems() -> [LibraryItem] {
        [
            LibraryItem(repo: "Leonxlnx/taste-skill", stars: "45.9k", license: "MIT",
                        link: "https://github.com/Leonxlnx/taste-skill", installed: true,
                        note: "Flagship anti-slop taste skill + variants (gpt, stitch, minimalist, brutalist)"),
            LibraryItem(repo: "ibelick/ui-skills", stars: "2.9k", license: "MIT",
                        link: "https://github.com/ibelick/ui-skills", installed: true,
                        note: "baseline-ui: mechanical deslop / polish pass (Tailwind + motion/react)"),
            LibraryItem(repo: "pbakaus/impeccable", stars: "n/a", license: "Apache-2.0",
                        link: "https://github.com/pbakaus/impeccable", installed: true,
                        note: "Opinionated design framework, 23 subcommands"),
            LibraryItem(repo: "emilkowalski/skill", stars: "n/a", license: "n/a",
                        link: "https://github.com/emilkowalski/skill", installed: true,
                        note: "Emil Kowalski UI polish philosophy"),
            LibraryItem(repo: "h3nryprod01/design-taste", stars: "n/a", license: "n/a",
                        link: "https://github.com/h3nryprod01/design-taste", installed: false,
                        note: "Merged synthesis of emil + impeccable + taste-skill; alternative to running them separately",
                        installURL: "https://raw.githubusercontent.com/h3nryprod01/design-taste/main/SKILL.md",
                        installFolder: "design-taste")
        ]
    }
}
