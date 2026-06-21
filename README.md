# AgencyOS

A local control plane for MCP servers, skills, divisions, and CARL rules across
Claude Code, Claude Desktop, OpenAI Codex, and Antigravity. Native SwiftUI for
macOS.

AgencyOS reads its data live from your home directory. Nothing is stored in this
repository and no data leaves your machine; it is a thin viewer and toggler over
config files you already have.

## What it does

- Lists MCP servers declared across each agent's config and shows which are active.
- Discovers installed skills under `~/.claude/skills` and lets you enable or disable
  them by moving folders between `skills` and `skills_disabled` (no data loss, just a move).
- Parses a divisions map into divisions and their skill entries.
- Reads CARL domains and rules from `~/.carl/carl.json`.
- Tracks an install-later library of source repos at `~/.agency-os/library.json`.

## Data sources (read at runtime)

| Source | Path |
| --- | --- |
| Claude Code MCP | `~/.claude.json` |
| Claude Desktop MCP | `~/Library/Application Support/Claude/claude_desktop_config.json` |
| Codex MCP | `~/.codex/config.toml` |
| Antigravity MCP | `~/.gemini/config/mcp_config.json` |
| Installed skills | `~/.claude/skills/<folder>/SKILL.md` |
| CARL rules | `~/.carl/carl.json` |
| Divisions map | `~/.agency-os/divisions.md` |
| Install library | `~/.agency-os/library.json` |

Sources you do not use are simply skipped; the relevant panels stay empty.

## Divisions map format

Create `~/.agency-os/divisions.md`. Each `## <Name> Division` header starts a
division. Markdown table rows whose first cell contains a `/invoke` token become
entries, with the last cell used as the purpose. Example:

```markdown
## Design Division

| Skill | Purpose |
| --- | --- |
| `/impeccable` | Frontend design critique and polish |
| `/ui-ux-pro-max` | UI/UX design intelligence |

## Sales Division

| Skill | Purpose |
| --- | --- |
| `/sales-coach` | Pipeline reviews and call technique |
```

Agent-roster divisions are also read automatically from
`~/.claude/agents/divisions/<division>/*.md` (each subfolder is a division, each
`.md` an agent). The `engineering` and `testing` folders are surfaced under the
display names "Development" and "Code Quality".

## Requirements

- macOS (Apple Silicon or Intel)
- Swift toolchain (Xcode command line tools)

## Build and run

```bash
# Build the .app bundle and copy it to the Desktop
bash scripts/build-app.sh

# Or build and run the binary directly
swift build -c release
```

The build script ad-hoc signs the app, so it runs locally without a developer
certificate.

## License

MIT. See [LICENSE](LICENSE).

---

Built by [Reactt Agency](https://reacttagency.com).
