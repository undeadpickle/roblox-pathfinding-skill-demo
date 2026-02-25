# Session Handoff

> Updated: 2026-02-24 (Session 15)
> Focus: Suburban house interior construction (two-story, MCP-built)

---

## What Got Done

### Suburban House Construction

Built a complete two-story suburban home interior in Roblox Studio via MCP `run_code`. The house is a `SuburbanHouse` Model in Workspace with 96 parts, placed well clear of the existing NPC demo area (world X:80-210).

**First Floor (Y=0):**
- 9 rooms: Living Room (30x60), Kitchen/Dining (30x26), Master Bedroom (40x26), Corridor (70x8), Entrance Hall (L-shaped, split for stairwell), Bedroom 2 (22x26), Bathroom (14x26), Utility Room (12x26), Garage (30x40)
- Color-coded floors per room (warm wood, cream tile, blue-grey carpet, etc.)
- Front door opening (south wall), garage door (14-stud wide, east wall), utility-to-garage door
- Open-plan kitchen (20-stud opening to corridor)
- 12-step staircase in entrance hall (ascending south-to-north, Y=1 to Y=13)

**Second Floor (Y=13):**
- 6 rooms: Bedroom 3 (36x30), Bedroom 4 (36x30), Landing/Hallway (20x60, split into 4 parts), Master Suite (44x34), Upstairs Bath (22x26), Master Ensuite (22x26)
- Stairwell void in landing floor (no floor over X=40..52, Z=34..48)
- Stairwell safety walls on 3 sides (north open = exit onto landing)
- All rooms have doorway openings to landing/hallway

**Construction approach:**
- Two Luau scripts executed via `mcp__roblox-studio__run_code`
- Script 1: First floor (rebuilt with staircase modifications)
- Script 2: Second floor (added to existing model)
- Idempotent: destroys and recreates on re-run
- Plan file: `.claude/plans/ethereal-wiggling-sonnet.md`

## Files Changed

### Docs
- `CLAUDE.md` — Added "Suburban House" subsection under Map & Obstacles
- `docs/lessons-learned.md` — 2 new entries (MCP construction patterns)
- `docs/session-handoff.md` — This file

## What's Next

### House NPCs
1. **Add NPCs to the house** — Place pathfinding NPCs inside the suburban home to test multi-room and multi-story navigation
2. **Test staircase pathfinding** — Verify NPCs can navigate stairs between floors (may need AgentCanClimb or step height tuning)

### Debug Panel Roadmap (carried forward)
3. **Batch 2**: Force state transitions + Respawn individual NPC
4. **Batch 3**: Config overrides / tuning sliders (live walk speed, detection radius)
5. **Batch 4**: Event log (timestamped state transitions) + Player state inspector

### Other
6. **More elevation variety**: Ramps, platforms, multi-level terrain
7. **Phase 1 core loop**: Player-facing UI, one complete player flow

## Blockers

None.

---

## Key Architecture Notes for Next Session

- **House is MCP-constructed, not in source code.** The `SuburbanHouse` model exists only in the Studio place file. It's not created by MapSetup or GameConfig. To rebuild, re-run the construction scripts (see plan file for the complete Luau code).
- **Staircase pathfinding may need tuning.** Steps are 1 stud high x ~1.17 studs deep. Default PathfindingService agent parameters (`AgentCanClimb = false`) may not handle stairs. Options: enable `AgentCanClimb`, reduce step height, or use a ramp instead.
- **No collision group on house parts.** House walls are standard Parts (no collision group). NPCs using the "NPCs" collision group will collide with walls normally, which is correct behavior.
- **Second floor exterior walls are independent of first floor.** The F2 exterior walls sit at Y=14-26, directly above F1 exterior walls at Y=1-13. They're separate Parts, not extensions.

---

## CLAUDE.md Suggestions

None — updated this session.
