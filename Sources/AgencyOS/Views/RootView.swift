import SwiftUI
import AppKit
import Observation

@Observable
final class AppModel {
    var servers: [MCPServer] = []
    var skills: [SkillItem] = []
    var divisions: [Division] = []
    var library: [LibraryItem] = []
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

        var scanned = SkillScanner.scan()
        let folders = Set(scanned.map { $0.folder })
        divisions = DivisionParser.parse(installedFolders: folders)

        var lookup: [String: String] = [:]
        for division in divisions {
            for entry in division.entries {
                let folder = entry.invoke.hasPrefix("/") ? String(entry.invoke.dropFirst()) : entry.invoke
                if lookup[folder] == nil { lookup[folder] = division.name }
            }
        }
        for index in scanned.indices {
            scanned[index].division = lookup[scanned[index].folder]
        }
        skills = scanned
        library = LibraryStore.load()
        rules = RulesReader.load()
    }

    func addLibraryItem(repo: String, installURL: String) {
        let trimmed = repo.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !library.contains(where: { $0.repo == trimmed }) else { return }
        let urlTrim = installURL.trimmingCharacters(in: .whitespaces)
        let folder = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
        library.append(LibraryItem(
            repo: trimmed, stars: "n/a", license: "n/a",
            link: "https://github.com/\(trimmed)",
            installed: false, note: "",
            installURL: urlTrim.isEmpty ? nil : urlTrim,
            installFolder: folder
        ))
        LibraryStore.save(library)
    }

    func installLibraryItem(_ item: LibraryItem) {
        guard let url = item.installURL, let folder = item.installFolder else { return }
        guard ConfigWriter.installSkill(from: url, folder: folder) else { return }
        if let index = library.firstIndex(where: { $0.id == item.id }) {
            library[index].installed = true
            LibraryStore.save(library)
        }
        reload()
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
        ConfigWriter.setServerEnabled(agent: server.source, name: server.name, enabled: !server.active)
        reload()
    }

    func revealConfig(for agent: AgentTarget) {
        let url: URL? = (agent == .codex)
            ? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/config.toml")
            : ConfigWriter.jsonURL(for: agent)
        if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(title: "Skills",
                              subtitle: "\(model.skills.count) installed in ~/.claude/skills")
                ForEach(model.skills) { skill in
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        HStack(spacing: Theme.Space.s) {
                            Text("/" + skill.name)
                                .font(.headline)
                                .foregroundStyle(Theme.textPrimary)
                            if let division = skill.division {
                                Pill(text: division, color: Theme.accent)
                            }
                            Spacer()
                            ToggleChip(isOn: skill.enabled) { model.toggleSkill(skill) }
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
            .padding(Theme.Space.xl)
        }
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
                        onOpen: { open(item.link) },
                        onInstall: { model.installLibraryItem(item) },
                        onToggle: { model.toggleInstalled(item.id) },
                        onRemove: { model.removeLibraryItem(item.id) }
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
    let onOpen: () -> Void
    let onInstall: () -> Void
    let onToggle: () -> Void
    let onRemove: () -> Void

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
            HStack(spacing: Theme.Space.s) {
                if item.stars != "n/a" { Pill(text: "\(item.stars) stars") }
                if item.license != "n/a" { Pill(text: item.license) }
                Spacer()
                if !item.installed, item.installURL != nil {
                    Button("Install", action: onInstall)
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.success)
                }
                Button("Open", action: onOpen).buttonStyle(.plain).foregroundStyle(Theme.accent)
                Button(item.installed ? "Mark wishlist" : "Mark installed", action: onToggle)
                    .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
                Button(action: onRemove) { Image(systemName: "trash") }
                    .buttonStyle(.plain).foregroundStyle(Theme.danger)
            }
            .font(.caption)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel()
    }
}

struct DivisionsView: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(
                    title: "Divisions",
                    subtitle: "\(model.divisions.count) divisions from your Agency-OS map"
                )
                ForEach(model.divisions) { division in
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        HStack {
                            Text(division.name)
                                .font(.title3.bold())
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            let installed = division.entries.filter { $0.installed }.count
                            Pill(text: "\(installed)/\(division.entries.count) local", color: Theme.accent)
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

struct PlaceholderView: View {
    let title: String

    var body: some View {
        VStack(spacing: Theme.Space.m) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 36))
                .foregroundStyle(Theme.textSecondary)
            Text("\(title) lands in the next milestone")
                .font(.title3)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
