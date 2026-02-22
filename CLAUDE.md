# RobloxPathfindingSkillDemo

## Overview

Brief description of what this project does.

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
- `GameConfig` — Central configuration values
- `Remotes` — Client-server communication helpers
- `Logger` — Debug logging with [Server]/[Client] prefixes

### Genre-Specific Systems (to build)
_No game type selected — add your custom systems here as you design the game loop._

## Development Workflow

```bash
# Start Rojo sync
rojo serve

# In Studio: Rojo plugin > Connect

# Before committing
selene src/
stylua --check src/
```

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

<!-- Add project-specific learnings below -->
