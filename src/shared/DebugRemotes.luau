--!strict
--[[
	DebugRemotes: String constants for debug panel remote names.

	Single source of truth — both client and server require this module
	so remote names stay in sync without magic strings.
]]

local DebugRemotes = {}

-- RemoteFunctions (request/response)
DebugRemotes.GET_NPC_STATUS = "Debug_GetNPCStatus"

-- RemoteEvents (client → server commands)
DebugRemotes.SPAWN_NPC = "Debug_SpawnNPC"
DebugRemotes.DESPAWN_NPC = "Debug_DespawnNPC"
DebugRemotes.CLEAR_ALL_NPCS = "Debug_ClearAllNPCs"
DebugRemotes.TOGGLE_VISUAL = "Debug_ToggleVisual"
DebugRemotes.TELEPORT_TO_NPC_CURRENT = "Debug_TeleportToNPCCurrent"
DebugRemotes.TELEPORT_NPC_TO_PLAYER = "Debug_TeleportNPCToPlayer"
DebugRemotes.SET_BEHAVIOR = "Debug_SetBehavior"

-- RemoteEvents (server → client pushes)
DebugRemotes.NPC_STATE_CHANGED = "Debug_NPCStateChanged"

return DebugRemotes
