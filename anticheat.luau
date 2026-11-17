--[[
thx for downloading this anti cheat by valaentd on github

this code checks for :
speed cheats
flying  / the super big jumps
noclipping
and SHOULD prevent teleports, as

ve tested this and it stopped flying and rapid changes
in the C frames

theres basically a like "budget" if that makes sense
where it allow syou to have a certain amount of speed
it refills as they walk so they cant get flagged if
theyre actually moving at a proper speed

MAX_AIR_TIME is self explanatory xd
its the max air time that your allowed to have (prevents flying)

it also waits to start so theres a small grace period
when the player joins so that they arent just like
insta flagged from the anti cheat

lastly,  the movement "budget" can bank back so that
laggy players arent just like executed

thx for using <3 
]]


--setup
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local SPEED_MULTIPLIER = 1.3 -- allowed speed = WalkSpeed x this
local MIN_ALLOWED_SPEED = 16 -- floor for allowed speed (e.g. WalkSpeed is 0 while stunned)
local SPEED_BUDGET_SECONDS = 2 -- seconds of movement a player can bank (lag tolerance)
local SPEED_SLACK = 4 -- extra studs always allowed on top of the budget
local MAX_AIR_TIME = 2.5 -- seconds airborne without coming down before it counts as flying
local JUMP_HEIGHT_SLACK = 6 -- studs allowed above the normal jump height
local GROUND_CHECK_SLACK = 2.5 -- studs below the feet that still count as "on the ground"
local GROUND_PROBE_SIZE = Vector3.new(2, 0.5, 2)
local MIN_MOVE_TO_RAYCAST = 0.05
local SNAP_ACCEPT_DISTANCE = 3 -- client is "caught up" once this close to the snap point
local SNAP_SETTLE_TIME = 1 -- re-snap if the client hasn't caught up after this long
local SPAWN_GRACE = 2
local WARN_COOLDOWN = 5

local tracked = {} -- [player] = state

local pathParams = RaycastParams.new()
pathParams.FilterType = Enum.RaycastFilterType.Exclude
pathParams.RespectCanCollide = true
pathParams.IgnoreWater = true

local function refreshPathFilter()
	local characters = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(characters, player.Character)
		end
	end
	pathParams.FilterDescendantsInstances = characters
end

local function getJumpHeight(humanoid)
	if humanoid.UseJumpPower then
		return (humanoid.JumpPower ^ 2) / (2 * workspace.Gravity)
	end
	return humanoid.JumpHeight
end

local function getGroundDistance(humanoid, root)
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		return root.Size.Y / 2 + 2 -- r6 handling
	end
	return humanoid.HipHeight + root.Size.Y / 2
end

local function isGrounded(state)
	local distance = getGroundDistance(state.humanoid, state.root) + GROUND_CHECK_SLACK
	local result = workspace:Blockcast(
		CFrame.new(state.root.Position),
		GROUND_PROBE_SIZE,
		Vector3.new(0, -distance, 0),
		state.groundParams
	)
	return result ~= nil
end

local function logViolation(player, state, reason)
	local now = os.clock()
	if now - state.lastWarn > WARN_COOLDOWN then
		state.lastWarn = now
		warn(string.format("[AntiCheat] %s snapped back: %s", player.Name, reason))
	end
end

local function snapBack(player, state, position, reason)
	local root = state.root
	root.CFrame = CFrame.new(position) * root.CFrame.Rotation
	root.AssemblyLinearVelocity = Vector3.zero

	local now = os.clock()
	state.lastPos = position
	state.lastGroundedTime = now
	state.settleMode = "snap"
	state.settleUntil = now + SNAP_SETTLE_TIME
	logViolation(player, state, reason)
end

local function startTracking(player, character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")

	if not humanoid or not root then
		return
	end

	--dont flag standing on top of someone else
	local groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Exclude
	groundParams.FilterDescendantsInstances = { character }
	groundParams.RespectCanCollide = true

	local now = os.clock()
	tracked[player] = {
		humanoid = humanoid,
		root = root,
		groundParams = groundParams,
		lastPos = root.Position,
		budget = MIN_ALLOWED_SPEED * SPEED_MULTIPLIER * SPEED_BUDGET_SECONDS + SPEED_SLACK,
		lastGroundedTime = now,
		lastGroundedPos = root.Position,
		settleMode = "spawn",
		settleUntil = now + SPAWN_GRACE,
		lastWarn = 0,
		sampleElapsed = 0,
	}
	refreshPathFilter()
end

local function onPlayerAdded(player)
	player.CharacterAdded:Connect(function(character)
		startTracking(player, character)
	end)
	player.CharacterRemoving:Connect(function()
		tracked[player] = nil
		task.defer(refreshPathFilter)
	end)
	if player.Character then
		task.spawn(startTracking, player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
Players.PlayerRemoving:Connect(function(player)
	tracked[player] = nil
	task.defer(refreshPathFilter)
end)

RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()

	for player, state in tracked do
		local root = state.root
		local humanoid = state.humanoid
		local position = root.Position

		--if ur dead ur good
		if not root.Parent or humanoid.Health <= 0 or root.Anchored or humanoid.SeatPart then
			state.lastPos = position
			state.lastGroundedTime = now
			continue
		end

		state.sampleElapsed += dt
		if state.sampleElapsed < 0.1 then
			continue
		end
		local sampleDt = state.sampleElapsed
		state.sampleElapsed = 0

		local allowedSpeed = math.max(humanoid.WalkSpeed, MIN_ALLOWED_SPEED) * SPEED_MULTIPLIER
		local maxBudget = allowedSpeed * SPEED_BUDGET_SECONDS + SPEED_SLACK
		state.budget = math.min(state.budget + allowedSpeed * sampleDt, maxBudget)

		local graceUntil = player:GetAttribute("AntiCheatGraceUntil")
		if type(graceUntil) == "number" and now < graceUntil then
			state.lastPos = position
			state.lastGroundedTime = now
			state.budget = maxBudget
			continue
		end

		--let them spawn so they dont get insta flagged
		if state.settleMode == "spawn" then
			if now < state.settleUntil then
				state.lastPos = position
				state.lastGroundedPos = position
				state.lastGroundedTime = now
				continue
			end
			state.settleMode = nil
		end

		if state.settleMode == "snap" then
			if (position - state.lastPos).Magnitude <= SNAP_ACCEPT_DISTANCE then
				state.settleMode = nil
				state.lastPos = position
			elseif now > state.settleUntil then
				snapBack(player, state, state.lastPos, "ignored correction")
				continue
			else
				state.lastGroundedTime = now
				continue
			end
		end

		local delta = position - state.lastPos

		--noclip
		if delta.Magnitude > MIN_MOVE_TO_RAYCAST then
			local hit = workspace:Raycast(state.lastPos, delta, pathParams)
			if hit then
				snapBack(player, state, state.lastPos, "moved through " .. hit.Instance:GetFullName())
				continue
			end
		end

		--speeeed
		state.budget -= Vector3.new(delta.X, 0, delta.Z).Magnitude
		if state.budget < 0 then
			state.budget = 0
			snapBack(player, state, state.lastPos, "moving too fast")
			continue
		end

		--anti fly
		if isGrounded(state) then
			state.lastGroundedTime = now
			state.lastGroundedPos = position
		else
			local heightAboveTakeoff = position.Y - state.lastGroundedPos.Y
			if heightAboveTakeoff > getJumpHeight(humanoid) + JUMP_HEIGHT_SLACK then
				snapBack(player, state, state.lastGroundedPos, "jumped too high")
				continue
			elseif now - state.lastGroundedTime > MAX_AIR_TIME and heightAboveTakeoff > -1 then
				snapBack(player, state, state.lastGroundedPos, "flying")
				continue
			end
		end

		state.lastPos = position
	end
end)
