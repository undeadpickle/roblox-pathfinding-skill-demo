# RobloxPathfindingSkillDemo

## Overview

NPC pathfinding demo showcasing chase, patrol, wander, and guard behaviors using PathfindingService.

> Generated with roblox-dev skill v1.1.0

## Project Profile

> Captured during initial setup — informs architecture decisions.

- **Intent:** Prototype
- **Source of truth:** Git + Rojo
- **Team:** Solo, no PRs
- **Core loop:** General / undecided
- **Session format:** Undecided
- **Platform:** Cross-platform
- **Exploit sensitivity:** Low — client-trusted for prototype
- **Persistence:** None — no DataManager
- **Structure:** Layered

**Auto-included modules:** None

## Build Roadmap

> Suggested build order based on your game type. Tackle Phase 1 first for a playable vertical slice.

### Phase 1: Core Loop
- [ ] Core gameplay mechanic working
- [ ] Basic UI showing game state
- [ ] One complete player flow (join > play > result)

### Phase 2: Depth
- [ ] Additional content/variety
- [ ] Polish and feedback (sounds, effects)
- [ ] Edge case handling

### Phase 3: Engagement
- [ ] Progression systems
- [ ] Social features
- [ ] Monetization hooks (if applicable)

**Current focus:** Phase 1 — get the core loop working first.

> Ask Claude: "Help me implement [next item]" to continue.

## Architecture

### Code Organization
- `src/client/` — Client-side code (runs on player's device)
- `src/server/` — Server-side code (runs on Roblox servers)
- `src/shared/` — Shared modules (used by both client and server)
- `src/replicatedFirst/` — Early client code (loading screens, pre-game setup)
- `Packages/` — Wally dependencies (auto-generated, don't edit)

### Key Modules
- `GameConfig` — Central configuration values (NPC config, UI)
- `Remotes` — Client-server communication helpers
- `Logger` — Debug logging with [Server]/[Client] prefixes
- `NPCPathfinder` — PathfindingService wrapper with moveTo, patrol, followTarget, wander, hasLineOfSight, setVisualizeEnabled
- `NPCStateMachine` — Generic finite state machine (shared, reusable for any system). Optional `onStateChanged` callback (4th param) fires on initial state and every transition.
- `NPCManager` — Registry-based NPC orchestrator. Public API: `spawnNPC(config)` (creates rig + registers), `registerNPC(model, config)` (adopts pre-placed model), `despawnNPC(npcId)` (individual teardown), `setBehavior(npcId, behaviorType, behaviorConfig?)` (runtime behavior swap — tears down SM, scrubs ctx, cleans visuals, re-wires), `initializeDemo()` (spawns original 4 demo NPCs from GameConfig). Also exposes `getAllNPCStatus()`, `getAvailableBehaviors()`, `getNPCSpawnPosition()`, `setDebugVisualEnabled()`, `setDebugStateCallback()`, `getNPCPosition()`, `teleportNPC()` for debug panel. Internal BehaviorRegistry maps behavior type strings to state modules. State definitions live in `behaviors/` modules.
- `DebugVisuals` — Debug visualization: state labels, detection discs, visual toggling (`setVisualEnabled`), per-frame debug updates (`updateTick`), cleanup. Extracted from NPCManager to separate presentation from NPC lifecycle.
- `behaviors/ChaseStates` — Chase NPC state definitions (Idle ↔ Chasing). Reads from `ctx.behaviorConfig`, uses `ctx.activeTarget` for chase target.
- `behaviors/PatrolStates` — Patrol NPC state definitions (Patrolling). Reads from `ctx.behaviorConfig`.
- `behaviors/WanderStates` — Wander NPC state definitions (Wandering). Reads from `ctx.behaviorConfig`.
- `behaviors/GuardStates` — Guard NPC state definitions (Guarding ↔ Chasing ↔ Returning). Reads from `ctx.behaviorConfig`, uses `ctx.activeTarget` for chase target.
- `behaviors/BehaviorHelpers` — Shared utilities: findNearestPlayer, detectNearestPlayerInRange, getRandomPointInRadius, createWaypointMarkers, evaluateChaseTarget
- `DebugRemotes` — String constants for debug remote names (shared, single source of truth). Includes GET_NPC_STATUS, TOGGLE_VISUAL, TELEPORT_TO_NPC, TELEPORT_TO_NPC_CURRENT, TELEPORT_NPC_TO_PLAYER, SET_BEHAVIOR, NPC_STATE_CHANGED.
- `DebugService` — Server-side handler bridging debug panel requests into NPCManager. Augments status response with `_meta.availableBehaviors`. SET_BEHAVIOR handler supplies default configs from GameConfig per behavior type to prevent nil field crashes from incompatible configs.
- `DebugPanel` — Client-side debug panel logic. Server-driven dynamic NPC list (no hardcoded NPC_ORDER). Polls status every 0.5s, diffs NPC list, rebuilds status/teleport/behavior sections on add/remove. Behavior section shows per-NPC swap buttons with active highlight. Visual toggle states persist across rebuilds and sync to newly spawned NPCs.
- `DebugPanelUI` — UI factory functions for debug panel elements (raw Roblox instances, no framework). Includes `createBehaviorRow` for per-NPC behavior swap buttons with update callback.

### NPC Pathfinding System
- Registry-based NPC system: `spawnNPC(config)` creates R15 rigs, `registerNPC(model, config)` adopts pre-placed models, `despawnNPC(npcId)` tears down individual NPCs, `setBehavior(npcId, behaviorType, behaviorConfig?)` swaps behavior at runtime (model + pathfinder persist). `initializeDemo()` spawns the original 4 demo NPCs.
- Config-driven behaviors: behavior type + config table passed at spawn/register time. Behavior modules read from `ctx.behaviorConfig` (not GameConfig). Chase/guard use `ctx.activeTarget` (standardized from old `chaseTarget`/`guardTarget`).
- BehaviorRegistry maps string keys ("chase", "patrol", "wander", "guard") to state modules + initial states.
- 4 demo NPCs: Chase (follows nearest player), Patrol (loops waypoints), Wander (random points in radius), Guard (random patrol + LOS-triggered chase + return-to-post)
- Behavior driven by state machines: Chase (Idle ↔ Chasing), Patrol (Patrolling), Wander (Wandering), Guard (Guarding ↔ Chasing ↔ Returning)
- Single PostSimulation tick drives all state machines; states call NPCPathfinder methods
- R15 rigs created at runtime via `Players:CreateHumanoidModelFromDescription()`
- Server-authoritative: `SetNetworkOwner(nil)` on all NPC parts
- Collision group "NPCs" prevents NPC-to-NPC physics jitter
- `game:BindToClose` ensures cleanup on server shutdown
- Chase `followTarget` uses continuous-motion loop (0.1s tick) with event-driven waypoint advancement (`MoveToFinished`), timer-based path recomputation, stuck detection + auto-jump recovery
- Guard detection: distance + LOS raycast (via `hasLineOfSight`) to initiate chase, LOS memory timer during chase (counts down when sight lost, drops target when expired). Returns to nearest waypoint when target lost.
- `hasLineOfSight(targetPos, excludeModels?)` is public on NPCPathfinder. Raycasts from NPC root to target, excluding the NPC model and optionally additional models (e.g., the target player's character).
- Debug visuals gated by `GameConfig.GAME.DEBUG`: state labels above heads, detection radius disc (chase=red, guard=orange, anchored + tick-updated), waypoint spheres (chase path, color-coded), patrol waypoint markers (yellow), guard waypoint markers (orange, no lines — random order), wander beam + target marker
- Debug panel (F8 toggle): dynamic server-driven NPC list (rebuilds on spawn/despawn), live NPC status readout, per-visual toggles (disc, stateLabel, chasePath, waypoints, waypointNumbers, nameLabel, wanderBeam) with Toggle All master switch, teleport (spawn zone, NPC current pos, summon NPC to player), per-NPC behavior swap buttons. Client polls server every 0.5s + push events for instant state changes. Visual toggle states tracked in `visualToggleStates` map and synced to new NPCs on rebuild.
- Performance strip (always visible, top-left): FPS, frame time (ms, color-coded green/yellow/red), instance count (3s poll). Independent of F8 panel toggle.
- Chase path dot toggle uses `_visualizeOverride` pattern in NPCPathfinder so debug panel state persists across `followTarget` restarts during state transitions.

### Map & Obstacles
- Obstacle geometry is Studio-placed in `Workspace.Obstacles` (24 parts: walls, blocks, staircase steps). Not generated at runtime — placed via MCP `run_code`
- PathfindingService auto-carves obstacles from navmesh — no pathfinder code changes needed
- Wander target generation uses `Workspace:Raycast` to reject points inside obstacle footprints (`BehaviorHelpers.getObstacleFolder()`)
- Guard zone has 2 walls flanking patrol center to create LOS-breaking corridors
- Chase NPC: `WALK_SPEED` 4, `DETECTION_RADIUS` 20, `REQUIRE_LOS` true, `LOS_MEMORY` 3s
- Guard NPC: `WALK_SPEED` 10, `DETECTION_RADIUS` 18, `REQUIRE_LOS` true, `LOS_MEMORY` 5s, 5 waypoints in pentagon layout (north quadrant)
- LOS detection: `REQUIRE_LOS = true` (default) blocks detection through walls; `LOS_MEMORY` adds a countdown timer when LOS is lost during chase — NPC gives up after N seconds without regaining sight. Both Chase and Guard support these. Set `REQUIRE_LOS = false` for omniscient NPCs; omit `LOS_MEMORY` for infinite chase persistence.
- State label annotates LOS countdown in cyan during memory phase: `Chasing (3.0s)` → `Chasing (0.0s)` → transitions to lost state

### Suburban House (MCP-constructed, not in source)
- Two-story suburban home built via MCP `run_code` directly in Studio (not config-driven)
- Model: `Workspace.SuburbanHouse` — 96 parts (floors, walls, stairs)
- World position: main house X:80-180, Z:-30 to Z:30; garage extends to X:210
- **First floor (Y=0):** Living Room, Kitchen/Dining, Master Bedroom, Corridor, Entrance Hall, Bedroom 2, Bathroom, Utility Room, Garage, 12-step staircase in entrance hall
- **Second floor (Y=13):** Bedroom 3, Bedroom 4, Landing (with stairwell void), Master Suite, Upstairs Bath, Master Ensuite
- Color-coded floors per room, off-white walls, doorway openings (5-stud wide, 9-stud tall), open-plan kitchen (20-stud opening), 14-stud garage door
- Staircase: 12 steps ascending south-to-north (Z=48→Z=34) from entrance hall to second floor landing
- Idempotent construction script — re-run to rebuild. Plan file: `.claude/plans/ethereal-wiggling-sonnet.md`
- No NPCs placed in house yet

## Development Workflow

```bash
# Start Rojo sync
rojo serve

# In Studio: Rojo plugin > Connect
# If files don't appear, verify sync via MCP (run_code) before debugging code

# Before committing
selene src/
stylua --check src/
```

### MCP Servers
- **Official** (`roblox-studio`): `mcp__roblox-studio__run_code` / `insert_model` — primary tool
- **boshyxd** (`robloxstudio`): HTTP API at `localhost:3003/mcp/*` — health check: `curl localhost:3003/health`
  - Useful for: `get_project_structure`, `search_objects`, `get_script_source`, `mass_set_property`
  - Does NOT register tools in Claude Code — use via `curl` only

## Documentation

**Primary (Context7 MCP):**
- `/websites/create_roblox` — Tutorials, guides, best practices
- `/websites/create_roblox_reference_engine` — Engine API reference

**Fallback (if Context7 unavailable):**
- Engine API: https://create.roblox.com/docs/reference/engine
- Guides: https://create.roblox.com/docs
- Use WebSearch/WebFetch with `site:create.roblox.com` for specific lookups

## Conventions

- Luau style guide: `docs/luau-conventions.md` — read before writing Luau code
- Luau implementation patterns: `docs/luau-patterns.md` — read when implementing common systems
- Lessons learned: `docs/lessons-learned.md` — read at session start, update via `/session:postmortem`
- Use `Logger` module instead of raw `print()`
- All remote events go through `Remotes` module

## Learnings & Gotchas

**AI agents: Update this section when you discover something doesn't work as expected, is outdated, or has a better alternative. Check this section before implementing to avoid repeating mistakes.**

Format: `- [Category] Brief description of what doesn't work and what to do instead`

### Luau Type Gotchas

- **[Types] String unions as table keys** — `{ [MyUnion]: number }` breaks dot-access like `TABLE.KEY`. Let Luau infer instead.
- **[Types] Type narrowing on self.field** — `if self._foo then self._foo:Method()` doesn't narrow. Assign to local first: `local foo = self._foo; if foo then foo:Method() end`
- **[Types] Optional returns** — When a function can return nil (validation failure, etc.), explicitly type return as `T?`
- **[Types] Module field annotations** — Use `Module.field = {} :: Type` not `Module.field: Type = {}`
- **[Types] Private fields in classes** — Define internal impl type (`type FooImpl = { _field: T? }`) and use in constructor: `local self: FooImpl = setmetatable({} :: any, Foo)`

### PathfindingService Gotchas

- **[Pathfinding] GetWaypoints() waypoint 1 is start position** — Always skip index 1 and start traversal from index 2. Waypoint 1 has the same XZ as the NPC but at navmesh height (Y=0), causing 3D distance checks to fail (hip height Y mismatch). `MoveToFinished:Wait()` doesn't have this problem (it ignores Y).
- **[Pathfinding] SpawnLocation blocks NPC movement** — Default `CanCollide = true` makes it a physical wall. Set `CanCollide = false`; spawning uses `Enabled`, not collision.
- **[Pathfinding] PathfindingUseImprovedSearch** — Not scriptable. Must be set manually in Studio: Workspace > Properties > Enabled.

- **[Pathfinding] LOS raycast must exclude target model** — `Workspace:Raycast` from NPC to player hits the player's own body parts (legs, torso) before reaching the HumanoidRootPart position. Always include the target character in `FilterDescendantsInstances` alongside the NPC model when checking line of sight for detection.

### Humanoid & Physics Gotchas

- **[Humanoid] State disabling is environment-dependent** — `_disableUnusedStates` disables physics recovery states (`FallingDown`, `GettingUp`, `Freefall`, `Landed`). Safe on flat baseplates, but causes permanently stuck NPCs when obstacles can knock them over. Keep recovery states enabled when physical geometry exists.
