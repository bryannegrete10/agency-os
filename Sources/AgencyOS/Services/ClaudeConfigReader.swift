import Foundation

// Reads MCP server declarations from the Claude config files on disk.
// Read-only in M1; write-back (activate/deactivate) lands in a later milestone.
enum ClaudeConfigReader {
    static var homeURL: URL { FileManager.default.homeDirectoryForCurrentUser }

    static func loadClaudeCodeServers() -> [MCPServer] {
        let url = homeURL.appendingPathComponent(".claude.json")
        return servers(in: url, source: .claudeCode, idPrefix: "cc")
    }

    static func loadClaudeDesktopServers() -> [MCPServer] {
        let url = homeURL.appendingPathComponent(
            "Library/Application Support/Claude/claude_desktop_config.json"
        )
        return servers(in: url, source: .claudeDesktop, idPrefix: "desktop")
    }

    private static func servers(in url: URL, source: AgentTarget, idPrefix: String) -> [MCPServer] {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

        let activeDict = root["mcpServers"] as? [String: Any] ?? [:]
        let disabledDict = root["mcpServers_disabled"] as? [String: Any] ?? [:]

        let all = activeDict.map { build($0, $1, source: source, idPrefix: idPrefix, active: true) }
            + disabledDict.map { build($0, $1, source: source, idPrefix: idPrefix, active: false) }
        return all.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func build(_ name: String, _ value: Any, source: AgentTarget,
                              idPrefix: String, active: Bool) -> MCPServer {
        let dict = value as? [String: Any] ?? [:]
        return MCPServer(
            id: "\(idPrefix):\(name)",
            name: name,
            command: commandString(from: dict),
            source: source,
            active: active,
            category: dict["type"] as? String
        )
    }

    private static func commandString(from dict: [String: Any]) -> String {
        if let url = dict["url"] as? String, (dict["command"] as? String) == nil {
            return url
        }
        let cmd = dict["command"] as? String ?? ""
        let args = (dict["args"] as? [String])?.joined(separator: " ") ?? ""
        return [cmd, args].filter { !$0.isEmpty }.joined(separator: " ")
    }
}
