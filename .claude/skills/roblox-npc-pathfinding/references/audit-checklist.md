# Pathfinding Audit Checklist

Use this checklist when reviewing existing pathfinding code. Work through each section in order. Output findings as: CRITICAL (will cause bugs/crashes), WARNING (fragile/suboptimal), or SUGGESTION (nice-to-have improvement).

## 1. API Currency

- [ ] **No deprecated APIs** — Check for `ComputeSmoothPathAsync`, `ComputeRawPathAsync`, `FindPathAsync`. All should be replaced with `CreatePath()` → `ComputeAsync()`.
  - Severity: CRITICAL if found

- [ ] **PathfindingUseImprovedSearch enabled** — Check Workspace property. Should be `Enabled`.
  - Severity: WARNING (missing major quality improvements)

- [ ] **Using PathSettings.SupportPartialPath** — Is the game benefiting from partial paths? Should it be?
  - Severity: SUGGESTION

- [ ] **Agent params explicitly set** — Is `CreatePath()` called with agent parameters, or using defaults?
  - Severity: WARNING if defaults don't match NPC size

## 2. Error Handling

- [ ] **pcall around ComputeAsync** — `ComputeAsync` can throw. Must be wrapped.
  - Severity: CRITICAL if missing

- [ ] **Path.Status checked after compute** — Code must check for `Success` (and optionally `ClosestNoPath`) before traversing.
  - Severity: CRITICAL if missing

- [ ] **Empty waypoints handled** — `GetWaypoints()` can return an empty array. Check before iterating.
  - Severity: WARNING

- [ ] **NaN/nil position guards** — Start and end positions validated before ComputeAsync. Destroyed NPCs can produce nil/NaN.
  - Severity: CRITICAL for production code

## 3. Network and Physics

- [ ] **Network ownership locked** — `PrimaryPart:SetNetworkOwner(nil)` called on NPC spawn.
  - Severity: CRITICAL (causes jitter, MoveToFinished latency, unreliable movement)

- [ ] **Set once, not repeatedly** — SetNetworkOwner should be called once at spawn, not every frame/update.
  - Severity: WARNING (unnecessary overhead)

- [ ] **PrimaryPart set on model** — `npcModel.PrimaryPart` must be assigned to HumanoidRootPart.
  - Severity: CRITICAL if missing

- [ ] **NPC collision group configured** — NPCs assigned to a collision group with self-collisions disabled. Without this, grouped NPCs (e.g., converging on chase target) jitter from physics collisions.
  - Severity: WARNING for 1-5 NPCs, CRITICAL for 5+ NPCs that can group up

## 4. Path Traversal

- [ ] **Jump waypoints handled** — Check for `waypoint.Action == Enum.PathWaypointAction.Jump` and set `Humanoid.Jump = true`.
  - Severity: WARNING (NPCs fail to jump over gaps)

- [ ] **Custom waypoints handled** — If using PathfindingLinks, check for `Enum.PathWaypointAction.Custom` and `waypoint.Label`.
  - Severity: WARNING if links exist but aren't handled

- [ ] **MoveToFinished timeout protection** — `MoveToFinished` passes a `reached` boolean (`true` if arrived, `false` if the engine's hard 8-second timeout fired). Code must check this value. Ignoring it is a primary cause of NPCs freezing in production.
  - Severity: CRITICAL (NPC loops silently stop when timeout fires and code assumes arrival)

- [ ] **Blocked path handling** — `path.Blocked` event connected and triggers recompute when blocked waypoint is ahead of current position.
  - Severity: WARNING (NPCs walk into moved obstacles)

- [ ] **Stuck detection** — If NPC position hasn't changed meaningfully after several seconds, trigger recovery (recompute, teleport, or fail gracefully).
  - Severity: SUGGESTION

## 5. Architecture

- [ ] **Not script-per-NPC** — Using a centralized ModuleScript or OOP pattern, not individual Scripts parented to each NPC model.
  - Severity: WARNING for 10+ NPCs, CRITICAL for 30+

- [ ] **Connections cleaned up** — All event connections (MoveToFinished, Path.Blocked, Heartbeat) disconnected when NPC is destroyed.
  - Severity: CRITICAL (memory leak, ghost connections)

- [ ] **Path objects not re-created unnecessarily** — Reuse the same Path object with `ComputeAsync` instead of calling `CreatePath()` every recompute.
  - Severity: SUGGESTION (minor optimization)

- [ ] **Server-side execution** — Pathfinding logic runs on server for authoritative NPCs.
  - Severity: WARNING if on client (exploitable, inconsistent across clients)

## 6. Performance

- [ ] **Recompute throttled** — Not calling `ComputeAsync` every frame. Minimum interval of 0.3–1 second between recomputes.
  - Severity: CRITICAL if computing every frame with many NPCs

- [ ] **Direct MoveTo for short range** — Using direct `Humanoid:MoveTo()` when target is close and line-of-sight is clear, instead of pathfinding.
  - Severity: SUGGESTION (performance optimization)

- [ ] **Staggered computation** — For 10+ NPCs, not all recomputing on the same frame.
  - Severity: WARNING for 10-30 NPCs, CRITICAL for 30+

- [ ] **WaypointSpacing appropriate** — Not using default `4` everywhere. Outdoor areas should use larger spacing.
  - Severity: SUGGESTION

- [ ] **Unused Humanoid states disabled** — For 30+ NPCs, unnecessary Humanoid states disabled to reduce simulation cost.
  - Severity: SUGGESTION for 30-50 NPCs, WARNING for 50+

## 7. Robustness

- [ ] **NPC death handled** — When NPC dies (health = 0), pathfinding stops cleanly. No errors from trying to move a dead NPC.
  - Severity: CRITICAL

- [ ] **Target validation** — If chasing a player, check that player.Character exists and is alive before pathfinding to them.
  - Severity: CRITICAL (will error when player leaves/respawns)

- [ ] **Graceful degradation** — When path fails completely (NoPath), NPC does something sensible (wait, wander, return to spawn) instead of freezing or erroring.
  - Severity: WARNING

- [ ] **No infinite loops** — `while true do` loops have proper yield (`task.wait()`) and exit conditions (NPC destroyed, target lost).
  - Severity: CRITICAL if missing yield

## Output Template

After running the audit, present findings in this format:

### CRITICAL (Fix Immediately)
1. [Issue] — [Where in code] — [Specific fix]

### WARNINGS (Fix When Convenient)
1. [Issue] — [Where in code] — [Recommended change]

### SUGGESTIONS (Nice to Have)
1. [Improvement] — [What it would improve] — [How to implement]

For each CRITICAL and WARNING, provide the exact code change (before/after).
