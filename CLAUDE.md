# RobloxPathfindingSkillDemo

## Overview

NPC pathfinding demo showcasing chase, patrol, and wander behaviors using PathfindingService.

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
- `GameConfig` — Central configuration values (NPC config, map obstacles)
- `Remotes` — Client-server communication helpers
- `Logger` — Debug logging with [Server]/[Client] prefixes
- `MapSetup` — Config-driven obstacle geometry spawner (reads `GameConfig.MAP.OBSTACLES`)
- `NPCPathfinder` — PathfindingService wrapper with moveTo, patrol, followTarget, wander
- `NPCStateMachine` — Generic finite state machine (shared, reusable for any system). Optional `onStateChanged` callback (4th param) fires on initial state and every transition.
- `NPCManager` — Spawns NPCs, wires state machines to pathfinder, manages lifecycle

### NPC Pathfinding System
- 3 demo NPCs: Chase (follows nearest player), Patrol (loops waypoints), Wander (random points in radius)
- Behavior driven by state machines: Chase (Idle ↔ Chasing), Patrol (Patrolling), Wander (Wandering)
- Single PostSimulation tick drives all state machines; states call NPCPathfinder methods
- R15 rigs created at runtime via `Players:CreateHumanoidModelFromDescription()`
- Server-authoritative: `SetNetworkOwner(nil)` on all NPC parts
- Collision group "NPCs" prevents NPC-to-NPC physics jitter
- `game:BindToClose` ensures cleanup on server shutdown
- Debug state labels (BillboardGui) above NPC heads show current state with color coding, gated by `GameConfig.GAME.DEBUG`

### Map & Obstacles
- Obstacle geometry defined in `GameConfig.MAP.OBSTACLES` (position, size, color per obstacle)
- `MapSetup.initialize()` creates anchored `CanCollide = true` Parts in a `Workspace.Obstacles` folder
- PathfindingService auto-carves obstacles from navmesh — no pathfinder code changes needed
- MapSetup runs before NPCManager so navmesh includes obstacles on first path computation
- Wander target generation uses `Workspace:Raycast` to reject points inside obstacle footprints
- Chase NPC has configurable `WALK_SPEED` (default 24, vs player default 16)

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

- See `.claude/rules/` for Luau style guide
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

### Humanoid & Physics Gotchas

- **[Humanoid] State disabling is environment-dependent** — `_disableUnusedStates` disables physics recovery states (`FallingDown`, `GettingUp`, `Freefall`, `Landed`). Safe on flat baseplates, but causes permanently stuck NPCs when obstacles can knock them over. Keep recovery states enabled when physical geometry exists.
