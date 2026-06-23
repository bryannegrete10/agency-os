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
    var version: String? = nil   // from SKILL.md `version:` frontmatter, when present
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

// A logged CARL decision within a domain (the running decision log, distinct
// from hard rules). Surfaced behind a "Show all" toggle in the Rules view.
struct CarlDecision: Identifiable, Sendable {
    var id: String
    var text: String
    var rationale: String
    var date: String
    var status: String
}

// A CARL domain (GLOBAL, DEVELOPMENT, SHOPIFY, ...) from ~/.carl/carl.json.
struct CarlDomain: Identifiable, Sendable {
    var id: String { name }
    var name: String
    var state: String
    var alwaysOn: Bool
    var recall: [String]
    var rules: [CarlRule]
    var decisions: [CarlDecision]
    var decisionCount: Int { decisions.count }
}

// MARK: - Skill update tracking

// Where an installed skill came from -> which update lane applies.
enum SkillSourceKind: String, Codable, Sendable {
    case npmCli            // vendor CLI updater (npx impeccable / uipro)
    case githubSingleFile  // re-download SKILL.md from a GitHub repo
    case plugin            // managed by Claude Code; read-only here
    case unknown           // manual copy, no known update path
}

// How the newest upstream version is discovered.
enum LatestStrategy: String, Codable, Sendable {
    case npmVersion        // registry.npmjs.org/<ref>/latest -> .version
    case githubRelease     // api.github.com/repos/<ref>/releases/latest -> .tag_name
    case githubFileVersion // upstream SKILL.md `version:` frontmatter
    case none
}

// Provenance + update recipe for one installed skill (persisted in skills.json).
struct SkillSource: Codable, Sendable {
    var folder: String
    var kind: SkillSourceKind
    var ref: String               // npm package name OR "owner/repo"
    var latest: LatestStrategy
    var updateExe: String?        // e.g. "npx" | "uipro" (nil = no in-app update)
    var updateArgs: [String]
    var installedVersion: String? // last-known installed version (for skills w/o frontmatter version)
}

enum UpdateState: String, Sendable {
    case current     // up to date
    case available   // newer version upstream
    case unknown     // could not determine (no version signal / network)
    case noSource    // no known provenance
    case error       // check failed
}

// Result of one update check, keyed by skill folder.
struct UpdateStatus: Identifiable, Sendable {
    var id: String { folder }
    var folder: String
    var state: UpdateState
    var installed: String?
    var latest: String?
    var message: String?
}
