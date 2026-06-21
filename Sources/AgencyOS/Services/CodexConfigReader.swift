import Foundation

// Reads MCP servers from ~/.codex/config.toml. Foundation has no TOML decoder,
// so this is a focused parser for the [mcp_servers.<name>] tables only
// (command + args). The [mcp_servers.<name>.env] subtables are skipped.
enum CodexConfigReader {
    static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/config.toml")
    }

    static func loadServers() -> [MCPServer] {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return [] }

        var commands: [String: String] = [:]
        var argLists: [String: [String]] = [:]
        var activeMap: [String: Bool] = [:]
        var order: [String] = []
        var current: String?
        var inEnvSubtable = false

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                let header = String(line.dropFirst().dropLast())
                let (prefix, active): (String?, Bool) =
                    header.hasPrefix("mcp_servers_disabled.") ? ("mcp_servers_disabled.", false)
                    : header.hasPrefix("mcp_servers.") ? ("mcp_servers.", true)
                    : (nil, true)

                if let prefix {
                    let rest = String(header.dropFirst(prefix.count))
                    if rest.hasSuffix(".env") {
                        inEnvSubtable = true
                    } else {
                        let name = unquote(rest)
                        current = name
                        inEnvSubtable = false
                        if commands[name] == nil {
                            commands[name] = ""
                            order.append(name)
                            activeMap[name] = active
                        }
                    }
                } else {
                    current = nil
                    inEnvSubtable = false
                }
                continue
            }

            guard let name = current, !inEnvSubtable,
                  let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if key == "command" {
                commands[name] = unquote(value)
            } else if key == "args" {
                argLists[name] = parseStringArray(value)
            }
        }

        return order.map { name in
            let cmd = ([commands[name] ?? ""] + (argLists[name] ?? []))
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return MCPServer(id: "codex:\(name)", name: name, command: cmd,
                             source: .codex, active: activeMap[name] ?? true, category: nil)
        }
    }

    private static func unquote(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.count >= 2,
           (t.hasPrefix("\"") && t.hasSuffix("\"")) || (t.hasPrefix("'") && t.hasSuffix("'")) {
            t = String(t.dropFirst().dropLast())
        }
        return t
    }

    private static func parseStringArray(_ s: String) -> [String] {
        guard let open = s.firstIndex(of: "["), let close = s.lastIndex(of: "]"), open < close else { return [] }
        let inner = s[s.index(after: open)..<close]
        return inner.split(separator: ",")
            .map { unquote(String($0)) }
            .filter { !$0.isEmpty }
    }
}
