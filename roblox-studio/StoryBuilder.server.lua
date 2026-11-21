-- StoryBuilder: builds a small map and plays "The new player nobody wanted".
-- Put this as a *Script* in ServerScriptService, and CameraAndCaptions.client.lua
-- as a *LocalScript* in StarterPlayer > StarterPlayerScripts. Press Play (F5).
-- Record each scene as its own clip (01_spawn ... 05_end) for build_video.py.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

---------------------------------------------------------------- settings
local SCENES_TO_PLAY = {1, 2, 3, 4, 5} -- e.g. {2} to replay only scene 2
local SCENE_GAP = 4                    -- seconds between scenes (stop/start your recorder)
local SHOW_CAPTIONS = false            -- leave false: build_video.py adds captions

Players.CharacterAutoLoads = false     -- no player avatar in the shot

local remote = Instance.new("RemoteEvent")
remote.Name = "StoryEvent"
remote.Parent = ReplicatedStorage

---------------------------------------------------------------- map
local function makePart(name, size, pos, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Position = pos
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = Workspace
	return p
end

for _, child in ipairs(Workspace:GetChildren()) do
	if child:IsA("BasePart") and child.Name == "Baseplate" then child:Destroy() end
end
makePart("Ground", Vector3.new(300, 1, 300), Vector3.new(0, -0.5, 0), Color3.fromRGB(106, 200, 80), Enum.Material.Grass)
makePart("SpawnPad", Vector3.new(14, 0.4, 14), Vector3.new(0, 0.2, 0), Color3.fromRGB(255, 255, 255))

local GROUP_SPOTS = {
	A = Vector3.new(-40, 0, -35),
	B = Vector3.new(0, 0, -50),
	C = Vector3.new(40, 0, -35),
}
local GROUP_COLORS = {
	A = Color3.fromRGB(255, 90, 60),
	B = Color3.fromRGB(255, 200, 0),
	C = Color3.fromRGB(160, 90, 255),
}
for key, pos in pairs(GROUP_SPOTS) do
	makePart("Group" .. key, Vector3.new(16, 0.4, 16), pos + Vector3.new(0, 0.2, 0), GROUP_COLORS[key])
end

local ARENA = Vector3.new(0, 0, 55)
makePart("Arena", Vector3.new(60, 0.6, 40), ARENA + Vector3.new(0, 0.3, 0), Color3.fromRGB(60, 120, 255))
local board = makePart("Scoreboard", Vector3.new(24, 10, 1), ARENA + Vector3.new(0, 7, 18), Color3.fromRGB(20, 20, 30))
local gui = Instance.new("SurfaceGui")
gui.Face = Enum.NormalId.Front
gui.Parent = board
local boardText = Instance.new("TextLabel")
boardText.Size = UDim2.fromScale(1, 1)
boardText.BackgroundTransparency = 1
boardText.TextScaled = true
boardText.Font = Enum.Font.GothamBlack
boardText.TextColor3 = Color3.new(1, 1, 1)
boardText.Text = "TOURNAMENT"
boardText.Parent = gui
-- the board's front face should point at the camera (toward -Z side)
board.CFrame = CFrame.lookAt(board.Position, board.Position + Vector3.new(0, 0, -1))

---------------------------------------------------------------- characters
-- Standard Roblox R15 animation ids. If one does not play, search the Creator Store
-- for an R15 animation and replace the id here.
local ANIM = {
	idle = "rbxassetid://507766666",
	walk = "rbxassetid://507777826",
	wave = "rbxassetid://507770239",
	point = "rbxassetid://507770453",
	cheer = "rbxassetid://507770677",
	laugh = "rbxassetid://507770818",
}

local function makeNpc(name, pos, color)
	local desc = Instance.new("HumanoidDescription")
	desc.HeadColor = color
	desc.TorsoColor = color
	desc.LeftArmColor = color
	desc.RightArmColor = color
	desc.LeftLegColor = color
	desc.RightLegColor = color
	local model = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	model.Name = name
	model.Parent = Workspace
	model:PivotTo(CFrame.new(pos + Vector3.new(0, 3, 0)))
	return model
end

local function play(model, animName, looped)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
	local anim = Instance.new("Animation")
	anim.AnimationId = ANIM[animName]
	local track = animator:LoadAnimation(anim)
	track.Looped = looped or false
	track:Play()
	return track
end

local function walkTo(model, pos)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local walk = play(model, "walk", true)
	hum:MoveTo(pos)
	hum.MoveToFinished:Wait()
	walk:Stop()
end

local function face(model, target)
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	local p = root.Position
	root.CFrame = CFrame.lookAt(p, Vector3.new(target.X, p.Y, target.Z))
end

local function lookAway(model, from)
	local root = model:FindFirstChild("HumanoidRootPart")
	local p = root.Position
	root.CFrame = CFrame.lookAt(p, p + (p - from) * Vector3.new(1, 0, 1))
end

local hero = makeNpc("Hero", Vector3.new(0, 0, 0), Color3.fromRGB(255, 220, 120))
face(hero, Vector3.new(0, 0, -50))

local crowd = {}
local COLORS = { Color3.fromRGB(255, 120, 150), Color3.fromRGB(100, 200, 255),
	Color3.fromRGB(150, 255, 150), Color3.fromRGB(255, 160, 60) }
for key, pos in pairs(GROUP_SPOTS) do
	crowd[key] = {}
	for i = 1, 3 do
		local npc = makeNpc("NPC_" .. key .. i, pos + Vector3.new((i - 2) * 4, 0, 0), COLORS[(i % #COLORS) + 1])
		face(npc, Vector3.new(0, 0, 0))
		table.insert(crowd[key], npc)
	end
end
local teamNpcs = {}
for i = 1, 4 do
	local npc = makeNpc("Team" .. i, ARENA + Vector3.new((i - 2.5) * 5, 0, -8), COLORS[(i % #COLORS) + 1])
	face(npc, ARENA + Vector3.new(0, 0, 20))
	table.insert(teamNpcs, npc)
end

---------------------------------------------------------------- camera helper
local function shot(camPos, lookAt, hold, caption, tween)
	remote:FireAllClients({
		cframe = CFrame.lookAt(camPos, lookAt),
		caption = SHOW_CAPTIONS and caption or "",
		tween = tween or 0.7,
	})
	task.wait(hold)
end

local function root(m) return m:FindFirstChild("HumanoidRootPart").Position end

---------------------------------------------------------------- scenes
local scenes = {}

scenes[1] = function() -- 01_spawn: hero alone while others walk past
	play(hero, "idle", true)
	shot(Vector3.new(14, 6, 16), root(hero) + Vector3.new(0, 3, 0), 2.5, "Nobody wanted the new kid...")
	task.spawn(function() walkTo(crowd.A[1], Vector3.new(30, 0, 5)) end)
	task.spawn(function() walkTo(crowd.C[1], Vector3.new(-30, 0, 5)) end)
	shot(Vector3.new(8, 4, 12), root(hero) + Vector3.new(0, 3, 0), 3, "")
end

scenes[2] = function() -- 02_asking: asks three groups, gets turned away
	for _, key in ipairs({ "A", "B", "C" }) do
		local spot = GROUP_SPOTS[key]
		shot(spot + Vector3.new(0, 7, 22), spot + Vector3.new(0, 3, 0), 0.6, "He asked group " .. key)
		walkTo(hero, spot + Vector3.new(0, 0, 8))
		face(hero, spot)
		play(hero, "wave", false)
		task.wait(1.2)
		for _, npc in ipairs(crowd[key]) do lookAway(npc, root(hero)) end
		task.wait(1.2)
		walkTo(hero, Vector3.new(0, 0, 0))
	end
end

scenes[3] = function() -- 03_tourney: arena, one team short
	boardText.Text = "TOURNAMENT"
	shot(ARENA + Vector3.new(0, 14, -30), ARENA + Vector3.new(0, 4, 5), 3, "Then the tournament started")
	shot(ARENA + Vector3.new(0, 5, -12), root(teamNpcs[2]) + Vector3.new(0, 2, 0), 2.5, "One team had only four players")
end

scenes[4] = function() -- 04_win: hero joins and wins every round
	task.spawn(function() walkTo(hero, ARENA + Vector3.new(0, 0, -8)) end)
	shot(ARENA + Vector3.new(0, 8, -28), ARENA + Vector3.new(0, 3, -8), 3, "So he joined them")
	for round = 1, 5 do
		boardText.Text = "ROUND " .. round .. "  -  WIN"
		play(hero, "cheer", false)
		for _, npc in ipairs(teamNpcs) do play(npc, "cheer", false) end
		shot(ARENA + Vector3.new(0, 4, -20 + round), root(hero) + Vector3.new(0, 3, 0), 1.2, "Round " .. round)
	end
	boardText.Text = "CHAMPIONS!"
end

scenes[5] = function() -- 05_end: everybody wants him on their team
	shot(ARENA + Vector3.new(0, 6, -25), ARENA + Vector3.new(0, 3, -8), 1, "")
	for key, list in pairs(crowd) do
		for _, npc in ipairs(list) do
			task.spawn(function() walkTo(npc, ARENA + Vector3.new(math.random(-6, 6), 0, -14)) end)
		end
	end
	task.wait(5)
	for _, list in pairs(crowd) do for _, npc in ipairs(list) do face(npc, root(hero)); play(npc, "wave", false) end end
	play(hero, "laugh", false)
	shot(ARENA + Vector3.new(0, 4, -22), root(hero) + Vector3.new(0, 3, 0), 4, "Part 2? Comment a star")
end

---------------------------------------------------------------- run
if #Players:GetPlayers() == 0 then Players.PlayerAdded:Wait() end
task.wait(3)
for _, n in ipairs(SCENES_TO_PLAY) do
	print(("=== SCENE %02d: START RECORDING ==="):format(n))
	scenes[n]()
	print(("=== SCENE %02d: STOP RECORDING ==="):format(n))
	task.wait(SCENE_GAP)
end
print("=== STORY FINISHED ===")
