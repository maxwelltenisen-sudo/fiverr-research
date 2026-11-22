-- BGServer (Script, ServerScriptService): runs the authoritative fight (BGCore) and talks to clients.
-- Clients send INPUT only (move, m1, skill, guard ...). Damage, cooldowns, meter, form changes and ability eligibility
-- are all decided here in BGCore. Studio-only preview buttons are refused outside Studio.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("BGConfig"))
local Clips = require(ReplicatedStorage:WaitForChild("BGClips"))
local Core = require(ReplicatedStorage:WaitForChild("BGCore"))

local stage = Workspace:WaitForChild("Showcase")
while not stage:GetAttribute("Ready") do task.wait(0.1) end

local remotes = ReplicatedStorage:FindFirstChild("BGRemotes")
if remotes then remotes:Destroy() end
remotes = Instance.new("Folder")
remotes.Name = "BGRemotes"
local function remote(name)
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local InputRE, ControlRE, SnapRE, EventRE = remote("Input"), remote("Control"), remote("Snap"), remote("Event")
remotes.Parent = ReplicatedStorage

local world = Core.new(Config, Clips)
local state = { controlled = "Blue", aiMode = "Idle" }
local isStudio = RunService:IsStudio()

local function applyAI()
	world:setAI(state.controlled, nil)
	local other = state.controlled == "Blue" and "Purple" or "Blue"
	world:setAI(other, state.aiMode)
end
applyAI()

---------------------------------------------------------------- validation
local INPUT_KINDS = { move = true, m1 = true, skill = true, guard = true, counter = true, ult = true, form1 = true, final = true }
local buckets = {}
local function allow(plr)
	local b = buckets[plr]
	local now = os.clock()
	if not b then b = { tokens = 60, last = now }; buckets[plr] = b end
	b.tokens = math.min(60, b.tokens + (now - b.last) * 60)
	b.last = now
	if b.tokens < 1 then return false end
	b.tokens -= 1
	return true
end
Players.PlayerRemoving:Connect(function(p) buckets[p] = nil end)

InputRE.OnServerEvent:Connect(function(plr, kind, a, b)
	if typeof(kind) ~= "string" or not INPUT_KINDS[kind] or not allow(plr) then return end
	if stage:GetAttribute("Mode") ~= "Play" then return end
	if kind == "move" then
		if typeof(a) ~= "number" or typeof(b) ~= "number" then return end
	elseif kind == "skill" then
		if typeof(a) ~= "number" or a < 1 or a > 4 or a % 1 ~= 0 then return end
	elseif kind == "guard" then
		if typeof(a) ~= "boolean" then return end
	end
	world:input(state.controlled, kind, a, b)
end)

ControlRE.OnServerEvent:Connect(function(plr, kind, a)
	if typeof(kind) ~= "string" or not allow(plr) then return end
	if kind == "mode" and (a == "Play" or a == "Cinematic") then
		if stage:GetAttribute("Mode") ~= a then
			stage:SetAttribute("Mode", a)
			if a == "Play" then world:reset(); applyAI() end
		end
	elseif kind == "select" and (a == "Blue" or a == "Purple") then
		state.controlled = a
		world:reset()
		applyAI()
	elseif kind == "ai" and (a == "Idle" or a == "Guard" or a == "Attack") then
		state.aiMode = a
		applyAI()
	elseif kind == "reset" then
		world:reset()
		applyAI()
	elseif kind == "preview" and isStudio and (a == "Base" or a == "Form1" or a == "Final") then
		if stage:GetAttribute("Mode") == "Play" then world:forceForm(state.controlled, a) end
	end
end)

---------------------------------------------------------------- loop
local acc = 0
RunService.Heartbeat:Connect(function(dt)
	if stage:GetAttribute("Mode") ~= "Play" then return end
	dt = math.min(dt, 1 / 20)
	world:update(dt)
	local ev = world:drain()
	if #ev > 0 then EventRE:FireAllClients(ev) end
	acc += dt
	if acc >= 1 / 30 then
		acc = 0
		SnapRE:FireAllClients(world:snapshot(), state.controlled, state.aiMode, isStudio)
	end
end)
print("[BG] server ready. Studio preview controls:", isStudio and "enabled" or "disabled")
