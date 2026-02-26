# Session Handoff

> Updated: 2026-02-26
> Focus: Toolkit refactor Phase 1 — registry pattern, config-driven behaviors

---

## What Got Done

- **Behavior module decoupling**: All 4 behavior modules (ChaseStates, PatrolStates, WanderStates, GuardStates) now read from `ctx.behaviorConfig` instead of hardcoded `GameConfig.NPC.*` references. Zero remaining GameConfig.NPC.* references in behavior modules.
- **Target field standardization**: `chaseTarget`/`guardTarget` unified to `activeTarget` across ChaseStates, GuardStates, and NPCManager. Eliminates behaviorType switches in `getAllNPCStatus()`.
- **NPCManager registry rewrite**: New public API: `spawnNPC(config)`, `registerNPC(model, config)`, `despawnNPC(npcId)`, `initializeDemo()`. Internal BehaviorRegistry maps string keys to state modules. `initializeDemo()` rebuilds the original 4 demo NPCs from GameConfig.
- **DebugVisuals decoupled**: `updateTick()` reads `entry.behaviorConfig.LOS_MEMORY` instead of switching on behaviorType.
- **Verified working**: Demo behaves identically to before. New API tested via MCP and Command Bar (spawnNPC + despawnNPC both confirmed).

## What's Next

1. **Phase 2: Runtime behavior swap** — `NPCManager.setBehavior(npcId, behaviorType, behaviorConfig?)`. Teardown flow: destroy SM → scrub ctx fields → clean debug visuals → set new config → wire new behavior. Files: `src/server/modules/NPCManager.luau`
2. **Phase 2: Dynamic debug panel** — Server-driven NPC list instead of hardcoded `NPC_ORDER` in DebugPanel. Dynamically spawned NPCs should appear in the panel. Files: `src/client/DebugPanel.luau`, `src/server/modules/DebugService.luau`
3. **Phase 2: DebugService spawn position fix** — `TELEPORT_TO_NPC` reads `GameConfig.NPC.SPAWN_POSITIONS` which won't work for dynamic NPCs. Should read from `NPCEntry.spawnPosition` instead. File: `src/server/modules/DebugService.luau`
4. **Phase 3: Polish** — Waypoint tag resolver utility, optional camelCase config field rename, API documentation

## Blockers

None.

---

## Session Retrospective

### What Worked

- **Pre-mortem before implementation**: Caught `activeTarget` standardization as a blocker before writing code. Would have broken `getAllNPCStatus` at runtime.
- **Behavior modules first, then NPCManager**: Mechanical decoupling of 4 small files reduced risk before the big rewrite. Grep verification after confirmed completeness.
- **Parallel explore agents for research**: Three agents scanned different coupling surfaces simultaneously, producing comprehensive findings that directly informed the plan.

### What Broke

- **MCP/Command Bar require isolation**: Both MCP `run_code` and Command Bar `require()` return separate module instances from server scripts. Can't interact with the server's live NPC registry. Only way to test server APIs at runtime is through RemoteEvents or code added to the server script itself.
- **Command Bar client context default**: Defaults to Client context during play mode, where ServerScriptService is inaccessible. Must switch dropdown to "Server".

### Wrong Assumptions

- **Assumed Command Bar (Server) shares require cache with server scripts**: Expected that switching to Server context would give access to the same module tables the server script populated. It doesn't — three separate require caches exist (server scripts, Command Bar, MCP plugin). They share the DataModel but not module-local state.

---

## Quirks Discovered

- **Roblox has 3 require caches during play mode**: Server scripts, Command Bar (even in Server context), and MCP plugin. All share Workspace/DataModel but have independent module-local state. This means `activeNPCs` populated by `initializeDemo()` is invisible to Command Bar and MCP.

---

## Architecture Notes

- **Plan file**: `.claude/plans/enchanted-noodling-stallman.md` — Full Phase 1/2/3 plan with design decisions, file changes, and pre-mortem results. Still relevant for Phase 2 work.
- **NPCConfig shape** (used by spawnNPC/registerNPC):
  ```lua
  {
      displayName: string,
      behaviorType: string,        -- "chase" | "patrol" | "wander" | "guard"
      spawnPosition: Vector3?,     -- required for spawnNPC, ignored for registerNPC
      walkSpeed: number?,          -- applied to Humanoid, nil = default 16
      behavior: { [string]: any }, -- same SCREAMING_CASE fields as GameConfig.NPC.* sub-tables
  }
  ```
- **table.freeze safety**: Frozen GameConfig tables passed as `behaviorConfig` are safe — all behavior modules only read, never write.

## CLAUDE.md Suggestions

None — already updated this session.
