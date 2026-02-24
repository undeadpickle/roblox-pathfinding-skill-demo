# Session Handoff

> Updated: 2026-02-23 (Session 10)
> Focus: Guard NPC — patrol + chase hybrid with LOS detection and return-to-post

---

## What Got Done

- **Guard NPC (4th NPC type)**: 3-state machine (Guarding ↔ Chasing ↔ Returning) combining random patrol with LOS-triggered chase. Spawns at (0, 5, 30) — north quadrant, away from other NPCs.
- **Random patrol**: Visits 5 waypoints in pentagon layout randomly (excludes last-visited to prevent back-to-back repeats). Uses `moveTo` in a spawned thread loop — same pattern as Wander NPC.
- **LOS detection**: Distance + raycast to initiate chase. `hasLineOfSight` exposed as public on NPCPathfinder with optional `excludeModels` parameter.
- **LOS raycast bug fix**: Initial implementation always returned false because the raycast hit the target player's body parts. Fixed by passing the player's character model in `excludeModels`.
- **Chase/disengage asymmetry**: LOS+distance required to START chasing, distance-only to MAINTAIN chase. Prevents LOS flicker at wall edges.
- **Return-to-post**: When target lost, Guard finds nearest waypoint, walks to it, then resumes random patrol. Uses `guardReachedWaypoint` flag (initialized false in onEnter) to signal completion.
- **Guard obstacles**: 2 wall obstacles flanking patrol zone center create LOS-breaking corridors for meaningful LOS gameplay.
- **Debug visuals**: Orange detection disc (18-stud radius), orange numbered waypoint markers (no connecting lines — random order), state labels (Guarding=orange, Chasing=red, Returning=cyan).
- **Throttled detection**: Guard's `onUpdate` detection check throttled at 0.2s (`DETECT_INTERVAL`) to avoid raycasting every frame.
- **Lessons learned**: 3 new rules (LOS raycast target exclusion, chase/disengage asymmetry, behavior logic in state machine not pathfinder).
- **CLAUDE.md updated**: Architecture sections updated for 4th NPC, Guard-specific docs, LOS gotcha.

## Files Changed

- `src/server/modules/NPCManager.luau` — Guard NPCEntry fields, GUARD_STATES (3 states), createGuardWaypointMarkers helper, Guard spawn wiring, orange detection disc
- `src/server/modules/NPCPathfinder.luau` — Renamed `_hasLineOfSight` to public `hasLineOfSight`, added optional `excludeModels` parameter
- `src/shared/GameConfig.luau` — Guard config block (spawn pos, speeds, waypoints, detection), 2 guard wall obstacles, state label colors (Guarding, Returning)
- `docs/lessons-learned.md` — 3 new rules
- `CLAUDE.md` — Architecture updates for Guard NPC, LOS gotcha

## What's Next

1. **Playtest verification**: Stairs pathfinding, NPC orientation during chase, wander beam rendering (carried over from last session)
2. **More elevation variety**: Ramps, platforms, multi-level terrain to test vertical pathfinding
3. **Guard tuning**: Adjust WALK_SPEED, DETECTION_RADIUS, waypoint positions based on playtest feel
4. **Phase 1 core loop**: Basic UI showing game state, one complete player flow

## Blockers

None.

---

## Session Retrospective

### What Worked

- **Pre-mortem caught real bugs**: The pre-mortem identified the LOS flicker issue (Chasing→Returning using LOS would cause flicker at wall edges) and the `guardReachedWaypoint` race condition — both were addressed before they became runtime bugs.
- **Reusing existing patterns**: Guard random patrol reuses the Wander NPC's thread+moveTo loop. Guard chase reuses `followTarget` unchanged. Guard detection disc reuses `createDetectionRadiusCircle` with a post-creation color override. Zero new methods needed on NPCPathfinder beyond exposing `hasLineOfSight`.
- **State machine scales well**: Adding a 3-state NPC required zero changes to NPCStateMachine. The generic state machine + PostSimulation tick pattern handles 4 NPCs with different complexities cleanly.

### What Broke

- **LOS raycast hitting player body**: The `hasLineOfSight` method excluded only the NPC model from the raycast. The ray to the player's HumanoidRootPart hit the player's own legs/torso first, making LOS always false. Required adding `excludeModels` parameter.
- **State label appeared non-functional on first test**: Was actually a stale Rojo sync — the label worked on the next playtest. Logs confirmed transitions were firing correctly the whole time.

### Wrong Assumptions

- Assumed `hasLineOfSight` would work for player detection out of the box. The method was designed for pursuit optimization (NPC→point), not NPC→player-model detection. The target model's own collision geometry wasn't considered.

---

## Key Architecture Notes for Next Session

- **Guard NPC has 3 states**: Guarding (random patrol thread), Chasing (followTarget), Returning (moveTo nearest waypoint). Transitions: Guarding→Chasing (LOS+distance), Chasing→Returning (distance-only), Returning→Guarding (reached waypoint), Returning→Chasing (LOS+distance interrupt).
- **`hasLineOfSight` is now public** with optional `excludeModels: { Model }?` parameter. Internal callers in `moveTo` and `followTarget` don't pass it (backward-compatible). Guard detection passes `{ target }` to exclude the player model.
- **Guard detection is throttled**: `DETECT_INTERVAL = 0.2s` in both Guarding and Returning states. Chase re-evaluation uses `REEVALUATE_INTERVAL = 1s`.
- **Guard patrol uses `moveTo` loop, not `patrol()`**: Random waypoint selection doesn't fit the sequential `patrol()` API. The thread pattern matches Wander NPC.
- **Chase config values**: Chase NPC: WALK_SPEED=8, DETECTION_RADIUS=15. Guard NPC: WALK_SPEED=10, DETECTION_RADIUS=18.

---

## CLAUDE.md Suggestions

None — updated during this session.
