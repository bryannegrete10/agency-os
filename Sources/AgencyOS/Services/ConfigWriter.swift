import Foundation

// The only component that mutates on-disk state. Every operation is reversible:
//  - Skills toggle by moving the folder between ~/.claude/skills and
//    ~/.claude/skills_disabled (no data loss, just a move).
//  - MCP servers toggle by moving the entry between "mcpServers" and
//    "mcpServers_disabled" inside the agent's JSON config. The file is copied to
//    a timestamped .bak first, then written atomically and re-validated; if the
//    result does not parse as JSON, the backup is restored.
// Codex's config.toml is intentionally not written here (TOML round-tripping is
// lossy); callers expose a "reveal config" action for it instead.
enum ConfigWriter {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    // MARK: - Skills

    @discardableResult
    static func setSkillEnabled(folder: String, enabled: Bool) -> Bool {
        let fm = FileManager.default
        let from = (enabled ? SkillScanner.skillsDisabledURL : SkillScanner.skillsURL)
            .appendingPathComponent(folder)
        let toDir = enabled ? SkillScanner.skillsURL : SkillScanner.skillsDisabledURL
        let to = toDir.appendingPathComponent(folder)

        guard fm.fileExists(atPath: from.path) else { return false }
        try? fm.createDirectory(at: toDir, withIntermediateDirectories: true)
        if fm.fileExists(atPath: to.path) { return false }
        do { try fm.moveItem(at: from, to: to); return true } catch { return false }
    }

    // Telemetry-free install: download a single SKILL.md straight from a raw
    // GitHub URL into ~/.claude/skills/<folder>/SKILL.md. No vendor installer.
    @discardableResult
    static func installSkill(from urlString: String, folder: String) -> Bool {
        guard let url = URL(string: urlString),
              let data = try? Data(contentsOf: url), !data.isEmpty else { return false }
        let dir = SkillScanner.skillsURL.appendingPathComponent(folder)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: dir.appendingPathComponent("SKILL.md"), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    // MARK: - MCP servers (JSON agents only)

    static func canWrite(_ agent: AgentTarget) -> Bool { jsonURL(for: agent) != nil }

    static func jsonURL(for agent: AgentTarget) -> URL? {
        switch agent {
        case .claudeCode: return home.appendingPathComponent(".claude.json")
        case .claudeDesktop:
            return home.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
        case .antigravity: return home.appendingPathComponent(".gemini/config/mcp_config.json")
        case .codex: return nil
        }
    }

    @discardableResult
    static func setServerEnabled(agent: AgentTarget, name: String, enabled: Bool) -> Bool {
        guard let url = jsonURL(for: agent),
              let data = try? Data(contentsOf: url), !data.isEmpty,
              var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }

        var active = root["mcpServers"] as? [String: Any] ?? [:]
        var disabled = root["mcpServers_disabled"] as? [String: Any] ?? [:]

        if enabled {
            guard let entry = disabled[name] else { return false }
            disabled[name] = nil
            active[name] = entry
        } else {
            guard let entry = active[name] else { return false }
            active[name] = nil
            disabled[name] = entry
        }
        root["mcpServers"] = active
        root["mcpServers_disabled"] = disabled

        guard let backup = makeBackup(url),
              let out = try? JSONSerialization.data(withJSONObject: root,
                                                    options: [.prettyPrinted, .sortedKeys]) else { return false }
        do {
            try out.write(to: url, options: .atomic)
        } catch {
            return false
        }

        // Validate the written file; restore the backup if it is not valid JSON.
        if let check = try? Data(contentsOf: url),
           (try? JSONSerialization.jsonObject(with: check)) != nil {
            return true
        }
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.copyItem(at: backup, to: url)
        return false
    }

    private static func makeBackup(_ url: URL) -> URL? {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = url.appendingPathExtension("bak-\(stamp)")
        do {
            if FileManager.default.fileExists(atPath: backup.path) {
                try FileManager.default.removeItem(at: backup)
            }
            try FileManager.default.copyItem(at: url, to: backup)
            return backup
        } catch {
            return nil
        }
    }
}
