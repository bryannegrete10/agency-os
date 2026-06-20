import Foundation

// Parses the Agency-OS divisions map (a markdown file at ~/.agency-os/divisions.md)
// into divisions and their skill entries. Each "## <X> Division" header starts a
// division; markdown table rows whose first cell holds a `/invoke` token become
// entries, with the last cell as the purpose.
enum DivisionParser {
    static var mapURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agency-os/divisions.md")
    }

    static func parse(installedFolders: Set<String>) -> [Division] {
        guard let text = try? String(contentsOf: mapURL, encoding: .utf8) else { return [] }

        var divisions: [Division] = []
        var currentName: String?
        var entries: [DivisionEntry] = []
        var seen: Set<String> = []

        func flush() {
            if let name = currentName, !entries.isEmpty {
                divisions.append(Division(name: name, entries: entries))
            }
            entries = []
            seen = []
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("## "), line.contains("Division") {
                flush()
                var name = String(line.dropFirst(3))
                if let range = name.range(of: "Division") { name = String(name[..<range.lowerBound]) }
                currentName = name.trimmingCharacters(in: .whitespaces)
                continue
            }

            guard currentName != nil, line.hasPrefix("|") else { continue }
            let cells = line.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard cells.count >= 2 else { continue }
            if cells.allSatisfy({ $0.allSatisfy { $0 == "-" || $0 == ":" } }) { continue }
            if cells[0].lowercased().contains("invoke via") { continue }

            guard let invoke = firstInvoke(in: cells[0]), !seen.contains(invoke) else { continue }
            seen.insert(invoke)
            let folder = invoke.hasPrefix("/") ? String(invoke.dropFirst()) : invoke
            entries.append(DivisionEntry(
                invoke: invoke,
                purpose: cells.last ?? "",
                installed: installedFolders.contains(folder)
            ))
        }
        flush()
        return divisions
    }

    private static func firstInvoke(in cell: String) -> String? {
        let cleaned = cell.replacingOccurrences(of: "`", with: " ")
        for raw in cleaned.split(whereSeparator: { $0 == " " || $0 == "," }) {
            let token = raw.trimmingCharacters(in: CharacterSet(charactersIn: " ,()"))
            if token.hasPrefix("/"), token.count > 1 { return token }
        }
        return nil
    }
}
