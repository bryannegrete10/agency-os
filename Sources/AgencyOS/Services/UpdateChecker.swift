import Foundation

// Resolves whether an installed skill has a newer version upstream. Read-only:
// it only queries npm / GitHub and compares, never mutates. Each source declares
// how its newest version is found (npm registry, GitHub release tag, or the
// upstream SKILL.md `version:` field). Best-effort: any failure -> .unknown.
enum UpdateChecker {

    // MARK: - Version comparison (semver-ish, tolerant of "v" prefix + component count)

    static func components(_ s: String) -> [Int] {
        let cleaned = s.trimmingCharacters(in: .whitespaces).lowercased().drop { $0 == "v" }
        return cleaned.split(whereSeparator: { !$0.isNumber }).map { Int($0) ?? 0 }
    }

    static func isNewer(latest: String, than installed: String) -> Bool {
        let a = components(latest), b = components(installed)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - Check

    static func check(skill: SkillItem, source: SkillSource) async -> UpdateStatus {
        let installed = skill.version ?? source.installedVersion
        guard let latest = await latestVersion(for: source) else {
            return UpdateStatus(folder: skill.folder, state: .unknown,
                                installed: installed, latest: nil, message: "Couldn't reach upstream")
        }
        // An upstream tag we can't parse into numbers (e.g. "stable", "latest")
        // must not silently compare as 0.0.0 and report "up to date".
        guard !components(latest).isEmpty else {
            return UpdateStatus(folder: skill.folder, state: .unknown,
                                installed: installed, latest: latest,
                                message: "Upstream version not comparable: \(latest)")
        }
        guard let installed else {
            return UpdateStatus(folder: skill.folder, state: .unknown,
                                installed: nil, latest: latest,
                                message: "Latest \(latest); installed version unknown")
        }
        let state: UpdateState = isNewer(latest: latest, than: installed) ? .available : .current
        return UpdateStatus(folder: skill.folder, state: state,
                            installed: installed, latest: latest, message: nil)
    }

    static func latestVersion(for source: SkillSource) async -> String? {
        switch source.latest {
        case .npmVersion:        return await npmLatest(pkg: source.ref)
        case .githubRelease:     return await githubLatestRelease(repo: source.ref)
        case .githubFileVersion: return await githubSkillVersion(repo: source.ref)
        case .none:              return nil
        }
    }

    // MARK: - Upstream resolvers

    private static func npmLatest(pkg: String) async -> String? {
        guard let data = await getOK("https://registry.npmjs.org/\(pkg)/latest"),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return root["version"] as? String
    }

    private static func githubLatestRelease(repo: String) async -> String? {
        guard let data = await getOK("https://api.github.com/repos/\(repo)/releases/latest"),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        // Only the tag is a reliable version; `name` is often a human title.
        return root["tag_name"] as? String
    }

    private static func githubSkillVersion(repo: String) async -> String? {
        for branch in ["main", "master"] {
            if let data = await getOK("https://raw.githubusercontent.com/\(repo)/\(branch)/SKILL.md"),
               let text = String(data: data, encoding: .utf8),
               let version = SkillScanner.versionFrom(content: text) { return version }
        }
        for branch in ["main", "master"] {
            if let path = await shallowestSkillPath(repo: repo, branch: branch),
               let data = await getOK("https://raw.githubusercontent.com/\(repo)/\(branch)/\(path)"),
               let text = String(data: data, encoding: .utf8),
               let version = SkillScanner.versionFrom(content: text) { return version }
        }
        return nil
    }

    private static func shallowestSkillPath(repo: String, branch: String) async -> String? {
        guard let data = await getOK("https://api.github.com/repos/\(repo)/git/trees/\(branch)?recursive=1"),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tree = root["tree"] as? [[String: Any]] else { return nil }
        return tree.compactMap { $0["path"] as? String }
            .filter { $0.lowercased().hasSuffix("skill.md") }
            .sorted { $0.count < $1.count }
            .first
    }

    private static func getOK(_ urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("AgencyOS", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty { return data }
        } catch {}
        return nil
    }
}
