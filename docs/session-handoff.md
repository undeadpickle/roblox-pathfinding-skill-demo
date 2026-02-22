# Session Handoff

> Updated: 2026-02-22 00:00
> Focus: Initial project setup

---

## What Got Done

- **Project scaffolded**: Full Rojo + Wally + Selene + StyLua setup via roblox-dev skill
- **Rokit tools pinned**: Rojo 7.6.1, Wally 0.3.2, StyLua 2.3.1, Selene 0.30.0
- **Wally packages installed**: Promise, GoodSignal, Trove (core only, no persistence)
- **Starter code deployed**: Client/server entry points, GameConfig, Remotes, Logger
- **Rojo connected to Studio**: Place ID `105075058557529` added to `servePlaceIds`
- **MCPs configured**: Official Roblox Studio MCP, boshyxd community MCP, Context7 (all in `.mcp.json`)
- **All MCPs verified working**: `run_code` tested in Studio, Context7 queried PathfindingService docs
- **Skill gotcha documented**: Empty `servePlaceIds` bug added to `~/.claude/skills/roblox-dev/references/gotchas-tooling.md`
- **Skill template fixed**: Removed empty `servePlaceIds: []` from `default.project.json` template

## What's Next

1. **Define the game loop**: No game type chosen yet — decide what to build and update CLAUDE.md
2. **Build Phase 1 core mechanic**: Once game type is decided, implement the first playable mechanic
3. **Set up boshyxd Studio plugin**: Installed as MCP but the Studio plugin side (port 3003) hasn't been connected yet — optional, official MCP covers most needs

## Blockers

- None

---

## Session Retrospective

### What Worked

- **Scaffold script**: One-shot `scaffold.sh` created the entire project structure cleanly
- **Reusing MCP configs**: Found existing configs from other Roblox projects in `~/.claude.json` and copied them verbatim — avoided setup trial-and-error
- **Context7 for Roblox docs**: Queried PathfindingService API instantly without web search

### What Broke

- **Empty `servePlaceIds` blocked Rojo connection**: The scaffold template shipped `"servePlaceIds": []` which Rojo interprets as "no places allowed." Fixed by adding the place ID, then also fixed the template and documented the gotcha.
- **Rojo didn't hot-reload config change**: After editing `default.project.json`, had to restart the Rojo server manually. The server reads config at startup only.

### Wrong Assumptions

- **`servePlaceIds: []` would mean "any place"**: Actually means "no places." Omitting the field entirely is what allows any place. Template now omits it.

---

## Quirks Discovered

- **Rojo `servePlaceIds`**: Empty array = block all, missing field = allow all. Must restart Rojo after changing. Documented in skill gotchas.
- **Rokit tools are project-scoped**: Even though Rojo was available globally, `wally`/`selene`/`stylua` weren't until `rokit init` + `rokit add` was run in the project.

---

## CLAUDE.md Suggestions

None — CLAUDE.md looks current for the project state.
