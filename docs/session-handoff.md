# Session Handoff

> Updated: 2026-02-22 (Session 4)
> Focus: GC audit, cleanup fixes, state machine architecture

---

## What Got Done

- **GC/cleanup audit**: Subagent-driven audit found 2 critical leaks (untracked `PlayerAdded` connection, untracked waypoint marker folder) and 5 warnings. All critical and warning issues fixed.
- **BindToClose hook**: `NPCManager.cleanup()` is now called on server shutdown via `game:BindToClose`.
- **IsDescendantOf safety**: `followTarget` loop now checks model existence after `task.wait` yield.
- **Defensive thread cancellation**: `startChaseBehavior` and `startWanderBehavior` cancel existing threads before spawning new ones.
- **NPCStateMachine module**: New generic FSM class in `src/shared/NPCStateMachine.luau`. States have `onEnter`/`onUpdate`/`onExit` hooks, ticked externally via `PostSimulation`.
- **NPCManager refactored to state machines**: Replaced `startChaseBehavior`/`startPatrolBehavior`/`startWanderBehavior` with state definitions. Chase uses Idle ↔ Chasing, Patrol uses Patrolling, Wander uses Wandering.
- **Chase no longer needs PlayerAdded connection**: Idle state's `onUpdate` scans for players automatically. Eliminated the `chaseStarted` flag and deferred-start logic.
- **Pathfinding research**: Surveyed Roblox community patterns (SimplePath, state machines, ECS) and general game AI (behavior trees, utility AI, steering behaviors, HTN). Informed the state machine decision.
- **All behaviors verified in Studio**: MCP log analysis confirmed Patrol cycling waypoints, Wander hitting random points, Chase transitioning Idle → Chasing on player detection.
- **Post-mortem completed**: 2 new lessons added to `tasks/lessons.md`, CLAUDE.md updated with state machine architecture.

## What's Next

1. **Phase 1 UI**: Show NPC states (Idle/Chasing/Patrolling/Wandering) via BillboardGuis above NPCs. `stateMachine:getCurrentState()` is already exposed for this. Relevant files: `src/server/modules/NPCManager.luau`
2. **Add obstacles**: Current map is flat baseplate. Add walls/obstacles to test pathfinding around geometry.
3. **Wander radius visualization**: Debug circle showing wander boundary, similar to patrol waypoint markers. Gate behind `GameConfig.GAME.DEBUG`.
4. **Polish NPC behaviors**: Tune speeds, detection distances, patrol waypoints. Consider health bars.

## Blockers

- None

---

## Session Retrospective

### What Worked

- **Subagent-driven GC audit**: Launching an Explore agent with specific audit criteria (connection leaks, instance leaks, thread leaks, table leaks, per-frame costs) produced a thorough report with line numbers. Systematic and faster than manual review.
- **Research-then-decide pattern**: 3 parallel Explore agents (current code, Roblox community, general game AI) gave a comprehensive landscape before committing to state machines. Informed decision, not a guess.
- **MCP playtest verification**: `LogService:GetLogHistory()` confirmed state machine transitions without manual testing reports.
- **Atomic commits**: GC fixes and state machine in separate commits. Clean history.

### What Broke

- Nothing broke this session. GC fixes and state machine refactor both worked on first playtest.

### Wrong Assumptions

- None this session. The GC audit caught issues before they became problems, and the state machine was a straightforward refactor of existing implicit states.

---

## Key Architecture Notes for Next Session

- **State machine module** is in `src/shared/` (not `src/server/`) — it's generic and reusable for client systems too.
- **State hooks receive the NPCEntry as `context`** — chase state stores `chaseTarget` and `chaseReevalTimer` directly on the entry table.
- **Self-transitions are allowed** — `Chasing → Chasing` triggers exit/enter cycle for target switching. This is intentional.
- **Patrol and Wander are single-state machines** — extensibility point for future Alert, Flee, Curious states.
- **One PostSimulation connection ticks all machines** — stored in `moduleConnections`, disconnected in cleanup.

---

## CLAUDE.md Suggestions

None — CLAUDE.md was updated this session with NPCStateMachine in Key Modules and state machine architecture in NPC Pathfinding System.
