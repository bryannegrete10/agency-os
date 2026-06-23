import Foundation

// CLT-only, XCTest-free self-test (full Xcode is not installed). Run with:
//   swift run AgencyOS --self-test
// Exits 0 if all checks pass, 1 otherwise. Covers the pure update-checker logic
// plus a best-effort live network probe that prints (but does not fail) results.
enum SelfTest {
    nonisolated(unsafe) static var passes = 0
    nonisolated(unsafe) static var failures = 0

    static func check(_ name: String, _ condition: Bool) {
        if condition { passes += 1; print("  PASS  \(name)") }
        else { failures += 1; print("  FAIL  \(name)") }
    }

    static func runAndExit() -> Never {
        print("AgencyOS self-test\n")

        // Version comparison
        check("3.8.0 newer than 3.1.0", UpdateChecker.isNewer(latest: "3.8.0", than: "3.1.0"))
        check("v2.6.2 newer than v2.5.0", UpdateChecker.isNewer(latest: "v2.6.2", than: "v2.5.0"))
        check("equal is not newer", !UpdateChecker.isNewer(latest: "2.6.2", than: "2.6.2"))
        check("older is not newer", !UpdateChecker.isNewer(latest: "2.5.0", than: "2.6.2"))
        check("v-prefix tolerated", !UpdateChecker.isNewer(latest: "v2.6.2", than: "2.6.2"))
        check("2.10.0 newer than 2.9.0", UpdateChecker.isNewer(latest: "2.10.0", than: "2.9.0"))
        check("component parse v2.6.2", UpdateChecker.components("v2.6.2") == [2, 6, 2])
        check("unparseable tag -> empty components", UpdateChecker.components("stable").isEmpty)

        // Frontmatter version extraction
        let sample = "---\nname: x\nversion: 3.8.0\ndescription: y\n---\nbody"
        check("frontmatter version parsed", SkillScanner.versionFrom(content: sample) == "3.8.0")
        check("no version -> nil", SkillScanner.versionFrom(content: "---\nname: x\n---") == nil)

        // Manifest round-trip
        let probe = SkillSource(folder: "selftest", kind: .npmCli, ref: "owner/repo",
                                latest: .githubRelease, updateExe: "uipro",
                                updateArgs: ["update"], installedVersion: "1.0.0")
        if let data = try? JSONEncoder().encode([probe]),
           let back = try? JSONDecoder().decode([SkillSource].self, from: data),
           let first = back.first {
            check("manifest round-trip", first.folder == "selftest" && first.kind == .npmCli
                  && first.latest == .githubRelease && first.updateArgs == ["update"])
        } else {
            check("manifest round-trip", false)
        }

        // Registry seed (public build ships an empty registry)
        let registry = SkillSourceStore.registry()
        check("public registry is empty", registry.isEmpty)
        check("registry entries well-formed", registry.allSatisfy { !$0.folder.isEmpty && !$0.ref.isEmpty })

        // Executable whitelist
        check("npx is allowed", SkillUpdater.allowedExe.contains("npx"))
        check("rm is rejected", SkillUpdater.resolve("rm") == nil)
        check("sh is rejected", SkillUpdater.resolve("sh") == nil)

        // Live probe (prints only; offline does not fail the suite)
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            for source in registry {
                let latest = await UpdateChecker.latestVersion(for: source)
                print("  LIVE  \(source.folder): latest = \(latest ?? "nil")")
            }
            semaphore.signal()
        }
        semaphore.wait()

        print("\nself-test: \(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
