# Session Handoff

> Updated: 2026-02-26
> Focus: Toolkit refactor Phase 2 — runtime behavior swap

---

## What Got Done

- **`setBehavior(npcId, behaviorType, behaviorConfig?)`**: Full runtime behavior swap on NPCManager. Tears down old state machine (triggers onExit), scrubs all 12 behavior-specific ctx fields via `scrubBehaviorFields`, cleans debug visuals (disc + waypoint folder), updates entry identity, re-wires via `wireBehavior`. Model and pathfinder persist across swaps.
- **`wireBehavior` idempotency**: State label creation guarded with `if not entry.stateLabel then` so it persists across swaps. Detection disc is always freshly created (old one destroyed by `cleanupEntry`).
- **`DebugVisuals.cleanupEntry` nil fix**: Now nils `debugFolder` and `debugDisc` fields after `:Destroy()`. Prevents `updateTick` from accessing destroyed Instances when entries stay in `activeNPCs` (as they do during `setBehavior`, unlike `despawnNPC`).
- **Verified working**: Three swap scenarios tested in Studio playtest (chase→patrol, patrol→chase, guard→wander). Zero errors. Disc creation/destruction, state label persistence, and behavior re-wiring all confirmed.

## What's Next

1. **Phase 2: Dynamic debug panel** — Server-driven NPC list instead of hardcoded `NPC_ORDER` in DebugPanel. Dynamically spawned NPCs should appear in the panel. Files: `src/client/DebugPanel.luau`, `src/server/modules/DebugService.luau`
2. **Phase 2: DebugService spawn position fix** — `TELEPORT_TO_NPC` reads `GameConfig.NPC.SPAWN_POSITIONS` which won't work for dynamic NPCs. Should read from `NPCEntry.spawnPosition` instead. File: `src/server/modules/DebugService.luau`
3. **Phase 2: Debug panel setBehavior UI** — Add a remote + UI control so the debug panel can trigger behavior swaps. `DebugRemotes.SET_BEHAVIOR` → `NPCManager.setBehavior()`.
4. **Phase 3: Polish** — Waypoint tag resolver utility, optional camelCase config field rename, API documentation
5. **CLAUDE.md update** — NPCManager description (lines 63, 76) needs `setBehavior` added to the public API list. Suggested but not auto-edited per global rules.

## Blockers

None.

---

## Session Retrospective

### What Worked

- **Pre-mortem before implementation**: Caught the `cleanupEntry` nil issue — `updateTick` would have accessed destroyed disc Instances since entries stay in `activeNPCs` during swaps. Also validated that all state `onExit` handlers properly clean up threads before the safety-net scrub.
- **Plan-first with thorough exploration**: Three parallel explore agents mapped every ctx field written by every state across all 4 behaviors. The scrub list was complete on first try — no missed fields.
- **Reusing `wireBehavior`**: One guard clause was the only modification needed. No code duplication.

### What Broke

Nothing. Clean implementation.

### Wrong Assumptions

None this session.

---

## Architecture Notes

- **Plan file**: `.claude/plans/lexical-humming-sparrow.md` — setBehavior design decisions, pre-mortem results, verification checklist.
- **Previous plan**: `.claude/plans/enchanted-noodling-stallman.md` — Full Phase 1/2/3 plan. Still relevant for remaining Phase 2/3 work.
- **setBehavior flow**: destroy SM → `scrubBehaviorFields()` → `DebugVisuals.cleanupEntry()` → update entry fields → `wireBehavior()`. All synchronous, no yields.
- **Key invariant**: `wireBehavior` is now safe for both initial setup and re-wiring. State label is idempotent. Disc and state machine are always created fresh.

## CLAUDE.md Suggestions

- Add `setBehavior` to NPCManager public API list (line 63) and NPC Pathfinding System section (line 76)
