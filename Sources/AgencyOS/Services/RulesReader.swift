import Foundation

// Reads CARL rules from ~/.carl/carl.json (the carl-mcp data store). Surfaces
// each domain with its state, always-on flag, recall triggers, rules, and a
// decision count. Read-only.
enum RulesReader {
    static var carlURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".carl/carl.json")
    }

    static func load() -> [CarlDomain] {
        guard let data = try? Data(contentsOf: carlURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let domains = root["domains"] as? [String: Any] else { return [] }

        var result: [CarlDomain] = []
        for (name, value) in domains {
            let dict = value as? [String: Any] ?? [:]
            let rulesRaw = (dict["rules"] as? [[String: Any]]) ?? []
            let rules = rulesRaw.enumerated().map { index, rule in
                CarlRule(
                    id: "\(name)-\(index)",
                    text: rule["text"] as? String ?? "",
                    source: rule["source"] as? String ?? ""
                )
            }
            result.append(CarlDomain(
                name: name,
                state: dict["state"] as? String ?? "unknown",
                alwaysOn: dict["always_on"] as? Bool ?? false,
                recall: (dict["recall"] as? [String]) ?? [],
                rules: rules,
                decisionCount: ((dict["decisions"] as? [Any]) ?? []).count
            ))
        }

        // GLOBAL first, then alphabetical.
        return result.sorted {
            if $0.name == "GLOBAL" { return true }
            if $1.name == "GLOBAL" { return false }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
