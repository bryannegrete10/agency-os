import Foundation

// Resolves and installs a skill's SKILL.md from a GitHub repo for the Library
// "Install" button. If no explicit raw URL is known, it auto-resolves: tries
// /main/SKILL.md and /master/SKILL.md, then searches the repo tree via the
// GitHub API for the shallowest SKILL.md. Telemetry-free (direct GitHub).
enum SkillInstaller {
    enum InstallResult: Sendable {
        case installed(folder: String)
        case notFound
        case failed(String)
    }

    static func sanitizeRepo(_ raw: String) -> String {
        var r = raw.trimmingCharacters(in: .whitespaces)
        for prefix in ["https://github.com/", "http://github.com/", "github.com/"] {
            if r.hasPrefix(prefix) { r = String(r.dropFirst(prefix.count)) }
        }
        if r.hasSuffix(".git") { r = String(r.dropLast(4)) }
        return r.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static func install(repo: String, explicitURL: String?, folder: String) async -> InstallResult {
        let clean = sanitizeRepo(repo)
        guard !clean.isEmpty else { return .failed("invalid repo") }

        if let explicitURL, let data = await fetchOK(explicitURL) {
            return write(data, folder: folder)
        }
        for branch in ["main", "master"] {
            if let data = await fetchOK("https://raw.githubusercontent.com/\(clean)/\(branch)/SKILL.md") {
                return write(data, folder: folder)
            }
        }
        for branch in ["main", "master"] {
            if let path = await findSkillPath(repo: clean, branch: branch),
               let data = await fetchOK("https://raw.githubusercontent.com/\(clean)/\(branch)/\(path)") {
                return write(data, folder: folder)
            }
        }
        return .notFound
    }

    private static func fetchOK(_ urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty {
                return data
            }
        } catch {}
        return nil
    }

    private static func findSkillPath(repo: String, branch: String) async -> String? {
        guard let data = await fetchOK("https://api.github.com/repos/\(repo)/git/trees/\(branch)?recursive=1"),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tree = root["tree"] as? [[String: Any]] else { return nil }
        return tree.compactMap { $0["path"] as? String }
            .filter { $0.lowercased().hasSuffix("skill.md") }
            .sorted { $0.count < $1.count }
            .first
    }

    private static func write(_ data: Data, folder: String) -> InstallResult {
        let dir = SkillScanner.skillsURL.appendingPathComponent(folder)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: dir.appendingPathComponent("SKILL.md"), options: .atomic)
            return .installed(folder: folder)
        } catch {
            return .failed("write error")
        }
    }
}
