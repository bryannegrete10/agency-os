import SwiftUI
import AppKit
import Observation

@MainActor
@Observable
final class AppModel {
    var servers: [MCPServer] = []
    var skills: [SkillItem] = []
    var divisions: [Division] = []
    var library: [LibraryItem] = []
    var installMessages: [String: String] = [:]
    var rules: [CarlDomain] = []
    private var loaded = false

    func loadIfNeeded() {
        guard !loaded else { return }
        reload()
        loaded = true
    }

    func reload() {
        servers = ClaudeConfigReader.loadClaudeCodeServers()
            + ClaudeConfigReader.loadClaudeDesktopServers()
            + CodexConfigReader.loadServers()
            + AntigravityConfigReader.loadServers()

        var userSkills = SkillScanner.scan()
        let folders = Set(userSkills.map { $0.folder })
        let skillDivisions = DivisionParser.parse(installedFolders: folders)
        divisions = skillDivisions + AgentDivisionScanner.scan()

        var lookup: [String: String] = [:]
        for division in skillDivisions {
            for entry in division.entries {
                let folder = entry.invoke.hasPrefix("/") ? String(entry.invoke.dropFirst()) : entry.invoke
                if lookup[folder] == nil { lookup[folder] = division.name }
            }
        }
        for index in userSkills.indices {
            userSkills[index].division = lookup[userSkills[index].folder]
        }

        var all = userSkills + PluginScanner.scan()
        all.sort {
            $0.kind.rank != $1.kind.rank
                ? $0.kind.rank < $1.kind.rank
                : $0.invoke.localizedCaseInsensitiveCompare($1.invoke) == .orderedAscending
        }
        skills = all
        library = LibraryStore.load()
        rules = RulesReader.load()
    }

    func addLibraryItem(repo: String, installURL: String) {
        let clean = SkillInstaller.sanitizeRepo(repo)
        guard !clean.isEmpty, !library.contains(where: { $0.repo == clean }) else { return }
        let urlTrim = installURL.trimmingCharacters(in: .whitespaces)
        let folder = clean.split(separator: "/").last.map(String.init) ?? clean
        library.append(LibraryItem(
            repo: clean, stars: "n/a", license: "n/a",
            link: "https://github.com/\(clean)",
            installed: false, note: "",
            installURL: urlTrim.isEmpty ? nil : urlTrim,
            installFolder: folder
        ))
        LibraryStore.save(library)
    }

    func installLibraryItem(_ item: LibraryItem) {
        installMessages[item.id] = "Installing..."
        let repo = item.repo
        let explicit = item.installURL
        let sanitized = SkillInstaller.sanitizeRepo(item.repo)
        let folder = item.installFolder
            ?? sanitized.split(separator: "/").last.map(String.init)
            ?? sanitized
        Task { @MainActor in
            let result = await SkillInstaller.install(repo: repo, explicitURL: explicit, folder: folder)
            switch result {
            case .installed(let installedFolder):
                if let index = library.firstIndex(where: { $0.id == item.id }) {
                    library[index].installed = true
                    if library[index].installFolder == nil { library[index].installFolder = installedFolder }
                }
                installMessages[item.id] = nil
                LibraryStore.save(library)
                reload()
            case .notFound:
                installMessages[item.id] = "No SKILL.md found in that repo (it may be an MCP server, not a skill)."
            case .failed(let message):
                installMessages[item.id] = "Install failed: \(message)"
            }
        }
    }

    func addServerFromLibrary(_ item: LibraryItem, agent: AgentTarget, command: String) {
        let parts = command.split(separator: " ").map(String.init)
        guard let cmd = parts.first, !cmd.isEmpty else {
            installMessages[item.id] = "Enter a run command first."
            return
        }
        let args = Array(parts.dropFirst())
        let sanitized = SkillInstaller.sanitizeRepo(item.repo)
        let name = sanitized.split(separator: "/").last.map(String.init) ?? sanitized

        if ServerInstaller.add(agent: agent, name: name, command: cmd, args: args) {
            if let index = library.firstIndex(where: { $0.id == item.id }) {
                library[index].installed = true
            }
            installMessages[item.id] = "Added '\(name)' to \(agent.rawValue). Set any API keys in its config."
            LibraryStore.save(library)
            reload()
        } else {
            installMessages[item.id] = "Could not add to \(agent.rawValue) (already exists or write failed)."
        }
    }

    func removeLibraryItem(_ id: String) {
        library.removeAll { $0.id == id }
        LibraryStore.save(library)
    }

    func toggleInstalled(_ id: String) {
        guard let index = library.firstIndex(where: { $0.id == id }) else { return }
        library[index].installed.toggle()
        LibraryStore.save(library)
    }

    func toggleSkill(_ skill: SkillItem) {
        ConfigWriter.setSkillEnabled(folder: skill.folder, enabled: !skill.enabled)
        reload()
    }

    func toggleServer(_ server: MCPServer) {
        guard ConfigWriter.canWrite(server.source) else { return }
        if server.source == .codex {
            ConfigWriter.setCodexServerEnabled(name: server.name, enabled: !server.active)
        } else {
            ConfigWriter.setServerEnabled(agent: server.source, name: server.name, enabled: !server.active)
        }
        reload()
    }

    func revealConfig(for agent: AgentTarget) {
        let url: URL? = (agent == .codex)
            ? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/config.toml")
            : ConfigWriter.jsonURL(for: agent)
        if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    func copyInvoke(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

enum NavSection: String, CaseIterable, Identifiable, Hashable {
    case servers = "Servers"
    case skills = "Skills"
    case divisions = "Divisions"
    case rules = "Rules"
    case library = "Library"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .servers: return "server.rack"
        case .skills: return "wand.and.stars"
        case .divisions: return "square.grid.2x2"
        case .rules: return "list.bullet.rectangle"
        case .library: return "books.vertical"
        }
    }
}

struct RootView: View {
    @State private var model = AppModel()
    @State private var section: NavSection? = .servers

    var body: some View {
        NavigationSplitView {
            List(NavSection.allCases, id: \.self, selection: $section) { item in
                Label(item.rawValue, systemImage: item.icon)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .listStyle(.sidebar)
            .navigationTitle("Agency OS")
            .safeAreaInset(edge: .bottom) {
                Button { model.reload() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.callout)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Space.s)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
                .padding(Theme.Space.s)
            }
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.bg)
        }
        .task { model.loadIfNeeded() }
    }

    @ViewBuilder
    private var detail: some View {
        switch section ?? .servers {
        case .servers: ServersView(model: model)
        case .skills: SkillsView(model: model)
        case .divisions: DivisionsView(model: model)
        case .library: LibraryView(model: model)
        case .rules: RulesView(model: model)
        }
    }
}

struct ServersView: View {
    let model: AppModel
    @State private var filter: AgentTarget?

    private var filtered: [MCPServer] {
        guard let filter else { return model.servers }
        return model.servers.filter { $0.source == filter }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(
                    title: "Servers",
                    subtitle: "\(model.servers.count) MCP servers across \(AgentTarget.allCases.count) agents"
                )

                HStack(spacing: Theme.Space.s) {
                    FilterChip(label: "All", count: model.servers.count, selected: filter == nil) {
                        filter = nil
                    }
                    ForEach(AgentTarget.allCases) { agent in
                        FilterChip(
                            label: agent.rawValue,
                            count: model.servers.filter { $0.source == agent }.count,
                            selected: filter == agent
                        ) { filter = agent }
                    }
                }
                .padding(.bottom, Theme.Space.xs)

                if filtered.isEmpty {
                    EmptyHint(text: "No MCP servers wired for this agent yet.")
                } else {
                    ForEach(filtered) { server in
                        ServerCard(
                            server: server,
                            onToggle: { model.toggleServer(server) },
                            onReveal: { model.revealConfig(for: server.source) }
                        )
                    }
                }
            }
            .padding(Theme.Space.xl)
        }
    }
}

struct ServerCard: View {
    let server: MCPServer
    let onToggle: () -> Void
    let onReveal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                Circle()
                    .fill(server.active ? Theme.success : Theme.textSecondary.opacity(0.4))
                    .frame(width: 8, height: 8)
                Text(server.name).font(.headline).foregroundStyle(Theme.textPrimary)
                Pill(text: server.source.rawValue, color: Theme.accent)
                Spacer()
                if ConfigWriter.canWrite(server.source) {
                    ToggleChip(isOn: server.active, action: onToggle)
                } else {
                    Button("Reveal", action: onReveal)
                        .buttonStyle(.plain)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Text(server.command.isEmpty ? "(no command)" : server.command)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(server.active ? 1 : 0.55)
        .glassPanel()
    }
}

struct FilterChip: View {
    let label: String
    var count: Int?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.xs) {
                Text(label)
                if let count {
                    Text("\(count)")
                        .foregroundStyle(selected ? Theme.bg.opacity(0.7) : Theme.textSecondary.opacity(0.7))
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(selected ? Theme.bg : Theme.textSecondary)
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.s)
            .background(selected ? Theme.accent : Theme.panel)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct ToggleChip: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(isOn ? "On" : "Off")
                .font(.caption2.weight(.bold))
                .foregroundStyle(isOn ? Theme.bg : Theme.textSecondary)
                .frame(width: 36)
                .padding(.vertical, 4)
                .background(isOn ? Theme.success : Theme.panel)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct EmptyHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(Theme.textSecondary)
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel()
    }
}

struct SkillsView: View {
    let model: AppModel
    @State private var kindFilter: SkillKind?
    @State private var query = ""

    private var filtered: [SkillItem] {
        model.skills.filter { skill in
            (kindFilter == nil || skill.kind == kindFilter) && matches(skill)
        }
    }

    private func matches(_ skill: SkillItem) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return true }
        return skill.invoke.lowercased().contains(needle)
            || skill.name.lowercased().contains(needle)
            || skill.summary.lowercased().contains(needle)
            || (skill.namespace?.lowercased().contains(needle) ?? false)
            || (skill.division?.lowercased().contains(needle) ?? false)
    }

    private func count(_ kind: SkillKind) -> Int { model.skills.filter { $0.kind == kind }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(
                    title: "Skills",
                    subtitle: query.isEmpty
                        ? "\(model.skills.count) skills + commands across user folders and installed plugins"
                        : "\(filtered.count) of \(model.skills.count) match"
                )

                HStack(spacing: Theme.Space.s) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                    TextField("Search skills, commands, descriptions...", text: $query)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Theme.textPrimary)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(Theme.Space.s)
                .background(Theme.panel)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.s))

                HStack(spacing: Theme.Space.s) {
                    FilterChip(label: "All", count: model.skills.count, selected: kindFilter == nil) { kindFilter = nil }
                    FilterChip(label: "Skills", count: count(.skill), selected: kindFilter == .skill) { kindFilter = .skill }
                    FilterChip(label: "Commands", count: count(.command), selected: kindFilter == .command) { kindFilter = .command }
                    FilterChip(label: "Plugin", count: count(.pluginSkill), selected: kindFilter == .pluginSkill) { kindFilter = .pluginSkill }
                }
                .padding(.bottom, Theme.Space.xs)

                if filtered.isEmpty {
                    EmptyHint(text: "No skills or commands match.")
                } else {
                    ForEach(filtered) { skill in
                        SkillCard(
                            skill: skill,
                            onCopy: { model.copyInvoke(skill.invoke.isEmpty ? "/" + skill.name : skill.invoke) },
                            onToggle: skill.kind == .skill ? { model.toggleSkill(skill) } : nil
                        )
                    }
                }
            }
            .padding(Theme.Space.xl)
        }
    }
}

struct SkillCard: View {
    let skill: SkillItem
    let onCopy: () -> Void
    let onToggle: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.s) {
                Text(skill.invoke.isEmpty ? "/" + skill.name : skill.invoke)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                if skill.kind != .skill { Pill(text: skill.kind.label, color: Theme.warn) }
                if let division = skill.division { Pill(text: division, color: Theme.accent) }
                Spacer()
                Button(action: onCopy) { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textSecondary)
                    .help("Copy invocation")
                if let onToggle { ToggleChip(isOn: skill.enabled, action: onToggle) }
            }
            Text(skill.summary.isEmpty ? skill.folder : skill.summary)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(skill.enabled ? 1 : 0.55)
        .glassPanel()
    }
}

struct LibraryView: View {
    let model: AppModel
    @State private var newRepo = ""
    @State private var newURL = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(
                    title: "Library",
                    subtitle: "\(model.library.filter { $0.installed }.count) installed, "
                        + "\(model.library.filter { !$0.installed }.count) to install later"
                )

                HStack(spacing: Theme.Space.s) {
                    field("owner/repo", text: $newRepo)
                    field("raw SKILL.md URL (optional)", text: $newURL)
                    Button {
                        model.addLibraryItem(repo: newRepo, installURL: newURL)
                        newRepo = ""; newURL = ""
                    } label: {
                        Text("Add")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, Theme.Space.m)
                            .padding(.vertical, Theme.Space.s)
                            .background(Theme.accent)
                            .foregroundStyle(Theme.bg)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                ForEach(model.library) { item in
                    LibraryCard(
                        item: item,
                        message: model.installMessages[item.id],
                        onOpen: { open(item.link) },
                        onInstall: { model.installLibraryItem(item) },
                        onToggle: { model.toggleInstalled(item.id) },
                        onRemove: { model.removeLibraryItem(item.id) },
                        onAddServer: { agent, command in model.addServerFromLibrary(item, agent: agent, command: command) }
                    )
                }
            }
            .padding(Theme.Space.xl)
        }
    }

    private func field(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .textFieldStyle(.plain)
            .foregroundStyle(Theme.textPrimary)
            .padding(Theme.Space.s)
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.s))
    }

    private func open(_ link: String) {
        guard let url = URL(string: link), !link.isEmpty else { return }
        NSWorkspace.shared.open(url)
    }
}

struct LibraryCard: View {
    let item: LibraryItem
    let message: String?
    let onOpen: () -> Void
    let onInstall: () -> Void
    let onToggle: () -> Void
    let onRemove: () -> Void
    let onAddServer: (AgentTarget, String) -> Void

    @State private var showServer = false
    @State private var serverCommand = ""

    private var installing: Bool { message == "Installing..." }
    private var commandGuess: String {
        let last = item.repo.split(separator: "/").last.map(String.init) ?? "server"
        return "npx -y \(last)-mcp"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                Text(item.repo).font(.headline).foregroundStyle(Theme.textPrimary)
                Spacer()
                Pill(text: item.installed ? "installed" : "wishlist",
                     color: item.installed ? Theme.success : Theme.warn)
            }
            if !item.note.isEmpty {
                Text(item.note).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(2)
            }
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(installing ? Theme.textSecondary : Theme.warn)
            }
            HStack(spacing: Theme.Space.s) {
                if item.stars != "n/a" { Pill(text: "\(item.stars) stars") }
                if item.license != "n/a" { Pill(text: item.license) }
                Spacer()
                if !item.installed {
                    Button(installing ? "Installing..." : "Install skill", action: onInstall)
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.success)
                        .disabled(installing)
                        .help("Downloads the repo's SKILL.md into ~/.claude/skills (a local Claude Code skill).")
                    Button("Add server") {
                        if serverCommand.isEmpty { serverCommand = commandGuess }
                        showServer.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .help("Adds this as an MCP server to an agent config you choose (Claude Code / Desktop / Codex / Antigravity).")
                }
                Button("Open", action: onOpen).buttonStyle(.plain).foregroundStyle(Theme.accent)
                Button(item.installed ? "Mark wishlist" : "Mark installed", action: onToggle)
                    .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
                Button(action: onRemove) { Image(systemName: "trash") }
                    .buttonStyle(.plain).foregroundStyle(Theme.danger)
            }
            .font(.caption)

            if showServer {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    TextField("Run command, e.g. npx -y firecrawl-mcp", text: $serverCommand)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(Theme.Space.s)
                        .background(Theme.bg)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.s))
                    HStack(spacing: Theme.Space.s) {
                        Text("Add to:").font(.caption2).foregroundStyle(Theme.textSecondary)
                        ForEach(AgentTarget.allCases) { agent in
                            Button(agent.rawValue) {
                                onAddServer(agent, serverCommand)
                                showServer = false
                            }
                            .buttonStyle(.plain)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Theme.bg)
                            .padding(.horizontal, Theme.Space.s)
                            .padding(.vertical, Theme.Space.xs)
                            .background(Theme.accent)
                            .clipShape(Capsule())
                        }
                    }
                    Text("Edit the command, pick an agent. Add any API keys in the config afterward.")
                        .font(.caption2).foregroundStyle(Theme.textSecondary.opacity(0.7))
                }
                .padding(.top, Theme.Space.xs)
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel()
    }
}

struct DivisionsView: View {
    let model: AppModel
    @State private var kindFilter: DivisionKind?

    private var filtered: [Division] {
        guard let kindFilter else { return model.divisions }
        return model.divisions.filter { $0.kind == kindFilter }
    }

    private func count(_ kind: DivisionKind) -> Int { model.divisions.filter { $0.kind == kind }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(
                    title: "Divisions",
                    subtitle: "\(model.divisions.count) divisions (skill map + agent roster)"
                )
                HStack(spacing: Theme.Space.s) {
                    FilterChip(label: "All", count: model.divisions.count, selected: kindFilter == nil) { kindFilter = nil }
                    FilterChip(label: "Skills", count: count(.skills), selected: kindFilter == .skills) { kindFilter = .skills }
                    FilterChip(label: "Agents", count: count(.agents), selected: kindFilter == .agents) { kindFilter = .agents }
                }
                .padding(.bottom, Theme.Space.xs)

                ForEach(filtered) { division in
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        HStack(spacing: Theme.Space.s) {
                            Text(division.name)
                                .font(.title3.bold())
                                .foregroundStyle(Theme.textPrimary)
                            Pill(text: division.kind == .agents ? "agents" : "skills",
                                 color: division.kind == .agents ? Theme.warn : Theme.accent)
                            Spacer()
                            Text("\(division.entries.count)")
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        ForEach(division.entries) { entry in
                            HStack(alignment: .top, spacing: Theme.Space.s) {
                                Circle()
                                    .fill(entry.installed ? Theme.success : Theme.textSecondary.opacity(0.3))
                                    .frame(width: 7, height: 7)
                                    .padding(.top, 5)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.invoke)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(entry.purpose)
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                    .padding(Theme.Space.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassPanel()
                }
            }
            .padding(Theme.Space.xl)
        }
    }
}

struct RulesView: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(
                    title: "Rules",
                    subtitle: "\(model.rules.count) CARL domains from ~/.carl/carl.json"
                )
                ForEach(model.rules) { domain in
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        HStack(spacing: Theme.Space.s) {
                            Text(domain.name).font(.title3.bold()).foregroundStyle(Theme.textPrimary)
                            if domain.alwaysOn { Pill(text: "always-on", color: Theme.success) }
                            Pill(text: domain.state,
                                 color: domain.state == "active" ? Theme.accent : Theme.textSecondary)
                            Spacer()
                            if domain.decisionCount > 0 { Pill(text: "\(domain.decisionCount) decisions") }
                        }
                        if domain.rules.isEmpty {
                            Text("No hard rules (recall-triggered domain).")
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        } else {
                            ForEach(domain.rules) { rule in
                                HStack(alignment: .top, spacing: Theme.Space.s) {
                                    Circle().fill(Theme.accent.opacity(0.6))
                                        .frame(width: 5, height: 5).padding(.top, 6)
                                    Text(rule.text).font(.caption).foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                        if !domain.recall.isEmpty {
                            Text("triggers: " + domain.recall.prefix(8).joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary.opacity(0.7))
                                .lineLimit(2)
                        }
                    }
                    .padding(Theme.Space.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassPanel()
                }
            }
            .padding(Theme.Space.xl)
        }
    }
}

struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.textPrimary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.bottom, Theme.Space.s)
    }
}
