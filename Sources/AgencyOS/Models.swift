import Foundation

// Which agentic system a config entry belongs to.
enum AgentTarget: String, CaseIterable, Identifiable, Sendable {
    case claudeCode = "Claude Code"
    case claudeDesktop = "Claude Desktop"
    case codex = "OpenAI Codex"
    case antigravity = "Antigravity"

    var id: String { rawValue }
}

// An MCP server as declared in one agent's config file.
struct MCPServer: Identifiable, Sendable {
    let id: String
    var name: String
    var command: String
    var source: AgentTarget
    var active: Bool
    var category: String?
}

// An installed skill discovered in ~/.claude/skills/<folder>/SKILL.md.
enum SkillKind: String, Sendable {
    case skill, pluginSkill, command

    var rank: Int {
        switch self {
        case .skill: return 0
        case .command: return 1
        case .pluginSkill: return 2
        }
    }

    var label: String {
        switch self {
        case .skill: return "skill"
        case .command: return "command"
        case .pluginSkill: return "plugin"
        }
    }
}

struct SkillItem: Identifiable, Sendable {
    let id: String
    var name: String
    var folder: String
    var summary: String
    var division: String?
    var path: String
    var enabled: Bool
    var kind: SkillKind = .skill
    var invoke: String = ""
    var namespace: String? = nil
}

// A source repo for the install-later library view.
struct LibraryItem: Identifiable, Codable, Sendable {
    var id: String { repo }
    var repo: String
    var stars: String
    var license: String
    var link: String
    var installed: Bool
    var note: String
    var installURL: String? = nil
    var installFolder: String? = nil
}

// A skill entry within a division, as declared in the Agency-OS map.
struct DivisionEntry: Identifiable, Sendable {
    var id: String { invoke }
    var invoke: String
    var purpose: String
    var installed: Bool
}

enum DivisionKind: String, Sendable {
    case skills   // from the Agency-OS skill map
    case agents   // from ~/.claude/agents/divisions/
}

// A division (Creative, Sales, Marketing, Design, Ops, Tooling, ...).
struct Division: Identifiable, Sendable {
    var id: String { "\(kind.rawValue):\(name)" }
    var name: String
    var entries: [DivisionEntry]
    var kind: DivisionKind = .skills
}

// A single CARL rule within a domain.
struct CarlRule: Identifiable, Sendable {
    var id: String
    var text: String
    var source: String
}

// A CARL domain (GLOBAL, DEVELOPMENT, SHOPIFY, ...) from ~/.carl/carl.json.
struct CarlDomain: Identifiable, Sendable {
    var id: String { name }
    var name: String
    var state: String
    var alwaysOn: Bool
    var recall: [String]
    var rules: [CarlRule]
    var decisionCount: Int
}
