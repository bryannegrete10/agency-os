import Foundation

// Discovers installed skills by walking ~/.claude/skills/ and parsing the YAML
// frontmatter (name + description) at the top of each SKILL.md.
enum SkillScanner {
    static var skillsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/skills")
    }

    static var skillsDisabledURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/skills_disabled")
    }

    static func scan() -> [SkillItem] {
        let items = scanDir(skillsURL, enabled: true) + scanDir(skillsDisabledURL, enabled: false)
        return items.sorted { $0.folder.localizedCaseInsensitiveCompare($1.folder) == .orderedAscending }
    }

    private static func scanDir(_ base: URL, enabled: Bool) -> [SkillItem] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }

        var items: [SkillItem] = []
        for dir in entries {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let skillFile = dir.appendingPathComponent("SKILL.md")
            guard fm.fileExists(atPath: skillFile.path) else { continue }

            let parsed = parseFrontmatter(skillFile, fallback: dir.lastPathComponent)
            items.append(SkillItem(
                id: dir.lastPathComponent,
                name: parsed.name,
                folder: dir.lastPathComponent,
                summary: parsed.summary,
                division: nil,
                path: dir.path,
                enabled: enabled,
                kind: .skill,
                invoke: "/" + parsed.name,
                namespace: nil
            ))
        }
        return items
    }

    private static func parseFrontmatter(_ url: URL, fallback: String) -> (name: String, summary: String) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return (fallback, "") }
        let lines = content.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return (fallback, "") }

        var name = fallback
        var summary = ""
        for line in lines.dropFirst() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t == "---" { break }
            if t.hasPrefix("name:") {
                name = String(t.dropFirst("name:".count)).trimmingCharacters(in: .whitespaces)
            } else if t.hasPrefix("description:") {
                summary = String(t.dropFirst("description:".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return (name.isEmpty ? fallback : name, summary)
    }
}
