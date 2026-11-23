-- BGBuilder (Script, ServerScriptService): builds the moonlit stone arena and the two R15 fighters (Kael = "Blue", Ren = "Purple").
-- It does not animate or fight: BGServer decides combat, BGClient / BGDirector pose the rigs.
-- Re-running is safe (the previous build is deleted first). Edit costume colours / parts in the two build functions below.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local Data = require(ReplicatedStorage:WaitForChild("BGCinematicData"))
local Config = require(ReplicatedStorage:WaitForChild("BGConfig"))

Players.CharacterAutoLoads = false

local old = Workspace:FindFirstChild("Showcase")
if old then old:Destroy() end
for _, c in ipairs(Lighting:GetChildren()) do
	if c:GetAttribute("ShowcaseFX") then c:Destroy() end
end

local stage = Instance.new("Folder")
stage.Name = "Showcase"
stage.Parent = Workspace

local BLUE = Data.colors.blue          -- electric blue
local CYAN = Color3.fromRGB(70, 215, 255)
local VIOLET = Data.colors.violet

---------------------------------------------------------------- helpers
local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do p[k] = v end
	p.Parent = parent or stage
	return p
end

local function weld(p, to, offset)
	p.Anchored = false
	p.Massless = true
	p.CFrame = to.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = to
	w.Part1 = p
	w.Parent = p
	return p
end

-- tag: optional attribute name set to true (Seam, Eye, Hair, Lining, Bracer, Accent) so BGClient can restyle parts per form
local function accessory(model, partName, size, offset, color, material, tag, props)
	local to = model:FindFirstChild(partName)
	if not to then return nil end
	local p = part({ Size = size, Color = color, Material = material or Enum.Material.SmoothPlastic }, model)
	if props then for k, v in pairs(props) do p[k] = v end end
	if tag then p:SetAttribute(tag, true) end
	return weld(p, to, offset)
end

---------------------------------------------------------------- stage: moonlit stone arena
Lighting.ClockTime = 0
Lighting.Brightness = 1.3
Lighting.ExposureCompensation = 0
Lighting.Ambient = Color3.fromRGB(60, 66, 100)
Lighting.OutdoorAmbient = Color3.fromRGB(70, 76, 112)

local function fx(inst)
	inst:SetAttribute("ShowcaseFX", true)
	inst.Parent = Lighting
	return inst
end
local atmo = Instance.new("Atmosphere")
atmo.Density = 0.28; atmo.Offset = 0.2; atmo.Color = Color3.fromRGB(100, 110, 175); atmo.Decay = Color3.fromRGB(40, 45, 90)
fx(atmo)
local bloom = Instance.new("BloomEffect")
bloom.Intensity = 0.25; bloom.Size = 12; bloom.Threshold = 1.9
fx(bloom)
local cc = Instance.new("ColorCorrectionEffect")
cc.Contrast = 0.08; cc.Saturation = -0.05; cc.TintColor = Color3.fromRGB(235, 238, 255)
fx(cc)
local dof = Instance.new("DepthOfFieldEffect")
dof.FarIntensity = 0.1; dof.NearIntensity = 0; dof.FocusDistance = 14; dof.InFocusRadius = 28; dof.Enabled = false
fx(dof)

local R = Config.arena.radius
local STONE, STONE2, STONE3 = Color3.fromRGB(58, 60, 74), Color3.fromRGB(40, 42, 56), Color3.fromRGB(78, 80, 98)
part({ Name = "Ground", Size = Vector3.new(500, 1, 500), Position = Vector3.new(0, -0.5, 0), Color = Color3.fromRGB(28, 30, 42),
	Material = Enum.Material.Slate, CanCollide = true })
-- raised stone disc
part({ Name = "ArenaFloor", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, (R + 3) * 2, (R + 3) * 2),
	CFrame = CFrame.new(0, -0.55, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(46, 48, 60), Material = Enum.Material.Slate, Reflectance = 0, CanCollide = true })   -- matte stone
part({ Size = Vector3.new(0.1, (R + 3.4) * 2, (R + 3.4) * 2), Shape = Enum.PartType.Cylinder,
	CFrame = CFrame.new(0, -0.02, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = STONE3, Material = Enum.Material.Slate })
part({ Size = Vector3.new(0.12, R * 2, R * 2), Shape = Enum.PartType.Cylinder,
	CFrame = CFrame.new(0, 0.0, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = STONE2, Material = Enum.Material.Cobblestone })
-- engraved rings: painted stone lines (matte), so only effect geometry glows
for _, spec in ipairs({ { R * 2 - 1, BLUE }, { R * 1.3, VIOLET }, { 7, Color3.fromRGB(150, 160, 210) } }) do
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.06, spec[1], spec[1]), CFrame = CFrame.new(0, 0.05, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = spec[2]:Lerp(STONE2, 0.7), Material = Enum.Material.Concrete })
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.07, spec[1] - 0.35, spec[1] - 0.35), CFrame = CFrame.new(0, 0.06, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = STONE2, Material = Enum.Material.Concrete })
end
part({ Name = "Moon", Shape = Enum.PartType.Ball, Size = Vector3.new(70, 70, 70), Position = Vector3.new(-70, 140, -260),
	Color = Color3.fromRGB(200, 208, 232), Material = Enum.Material.SmoothPlastic, Transparency = 0 })

math.randomseed(7)
-- broken wall ring and pillars
for i = 1, 20 do
	local a = (i / 20) * math.pi * 2
	local h = (i % 3 == 0) and 1.2 or 2.6
	if i % 5 ~= 0 then
		part({ Size = Vector3.new(4.2, h, 1.4), CFrame = CFrame.new(math.cos(a) * (R + 2.2), h / 2, math.sin(a) * (R + 2.2)) * CFrame.Angles(0, -a + math.pi / 2, 0),
			Color = STONE2, Material = Enum.Material.Cobblestone })
	end
end
for i = 1, 8 do
	local a = (i / 8) * math.pi * 2 + 0.2
	local h = 14 + (i % 3) * 5
	local r = R + 7
	part({ Size = Vector3.new(3, h, 3), CFrame = CFrame.new(math.cos(a) * r, h / 2, math.sin(a) * r) * CFrame.Angles(0, a, math.rad(math.random(-2, 2))),
		Color = STONE, Material = Enum.Material.Slate })
	part({ Size = Vector3.new(3.8, 0.8, 3.8), CFrame = CFrame.new(math.cos(a) * r, h + 0.4, math.sin(a) * r) * CFrame.Angles(0, a, 0), Color = STONE3, Material = Enum.Material.Slate })
end
-- far arch
part({ Size = Vector3.new(3.4, 18, 3.4), Position = Vector3.new(-8, 9, -34), Color = STONE, Material = Enum.Material.Slate })
part({ Size = Vector3.new(3.4, 18, 3.4), Position = Vector3.new(8, 9, -34), Color = STONE, Material = Enum.Material.Slate })
part({ Size = Vector3.new(21, 3, 4), Position = Vector3.new(0, 19.5, -34), Color = STONE3, Material = Enum.Material.Slate })
-- moon-cool and violet-warm lights
for _, spec in ipairs({ { Vector3.new(-10, 12, 10), Color3.fromRGB(110, 170, 255), 1.5 }, { Vector3.new(10, 12, 10), Color3.fromRGB(170, 120, 255), 1.3 },
	{ Vector3.new(0, 18, -6), Color3.fromRGB(215, 225, 255), 1.0 } }) do
	local lp = part({ Size = Vector3.new(1, 1, 1), Position = spec[1], Transparency = 1 })
	local l = Instance.new("PointLight")
	l.Color = spec[2]; l.Range = 48; l.Brightness = spec[3]
	l.Parent = lp
end
-- drifting motes (blue and violet) over the arena: a quiet particle layer that is always present
for i, col in ipairs({ BLUE, VIOLET }) do
	local mp = part({ Name = "Motes" .. i, Size = Vector3.new(34, 1, 34), Position = Vector3.new(0, 14, 0), Transparency = 1 })
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(col); pe.LightEmission = 1; pe.Rate = 7
	pe.Lifetime = NumberRange.new(7, 10); pe.Speed = NumberRange.new(0.4, 1.2)
	pe.EmissionDirection = Enum.NormalId.Bottom; pe.SpreadAngle = Vector2.new(20, 20)
	pe.Size = NumberSequence.new(0.16, 0.1); pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.45), NumberSequenceKeypoint.new(1, 1) })
	pe.Parent = mp
end
local focus = part({ Name = "FocusPoint", Size = Vector3.new(1, 1, 1), Position = Vector3.new(0, 4, 0), Transparency = 1 })
local function setFocus(plr) pcall(function() plr.ReplicationFocus = focus end) end
for _, plr in ipairs(Players:GetPlayers()) do setFocus(plr) end
Players.PlayerAdded:Connect(setFocus)

---------------------------------------------------------------- fighters
local function addTrail(model, partName, color)
	local p = model:FindFirstChild(partName)
	if not p then return end
	local a0 = Instance.new("Attachment"); a0.Name = "TrailA0"; a0.Position = Vector3.new(0.45, 0, 0); a0.Parent = p
	local a1 = Instance.new("Attachment"); a1.Name = "TrailA1"; a1.Position = Vector3.new(-0.45, 0, 0); a1.Parent = p
	local t = Instance.new("Trail")
	t.Name = "ShowcaseTrail"
	t.Attachment0, t.Attachment1 = a0, a1
	t.Lifetime = 0.16
	t.MinLength = 0.05
	t.Color = ColorSequence.new(color)
	t.Transparency = NumberSequence.new(0.1, 1)
	t.LightEmission = 1
	t.Enabled = false
	t.Parent = p
end

-- A hanging cloth chain: segments joined by Motor6Ds that BGCloth swings with a slight delay.
-- name = chain id, x/y/z = attach point on `onPart`, count segments of `size`.
local function cloth(model, onPart, chain, attach, count, size, color, lining)
	local prev = model:FindFirstChild(onPart)
	if not prev then return end
	for i = 1, count do
		local seg = part({ Name = chain .. i, Size = size, Color = color, Material = Enum.Material.Fabric, Anchored = false, Massless = true }, model)
		local m = Instance.new("Motor6D")
		m.Name = "Cloth_" .. chain .. "_" .. i
		m.Part0, m.Part1 = prev, seg
		m.C0 = (i == 1) and attach or CFrame.new(0, -size.Y / 2, 0)
		m.C1 = CFrame.new(0, size.Y / 2, 0)
		m:SetAttribute("Chain", chain)
		m:SetAttribute("Depth", i)
		m.Parent = seg
		if lining then
			local l = part({ Size = Vector3.new(size.X * 0.92, size.Y * 0.96, 0.05), Color = lining, Material = Enum.Material.Fabric, Transparency = 0 }, model)
			l:SetAttribute("Lining", true)
			weld(l, seg, CFrame.new(0, 0, -size.Z / 2 - 0.02))
		end
		prev = seg
	end
	return prev
end

local function newRig(name, colors)
	local d = Instance.new("HumanoidDescription")
	d.HeadColor = colors.skin
	d.TorsoColor = colors.torso
	d.LeftArmColor, d.RightArmColor = colors.arm, colors.arm
	d.LeftLegColor, d.RightLegColor = colors.leg, colors.leg
	local m = Players:CreateHumanoidModelFromDescription(d, Enum.HumanoidRigType.R15)
	m.Name = name
	m.Parent = stage
	local hum = m:FindFirstChildOfClass("Humanoid")
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	pcall(function() hum.EvaluateStateMachine = false end)
	-- Current Roblox rigs ship AnimationConstraints (no Motor6Ds). The poses drive Motor6D.Transform,
	-- so replace each constraint with an equivalent Motor6D (same parts, same C0/C1).
	for _, c in ipairs(m:GetDescendants()) do
		if c:IsA("AnimationConstraint") and c.Attachment0 and c.Attachment1 then
			local mot = Instance.new("Motor6D")
			mot.Name = c.Name
			mot.Part0, mot.Part1 = c.Attachment0.Parent, c.Attachment1.Parent
			mot.C0, mot.C1 = c.Attachment0.CFrame, c.Attachment1.CFrame
			local p1 = mot.Part1
			c:Destroy()
			mot.Parent = p1
		end
	end
	for _, c in ipairs(m:GetDescendants()) do
		if c:IsA("BallSocketConstraint") or c:IsA("HingeConstraint") then c:Destroy() end
	end
	-- the default face decal is replaced by built-in-shape faces (see face())
	local head = m:FindFirstChild("Head")
	if head then for _, c in ipairs(head:GetChildren()) do if c:IsA("Decal") then c:Destroy() end end end
	return m
end

-- Blocky expressive face made of thin parts on the front of the head. Irises and pupils hang off Motor6Ds (EyeJoint) so
-- the cinematic can move the eyes before the head turns. cfg: eye {w,h}, pupil {w,h}, brow {w,h,tiltDeg,y}, mouth {w,tiltDeg,y}, irisColor, browColor.
local function movable(model, size, offset, color, tag)
	local head = model:FindFirstChild("Head")
	local p = part({ Size = size, Color = color, Material = Enum.Material.SmoothPlastic, Anchored = false, Massless = true }, model)
	local m = Instance.new("Motor6D")
	m.Name = "EyeJoint"
	m.Part0, m.Part1, m.C0 = head, p, offset
	m:SetAttribute("EyeJoint", true)
	m.Parent = p
	if tag then p:SetAttribute(tag, true) end
	return p
end
local function face(model, cfg)
	local dark = Color3.fromRGB(18, 16, 20)
	for _, s in ipairs({ -1, 1 }) do
		local ex = s * 0.29
		accessory(model, "Head", Vector3.new(cfg.eye[1], cfg.eye[2], 0.04), CFrame.new(ex, 0.08, -0.61), Color3.fromRGB(240, 240, 244), Enum.Material.SmoothPlastic)
		movable(model, Vector3.new(cfg.pupil[1], cfg.pupil[2], 0.05), CFrame.new(ex - s * 0.02, 0.07, -0.625), cfg.irisColor, "Eye")
		movable(model, Vector3.new(cfg.pupil[1] * 0.45, cfg.pupil[2] * 0.45, 0.055), CFrame.new(ex - s * 0.02, 0.07, -0.63), dark)
		accessory(model, "Head", Vector3.new(cfg.brow[1], cfg.brow[2], 0.05),
			CFrame.new(ex, cfg.brow[4], -0.615) * CFrame.Angles(0, 0, math.rad(-s * cfg.brow[3])), cfg.browColor or dark, Enum.Material.SmoothPlastic, "Brow")
	end
	accessory(model, "Head", Vector3.new(cfg.mouth[1], 0.05, 0.04), CFrame.new(0.02, cfg.mouth[3], -0.61) * CFrame.Angles(0, 0, math.rad(cfg.mouth[2])), dark)
end

local MAT = Enum.Material.Fabric       -- clothing and hair are matte; nothing on a character is Neon except the one cyan seam on Kael

-- KAEL: broad blocky torso (wide shirt, wide shoulders), matte black swept-back hair with a fringe, warm tan face, fitted navy shirt,
-- short asymmetric scarf, charcoal pants, squared boots. ONE cyan seam on the right sleeve, and a compact angular bracer on the right forearm.
local function buildKael()
	local skin = Color3.fromRGB(214, 160, 116)
	local m = newRig("Blue", { skin = skin, torso = Color3.fromRGB(28, 36, 68), arm = Color3.fromRGB(28, 36, 68), leg = Color3.fromRGB(48, 50, 58) })
	m:SetAttribute("Character", "Kael")
	local navy, deep, char, black = Color3.fromRGB(28, 36, 68), Color3.fromRGB(20, 26, 50), Color3.fromRGB(48, 50, 58), Color3.fromRGB(26, 26, 32)
	local hairC = Color3.fromRGB(20, 18, 24)
	accessory(m, "Head", Vector3.new(1.3, 0.5, 1.3), CFrame.new(0, 0.62, 0.04), hairC, MAT, "Hair")
	for i = 1, 6 do          -- swept-back layers
		local x = (i - 3.5) * 0.32
		accessory(m, "Head", Vector3.new(0.34, 0.95 - math.abs(i - 3.5) * 0.12, 0.5), CFrame.new(x, 0.74, 0.28) * CFrame.Angles(0.8, 0, -x * 0.5), hairC, MAT, "Hair")
	end
	accessory(m, "Head", Vector3.new(0.34, 0.6, 0.45), CFrame.new(-0.62, 0.4, 0.22) * CFrame.Angles(0.5, 0, 0.3), hairC, MAT, "Hair")
	accessory(m, "Head", Vector3.new(0.34, 0.6, 0.45), CFrame.new(0.62, 0.4, 0.22) * CFrame.Angles(0.5, 0, -0.3), hairC, MAT, "Hair")
	-- fringe: three separate locks above the brows, swept to the left
	accessory(m, "Head", Vector3.new(0.45, 0.2, 0.4), CFrame.new(-0.4, 0.52, -0.5) * CFrame.Angles(-0.25, 0, 0.28), hairC, MAT, "Hair")
	accessory(m, "Head", Vector3.new(0.4, 0.2, 0.4), CFrame.new(0.02, 0.55, -0.52) * CFrame.Angles(-0.25, 0, 0.12), hairC, MAT, "Hair")
	accessory(m, "Head", Vector3.new(0.35, 0.18, 0.36), CFrame.new(0.4, 0.52, -0.5) * CFrame.Angles(-0.2, 0, -0.06), hairC, MAT, "Hair")
	face(m, { eye = { 0.28, 0.2 }, pupil = { 0.15, 0.18 }, brow = { 0.36, 0.08, 14, 0.3 }, mouth = { 0.3, 4, -0.3 }, irisColor = Color3.fromRGB(70, 48, 36) })
	-- broad torso: wide fitted navy shirt over the torso, broad shoulders
	accessory(m, "UpperTorso", Vector3.new(2.5, 1.5, 1.12), CFrame.new(0, -0.03, 0.01), navy, MAT)
	accessory(m, "UpperTorso", Vector3.new(2.62, 0.4, 1.16), CFrame.new(0, 0.62, 0.01), deep, MAT)                         -- shoulder yoke
	accessory(m, "UpperTorso", Vector3.new(1.0, 0.3, 0.9), CFrame.new(0, 0.88, 0), skin, Enum.Material.SmoothPlastic)      -- neck
	accessory(m, "LowerTorso", Vector3.new(2.2, 0.42, 1.12), CFrame.new(0, 0.1, 0.01), navy, MAT)
	accessory(m, "LowerTorso", Vector3.new(2.22, 0.2, 1.14), CFrame.new(0, -0.08, 0), black, Enum.Material.Leather)        -- belt
	for _, n in ipairs({ "RightUpperArm", "LeftUpperArm" }) do
		accessory(m, n, Vector3.new(1.3, 1.0, 1.3), CFrame.new(0, 0.12, 0), navy, MAT)                                        -- fitted sleeve
	end
	-- the one cyan seam (right sleeve, outer edge) so the viewer can track his lead arm
	accessory(m, "RightUpperArm", Vector3.new(0.07, 0.95, 0.07), CFrame.new(0.66, 0.12, 0), Color3.fromRGB(70, 215, 255), Enum.Material.Neon, "Seam")
	-- compact angular bracer: a plate with a forward wedge, matte charcoal
	local b1 = accessory(m, "RightLowerArm", Vector3.new(1.14, 0.62, 1.14), CFrame.new(0, 0.0, 0), char, Enum.Material.SmoothPlastic, "Bracer")
	if b1 then b1.Name = "KaelBracer" end
	accessory(m, "RightLowerArm", Vector3.new(0.5, 0.5, 0.42), CFrame.new(0, -0.02, -0.62) * CFrame.Angles(0.5, 0, 0), black, Enum.Material.SmoothPlastic, "Bracer")
	for _, n in ipairs({ "RightUpperLeg", "LeftUpperLeg" }) do accessory(m, n, Vector3.new(1.06, 1.12, 1.06), CFrame.new(0, 0, 0), char, MAT) end
	for _, n in ipairs({ "RightLowerLeg", "LeftLowerLeg" }) do accessory(m, n, Vector3.new(1.0, 1.0, 1.0), CFrame.new(0, 0.05, 0), char, MAT) end
	for _, n in ipairs({ "RightFoot", "LeftFoot" }) do accessory(m, n, Vector3.new(1.18, 0.78, 1.36), CFrame.new(0, 0.1, 0), black, Enum.Material.Leather) end   -- squared boots
	-- short asymmetric scarf: collar wrap + one long tail (3 segments) and one short tail (2 segments)
	accessory(m, "UpperTorso", Vector3.new(1.7, 0.4, 1.25), CFrame.new(0, 0.95, 0.04), Color3.fromRGB(40, 50, 90), MAT)
	local scarfC = Color3.fromRGB(40, 50, 90)
	local longTail = cloth(m, "UpperTorso", "Scarf1", CFrame.new(-0.3, 0.86, 0.62), 3, Vector3.new(0.5, 0.55, 0.16), scarfC)
	if longTail then longTail:SetAttribute("PowerSegment", true) end
	cloth(m, "UpperTorso", "Scarf2", CFrame.new(0.34, 0.86, 0.62), 2, Vector3.new(0.5, 0.5, 0.16), scarfC)
	addTrail(m, "RightHand", BLUE); addTrail(m, "LeftHand", BLUE)
	return m
end

-- REN: slightly taller, lean silhouette (tall hair clumps and a narrower torso), silver hair in distinct clumps with grey shadows,
-- visible brows and eyes, dark high collar below the mouth, charcoal split jacket, narrow violet cuffs. His face has its own light.
local function buildRen()
	local skin = Color3.fromRGB(236, 204, 178)
	local m = newRig("Purple", { skin = skin, torso = Color3.fromRGB(48, 50, 58), arm = Color3.fromRGB(48, 50, 58), leg = Color3.fromRGB(40, 42, 50) })
	m:SetAttribute("Character", "Ren")
	local coat, dark, char = Color3.fromRGB(48, 50, 58), Color3.fromRGB(26, 26, 34), Color3.fromRGB(40, 42, 50)
	local silver, shadowGrey = Color3.fromRGB(196, 200, 212), Color3.fromRGB(118, 122, 136)
	-- hair clumps: each lit clump has a grey shadow clump tucked behind / under it
	local clumps = {  -- pos, size, rot(x,y,z)
		{ Vector3.new(0.0, 0.85, -0.2), Vector3.new(0.7, 0.75, 0.6), Vector3.new(-0.3, 0, 0.1) },
		{ Vector3.new(-0.42, 0.9, 0.0), Vector3.new(0.5, 0.95, 0.55), Vector3.new(0, 0, 0.35) },
		{ Vector3.new(0.42, 0.95, 0.0), Vector3.new(0.5, 1.05, 0.55), Vector3.new(0, 0, -0.35) },
		{ Vector3.new(0.0, 1.05, 0.25), Vector3.new(0.6, 0.95, 0.6), Vector3.new(0.5, 0, 0.1) },
		{ Vector3.new(-0.62, 0.55, 0.1), Vector3.new(0.4, 0.8, 0.5), Vector3.new(0.1, 0, 0.5) },
		{ Vector3.new(0.62, 0.55, 0.1), Vector3.new(0.4, 0.8, 0.5), Vector3.new(0.1, 0, -0.5) },
		{ Vector3.new(0.0, 0.5, 0.5), Vector3.new(1.1, 0.7, 0.4), Vector3.new(0.3, 0, 0) },
	}
	accessory(m, "Head", Vector3.new(1.3, 0.45, 1.3), CFrame.new(0, 0.62, 0.04), shadowGrey, MAT, "Hair")
	for _, c in ipairs(clumps) do
		accessory(m, "Head", c[2] * 0.95, CFrame.new(c[1] + Vector3.new(0, -0.12, 0.1)) * CFrame.Angles(c[3].X, c[3].Y, c[3].Z), shadowGrey, MAT, "Hair")   -- shadow clump
		accessory(m, "Head", c[2], CFrame.new(c[1]) * CFrame.Angles(c[3].X, c[3].Y, c[3].Z), silver, MAT, "Hair")
	end
	-- fringe clumps above the brows (brows stay visible below them)
	accessory(m, "Head", Vector3.new(0.5, 0.2, 0.38), CFrame.new(-0.3, 0.5, -0.5) * CFrame.Angles(-0.25, 0, 0.2), silver, MAT, "Hair")
	accessory(m, "Head", Vector3.new(0.5, 0.2, 0.38), CFrame.new(0.25, 0.52, -0.5) * CFrame.Angles(-0.25, 0, -0.15), silver, MAT, "Hair")
	face(m, { eye = { 0.3, 0.17 }, pupil = { 0.17, 0.15 }, brow = { 0.42, 0.1, 10, 0.3 }, mouth = { 0.3, 0, -0.3 }, irisColor = Color3.fromRGB(96, 118, 170), browColor = Color3.fromRGB(80, 82, 94) })
	-- face light independent of any power: small, soft, white, no shadows
	local head = m:FindFirstChild("Head")
	local fl = Instance.new("PointLight")
	fl.Name = "BGFaceLight"
	fl.Range, fl.Brightness, fl.Color, fl.Shadows = 6, 0.6, Color3.fromRGB(255, 246, 238), false
	fl.Parent = head
	-- lean charcoal split jacket with a dark high collar below the mouth
	accessory(m, "UpperTorso", Vector3.new(2.0, 1.5, 1.08), CFrame.new(0, -0.03, 0.01), coat, MAT)
	accessory(m, "UpperTorso", Vector3.new(1.66, 0.62, 1.3), CFrame.new(0, 0.72, 0.0), dark, MAT)                           -- collar top sits just under the mouth
	accessory(m, "UpperTorso", Vector3.new(0.08, 1.35, 0.08), CFrame.new(0, -0.05, -0.58), Color3.fromRGB(70, 72, 86), Enum.Material.SmoothPlastic)
	accessory(m, "LowerTorso", Vector3.new(2.0, 0.42, 1.08), CFrame.new(0, 0.1, 0.01), coat, MAT)
	accessory(m, "LowerTorso", Vector3.new(2.02, 0.18, 1.1), CFrame.new(0, -0.08, 0), dark, Enum.Material.Leather)
	for _, n in ipairs({ "RightUpperArm", "LeftUpperArm" }) do accessory(m, n, Vector3.new(1.12, 1.0, 1.12), CFrame.new(0, 0.12, 0), coat, MAT) end
	-- narrow violet cuffs (matte)
	for _, n in ipairs({ "RightLowerArm", "LeftLowerArm" }) do
		accessory(m, n, Vector3.new(1.06, 0.14, 1.06), CFrame.new(0, -0.38, 0), Color3.fromRGB(140, 96, 220), Enum.Material.SmoothPlastic, "Seam")
	end
	for _, n in ipairs({ "RightUpperLeg", "LeftUpperLeg" }) do accessory(m, n, Vector3.new(1.0, 1.12, 1.0), CFrame.new(0, 0, 0), char, MAT) end
	for _, n in ipairs({ "RightLowerLeg", "LeftLowerLeg" }) do accessory(m, n, Vector3.new(0.96, 1.0, 0.96), CFrame.new(0, 0.05, 0), char, MAT) end
	for _, n in ipairs({ "RightFoot", "LeftFoot" }) do accessory(m, n, Vector3.new(1.1, 0.74, 1.3), CFrame.new(0, 0.1, 0), dark, Enum.Material.Leather) end
	-- split jacket flaps behind (violet lining shows when they swing)
	for k, x in ipairs({ -0.5, 0.5 }) do
		cloth(m, "LowerTorso", "Hem" .. k, CFrame.new(x, -0.1, 0.56), 2, Vector3.new(0.92, 0.8, 0.14), coat, Color3.fromRGB(110, 70, 190))
	end
	addTrail(m, "RightHand", VIOLET); addTrail(m, "LeftHand", VIOLET)
	return m
end


---------------------------------------------------------------- loose floor tiles (cinematic reacts through them)
local tiles = Instance.new("Folder")
tiles.Name = "Tiles"
tiles.Parent = stage
math.randomseed(21)
for ix = -7, 7 do
	for iz = -1, 1 do
		local shade = math.random(60, 78)
		local t = part({ Name = "Tile_" .. ix .. "_" .. iz, Size = Vector3.new(3.84, 0.5, 3.84), CFrame = CFrame.new(ix * 4, 0.02 - 0.25 + 0.02, iz * 4),
			Color = Color3.fromRGB(shade, shade + 2, shade + 14), Material = Enum.Material.Slate }, tiles)
		t:SetAttribute("Col", ix)
		t:SetAttribute("Row", iz)
	end
end

local kael = buildKael()
local ren = buildRen()
kael:PivotTo(CFrame.new(-Config.arena.spawn, 3, 0) * CFrame.Angles(0, math.rad(-90), 0))
ren:PivotTo(CFrame.new(Config.arena.spawn, 3, 0) * CFrame.Angles(0, math.rad(90), 0))
for _, m in ipairs({ kael, ren }) do
	m.HumanoidRootPart.Anchored = true     -- the clients position it each frame
end

stage:SetAttribute("Mode", "Cinematic")
stage:SetAttribute("Ready", true)
print("[BG] arena and fighters built (Blue = Kael, Purple = Ren).")
