import Foundation

// Reads MCP servers for Antigravity (Google's agentic IDE), which is Gemini-based
// and stores its MCP config at ~/.gemini/config/mcp_config.json. The file may be
// empty (0 bytes) when nothing is wired yet, which is handled as an empty list.
enum AntigravityConfigReader {
    static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/config/mcp_config.json")
    }

    static func loadServers() -> [MCPServer] {
        guard let data = try? Data(contentsOf: configURL), !data.isEmpty,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

        let servers = (root["mcpServers"] as? [String: Any])
            ?? (root["mcp_servers"] as? [String: Any])
            ?? [:]

        return servers.map { name, value in
            let dict = value as? [String: Any] ?? [:]
            let cmd = dict["command"] as? String ?? (dict["url"] as? String ?? "")
            let args = (dict["args"] as? [String])?.joined(separator: " ") ?? ""
            return MCPServer(
                id: "antigravity:\(name)",
                name: name,
                command: [cmd, args].filter { !$0.isEmpty }.joined(separator: " "),
                source: .antigravity,
                active: true,
                category: nil
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
