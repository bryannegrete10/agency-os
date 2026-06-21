import Foundation

// Discovers slash commands and skills provided by installed Claude Code plugins.
// Reads ~/.claude/plugins/installed_plugins.json, then for each installed plugin
// scans its installPath/commands/*.md and installPath/skills/*/SKILL.md. This is
// why /codex:review (a plugin command, not a ~/.claude/skills skill) now shows.
enum PluginScanner {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    static var manifestURL: URL { home.appendingPathComponent(".claude/plugins/installed_plugins.json") }

    static func scan() -> [SkillItem] {
        guard let data = try? Data(contentsOf: manifestURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plugins = root["plugins"] as? [String: Any] else { return [] }

        var items: [SkillItem] = []
        for (key, value) in plugins {
            let plugin = key.split(separator: "@").first.map(String.init) ?? key
            guard let entries = value as? [[String: Any]],
                  let installPath = entries.first?["installPath"] as? String else { continue }
            let base = URL(fileURLWithPath: installPath)
            items += commands(in: base.appendingPathComponent("commands"), plugin: plugin)
            items += pluginSkills(in: base.appendingPathComponent("skills"), plugin: plugin)
        }
        return items
    }

    private static func commands(in dir: URL, plugin: String) -> [SkillItem] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "md" }.map { file in
            let base = file.deletingPathExtension().lastPathComponent
            return SkillItem(
                id: "cmd:\(plugin):\(base)", name: base, folder: plugin,
                summary: frontmatterDescription(file), division: nil, path: file.path,
                enabled: true, kind: .command, invoke: "/\(plugin):\(base)", namespace: plugin
            )
        }
    }

    private static func pluginSkills(in dir: URL, plugin: String) -> [SkillItem] {
        let fm = FileManager.default
        guard let subdirs = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var out: [SkillItem] = []
        for sub in subdirs {
            let skillFile = sub.appendingPathComponent("SKILL.md")
            guard fm.fileExists(atPath: skillFile.path) else { continue }
            let name = sub.lastPathComponent
            out.append(SkillItem(
                id: "pskill:\(plugin):\(name)", name: name, folder: plugin,
                summary: frontmatterDescription(skillFile), division: nil, path: sub.path,
                enabled: true, kind: .pluginSkill, invoke: "/\(plugin):\(name)", namespace: plugin
            ))
        }
        return out
    }

    private static func frontmatterDescription(_ url: URL) -> String {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        let lines = content.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return "" }
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" { break }
            if trimmed.hasPrefix("description:") {
                return String(trimmed.dropFirst("description:".count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: " '\""))
            }
        }
        return ""
    }
}
