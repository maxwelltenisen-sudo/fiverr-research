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
Lighting.Brightness = 1.7
Lighting.ExposureCompensation = 0.45
Lighting.Ambient = Color3.fromRGB(62, 66, 105)
Lighting.OutdoorAmbient = Color3.fromRGB(78, 82, 125)

local function fx(inst)
	inst:SetAttribute("ShowcaseFX", true)
	inst.Parent = Lighting
	return inst
end
local atmo = Instance.new("Atmosphere")
atmo.Density = 0.28; atmo.Offset = 0.2; atmo.Color = Color3.fromRGB(100, 110, 175); atmo.Decay = Color3.fromRGB(40, 45, 90)
fx(atmo)
local bloom = Instance.new("BloomEffect")
bloom.Intensity = 0.9; bloom.Size = 26; bloom.Threshold = 0.9
fx(bloom)
local cc = Instance.new("ColorCorrectionEffect")
cc.Contrast = 0.28; cc.Saturation = -0.2; cc.TintColor = Color3.fromRGB(225, 228, 255)   -- high contrast, desaturated world: blue and violet are the only colours
fx(cc)
local dof = Instance.new("DepthOfFieldEffect")
dof.FarIntensity = 0.12; dof.NearIntensity = 0; dof.FocusDistance = 14; dof.InFocusRadius = 28
fx(dof)

local R = Config.arena.radius
local STONE, STONE2, STONE3 = Color3.fromRGB(58, 60, 74), Color3.fromRGB(40, 42, 56), Color3.fromRGB(78, 80, 98)
part({ Name = "Ground", Size = Vector3.new(500, 1, 500), Position = Vector3.new(0, -0.5, 0), Color = Color3.fromRGB(28, 30, 42),
	Material = Enum.Material.Slate, CanCollide = true })
-- raised stone disc
part({ Name = "ArenaFloor", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, (R + 3) * 2, (R + 3) * 2),
	CFrame = CFrame.new(0, -0.55, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(30, 32, 44), Material = Enum.Material.Slate, Reflectance = 0.3, CanCollide = true })   -- dark glossy floor
part({ Size = Vector3.new(0.1, (R + 3.4) * 2, (R + 3.4) * 2), Shape = Enum.PartType.Cylinder,
	CFrame = CFrame.new(0, -0.02, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = STONE3, Material = Enum.Material.Slate })
part({ Size = Vector3.new(0.12, R * 2, R * 2), Shape = Enum.PartType.Cylinder,
	CFrame = CFrame.new(0, 0.0, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = STONE2, Material = Enum.Material.Cobblestone })
-- engraved rings: restrained, so fighters stay the brightest things in the frame
for _, spec in ipairs({ { R * 2 - 1, 0.5, BLUE }, { R * 1.3, 0.4, VIOLET }, { 7, 0.35, Color3.fromRGB(150, 160, 210) } }) do
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.06, spec[1], spec[1]), CFrame = CFrame.new(0, 0.05, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = spec[3], Material = Enum.Material.Neon, Transparency = 0.82 })
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.07, spec[1] - 0.35, spec[1] - 0.35), CFrame = CFrame.new(0, 0.06, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = STONE2, Material = Enum.Material.Cobblestone })
end
part({ Name = "Moon", Shape = Enum.PartType.Ball, Size = Vector3.new(70, 70, 70), Position = Vector3.new(-70, 140, -260),
	Color = Color3.fromRGB(225, 232, 255), Material = Enum.Material.Neon, Transparency = 0.05 })

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
			local l = part({ Size = Vector3.new(size.X * 0.92, size.Y * 0.96, 0.05), Color = lining, Material = Enum.Material.Neon, Transparency = 0.55 }, model)
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

-- Blocky expressive face made of thin parts on the front of the head.
-- cfg: eye = {w,h}, pupil = {w,h}, brow = {w,h,tiltDeg,y}, mouth = {w,tiltDeg,y}, irisColor
local function face(model, cfg)
	local dark = Color3.fromRGB(18, 16, 20)
	for _, s in ipairs({ -1, 1 }) do
		local ex = s * 0.29
		accessory(model, "Head", Vector3.new(cfg.eye[1], cfg.eye[2], 0.04), CFrame.new(ex, 0.08, -0.61), Color3.fromRGB(246, 246, 250), Enum.Material.SmoothPlastic)
		accessory(model, "Head", Vector3.new(cfg.pupil[1], cfg.pupil[2], 0.05), CFrame.new(ex - s * 0.02, 0.07, -0.625), cfg.irisColor, Enum.Material.SmoothPlastic, "Eye")
		accessory(model, "Head", Vector3.new(cfg.pupil[1] * 0.45, cfg.pupil[2] * 0.45, 0.055), CFrame.new(ex - s * 0.02, 0.07, -0.63), dark)
		-- eyebrows tilt toward the nose and down = focused / stern
		accessory(model, "Head", Vector3.new(cfg.brow[1], cfg.brow[2], 0.05),
			CFrame.new(ex, cfg.brow[4], -0.615) * CFrame.Angles(0, 0, math.rad(-s * cfg.brow[3])), cfg.browColor or dark, Enum.Material.SmoothPlastic, "Brow")
	end
	accessory(model, "Head", Vector3.new(cfg.mouth[1], 0.05, 0.04), CFrame.new(0.02, cfg.mouth[3], -0.61) * CFrame.Angles(0, 0, math.rad(cfg.mouth[2])), dark)
end

-- KAEL (Blue): slightly leaner, dark swept-back spiky hair with one blue lock, warm tan face, navy fitted combat jacket with cyan piping,
-- short two-tail scarf, black belt with silver buckle, tapered dark pants, charcoal boots, fingerless gloves, slim right forearm guard.
local function buildKael()
	local m = newRig("Blue", { skin = Color3.fromRGB(222, 170, 124), torso = Color3.fromRGB(26, 34, 66),
		arm = Color3.fromRGB(26, 34, 66), leg = Color3.fromRGB(26, 28, 38) })
	m:SetAttribute("Character", "Kael")
	local navy, deep, black = Color3.fromRGB(26, 34, 66), Color3.fromRGB(18, 22, 44), Color3.fromRGB(14, 14, 18)
	local char = Color3.fromRGB(50, 52, 62)
	local hairC = Color3.fromRGB(22, 20, 30)
	-- hair: cap + swept-back spikes in layers, one blue lock near the fringe
	accessory(m, "Head", Vector3.new(1.3, 0.5, 1.3), CFrame.new(0, 0.62, 0.02), hairC, nil, "Hair")
	for i = 1, 7 do
		local x = (i - 4) * 0.3
		local h = 1.0 - math.abs(i - 4) * 0.1
		accessory(m, "Head", Vector3.new(0.34, h, 0.5), CFrame.new(x, 0.78, 0.22) * CFrame.Angles(0.75, 0, -x * 0.5), hairC, nil, "Hair")
	end
	accessory(m, "Head", Vector3.new(0.3, 0.7, 0.45), CFrame.new(-0.6, 0.45, 0.2) * CFrame.Angles(0.5, 0, 0.35), hairC, nil, "Hair")
	accessory(m, "Head", Vector3.new(0.3, 0.7, 0.45), CFrame.new(0.6, 0.45, 0.2) * CFrame.Angles(0.5, 0, -0.35), hairC, nil, "Hair")
	accessory(m, "Head", Vector3.new(0.2, 0.55, 0.3), CFrame.new(-0.3, 0.7, -0.45) * CFrame.Angles(-0.5, 0, 0.1), BLUE, Enum.Material.SmoothPlastic, "Accent")   -- the blue lock
	face(m, { eye = { 0.28, 0.2 }, pupil = { 0.16, 0.18 }, brow = { 0.36, 0.08, 16, 0.3 }, mouth = { 0.3, 5, -0.3 }, irisColor = Color3.fromRGB(38, 70, 120) })
	-- fitted jacket, collar and piping
	accessory(m, "UpperTorso", Vector3.new(2.05, 1.42, 1.08), CFrame.new(0, -0.05, 0.01), navy, Enum.Material.Fabric)
	accessory(m, "UpperTorso", Vector3.new(2.1, 0.5, 1.1), CFrame.new(0, 0.74, 0), deep, Enum.Material.Fabric)                   -- collar band
	accessory(m, "UpperTorso", Vector3.new(0.09, 1.3, 0.1), CFrame.new(0, -0.05, -0.58), Color3.fromRGB(170, 175, 195), Enum.Material.Metal)  -- zip
	accessory(m, "UpperTorso", Vector3.new(2.14, 0.07, 1.14), CFrame.new(0, 0.66, 0), CYAN, Enum.Material.Neon, "Seam")           -- shoulder line piping
	accessory(m, "UpperTorso", Vector3.new(0.07, 0.9, 0.07), CFrame.new(-0.5, -0.15, -0.58), CYAN, Enum.Material.Neon, "Seam")
	accessory(m, "UpperTorso", Vector3.new(0.07, 0.9, 0.07), CFrame.new(0.5, -0.15, -0.58), CYAN, Enum.Material.Neon, "Seam")
	accessory(m, "LowerTorso", Vector3.new(2.05, 0.4, 1.08), CFrame.new(0, 0.1, 0.01), navy, Enum.Material.Fabric)
	accessory(m, "LowerTorso", Vector3.new(2.06, 0.2, 1.1), CFrame.new(0, -0.06, 0), black, Enum.Material.Leather)                 -- matte belt
	accessory(m, "LowerTorso", Vector3.new(0.3, 0.2, 0.08), CFrame.new(0, -0.06, -0.57), Color3.fromRGB(205, 208, 220), Enum.Material.Metal) -- silver buckle
	for _, n in ipairs({ "RightUpperArm", "LeftUpperArm" }) do
		accessory(m, n, Vector3.new(1.12, 0.35, 1.12), CFrame.new(0, 0.48, 0), navy, Enum.Material.Fabric)                          -- angled shoulder
		accessory(m, n, Vector3.new(1.16, 0.07, 1.16), CFrame.new(0, 0.3, 0), CYAN, Enum.Material.Neon, "Seam")
	end
	for _, n in ipairs({ "RightLowerArm", "LeftLowerArm" }) do
		accessory(m, n, Vector3.new(1.06, 0.07, 1.06), CFrame.new(0, 0.3, 0), CYAN, Enum.Material.Neon, "Seam")                     -- forearm piping
		accessory(m, n, Vector3.new(1.06, 0.07, 1.06), CFrame.new(0, -0.3, 0), CYAN, Enum.Material.Neon, "Seam")
	end
	local g = accessory(m, "RightLowerArm", Vector3.new(1.14, 0.65, 1.14), CFrame.new(0, -0.02, 0), char, Enum.Material.Metal, "Bracer")   -- slim right forearm guard
	if g then g.Name = "KaelGuardR" end
	accessory(m, "RightLowerArm", Vector3.new(1.18, 0.06, 1.18), CFrame.new(0, 0.25, 0), CYAN, Enum.Material.Neon, "Seam")
	for _, n in ipairs({ "RightHand", "LeftHand" }) do
		accessory(m, n, Vector3.new(1.02, 0.34, 1.02), CFrame.new(0, 0.12, 0), black, Enum.Material.Leather)                         -- fingerless glove
	end
	for _, n in ipairs({ "RightUpperLeg", "LeftUpperLeg" }) do accessory(m, n, Vector3.new(1.04, 1.1, 1.04), CFrame.new(0, 0, 0), Color3.fromRGB(28, 30, 40), Enum.Material.Fabric) end
	for _, n in ipairs({ "RightLowerLeg", "LeftLowerLeg" }) do
		accessory(m, n, Vector3.new(0.92, 0.95, 0.92), CFrame.new(0, 0.02, 0), Color3.fromRGB(28, 30, 40), Enum.Material.Fabric)      -- tapered
		accessory(m, n, Vector3.new(1.1, 0.38, 1.1), CFrame.new(0, -0.45, 0), char, Enum.Material.Leather)                           -- boot cuff
	end
	for _, n in ipairs({ "RightFoot", "LeftFoot" }) do accessory(m, n, Vector3.new(1.1, 0.7, 1.25), CFrame.new(0, 0.1, 0), char, Enum.Material.Leather) end
	-- short scarf: collar wrap + two tails (third segment appears in power forms)
	accessory(m, "UpperTorso", Vector3.new(1.7, 0.42, 1.25), CFrame.new(0, 0.9, 0.04), Color3.fromRGB(34, 44, 86), Enum.Material.Fabric)
	local tailC = Color3.fromRGB(34, 44, 86)
	for k, x in ipairs({ -0.32, 0.32 }) do
		local last = cloth(m, "UpperTorso", "Scarf" .. k, CFrame.new(x, 0.78, 0.62), 3, Vector3.new(0.5, 0.55, 0.16), tailC)
		if last then
			last.Transparency = 1                      -- the long third segment is hidden until Charged Mode
			last:SetAttribute("PowerSegment", true)
			local trim = part({ Size = Vector3.new(0.5, 0.07, 0.17), Color = CYAN, Material = Enum.Material.Neon, Anchored = false, Massless = true }, m)
			trim:SetAttribute("Seam", true)
			weld(trim, m:FindFirstChild("Scarf" .. k .. 2) or last, CFrame.new(0, -0.27, 0))
		end
	end
	addTrail(m, "RightHand", BLUE); addTrail(m, "LeftHand", BLUE)
	return m
end

-- REN (Purple): broader shoulders, lower and heavier, silver-lavender side-swept hair, stern square face,
-- black high-collar coat with a split hem and violet lining, charcoal pants, heavy square boots, reinforced bracers, angular back emblem.
local function buildRen()
	local m = newRig("Purple", { skin = Color3.fromRGB(236, 200, 172), torso = Color3.fromRGB(16, 16, 22),
		arm = Color3.fromRGB(20, 20, 28), leg = Color3.fromRGB(44, 46, 56) })
	m:SetAttribute("Character", "Ren")
	local black, coat, char = Color3.fromRGB(14, 14, 20), Color3.fromRGB(18, 18, 26), Color3.fromRGB(46, 48, 58)
	local hairC = Color3.fromRGB(190, 184, 220)
	-- hair: cap + a long slab swept to one side so the brows stay visible
	accessory(m, "Head", Vector3.new(1.32, 0.5, 1.32), CFrame.new(0, 0.63, 0.02), hairC, nil, "Hair")
	accessory(m, "Head", Vector3.new(1.0, 0.34, 1.0), CFrame.new(0.22, 0.88, -0.05) * CFrame.Angles(0, 0, -0.28), hairC, nil, "Hair")
	accessory(m, "Head", Vector3.new(0.7, 0.3, 0.9), CFrame.new(0.62, 0.74, 0.0) * CFrame.Angles(0, 0, -0.5), hairC, nil, "Hair")
	accessory(m, "Head", Vector3.new(0.5, 0.28, 0.5), CFrame.new(0.85, 0.52, -0.05) * CFrame.Angles(0, 0, -0.9), hairC, nil, "Hair")
	accessory(m, "Head", Vector3.new(0.9, 0.18, 0.4), CFrame.new(0.2, 0.52, -0.45) * CFrame.Angles(-0.2, 0, -0.18), hairC, nil, "Hair")   -- fringe above the brows
	accessory(m, "Head", Vector3.new(0.35, 0.6, 0.5), CFrame.new(-0.58, 0.3, 0.2), hairC, nil, "Hair")
	face(m, { eye = { 0.3, 0.15 }, pupil = { 0.16, 0.14 }, brow = { 0.42, 0.1, 12, 0.28 }, mouth = { 0.32, 0, -0.3 }, irisColor = Color3.fromRGB(88, 70, 120), browColor = Color3.fromRGB(26, 22, 32) })
	-- high-collar coat
	accessory(m, "UpperTorso", Vector3.new(2.38, 1.5, 1.16), CFrame.new(0, -0.04, 0.01), coat, Enum.Material.Fabric)
	accessory(m, "UpperTorso", Vector3.new(2.2, 0.8, 1.32), CFrame.new(0, 0.86, 0.02), black, Enum.Material.Fabric)                -- high collar
	accessory(m, "UpperTorso", Vector3.new(0.12, 0.7, 1.34), CFrame.new(0, 0.86, 0), VIOLET, Enum.Material.Neon, "Seam", { Transparency = 1 })
	accessory(m, "UpperTorso", Vector3.new(0.08, 1.35, 0.08), CFrame.new(0, -0.05, -0.6), Color3.fromRGB(60, 60, 78), Enum.Material.Metal)
	accessory(m, "LowerTorso", Vector3.new(2.2, 0.42, 1.12), CFrame.new(0, 0.1, 0.01), coat, Enum.Material.Fabric)
	accessory(m, "LowerTorso", Vector3.new(2.22, 0.2, 1.14), CFrame.new(0, -0.06, 0), black, Enum.Material.Leather)
	-- angular emblem on the back: two nested chevron bars
	for i, w in ipairs({ 1.0, 0.62 }) do
		accessory(m, "UpperTorso", Vector3.new(w, 0.12, 0.05), CFrame.new(-w * 0.2, 0.25 - i * 0.32, 0.6) * CFrame.Angles(0, 0, 0.5), VIOLET, Enum.Material.Neon, "Emblem", { Transparency = 0.45 })
		accessory(m, "UpperTorso", Vector3.new(w, 0.12, 0.05), CFrame.new(w * 0.2, 0.25 - i * 0.32, 0.6) * CFrame.Angles(0, 0, -0.5), VIOLET, Enum.Material.Neon, "Emblem", { Transparency = 0.45 })
	end
	for _, n in ipairs({ "RightUpperArm", "LeftUpperArm" }) do
		accessory(m, n, Vector3.new(1.34, 0.45, 1.34), CFrame.new(0, 0.45, 0), black, Enum.Material.Fabric)                         -- broad shoulder
		accessory(m, n, Vector3.new(1.18, 0.9, 1.18), CFrame.new(0, -0.1, 0), coat, Enum.Material.Fabric)
	end
	-- reinforced bracers: width comes from the cinematic contact data so the clash geometry matches
	local gw = Data.contacts[1].guardRadius * 2
	for _, n in ipairs({ "RightLowerArm", "LeftLowerArm" }) do
		local la = m:FindFirstChild(n)
		local g = accessory(m, n, Vector3.new(gw, la.Size.Y * 0.85, gw), CFrame.new(0, 0, 0), Color3.fromRGB(24, 24, 32), Enum.Material.Metal, "Bracer")
		g.Name = (n == "LeftLowerArm") and "GuardL" or "GuardR"
		for _, y in ipairs({ 0.3, -0.3 }) do
			accessory(m, n, Vector3.new(gw + 0.04, 0.08, gw + 0.04), CFrame.new(0, la.Size.Y * y, 0), VIOLET, Enum.Material.Neon, "Seam", { Transparency = 1 })
		end
		accessory(m, n, Vector3.new(gw + 0.2, 0.5, gw + 0.2), CFrame.new(0, 0, 0), VIOLET, Enum.Material.Neon, "Accent", { Transparency = 1 })   -- translucent layer for Eclipse Form
	end
	for _, n in ipairs({ "RightHand", "LeftHand" }) do accessory(m, n, Vector3.new(1.04, 0.4, 1.04), CFrame.new(0, 0.1, 0), black, Enum.Material.Leather) end
	for _, n in ipairs({ "RightUpperLeg", "LeftUpperLeg" }) do accessory(m, n, Vector3.new(1.16, 1.12, 1.16), CFrame.new(0, 0, 0), char, Enum.Material.Fabric) end
	for _, n in ipairs({ "RightLowerLeg", "LeftLowerLeg" }) do accessory(m, n, Vector3.new(1.1, 1.0, 1.1), CFrame.new(0, 0.02, 0), char, Enum.Material.Fabric) end
	for _, n in ipairs({ "RightFoot", "LeftFoot" }) do accessory(m, n, Vector3.new(1.2, 0.8, 1.38), CFrame.new(0, 0.12, 0), black, Enum.Material.Leather) end   -- heavy square boots
	-- split hem: two flaps at the back, violet lining shows when they swing
	for k, x in ipairs({ -0.52, 0.52 }) do
		cloth(m, "LowerTorso", "Hem" .. k, CFrame.new(x, -0.1, 0.56), 2, Vector3.new(0.95, 0.75, 0.14), coat, VIOLET)
	end
	-- two long hair tails from the back of the head: cloth chains that swing with the body
	for k, x in ipairs({ -0.3, 0.3 }) do
		cloth(m, "Head", "HT" .. k, CFrame.new(x, 0.15, 0.6), 3, Vector3.new(0.42, 1.0, 0.14), hairC)
	end
	for _, c in ipairs(m:GetChildren()) do
		if c:IsA("BasePart") and c.Name:sub(1, 2) == "HT" then c:SetAttribute("Hair", true) end
	end
	addTrail(m, "RightHand", VIOLET); addTrail(m, "LeftHand", VIOLET)
	addTrail(m, "RightLowerArm", VIOLET); addTrail(m, "LeftLowerArm", VIOLET)
	return m
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
