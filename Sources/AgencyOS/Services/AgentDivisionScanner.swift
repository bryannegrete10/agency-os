import Foundation

// Reads the global agent roster at ~/.claude/agents/divisions/<division>/*.md.
// Each subfolder is a division (engineering, testing, design, ...); each .md is
// an agent with name + description frontmatter. Surfaces them in the Divisions
// tab alongside the skill-map divisions (this is why engineering = "development"
// and testing = "code quality" now appear).
enum AgentDivisionScanner {
    static var base: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/agents/divisions")
    }

    static func scan() -> [Division] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }

        var divisions: [Division] = []
        for dir in dirs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue,
                  let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }

            let entries = files
                .filter { $0.pathExtension == "md" }
                .compactMap { file -> DivisionEntry? in
                    let parsed = parseFrontmatter(file)
                    guard let name = parsed.name else { return nil }
                    return DivisionEntry(invoke: name, purpose: parsed.description, installed: true)
                }
                .sorted { $0.invoke.localizedCaseInsensitiveCompare($1.invoke) == .orderedAscending }

            guard !entries.isEmpty else { continue }
            divisions.append(Division(name: prettify(dir.lastPathComponent), entries: entries, kind: .agents))
        }
        return divisions.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func prettify(_ slug: String) -> String {
        // The agent roster stores these on disk as "engineering" and "testing",
        // but Agency-OS surfaces them under the names the team uses.
        switch slug {
        case "engineering": return "Development"
        case "testing": return "Code Quality"
        default:
            return slug.split(separator: "-")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
    }

    private static func parseFrontmatter(_ url: URL) -> (name: String?, description: String) {
        guard let content = try? String(contentsOf: url, encoding: .utf8), content.hasPrefix("---") else {
            return (nil, "")
        }
        var name: String?
        var description = ""
        for line in content.components(separatedBy: .newlines).dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" { break }
            if trimmed.hasPrefix("name:") {
                name = String(trimmed.dropFirst("name:".count)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("description:") {
                description = String(trimmed.dropFirst("description:".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return (name, description)
    }
}
