-- CombatScene v2: dark-ruins cinematic fight (blue vs purple energy), moon, fog, bloom, lightning.
-- Put as a *Script* in ServerScriptService (disable/delete the old CombatScene script).
-- Needs CameraAndCaptions.client.lua in StarterPlayerScripts. Press Play.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")

local SCENES_TO_PLAY = { 1, 2, 3, 4 }
local SCENE_GAP = 4

Players.CharacterAutoLoads = false
math.randomseed(7)

local remote = ReplicatedStorage:FindFirstChild("StoryEvent")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "StoryEvent"
	remote.Parent = ReplicatedStorage
end

local BLUE = Color3.fromRGB(60, 150, 255)
local PURPLE = Color3.fromRGB(180, 80, 255)
local RED = Color3.fromRGB(255, 50, 70)

---------------------------------------------------------------- helpers
local function tween(obj, time, props, style, dir, repeats, reverses)
	local info = TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out, repeats or 0, reverses or false)
	local t = TweenService:Create(obj, info, props)
	t:Play()
	return t
end

local function makePart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do p[k] = v end
	p.Parent = Workspace
	return p
end

local function shot(camPos, lookAt, hold, shake, fov, roll)
	remote:FireAllClients({
		cframe = CFrame.lookAt(camPos, lookAt) * CFrame.Angles(0, 0, math.rad(roll or 0)),
		caption = "",
		tween = 0.45,
		shake = shake or 0,
		fov = fov or 70,
	})
	task.wait(hold)
end

local function shake(power, time)
	remote:FireAllClients({ shakeOnly = true, shake = power, time = time or 0.4 })
end

---------------------------------------------------------------- look: lighting + post effects
Lighting.ClockTime = 0
Lighting.Brightness = 2
Lighting.ExposureCompensation = 0.6
Lighting.Ambient = Color3.fromRGB(95, 85, 150)
Lighting.OutdoorAmbient = Color3.fromRGB(100, 90, 160)

local atmo = Instance.new("Atmosphere")
atmo.Density = 0.38
atmo.Offset = 0.25
atmo.Color = Color3.fromRGB(110, 85, 170)
atmo.Decay = Color3.fromRGB(50, 35, 90)
atmo.Glare = 0
atmo.Haze = 2
atmo.Parent = Lighting

local bloom = Instance.new("BloomEffect")
bloom.Intensity = 1.1
bloom.Size = 28
bloom.Threshold = 0.8
bloom.Parent = Lighting

local cc = Instance.new("ColorCorrectionEffect")
cc.Contrast = 0.18
cc.Saturation = 0.25
cc.TintColor = Color3.fromRGB(225, 215, 255)
cc.Parent = Lighting

local dof = Instance.new("DepthOfFieldEffect")
dof.FarIntensity = 0.25
dof.FocusDistance = 40
dof.InFocusRadius = 45
dof.NearIntensity = 0
dof.Parent = Lighting

---------------------------------------------------------------- arena: ground, ruins, moon, banners, rocks
makePart({ Name = "Ground", Size = Vector3.new(500, 1, 500), Position = Vector3.new(0, -0.5, 0),
	Color = Color3.fromRGB(32, 30, 44), Material = Enum.Material.Slate, CanCollide = true })
makePart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 80, 80),
	CFrame = CFrame.new(0, 0.12, 0) * CFrame.Angles(0, 0, math.rad(90)),
	Color = PURPLE, Material = Enum.Material.Neon, Transparency = 0.7 })
makePart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 60, 60),
	CFrame = CFrame.new(0, 0.14, 0) * CFrame.Angles(0, 0, math.rad(90)),
	Color = BLUE, Material = Enum.Material.Neon, Transparency = 0.8 })

makePart({ Name = "Moon", Shape = Enum.PartType.Ball, Size = Vector3.new(90, 90, 90),
	Position = Vector3.new(60, 170, 300), Color = Color3.fromRGB(200, 150, 255),
	Material = Enum.Material.Neon, Transparency = 0.1 })

local function pillar(x, z, h, w)
	local p = makePart({ Size = Vector3.new(w, h, w), Position = Vector3.new(x, h / 2, z),
		CFrame = CFrame.new(x, h / 2, z) * CFrame.Angles(math.rad(math.random(-4, 4)), math.rad(math.random(0, 90)), math.rad(math.random(-4, 4))),
		Color = Color3.fromRGB(48, 42, 66), Material = Enum.Material.Slate })
	return p
end
for i = 1, 14 do
	local ang = (i / 14) * math.pi * 2
	local r = math.random(85, 130)
	pillar(math.cos(ang) * r, math.sin(ang) * r + 40, math.random(18, 55), math.random(7, 10))
end
-- big arch behind the fight
pillar(-24, 95, 46, 9)
pillar(24, 95, 46, 9)
makePart({ Size = Vector3.new(66, 8, 9), Position = Vector3.new(0, 50, 95),
	Color = Color3.fromRGB(48, 42, 66), Material = Enum.Material.Slate })
for _, x in ipairs({ -45, 45 }) do
	makePart({ Size = Vector3.new(7, 22, 0.4), Position = Vector3.new(x, 26, 70),
		Color = Color3.fromRGB(70, 35, 130), Material = Enum.Material.Fabric })
	makePart({ Size = Vector3.new(2.2, 7, 0.5), Position = Vector3.new(x, 27, 69.7),
		Color = PURPLE, Material = Enum.Material.Neon })
end
for i = 1, 14 do
	local s = math.random(3, 8)
	local rock = makePart({ Size = Vector3.new(s, s * 0.8, s),
		CFrame = CFrame.new(math.random(-60, 60), math.random(8, 30), math.random(-30, 60))
			* CFrame.Angles(math.random(), math.random(), math.random()),
		Color = Color3.fromRGB(40, 36, 56), Material = Enum.Material.Slate })
	tween(rock, 2.5 + math.random() * 2, { Position = rock.Position + Vector3.new(0, 3, 0) },
		Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
end

local focusPart = makePart({ Name = "FocusPoint", Size = Vector3.new(1, 1, 1),
	Position = Vector3.new(0, 5, 0), Transparency = 1 })
for _, spec in ipairs({ { Vector3.new(-25, 18, -20), BLUE }, { Vector3.new(25, 18, -20), PURPLE } }) do
	local lp = makePart({ Size = Vector3.new(1, 1, 1), Position = spec[1], Transparency = 1 })
	local light = Instance.new("PointLight", lp)
	light.Color = spec[2]; light.Range = 90; light.Brightness = 3
end
local function setFocus(plr) pcall(function() plr.ReplicationFocus = focusPart end) end
for _, plr in ipairs(Players:GetPlayers()) do setFocus(plr) end
Players.PlayerAdded:Connect(setFocus)

---------------------------------------------------------------- fighters
local function weld(part, to, offset)
	part.Anchored = false
	part.Massless = true
	part.CFrame = to.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = to
	w.Part1 = part
	w.Parent = part
	return part
end

local function addPart(model, partName, size, offset, color, material)
	local to = model:FindFirstChild(partName)
	if not to then return end
	return weld(makePart({ Size = size, Color = color, Material = material or Enum.Material.SmoothPlastic }), to, offset)
end

local function addTrail(model, partName, color)
	local part = model:FindFirstChild(partName)
	if not part then return end
	local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0, 0.4, 0); a0.Parent = part
	local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, -0.4, 0); a1.Parent = part
	local t = Instance.new("Trail")
	t.Attachment0, t.Attachment1 = a0, a1
	t.Lifetime = 0.35
	t.Color = ColorSequence.new(color)
	t.Transparency = NumberSequence.new(0.1, 1)
	t.LightEmission = 1
	t.Parent = part
end

local function addAura(model, color)
	local torso = model:FindFirstChild("UpperTorso")
	if not torso then return end
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Rate = 28
	e.Lifetime = NumberRange.new(0.6, 1.2)
	e.Speed = NumberRange.new(2, 7)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.Size = NumberSequence.new(0.5, 0)
	e.Transparency = NumberSequence.new(0, 1)
	e.Parent = torso
end

local function dress(model, hairColor, trim, cloak, spikeCount, lean)
	local head = "Head"
	for k = 1, spikeCount do
		local a = (k / spikeCount) * math.pi * 2
		addPart(model, head, Vector3.new(0.55, 1.25, 0.55),
			CFrame.new(math.cos(a) * 0.42, 0.78, math.sin(a) * 0.42)
				* CFrame.Angles(math.sin(a) * lean, 0, -math.cos(a) * lean), hairColor)
	end
	addPart(model, head, Vector3.new(0.7, 1.6, 0.7), CFrame.new(0, 0.95, 0.05) * CFrame.Angles(-0.25, 0, 0), hairColor)
	addPart(model, head, Vector3.new(1.25, 0.45, 1.25), CFrame.new(0, 0.5, 0.02), hairColor)
	-- fierce eyes
	addPart(model, head, Vector3.new(0.3, 0.09, 0.05), CFrame.new(-0.27, 0.08, -0.62) * CFrame.Angles(0, 0, 0.35), Color3.fromRGB(10, 10, 14))
	addPart(model, head, Vector3.new(0.3, 0.09, 0.05), CFrame.new(0.27, 0.08, -0.62) * CFrame.Angles(0, 0, -0.35), Color3.fromRGB(10, 10, 14))
	-- scarf, tail, cloak
	addPart(model, "UpperTorso", Vector3.new(1.9, 0.55, 1.35), CFrame.new(0, 0.85, 0), Color3.fromRGB(14, 14, 22), Enum.Material.Fabric)
	addPart(model, "UpperTorso", Vector3.new(0.6, 2.4, 0.15), CFrame.new(0.65, 0.1, 0.75) * CFrame.Angles(0.45, 0, 0.1), Color3.fromRGB(14, 14, 22), Enum.Material.Fabric)
	addPart(model, "UpperTorso", Vector3.new(2.7, 3.2, 0.15), CFrame.new(0, -0.5, 0.62) * CFrame.Angles(0.12, 0, 0), cloak, Enum.Material.Fabric)
	addPart(model, "UpperTorso", Vector3.new(2.7, 0.12, 0.17), CFrame.new(0, -2.05, 0.7) * CFrame.Angles(0.12, 0, 0), trim, Enum.Material.Neon)
	-- glowing trim lines
	addPart(model, "UpperTorso", Vector3.new(2.05, 0.1, 1.05), CFrame.new(0, 0.1, 0), trim, Enum.Material.Neon)
	for _, n in ipairs({ "RightUpperArm", "LeftUpperArm", "RightLowerArm", "LeftLowerArm" }) do
		addPart(model, n, Vector3.new(1.08, 0.1, 1.08), CFrame.new(0, 0.15, 0), trim, Enum.Material.Neon)
	end
	addTrail(model, "RightHand", trim)
	addTrail(model, "LeftHand", trim)
	addTrail(model, "RightFoot", trim)
	addAura(model, trim)
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
	m.Humanoid.WalkSpeed = 45
	return m
end

local DARK = Color3.fromRGB(22, 22, 32)
local toji = makeFighter("Toji", Vector3.new(30, 0, 0),
	{ skin = Color3.fromRGB(240, 205, 175), torso = DARK, arm = DARK, leg = DARK }, Vector3.new(0, 3, 0))
local gojo = makeFighter("Gojo", Vector3.new(-30, 0, 0),
	{ skin = Color3.fromRGB(245, 215, 190), torso = Color3.fromRGB(34, 28, 52), arm = Color3.fromRGB(34, 28, 52), leg = DARK }, Vector3.new(0, 3, 0))

dress(toji, Color3.fromRGB(14, 14, 24), BLUE, Color3.fromRGB(20, 20, 34), 10, 0.7)
dress(gojo, Color3.fromRGB(225, 225, 245), PURPLE, Color3.fromRGB(38, 28, 62), 10, 0.75)

local knife = addPart(toji, "RightHand", Vector3.new(0.25, 0.25, 2.4), CFrame.new(0, -0.3, -1.3), Color3.fromRGB(200, 215, 235), Enum.Material.Metal)
knife.Transparency = 1

print("DEBUG fighters built. Toji parts:", #toji:GetDescendants(), "Gojo parts:", #gojo:GetDescendants())

---------------------------------------------------------------- animation + effects
local ANIM = {
	walk = "rbxassetid://507777826",
	slash = "rbxassetid://522635514",
	lunge = "rbxassetid://522638767",
	point = "rbxassetid://507770453",
	fall = "rbxassetid://507767968",
}
local function playAnim(model, name, looped)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
	local anim = Instance.new("Animation")
	anim.AnimationId = ANIM[name]
	local track = animator:LoadAnimation(anim)
	track.Looped = looped or false
	track:Play()
	return track
end
local function root(m) return m.HumanoidRootPart end
local function lookAtPos(m, target)
	local p = root(m).Position
	root(m).CFrame = CFrame.lookAt(p, Vector3.new(target.X, p.Y, target.Z))
end
local function dashTo(m, pos)
	local track = playAnim(m, "walk", true)
	m.Humanoid:MoveTo(pos)
	m.Humanoid.MoveToFinished:Wait()
	track:Stop()
end
local function knockback(m, dir, power)
	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
	bv.Velocity = dir.Unit * power + Vector3.new(0, 22, 0)
	bv.Parent = root(m)
	Debris:AddItem(bv, 0.3)
	local t = playAnim(m, "fall", true)
	task.delay(1.2, function() t:Stop() end)
end

local function lightning(a, b, color, thick)
	local segs = 9
	local prev = a
	for i = 1, segs do
		local p = a:Lerp(b, i / segs)
		if i < segs then
			p = p + Vector3.new(math.random(-30, 30) / 10, math.random(-30, 30) / 10, math.random(-30, 30) / 10)
		end
		local len = (p - prev).Magnitude
		if len > 0.05 then
			local seg = makePart({ Size = Vector3.new(thick or 0.28, thick or 0.28, len),
				CFrame = CFrame.lookAt(prev, p) * CFrame.new(0, 0, -len / 2),
				Color = color, Material = Enum.Material.Neon })
			Debris:AddItem(seg, 0.18)
		end
		prev = p
	end
end

local function shockwave(pos, color, maxSize)
	local ring = makePart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 2, 2),
		CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)), Color = color,
		Material = Enum.Material.Neon, Transparency = 0.15 })
	tween(ring, 0.55, { Size = Vector3.new(0.5, maxSize, maxSize), Transparency = 1 })
	Debris:AddItem(ring, 0.65)
end

local function burst(pos, color, count)
	for _ = 1, count do
		local s = makePart({ Size = Vector3.new(0.8, 0.8, 0.8), Position = pos,
			Color = color, Material = Enum.Material.Neon, Anchored = false })
		s.Velocity = Vector3.new(math.random(-70, 70), math.random(20, 80), math.random(-70, 70))
		Debris:AddItem(s, 1.1)
	end
end

local function impact(pos, color, size)
	for _ = 1, 4 do
		lightning(pos, pos + Vector3.new(math.random(-14, 14), math.random(-4, 12), math.random(-14, 14)), color)
	end
	shockwave(Vector3.new(pos.X, 0.4, pos.Z), color, size or 22)
	burst(pos, color, 14)
	shake(0.9, 0.25)
end

local function orb(color, size, pos)
	local p = makePart({ Shape = Enum.PartType.Ball, Size = Vector3.new(size, size, size), Position = pos,
		Color = color, Material = Enum.Material.Neon, Transparency = 0.05 })
	local l = Instance.new("PointLight", p)
	l.Color = color; l.Range = 40; l.Brightness = 6
	return p
end

---------------------------------------------------------------- scenes
local scenes = {}
local mid = Vector3.new(0, 4, 0)

scenes[1] = function() -- standoff
	lookAtPos(gojo, root(toji).Position); lookAtPos(toji, root(gojo).Position)
	shot(Vector3.new(0, 30, -85), Vector3.new(0, 20, 60), 2.5, 0, 55)            -- wide: ruins and moon
	shot(Vector3.new(-14, 3, -9), root(gojo).Position + Vector3.new(0, 1.5, 0), 2.2, 0, 40, -6)
	shot(Vector3.new(14, 3, -9), root(toji).Position + Vector3.new(0, 1.5, 0), 2.2, 0, 40, 6)
	knife.Transparency = 0
	shot(Vector3.new(0, 2, -42), mid, 1.6, 0, 60, 0)
end

scenes[2] = function() -- the clash
	local barrier = makePart({ Shape = Enum.PartType.Ball, Size = Vector3.new(15, 15, 15), Position = Vector3.new(-6, 5, 0),
		Color = Color3.fromRGB(150, 190, 255), Material = Enum.Material.ForceField, Transparency = 0.35 })
	task.spawn(function() dashTo(toji, Vector3.new(4, 0, 0)) end)
	task.spawn(function() dashTo(gojo, Vector3.new(-12, 0, 0)) end)
	shot(Vector3.new(-6, 5, -42), mid, 1.5, 0, 70, 0)
	lookAtPos(toji, root(gojo).Position)
	local angles = {
		{ Vector3.new(-2, 3, -16), -10 },
		{ Vector3.new(10, 5, -12), 8 },
		{ Vector3.new(-14, 8, -10), -14 },
		{ Vector3.new(0, 2, -20), 6 },
	}
	for i = 1, 4 do
		playAnim(toji, (i % 2 == 1) and "slash" or "lunge")
		task.wait(0.3)
		impact(Vector3.new(-1, 5, 0), (i % 2 == 1) and BLUE or PURPLE, 24)
		shot(angles[i][1], Vector3.new(-2, 5, 0), 0.7, 1.0, 55, angles[i][2])
	end
	scenes._barrier = barrier
end

scenes[3] = function() -- blade breaks the barrier
	local barrier = scenes._barrier
	playAnim(toji, "lunge")
	shot(root(toji).Position + Vector3.new(-4, 3, -10), root(toji).Position + Vector3.new(0, 4, 0), 1.3, 0.3, 38, 8)
	task.wait(0.1)
	if barrier then barrier:Destroy() end
	impact(Vector3.new(-3, 5, 0), Color3.fromRGB(255, 255, 255), 40)
	burst(Vector3.new(-3, 5, 0), BLUE, 30)
	shake(2, 0.6)
	knockback(gojo, Vector3.new(-1, 0, 0), 55)
	shot(Vector3.new(-16, 6, -26), Vector3.new(-8, 6, 0), 2.2, 1.8, 55, -10)
end

scenes[4] = function() -- blue + red = purple blast
	lookAtPos(gojo, root(toji).Position)
	local blue = orb(BLUE, 4, root(gojo).Position + Vector3.new(-4, 5, -3))
	local red = orb(RED, 4, root(gojo).Position + Vector3.new(4, 5, -3))
	local cast = playAnim(gojo, "point", true)
	shot(root(gojo).Position + Vector3.new(0, 3, -17), root(gojo).Position + Vector3.new(0, 4, 0), 2, 0.4, 48, -5)
	local mergeAt = root(gojo).Position + Vector3.new(0, 6, -6)
	tween(blue, 0.8, { Position = mergeAt }); tween(red, 0.8, { Position = mergeAt })
	shot(mergeAt + Vector3.new(0, 1, -15), mergeAt, 1.0, 1, 42, 0)
	blue:Destroy(); red:Destroy()
	local purple = orb(PURPLE, 6, mergeAt)
	tween(purple, 1.2, { Position = root(toji).Position + Vector3.new(0, 3, 0), Size = Vector3.new(20, 20, 20) })
	shot(Vector3.new(14, 7, -32), root(toji).Position, 1.2, 1.5, 62, 10)
	impact(purple.Position, PURPLE, 70)
	shockwave(Vector3.new(purple.Position.X, 0.4, purple.Position.Z), BLUE, 100)
	burst(purple.Position, PURPLE, 50)
	purple:Destroy()
	knockback(toji, Vector3.new(1, 0, 0), 90)
	shake(3.5, 1)
	shot(root(toji).Position + Vector3.new(-16, 8, -24), root(toji).Position, 2.5, 3, 80, -12)
	cast:Stop()
	shot(root(gojo).Position + Vector3.new(5, 2, -10), root(gojo).Position + Vector3.new(0, 4, 0), 3.2, 0, 38, 4)
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
