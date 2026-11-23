-- BGBuilder (Script, ServerScriptService): builds the moonlit stone arena and the two R15 fighters (Kael = "Blue", Ren = "Purple").
-- It does not animate or fight: BGServer decides combat, BGClient / BGDirector pose the rigs.
-- Re-running is safe (the previous build is deleted first). Edit costume colours / parts in the two build functions below.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local Data = require(ReplicatedStorage:WaitForChild("BGCinematicData"))
local Duel = require(ReplicatedStorage:WaitForChild("BGDuel"))

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

---------------------------------------------------------------- courtyard (overcast dusk: matte stone, nothing glows)
Lighting.ClockTime = 17.6
Lighting.Brightness = 1.6
Lighting.ExposureCompensation = 0
Lighting.Ambient = Color3.fromRGB(104, 104, 118)
Lighting.OutdoorAmbient = Color3.fromRGB(116, 116, 130)
local function fx(inst)
	inst:SetAttribute("ShowcaseFX", true)
	inst.Parent = Lighting
	return inst
end
local atmo = Instance.new("Atmosphere")
atmo.Density = 0.22; atmo.Offset = 0.15; atmo.Color = Color3.fromRGB(170, 172, 190); atmo.Decay = Color3.fromRGB(120, 120, 140); atmo.Haze = 0.4
fx(atmo)
local bloom = Instance.new("BloomEffect")
bloom.Intensity = 0.2; bloom.Size = 12; bloom.Threshold = 2.0          -- low: white hair keeps its detail
fx(bloom)
local cc = Instance.new("ColorCorrectionEffect")
cc.Contrast = 0.08; cc.Saturation = -0.05; cc.TintColor = Color3.fromRGB(240, 238, 245)
fx(cc)

local STONE, STONE2, STONE3 = Color3.fromRGB(150, 148, 154), Color3.fromRGB(120, 118, 126), Color3.fromRGB(96, 94, 104)   -- pale but never white
part({ Name = "Ground", Size = Vector3.new(600, 1, 600), Position = Vector3.new(0, -0.5, 0), Color = Color3.fromRGB(96, 98, 104), Material = Enum.Material.Slate, CanCollide = true })
part({ Name = "CourtFloor", Size = Vector3.new(70, 0.6, 26), Position = Vector3.new(-6, -0.3, 0), Color = STONE2, Material = Enum.Material.Slate })
local A = Duel.arena
-- stair: four steps up to the walkway
local stepN = 4
for i = 1, stepN do
	local h = A.stair.topY * i / stepN
	local x0 = A.stair.x0 + (i - 1) * (A.stair.x1 - A.stair.x0) / stepN
	local w = (A.stair.x1 - A.stair.x0) / stepN
	part({ Name = "Step" .. i, Size = Vector3.new(w, h, 12), Position = Vector3.new(x0 + w / 2, h / 2, 0), Color = STONE:Lerp(STONE3, i * 0.08), Material = Enum.Material.Slate })
end
part({ Name = "Walkway", Size = Vector3.new(A.walkway.x1 - A.walkway.x0, A.walkway.y, 12), Position = Vector3.new((A.walkway.x0 + A.walkway.x1) / 2, A.walkway.y / 2, 0), Color = STONE, Material = Enum.Material.Slate })
for _, z in ipairs({ -6.2, 6.2 }) do
	part({ Size = Vector3.new(A.walkway.x1 - A.walkway.x0, 1.0, 0.5), Position = Vector3.new((A.walkway.x0 + A.walkway.x1) / 2, A.walkway.y + 0.5, z), Color = STONE3, Material = Enum.Material.Slate })
end
-- the broken step the glasses end on (a chipped corner of step 3)
part({ Name = "BrokenStep", Size = Vector3.new(1.4, 0.3, 1.6), CFrame = CFrame.new(A.step.x, A.step.y + 0.05, 1.6) * CFrame.Angles(0, 0.4, 0.12), Color = STONE3, Material = Enum.Material.Slate })
-- the broken pillar and its fallen top
part({ Name = "PillarBase", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.4, 3.0, 3.0), CFrame = CFrame.new(A.pillar.x, 1.7, -3.2) * CFrame.Angles(0, 0, math.rad(90)), Color = STONE, Material = Enum.Material.Slate })
part({ Name = "PillarJag", Size = Vector3.new(1.8, 1.3, 1.6), CFrame = CFrame.new(A.pillar.x + 0.2, 3.8, -3.3) * CFrame.Angles(0.3, 0.5, 0.2), Color = STONE2, Material = Enum.Material.Slate })
part({ Name = "PillarFallen", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4.6, 2.6, 2.6), CFrame = CFrame.new(A.pillar.x - 2.2, 1.3, -5.6) * CFrame.Angles(0, 0.5, math.rad(90)), Color = STONE, Material = Enum.Material.Slate })
-- the courtyard gate (left): two posts, lintel, and a darker opening
for _, z in ipairs({ -6, 6 }) do part({ Size = Vector3.new(1.6, 8, 1.6), Position = Vector3.new(A.gate.x - 2, 4, z), Color = STONE3, Material = Enum.Material.Slate }) end
part({ Name = "GateLintel", Size = Vector3.new(2.2, 1.2, 15), Position = Vector3.new(A.gate.x - 2, 8.4, 0), Color = STONE3, Material = Enum.Material.Slate })
part({ Name = "GateRoof", Size = Vector3.new(3.4, 0.5, 16), Position = Vector3.new(A.gate.x - 2, 9.3, 0), Color = Color3.fromRGB(70, 68, 78), Material = Enum.Material.Slate })
-- back wall with two blocks (depth for the wide shots)
part({ Size = Vector3.new(70, 6, 1.5), Position = Vector3.new(-2, 3, -13), Color = STONE2, Material = Enum.Material.Slate })
part({ Size = Vector3.new(14, 9, 8), Position = Vector3.new(-24, 4.5, -18), Color = STONE3, Material = Enum.Material.Slate })
part({ Size = Vector3.new(18, 11, 8), Position = Vector3.new(20, 5.5, -19), Color = STONE3, Material = Enum.Material.Slate })
-- soft cool sky fill and warm key
for _, spec in ipairs({ { Vector3.new(-8, 14, 12), Color3.fromRGB(190, 200, 235), 0.8 }, { Vector3.new(12, 14, 12), Color3.fromRGB(255, 226, 200), 0.7 } }) do
	local lp = part({ Size = Vector3.new(1, 1, 1), Position = spec[1], Transparency = 1 })
	lp:SetAttribute("Invisible", true)
	local l = Instance.new("PointLight")
	l.Color, l.Range, l.Brightness, l.Shadows = spec[2], 60, spec[3], false
	l.Parent = lp
end
local focus = part({ Name = "FocusPoint", Size = Vector3.new(1, 1, 1), Position = Vector3.new(0, 4, 0), Transparency = 1 })
focus:SetAttribute("Invisible", true)
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


local MAT = Enum.Material.Fabric       -- clothing and hair are matte; nothing on a character glows

-- Round dark glasses. Parts are tagged "Glasses" so the player can hide them from the face and show a loose prop instead.
local function buildGlasses(model, headPart, tag)
	local function lens(ex)
		local rim = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.05, 0.36, 0.36), Color = Color3.fromRGB(10, 10, 12), Material = Enum.Material.SmoothPlastic }, model)
		weld(rim, headPart, CFrame.new(ex, 0.08, -0.625) * CFrame.Angles(0, math.rad(90), 0))
		local gl = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.05, 0.28, 0.28), Color = Color3.fromRGB(22, 24, 30), Material = Enum.Material.Glass, Transparency = 0.3 }, model)
		weld(gl, headPart, CFrame.new(ex, 0.08, -0.65) * CFrame.Angles(0, math.rad(90), 0))
		rim:SetAttribute(tag, true); gl:SetAttribute(tag, true)
	end
	lens(-0.29); lens(0.29)
	local bridge = part({ Size = Vector3.new(0.2, 0.04, 0.05), Color = Color3.fromRGB(10, 10, 12) }, model)
	weld(bridge, headPart, CFrame.new(0, 0.1, -0.64)); bridge:SetAttribute(tag, true)
	for _, s in ipairs({ -1, 1 }) do
		local t = part({ Size = Vector3.new(0.04, 0.04, 0.7), Color = Color3.fromRGB(10, 10, 12) }, model)
		weld(t, headPart, CFrame.new(s * 0.62, 0.1, -0.28)); t:SetAttribute(tag, true)
	end
end

-- hair clump: a base block and a tapered tip, tilted outward
local function clump(model, base, tip, offset, rot, c, tag)
	-- three stacked, progressively narrower segments, each bent a little further: reads as a tapered lock, not a strip
	local cf = CFrame.new(offset) * CFrame.Angles(rot.X, rot.Y, rot.Z)
	local w, h, d = base.X, base.Y, base.Z
	accessory(model, "Head", Vector3.new(w, h, d), cf, c, MAT, tag or "Hair")
	cf = cf * CFrame.new(0, h / 2 + h * 0.3, 0) * CFrame.Angles(0.22, 0, rot.Z * 0.2)
	accessory(model, "Head", Vector3.new(w * 0.72, h * 0.8, d * 0.72), cf, c, MAT, tag or "Hair")
	cf = cf * CFrame.new(0, h * 0.4 + h * 0.28, 0) * CFrame.Angles(0.3, 0, rot.Z * 0.25)
	accessory(model, "Head", Vector3.new(w * 0.4, h * 0.7, d * 0.4), cf, c, MAT, tag or "Hair")
end

-- TEEN GOJO: tall and slender, layered irregular white clumps with cool grey roots and gaps over the forehead, small round dark glasses,
-- fine pale brows, bright blue irises with dark pupils, small relaxed mouth, dark high-collar uniform. Adult parts (hidden) are tagged "Adult".
local function buildGojo()
	local skin = Color3.fromRGB(240, 214, 194)
	local m = newRig("Blue", { skin = skin, torso = Color3.fromRGB(24, 26, 38), arm = Color3.fromRGB(24, 26, 38), leg = Color3.fromRGB(22, 24, 34) })
	m:SetAttribute("Character", "Kael"); m:SetAttribute("Persona", "Gojo")
	local head = m:FindFirstChild("Head")
	local white, root = Color3.fromRGB(238, 240, 248), Color3.fromRGB(148, 156, 178)
	local uniform, deep, shoe = Color3.fromRGB(36, 40, 58), Color3.fromRGB(24, 27, 42), Color3.fromRGB(26, 26, 32)
	accessory(m, "Head", Vector3.new(1.4, 0.6, 1.4), CFrame.new(0, 0.66, 0.04), white, MAT, "Hair")                -- one continuous hair mass the locks grow out of
	accessory(m, "Head", Vector3.new(1.34, 0.26, 1.34), CFrame.new(0, 0.44, 0.1), root, MAT, "Hair")               -- darker cool-grey underside and roots
	accessory(m, "Head", Vector3.new(0.34, 1.0, 1.0), CFrame.new(-0.7, 0.2, 0.18), white, MAT, "Hair")            -- side hair joins mass to the jaw line
	accessory(m, "Head", Vector3.new(0.34, 1.0, 1.0), CFrame.new(0.7, 0.2, 0.18), white, MAT, "Hair")
	local clumps = {
		{ Vector3.new(-0.5, 0.78, 0.0), Vector3.new(0.4, 0.5, 0.42), Vector3.new(0.5, 0, -0.55), 0.3 }, { Vector3.new(0.5, 0.8, 0.05), Vector3.new(0.42, 0.5, 0.42), Vector3.new(0.4, 0, 0.55), 0.3 },
		{ Vector3.new(-0.2, 0.88, 0.2), Vector3.new(0.42, 0.55, 0.42), Vector3.new(0.9, 0, -0.2), 0.35 }, { Vector3.new(0.25, 0.9, 0.22), Vector3.new(0.4, 0.55, 0.42), Vector3.new(0.9, 0, 0.3), 0.32 },
		{ Vector3.new(0.0, 0.85, -0.1), Vector3.new(0.45, 0.5, 0.4), Vector3.new(0.1, 0, 0.1), 0.3 }, { Vector3.new(-0.7, 0.45, 0.15), Vector3.new(0.34, 0.55, 0.45), Vector3.new(0.2, 0, -0.9), 0.3 },
		{ Vector3.new(0.7, 0.45, 0.15), Vector3.new(0.34, 0.55, 0.45), Vector3.new(0.2, 0, 0.9), 0.3 }, { Vector3.new(-0.3, 0.55, 0.62), Vector3.new(0.5, 0.6, 0.35), Vector3.new(1.2, 0, -0.2), 0.3 },
		{ Vector3.new(0.35, 0.55, 0.62), Vector3.new(0.5, 0.6, 0.35), Vector3.new(1.2, 0, 0.25), 0.3 },
	}
	for _, c in ipairs(clumps) do clump(m, c[2], Vector3.new(c[2].X * 0.5, c[4] * 1.6, c[2].Z * 0.5), c[1], c[3], white) end
	-- fringe: four separate locks with skin showing between them
	for i, x in ipairs({ -0.5, -0.16, 0.2, 0.52 }) do
		accessory(m, "Head", Vector3.new(0.24, 0.34, 0.26), CFrame.new(x, 0.52, -0.54) * CFrame.Angles(-0.35, 0, (i - 2.5) * 0.12), white, MAT, "Hair")
		accessory(m, "Head", Vector3.new(0.12, 0.2, 0.14), CFrame.new(x + (i - 2.5) * 0.03, 0.34, -0.6) * CFrame.Angles(-0.2, 0, (i - 2.5) * 0.12), white, MAT, "Hair")
	end
	face(m, { eye = { 0.3, 0.2 }, pupil = { 0.17, 0.19 }, brow = { 0.34, 0.05, 6, 0.3 }, mouth = { 0.22, 3, -0.3 }, irisColor = Color3.fromRGB(96, 186, 255), browColor = Color3.fromRGB(226, 228, 236) })
	for _, d in ipairs(m:GetDescendants()) do if d:IsA("BasePart") and d:GetAttribute("Eye") then d.Material = Enum.Material.Neon end end   -- tiny bright irises
	buildGlasses(m, head, "Glasses")
	-- teen uniform: dark high-collar jacket, clean shoulder line, fitted trousers, dark shoes
	local function teen(partName, size, off, c, mat) local p = accessory(m, partName, size, off, c, mat or MAT); if p then p:SetAttribute("Teen", true) end return p end
	teen("UpperTorso", Vector3.new(1.78, 1.5, 1.06), CFrame.new(0, -0.03, 0.01), uniform)
	teen("UpperTorso", Vector3.new(1.5, 0.5, 1.16), CFrame.new(0, 0.55, 0.0), deep)                                 -- stand-up collar, low enough to leave the jaw visible
	accessory(m, "UpperTorso", Vector3.new(0.9, 0.4, 0.8), CFrame.new(0, 0.9, 0), skin, Enum.Material.SmoothPlastic)  -- neck
	teen("UpperTorso", Vector3.new(2.0, 0.22, 1.1), CFrame.new(0, 0.66, 0.0), deep)                                 -- clean shoulder line
	teen("UpperTorso", Vector3.new(0.07, 1.4, 0.07), CFrame.new(0, -0.05, -0.56), Color3.fromRGB(150, 150, 165), Enum.Material.Metal)
	teen("LowerTorso", Vector3.new(1.8, 0.42, 1.06), CFrame.new(0, 0.1, 0.01), uniform)
	for _, n in ipairs({ "RightUpperArm", "LeftUpperArm", "RightLowerArm", "LeftLowerArm" }) do teen(n, Vector3.new(1.04, 1.0, 1.04), CFrame.new(0, 0.1, 0), uniform) end
	for _, n in ipairs({ "RightUpperLeg", "LeftUpperLeg" }) do teen(n, Vector3.new(0.96, 1.1, 0.96), CFrame.new(0, 0, 0), deep) end
	for _, n in ipairs({ "RightLowerLeg", "LeftLowerLeg" }) do teen(n, Vector3.new(0.9, 1.0, 0.9), CFrame.new(0, 0.05, 0), deep) end
	for _, n in ipairs({ "RightFoot", "LeftFoot" }) do teen(n, Vector3.new(1.04, 0.7, 1.22), CFrame.new(0, 0.1, 0), shoe, Enum.Material.Leather) end
	for _, n in ipairs({ "RightUpperArm", "LeftUpperArm", "RightLowerLeg", "LeftLowerLeg" }) do teen(n, Vector3.new(1.06, 0.05, 1.06), CFrame.new(0, -0.15, 0), Color3.fromRGB(58, 62, 84)) end
	-- adult outfit + blindfold (adult chapters only; hidden until then)
	local function adult(partName, size, off, c, tag)
		local p = accessory(m, partName, size, off, c, MAT, tag or "Adult")
		if p then p:SetAttribute("Adult", true); p.Transparency = 1 end
		return p
	end
	adult("UpperTorso", Vector3.new(1.86, 1.5, 1.1), CFrame.new(0, -0.03, 0.01), Color3.fromRGB(18, 22, 44))
	adult("UpperTorso", Vector3.new(1.9, 0.9, 1.3), CFrame.new(0, 0.95, 0.0), Color3.fromRGB(14, 16, 34))
	adult("LowerTorso", Vector3.new(1.86, 0.5, 1.1), CFrame.new(0, 0.1, 0.01), Color3.fromRGB(18, 22, 44))
	for _, n in ipairs({ "RightUpperArm", "LeftUpperArm", "RightLowerArm", "LeftLowerArm" }) do adult(n, Vector3.new(1.06, 1.0, 1.06), CFrame.new(0, 0.1, 0), Color3.fromRGB(18, 22, 44)) end
	local bl = adult("Head", Vector3.new(0.68, 0.42, 1.34), CFrame.new(-0.33, 0.1, 0.0), Color3.fromRGB(12, 12, 16), "BlindfoldL")
	local br = adult("Head", Vector3.new(0.68, 0.42, 1.34), CFrame.new(0.33, 0.1, 0.0), Color3.fromRGB(12, 12, 16), "BlindfoldR")
	for _, p in ipairs({ bl, br }) do p:SetAttribute("Blindfold", true) end
	addTrail(m, "RightHand", Color3.fromRGB(150, 190, 255)); addTrail(m, "LeftHand", Color3.fromRGB(150, 190, 255))
	return m
end

-- TOJI: broad shoulders, tapered waist, strong bare forearms, straight black hair across the forehead, narrow green eyes, a scar at the right
-- corner of the mouth, fitted black short-sleeve shirt, loose pale trousers gathered at the ankles, dark footwear, and the inventory curse.
local function buildToji()
	local skin = Color3.fromRGB(222, 178, 150)
	local m = newRig("Purple", { skin = skin, torso = Color3.fromRGB(20, 20, 24), arm = skin, leg = Color3.fromRGB(206, 202, 190) })
	m:SetAttribute("Character", "Ren"); m:SetAttribute("Persona", "Toji")
	local hairC, shirt, pale, palerDark, shoe = Color3.fromRGB(24, 22, 26), Color3.fromRGB(34, 34, 42), Color3.fromRGB(206, 202, 190), Color3.fromRGB(176, 172, 160), Color3.fromRGB(30, 30, 34)
	accessory(m, "Head", Vector3.new(1.3, 0.42, 1.3), CFrame.new(0, 0.64, 0.04), hairC, MAT, "Hair")
	accessory(m, "Head", Vector3.new(0.3, 0.9, 1.1), CFrame.new(-0.62, 0.3, 0.1), hairC, MAT, "Hair")
	accessory(m, "Head", Vector3.new(0.3, 0.9, 1.1), CFrame.new(0.62, 0.3, 0.1), hairC, MAT, "Hair")
	accessory(m, "Head", Vector3.new(1.3, 0.9, 0.34), CFrame.new(0, 0.3, 0.5), hairC, MAT, "Hair")
	local lens = { 0.62, 0.44, 0.58, 0.36, 0.52, 0.4, 0.5 }                       -- irregular lower edge: strands of different length and lean
	for i, x in ipairs({ -0.56, -0.38, -0.18, 0.02, 0.2, 0.4, 0.58 }) do
		accessory(m, "Head", Vector3.new(0.2, lens[i], 0.12), CFrame.new(x, 0.52 - lens[i] / 2 + 0.2, -0.6) * CFrame.Angles(-0.1, 0, (i - 4) * 0.09), hairC, MAT, "Hair")
		accessory(m, "Head", Vector3.new(0.1, 0.16, 0.1), CFrame.new(x + (i % 2 == 0 and 0.06 or -0.05), 0.52 - lens[i] + 0.16, -0.61), hairC, MAT, "Hair")
	end
	accessory(m, "Head", Vector3.new(1.3, 0.5, 0.2), CFrame.new(0, 0.55, -0.52), hairC, MAT, "Hair")
	face(m, { eye = { 0.3, 0.1 }, pupil = { 0.17, 0.1 }, brow = { 0.38, 0.07, 8, 0.25 }, mouth = { 0.26, 0, -0.3 }, irisColor = Color3.fromRGB(70, 138, 92), browColor = Color3.fromRGB(26, 22, 24) })
	local scar = accessory(m, "Head", Vector3.new(0.05, 0.17, 0.04), CFrame.new(0.19, -0.3, -0.625) * CFrame.Angles(0, 0, 0.5), Color3.fromRGB(190, 110, 110), Enum.Material.SmoothPlastic, "Scar")   -- right corner of the mouth
	-- broad shoulders, tapered waist, fitted short-sleeve shirt, strong forearms
	accessory(m, "UpperTorso", Vector3.new(2.9, 1.5, 1.14), CFrame.new(0, -0.03, 0.01), shirt, MAT)
	accessory(m, "UpperTorso", Vector3.new(3.04, 0.42, 1.18), CFrame.new(0, 0.6, 0.01), Color3.fromRGB(44, 44, 52), MAT)       -- trapezius / shoulder line
	accessory(m, "UpperTorso", Vector3.new(1.0, 0.36, 0.9), CFrame.new(0, 0.92, 0), skin, Enum.Material.SmoothPlastic)         -- neck
	accessory(m, "LowerTorso", Vector3.new(1.7, 0.5, 1.0), CFrame.new(0, 0.1, 0.01), shirt, MAT)                               -- tapered waist
	for _, n in ipairs({ "RightUpperArm", "LeftUpperArm" }) do accessory(m, n, Vector3.new(1.4, 0.95, 1.4), CFrame.new(0, 0.2, 0), shirt, MAT) end   -- short sleeves
	for _, n in ipairs({ "RightUpperArm", "LeftUpperArm" }) do accessory(m, n, Vector3.new(1.18, 0.55, 1.18), CFrame.new(0, -0.35, 0), skin, Enum.Material.SmoothPlastic) end
	for _, n in ipairs({ "RightLowerArm", "LeftLowerArm" }) do accessory(m, n, Vector3.new(1.12, 0.85, 1.12), CFrame.new(0, 0.05, 0), skin, Enum.Material.SmoothPlastic) end
	-- loose pale trousers, volume in the silhouette, gathered at the ankle
	for _, n in ipairs({ "RightUpperLeg", "LeftUpperLeg" }) do accessory(m, n, Vector3.new(1.6, 1.2, 1.6), CFrame.new(0, 0, 0), pale, MAT) end
	for _, n in ipairs({ "RightLowerLeg", "LeftLowerLeg" }) do
		accessory(m, n, Vector3.new(1.46, 0.85, 1.46), CFrame.new(0, 0.12, 0), pale, MAT)
		accessory(m, n, Vector3.new(0.98, 0.3, 0.98), CFrame.new(0, -0.45, 0), palerDark, MAT)                                      -- ankle gather
	end
	for _, n in ipairs({ "RightFoot", "LeftFoot" }) do accessory(m, n, Vector3.new(1.08, 0.72, 1.28), CFrame.new(0, 0.1, 0), shoe, Enum.Material.Leather) end
	-- the inventory curse: muted purple segmented body around the torso, with a head and tail that trail with a slight delay
	local curse, curseDark = Color3.fromRGB(112, 96, 134), Color3.fromRGB(84, 72, 104)
	for i = 1, 3 do
		local band = accessory(m, "UpperTorso", Vector3.new(2.78, 0.32, 1.5), CFrame.new(0, -0.55 + i * 0.3, 0.02) * CFrame.Angles(0, 0, (i - 2) * 0.12), (i % 2 == 0) and curse or curseDark, MAT, "Curse")
	end
	local headC = Color3.fromRGB(148, 126, 170)               -- lighter than the arm and the body bands so the head reads on its own
	local lastH = cloth(m, "UpperTorso", "CurseHead", CFrame.new(-0.85, 0.7, 0.66), 3, Vector3.new(0.6, 0.55, 0.42), curse)
	if lastH then
		local upper = part({ Size = Vector3.new(1.2, 0.6, 1.0), Color = headC, Material = MAT, Anchored = false, Massless = true }, m)
		upper:SetAttribute("Curse", true); upper.Name = "CurseSkull"
		weld(upper, lastH, CFrame.new(0, -0.55, 0))
		local jaw = part({ Size = Vector3.new(1.1, 0.34, 0.9), Color = headC, Material = MAT, Anchored = false, Massless = true }, m)
		jaw:SetAttribute("Curse", true); jaw.Name = "CurseJaw"
		local jm = Instance.new("Motor6D")
		jm.Name = "CurseJawJoint"; jm.Part0, jm.Part1 = upper, jaw
		jm.C0 = CFrame.new(0, -0.3, -0.38); jm.C1 = CFrame.new(0, 0.1, -0.38)
		jm:SetAttribute("JawJoint", true); jm.Parent = jaw
		local mouthIn = part({ Size = Vector3.new(0.96, 0.08, 0.8), Color = Color3.fromRGB(86, 26, 52), Material = Enum.Material.SmoothPlastic, Anchored = false, Massless = true }, m)
		weld(mouthIn, upper, CFrame.new(0, -0.31, 0.02))
		for _, s in ipairs({ -1, 1 }) do
			local e = part({ Size = Vector3.new(0.28, 0.2, 0.06), Color = Color3.fromRGB(235, 232, 220), Material = Enum.Material.SmoothPlastic, Anchored = false, Massless = true }, m)
			weld(e, upper, CFrame.new(s * 0.32, 0.1, -0.52))
			local pu = part({ Size = Vector3.new(0.12, 0.14, 0.07), Color = Color3.fromRGB(150, 30, 40), Material = Enum.Material.SmoothPlastic, Anchored = false, Massless = true }, m)
			weld(pu, upper, CFrame.new(s * 0.32, 0.1, -0.55))
		end
		for k = -3, 3 do
			local tooth = part({ Size = Vector3.new(0.1, 0.16, 0.06), Color = Color3.fromRGB(228, 224, 210), Material = Enum.Material.SmoothPlastic, Anchored = false, Massless = true }, m)
			weld(tooth, upper, CFrame.new(k * 0.15, -0.36, -0.46))
		end
	end
	local tail = cloth(m, "LowerTorso", "CurseTail", CFrame.new(0.4, -0.05, 0.56), 4, Vector3.new(0.5, 0.6, 0.3), curseDark)
	for i, f in ipairs({ 1.0, 0.8, 0.62, 0.45 }) do             -- tapered tail
		local seg = m:FindFirstChild("CurseTail" .. i)
		if seg then seg.Size = Vector3.new(0.5 * f, 0.6, 0.3 * f) end
	end
	for _, c in ipairs(m:GetChildren()) do
		if c:IsA("BasePart") and (c.Name:sub(1, 9) == "CurseHead" or c.Name:sub(1, 9) == "CurseTail") then c:SetAttribute("Curse", true) end
	end
	-- the Inverted Spear of Heaven (hidden until the curse produces it): a dark grip with a ring and a short jitte-like blade
	local grip = accessory(m, "RightHand", Vector3.new(0.14, 0.14, 1.0), CFrame.new(0, -0.1, -0.35), Color3.fromRGB(28, 26, 30), Enum.Material.SmoothPlastic, "Spear")
	local ring = accessory(m, "RightHand", Vector3.new(0.34, 0.34, 0.06), CFrame.new(0, -0.1, 0.18), Color3.fromRGB(40, 38, 44), Enum.Material.Metal, "Spear")
	local blade = accessory(m, "RightHand", Vector3.new(0.1, 0.26, 0.8), CFrame.new(0, -0.1, -1.2), Color3.fromRGB(182, 186, 196), Enum.Material.Metal, "Spear")
	local guard = accessory(m, "RightHand", Vector3.new(0.5, 0.1, 0.14), CFrame.new(0, -0.1, -0.84), Color3.fromRGB(60, 58, 66), Enum.Material.Metal, "Spear")
	for _, p in ipairs({ grip, ring, blade, guard }) do if p then p.Transparency = 1 end end
	return m
end

local tiles = Instance.new("Folder")
tiles.Name = "Tiles"
tiles.Parent = stage
math.randomseed(21)
for ix = -6, 1 do
	for iz = -1, 1 do
		local shade = math.random(138, 160)
		local t = part({ Name = "Tile_" .. ix .. "_" .. iz, Size = Vector3.new(3.84, 0.4, 3.84), CFrame = CFrame.new(ix * 4 - 2, 0.2, iz * 4),
			Color = Color3.fromRGB(shade, shade - 2, shade + 6), Material = Enum.Material.Slate }, tiles)
		t:SetAttribute("Col", ix); t:SetAttribute("Row", iz)
	end
end

local gojo = buildGojo()
local toji = buildToji()
gojo:PivotTo(CFrame.new(6, 3, 0) * CFrame.Angles(0, math.rad(90), 0))
toji:PivotTo(CFrame.new(-20, 3, 0) * CFrame.Angles(0, math.rad(-90), 0))
for _, m in ipairs({ gojo, toji }) do m.HumanoidRootPart.Anchored = true end

stage:SetAttribute("Mode", "Cinematic")
stage:SetAttribute("Ready", true)
print("[BG] courtyard and fighters built (Blue = teen Gojo, Purple = Toji).")
