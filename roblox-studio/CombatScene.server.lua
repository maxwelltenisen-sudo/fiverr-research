-- CombatScene: a cinematic fan-made fight between a Gojo-style and a Toji-style fighter.
-- Script in ServerScriptService. Needs CameraAndCaptions.client.lua (StarterPlayerScripts).
-- Everything is built from parts, so no asset ids are required except the walk animation.
-- Press Play, then record. Each scene prints START/STOP RECORDING in the Output window.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

---------------------------------------------------------------- settings
local SCENES_TO_PLAY = { 1, 2, 3, 4 }
local SCENE_GAP = 4
local ARM_SIGN = 1          -- if punches swing backwards, change to -1

Players.CharacterAutoLoads = false

local remote = ReplicatedStorage:FindFirstChild("StoryEvent")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "StoryEvent"
	remote.Parent = ReplicatedStorage
end

---------------------------------------------------------------- helpers
local function tween(obj, time, props, style)
	local t = TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quad), props)
	t:Play()
	return t
end

local function makePart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do p[k] = v end
	p.Parent = Workspace
	return p
end

local function shot(camPos, lookAt, hold, shake, fov)
	remote:FireAllClients({
		cframe = CFrame.lookAt(camPos, lookAt),
		caption = "",
		tween = 0.5,
		shake = shake or 0,
		fov = fov or 70,
	})
	task.wait(hold)
end

local function shake(power, time)
	remote:FireAllClients({ shakeOnly = true, shake = power, time = time or 0.4 })
end

---------------------------------------------------------------- arena
makePart({ Name = "Ground", Size = Vector3.new(300, 1, 300), Position = Vector3.new(0, -0.5, 0),
	Color = Color3.fromRGB(70, 70, 85), Material = Enum.Material.Concrete, CanCollide = true })
for i = -4, 4 do
	makePart({ Size = Vector3.new(6, 40 + math.abs(i) * 6, 6), Position = Vector3.new(i * 28, 20, 70),
		Color = Color3.fromRGB(40, 45, 70), Material = Enum.Material.Concrete })
end
local lighting = game:GetService("Lighting")
lighting.ClockTime = 18.5
lighting.Brightness = 2
lighting.Ambient = Color3.fromRGB(60, 60, 90)

---------------------------------------------------------------- fighters
local ANIM_WALK = "rbxassetid://507777826"
local base = {}   -- original joint C0 values

local function weld(part, to, offset)
	part.Anchored = false
	part.Massless = true
	part.CFrame = to.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = to
	w.Part1 = part
	w.Parent = part
end

local function makeFighter(name, pos, colors, facing)
	local d = Instance.new("HumanoidDescription")
	d.HeadColor = colors.skin
	d.TorsoColor = colors.torso
	d.LeftArmColor, d.RightArmColor = colors.arm, colors.arm
	d.LeftLegColor, d.RightLegColor = colors.leg, colors.leg
	local m = Players:CreateHumanoidModelFromDescription(d, Enum.HumanoidRigType.R15)
	m.Name = name
	m.Parent = Workspace
	m:PivotTo(CFrame.lookAt(pos + Vector3.new(0, 3, 0), facing))
	m.Humanoid.WalkSpeed = 40
	base[m] = {}
	for _, j in ipairs({ "RightShoulder", "LeftShoulder", "Waist", "RightHip", "LeftHip" }) do
		local motor = m:FindFirstChild(j, true)
		if motor then base[m][j] = { motor = motor, c0 = motor.C0 } end
	end
	return m
end

local gojo = makeFighter("Gojo", Vector3.new(-30, 0, 0),
	{ skin = Color3.fromRGB(255, 224, 205), torso = Color3.fromRGB(25, 30, 55),
	  arm = Color3.fromRGB(25, 30, 55), leg = Color3.fromRGB(25, 30, 55) }, Vector3.new(0, 3, 0))
local toji = makeFighter("Toji", Vector3.new(30, 0, 0),
	{ skin = Color3.fromRGB(225, 180, 150), torso = Color3.fromRGB(20, 20, 20),
	  arm = Color3.fromRGB(225, 180, 150), leg = Color3.fromRGB(60, 60, 65) }, Vector3.new(0, 3, 0))

-- Gojo: spiky white hair + black blindfold
local gHead = gojo.Head
for i, off in ipairs({ CFrame.new(0, 0.7, 0), CFrame.new(-0.6, 0.75, 0) * CFrame.Angles(0, 0, 0.5),
	CFrame.new(0.6, 0.75, 0) * CFrame.Angles(0, 0, -0.5), CFrame.new(0, 0.8, -0.5) * CFrame.Angles(-0.5, 0, 0),
	CFrame.new(0, 0.8, 0.5) * CFrame.Angles(0.5, 0, 0) }) do
	local spike = makePart({ Size = Vector3.new(0.7, 1, 0.7), Color = Color3.fromRGB(245, 245, 255) })
	weld(spike, gHead, off)
end
weld(makePart({ Size = Vector3.new(1.3, 0.35, 1.25), Color = Color3.fromRGB(10, 10, 15) }), gHead, CFrame.new(0, 0.1, -0.05))

-- Toji: short dark hair, scar, knife
local tHead = toji.Head
weld(makePart({ Size = Vector3.new(1.3, 0.35, 1.3), Color = Color3.fromRGB(20, 15, 15) }), tHead, CFrame.new(0, 0.55, 0))
weld(makePart({ Size = Vector3.new(0.12, 0.12, 0.06), Color = Color3.fromRGB(170, 70, 70) }), tHead, CFrame.new(0.3, -0.15, -0.62))
local knife = makePart({ Size = Vector3.new(0.25, 0.25, 2.2), Color = Color3.fromRGB(200, 205, 215), Material = Enum.Material.Metal })
weld(knife, toji.RightHand, CFrame.new(0, -0.3, -1.2))
knife.Transparency = 1   -- hidden until drawn

local RunService = game:GetService("RunService")
local twId = 0
local function lerpC0(motor, goal, time)
	twId += 1
	local myId = twId
	motor:SetAttribute("tw", myId)
	local start = motor.C0
	task.spawn(function()
		local t0 = os.clock()
		while motor:GetAttribute("tw") == myId do
			local a = math.min((os.clock() - t0) / math.max(time, 0.01), 1)
			motor.C0 = start:Lerp(goal, a)
			if a >= 1 then break end
			RunService.Heartbeat:Wait()
		end
	end)
end

local function pose(model, joint, rot, time)
	local j = base[model][joint]
	if j then lerpC0(j.motor, j.c0 * CFrame.Angles(rot.X, rot.Y, rot.Z), time or 0.12) end
end
local function resetPose(model, time)
	for _, j in pairs(base[model]) do lerpC0(j.motor, j.c0, time or 0.2) end
end
local function root(m) return m.HumanoidRootPart end
local function lookAt(m, target)
	local p = root(m).Position
	root(m).CFrame = CFrame.lookAt(p, Vector3.new(target.X, p.Y, target.Z))
end
local function dashTo(m, pos)
	local hum = m.Humanoid
	local anim = Instance.new("Animation"); anim.AnimationId = ANIM_WALK
	local track = (hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)):LoadAnimation(anim)
	track.Looped = true; track:Play()
	hum:MoveTo(pos); hum.MoveToFinished:Wait()
	track:Stop()
end
local function knockback(m, dir, power)
	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
	bv.Velocity = dir.Unit * power + Vector3.new(0, 18, 0)
	bv.Parent = root(m)
	Debris:AddItem(bv, 0.25)
end
local function punch(m, right)
	local joint = right and "RightShoulder" or "LeftShoulder"
	pose(m, joint, Vector3.new(-1.7 * ARM_SIGN, 0, 0), 0.08)
	pose(m, "Waist", Vector3.new(0, right and -0.5 or 0.5, 0), 0.08)
	task.wait(0.15)
	resetPose(m, 0.15)
end

---------------------------------------------------------------- effects
local function orb(color, size, pos)
	local p = makePart({ Shape = Enum.PartType.Ball, Size = Vector3.new(size, size, size), Position = pos,
		Color = color, Material = Enum.Material.Neon, Transparency = 0.1 })
	local light = Instance.new("PointLight", p); light.Color = color; light.Range = 30; light.Brightness = 4
	return p
end

local function shockwave(pos, color, maxSize)
	local ring = makePart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 2, 2),
		CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)), Color = color,
		Material = Enum.Material.Neon, Transparency = 0.2 })
	tween(ring, 0.5, { Size = Vector3.new(0.4, maxSize, maxSize), Transparency = 1 })
	Debris:AddItem(ring, 0.6)
end

local function burst(pos, color, count)
	for _ = 1, count do
		local s = makePart({ Size = Vector3.new(1, 1, 1), Position = pos, Color = color, Material = Enum.Material.Neon, Anchored = false })
		s.Velocity = Vector3.new(math.random(-60, 60), math.random(20, 70), math.random(-60, 60))
		Debris:AddItem(s, 1.2)
	end
end

---------------------------------------------------------------- scenes
local scenes = {}
local mid = Vector3.new(0, 3, 0)

scenes[1] = function() -- standoff
	lookAt(gojo, root(toji).Position); lookAt(toji, root(gojo).Position)
	shot(Vector3.new(0, 14, -60), mid, 2.5, 0, 60)
	shot(root(gojo).Position + Vector3.new(6, 2, -10), root(gojo).Position + Vector3.new(0, 1, 0), 2.5, 0, 45)
	shot(root(toji).Position + Vector3.new(-6, 2, -10), root(toji).Position + Vector3.new(0, 1, 0), 2.5, 0, 45)
	knife.Transparency = 0
	shot(Vector3.new(0, 4, -35), mid, 1.5, 0, 70)
end

scenes[2] = function() -- the clash: Gojo's barrier stops every hit
	local barrier = makePart({ Shape = Enum.PartType.Ball, Size = Vector3.new(14, 14, 14), Position = Vector3.new(-6, 5, 0),
		Color = Color3.fromRGB(120, 190, 255), Material = Enum.Material.ForceField, Transparency = 0.4 })
	task.spawn(function() dashTo(toji, Vector3.new(4, 0, 0)) end)
	task.spawn(function() dashTo(gojo, Vector3.new(-12, 0, 0)) end)
	shot(Vector3.new(-5, 6, -40), mid, 1.8, 0, 65)
	lookAt(toji, root(gojo).Position)
	for i = 1, 4 do
		punch(toji, i % 2 == 1)
		shockwave(Vector3.new(-3, 5, 0), Color3.fromRGB(160, 220, 255), 14)
		shake(0.6, 0.25)
		shot(Vector3.new(-3, 5, -18 + i), Vector3.new(-3, 5, 0), 0.6, 0.6, 55)
	end
	scenes._barrier = barrier
end

scenes[3] = function() -- Toji's blade breaks the barrier
	local barrier = scenes._barrier
	pose(toji, "RightShoulder", Vector3.new(-2.6 * ARM_SIGN, 0, 0), 0.25)
	shot(root(toji).Position + Vector3.new(-3, 3, -9), root(toji).Position + Vector3.new(0, 4, 0), 1.2, 0, 40)
	pose(toji, "RightShoulder", Vector3.new(-1.2 * ARM_SIGN, 0, 0), 0.08)
	task.wait(0.1)
	if barrier then barrier:Destroy() end
	burst(Vector3.new(-3, 5, 0), Color3.fromRGB(160, 220, 255), 25)
	shockwave(Vector3.new(-3, 5, 0), Color3.fromRGB(255, 255, 255), 30)
	shake(1.5, 0.5)
	knockback(gojo, Vector3.new(-1, 0, 0), 60)
	shot(Vector3.new(-12, 6, -22), Vector3.new(-6, 5, 0), 2, 1.5, 55)
	resetPose(toji, 0.3)
end

scenes[4] = function() -- Blue + Red = Purple
	lookAt(gojo, root(toji).Position)
	local blue = orb(Color3.fromRGB(40, 120, 255), 4, root(gojo).Position + Vector3.new(-3, 5, -3))
	local red = orb(Color3.fromRGB(255, 40, 60), 4, root(gojo).Position + Vector3.new(3, 5, -3))
	pose(gojo, "RightShoulder", Vector3.new(-1.6 * ARM_SIGN, 0, 0), 0.2)
	pose(gojo, "LeftShoulder", Vector3.new(-1.6 * ARM_SIGN, 0, 0), 0.2)
	shot(root(gojo).Position + Vector3.new(0, 4, -16), root(gojo).Position + Vector3.new(0, 4, 0), 2, 0.3, 50)
	local mergeAt = root(gojo).Position + Vector3.new(0, 6, -6)
	tween(blue, 0.8, { Position = mergeAt }); tween(red, 0.8, { Position = mergeAt })
	shot(mergeAt + Vector3.new(0, 1, -14), mergeAt, 1.0, 0.8, 45)
	blue:Destroy(); red:Destroy()
	local purple = orb(Color3.fromRGB(190, 60, 255), 6, mergeAt)
	tween(purple, 1.2, { Position = root(toji).Position + Vector3.new(0, 3, 0), Size = Vector3.new(18, 18, 18) })
	shot(Vector3.new(10, 8, -30), root(toji).Position, 1.2, 1, 60)
	burst(purple.Position, Color3.fromRGB(190, 60, 255), 40)
	shockwave(purple.Position, Color3.fromRGB(220, 120, 255), 80)
	purple:Destroy()
	knockback(toji, Vector3.new(1, 0, 0), 90)
	shake(3, 1)
	shot(root(toji).Position + Vector3.new(-14, 8, -22), root(toji).Position, 2.5, 3, 80)
	resetPose(gojo, 0.4)
	shot(root(gojo).Position + Vector3.new(4, 3, -9), root(gojo).Position + Vector3.new(0, 4, 0), 3, 0, 40)
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
print("=== FIGHT FINISHED ===")
