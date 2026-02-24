--!strict
--[[
	NPCStateMachine - A lightweight finite state machine.

	States have three optional lifecycle hooks:
	  onEnter(context)           — called once when entering the state
	  onUpdate(context, dt)      — called every tick; return a state name to transition, or nil to stay
	  onExit(context)            — called once when leaving the state

	The machine does NOT tick itself. Call :update(dt) from an external loop
	(e.g., RunService.PostSimulation). This keeps the machine decoupled from
	any specific timing — you control when and how often it ticks.

	"context" is any table you pass at construction. For NPCs, this is typically
	a table with the model, pathfinder, and behavior-specific state. The state
	machine doesn't care what's inside — it just passes it through to hooks.

	Usage:
		local sm = NPCStateMachine.new("Idle", {
			Idle = {
				onEnter = function(ctx) ... end,
				onUpdate = function(ctx, dt) return "Running" end,
				onExit = function(ctx) ... end,
			},
			Running = { ... },
		}, myContext)

		-- Each frame:
		sm:update(deltaTime)

		-- Query state:
		sm:getCurrentState() -- "Idle" or "Running"

		-- Force transition from outside:
		sm:transitionTo("Running")

		-- Cleanup:
		sm:destroy()

	Replace warn() calls with your project's logger if you have one.
]]

local NPCStateMachine = {}
NPCStateMachine.__index = NPCStateMachine

-- State definition: all hooks are optional.
-- onUpdate returns a state name to trigger a transition, or nil to stay.
export type StateDefinition = {
	onEnter: ((context: any) -> ())?,
	onUpdate: ((context: any, dt: number) -> string?)?,
	onExit: ((context: any) -> ())?,
}

export type StateMap = { [string]: StateDefinition }

function NPCStateMachine.new(
	initialState: string,
	states: StateMap,
	context: any,
	onStateChanged: ((newState: string, previousState: string?) -> ())?
)
	assert(states[initialState], `NPCStateMachine: initial state "{initialState}" not found in state map`)

	local self = setmetatable({}, NPCStateMachine)
	self._currentStateName = initialState
	self._states = states
	self._context = context
	self._isDestroyed = false
	self._onStateChanged = onStateChanged

	-- Enter the initial state immediately so the NPC starts doing something on frame 1
	local initial = states[initialState]
	if initial.onEnter then
		initial.onEnter(context)
	end

	-- Notify listener of initial state (previousState is nil for first state)
	if onStateChanged then
		onStateChanged(initialState, nil)
	end

	return self
end

-- Call every frame from an external loop (e.g., PostSimulation).
-- If onUpdate returns a state name, transitions to that state.
-- Only one transition per tick to prevent infinite loops.
function NPCStateMachine:update(dt: number): ()
	if self._isDestroyed then
		return
	end

	local currentState = self._states[self._currentStateName]
	if not currentState or not currentState.onUpdate then
		return
	end

	local nextStateName = currentState.onUpdate(self._context, dt)

	if nextStateName then
		self:transitionTo(nextStateName)
	end
end

-- Transition to a new state. Calls onExit on the old state, then onEnter on the new one.
-- Self-transitions are allowed (e.g., Chasing -> Chasing to switch targets).
function NPCStateMachine:transitionTo(stateName: string): ()
	if self._isDestroyed then
		return
	end

	local nextState = self._states[stateName]
	if not nextState then
		warn(`[NPCStateMachine] Attempted transition to unknown state: "{stateName}"`)
		return
	end

	-- Exit current state
	local currentState = self._states[self._currentStateName]
	if currentState and currentState.onExit then
		currentState.onExit(self._context)
	end

	local previousName = self._currentStateName
	self._currentStateName = stateName

	-- Enter new state
	if nextState.onEnter then
		nextState.onEnter(self._context)
	end

	-- Notify listener of state change
	if self._onStateChanged then
		self._onStateChanged(stateName, previousName)
	end
end

-- Returns the current state name. Useful for debug UI or logging.
function NPCStateMachine:getCurrentState(): string
	return self._currentStateName
end

-- Calls onExit on the current state (so it can clean up threads, stop pathfinder, etc.),
-- then marks the machine as destroyed.
function NPCStateMachine:destroy(): ()
	if self._isDestroyed then
		return
	end
	self._isDestroyed = true

	-- Let the current state clean up
	local currentState = self._states[self._currentStateName]
	if currentState and currentState.onExit then
		currentState.onExit(self._context)
	end

	-- Clear references for GC
	self._states = nil :: any
	self._context = nil
	self._onStateChanged = nil
end

return NPCStateMachine
