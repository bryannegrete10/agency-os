import Foundation

// Adds an MCP server entry to a chosen agent's config, backup-first. JSON agents
// (Claude Code, Claude Desktop, Antigravity) get a {command,args} entry under
// mcpServers; Codex gets an appended [mcp_servers.<name>] TOML block. This is how
// API/MCP-server repos (e.g. firecrawl) install, vs skill repos that ship SKILL.md.
enum ServerInstaller {
    static func add(agent: AgentTarget, name: String, command: String, args: [String]) -> Bool {
        agent == .codex
            ? addTOML(name: name, command: command, args: args)
            : addJSON(agent: agent, name: name, command: command, args: args)
    }

    private static func addJSON(agent: AgentTarget, name: String, command: String, args: [String]) -> Bool {
        guard let url = ConfigWriter.jsonURL(for: agent) else { return false }

        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: url), !data.isEmpty,
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = parsed
        }
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        guard servers[name] == nil else { return false }   // don't clobber an existing server
        servers[name] = ["command": command, "args": args]
        root["mcpServers"] = servers

        if FileManager.default.fileExists(atPath: url.path) { _ = ConfigWriter.makeBackup(url) }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        guard let out = try? JSONSerialization.data(withJSONObject: root,
                                                    options: [.prettyPrinted, .sortedKeys]) else { return false }
        do { try out.write(to: url, options: .atomic) } catch { return false }

        // Validate; corruption means failure.
        if let check = try? Data(contentsOf: url),
           (try? JSONSerialization.jsonObject(with: check)) != nil { return true }
        return false
    }

    private static func addTOML(name: String, command: String, args: [String]) -> Bool {
        let url = ConfigWriter.codexURL
        guard var text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        guard !text.contains("[mcp_servers.\(name)]"),
              !text.contains("[mcp_servers_disabled.\(name)]") else { return false }

        let argsToml = "[" + args.map { "\"\($0)\"" }.joined(separator: ", ") + "]"
        let block = "\n[mcp_servers.\(name)]\ncommand = \"\(command)\"\nargs = \(argsToml)\n"

        _ = ConfigWriter.makeBackup(url)
        text += block
        do { try text.write(to: url, atomically: true, encoding: .utf8); return true } catch { return false }
    }
}
