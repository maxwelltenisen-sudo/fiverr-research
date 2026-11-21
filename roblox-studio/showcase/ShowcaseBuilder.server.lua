-- ShowcaseBuilder (Script, ServerScriptService): builds the stage and the two R15 fighters.
-- It does NOT animate: ShowcaseDirector (LocalScript) plays the keyframes from ShowcaseData.
-- No combat gameplay exists in this project, so there is no hit detection to keep server-side;
-- if you add gameplay later, keep hit detection on the server and use this only for visuals.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local Data = require(ReplicatedStorage:WaitForChild("ShowcaseData"))

Players.CharacterAutoLoads = false

-- clean up a previous build so this is safe to re-run
local old = Workspace:FindFirstChild("Showcase")
if old then old:Destroy() end
for _, c in ipairs(Lighting:GetChildren()) do
	if c:GetAttribute("ShowcaseFX") then c:Destroy() end
end

local stage = Instance.new("Folder")
stage.Name = "Showcase"
stage.Parent = Workspace

local BLUE = Data.colors.blue
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

local function accessory(model, partName, size, offset, color, material, props)
	local to = model:FindFirstChild(partName)
	if not to then return nil end
	local p = part({ Size = size, Color = color, Material = material or Enum.Material.SmoothPlastic }, model)
	if props then for k, v in pairs(props) do p[k] = v end end
	return weld(p, to, offset)
end

---------------------------------------------------------------- stage
Lighting.ClockTime = 0
Lighting.Brightness = 2
Lighting.ExposureCompensation = 0.5
Lighting.Ambient = Color3.fromRGB(95, 85, 150)
Lighting.OutdoorAmbient = Color3.fromRGB(100, 90, 160)

local function fx(inst)
	inst:SetAttribute("ShowcaseFX", true)
	inst.Parent = Lighting
	return inst
end
local atmo = Instance.new("Atmosphere")
atmo.Density = 0.3; atmo.Offset = 0.2; atmo.Color = Color3.fromRGB(110, 85, 170); atmo.Decay = Color3.fromRGB(50, 35, 90)
fx(atmo)
local bloom = Instance.new("BloomEffect")
bloom.Intensity = 0.7; bloom.Size = 24; bloom.Threshold = 0.9
fx(bloom)
local cc = Instance.new("ColorCorrectionEffect")
cc.Contrast = 0.15; cc.Saturation = 0.2; cc.TintColor = Color3.fromRGB(225, 215, 255)
fx(cc)

part({ Name = "Ground", Size = Vector3.new(400, 1, 400), Position = Vector3.new(0, -0.5, 0),
	Color = Color3.fromRGB(38, 35, 52), Material = Enum.Material.Slate, CanCollide = true })
part({ Size = Vector3.new(0.2, 22, 22), CFrame = CFrame.new(-1.2, 0.08, 0) * CFrame.Angles(0, 0, math.rad(90)),
	Shape = Enum.PartType.Cylinder, Color = VIOLET, Material = Enum.Material.Neon, Transparency = 0.82 })
part({ Size = Vector3.new(0.2, 17, 17), CFrame = CFrame.new(-1.2, 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)),
	Shape = Enum.PartType.Cylinder, Color = BLUE, Material = Enum.Material.Neon, Transparency = 0.88 })
part({ Name = "Moon", Shape = Enum.PartType.Ball, Size = Vector3.new(80, 80, 80), Position = Vector3.new(40, 150, -260),
	Color = Color3.fromRGB(200, 150, 255), Material = Enum.Material.Neon, Transparency = 0.1 })
math.randomseed(11)
local function pillar(x, z, h, w)
	part({ Size = Vector3.new(w, h, w),
		CFrame = CFrame.new(x, h / 2, z) * CFrame.Angles(math.rad(math.random(-3, 3)), math.rad(math.random(0, 90)), math.rad(math.random(-3, 3))),
		Color = Color3.fromRGB(52, 46, 72), Material = Enum.Material.Slate })
end
for i = 1, 10 do
	local a = (i / 10) * math.pi * 2
	local r = math.random(32, 46)
	pillar(math.cos(a) * r - 1.2, math.sin(a) * r - 24, math.random(12, 34), math.random(4, 7))
end
pillar(-9, -26, 24, 5); pillar(7, -26, 24, 5)
part({ Size = Vector3.new(26, 4, 5), Position = Vector3.new(-1, 25, -26), Color = Color3.fromRGB(52, 46, 72), Material = Enum.Material.Slate })
for _, x in ipairs({ -14, 12 }) do
	part({ Size = Vector3.new(3, 9, 0.3), Position = Vector3.new(x, 14, -22), Color = Color3.fromRGB(70, 35, 130), Material = Enum.Material.Fabric })
	part({ Size = Vector3.new(0.8, 3, 0.35), Position = Vector3.new(x, 14.5, -21.8), Color = VIOLET, Material = Enum.Material.Neon })
end
for _, spec in ipairs({ { Vector3.new(-8, 9, 8), BLUE }, { Vector3.new(7, 9, 8), VIOLET }, { Vector3.new(-1, 14, 12), Color3.fromRGB(200, 200, 255) } }) do
	local lp = part({ Size = Vector3.new(1, 1, 1), Position = spec[1], Transparency = 1 })
	local l = Instance.new("PointLight")
	l.Color = spec[2]; l.Range = 40; l.Brightness = 1.6
	l.Parent = lp
end
local focus = part({ Name = "FocusPoint", Size = Vector3.new(1, 1, 1), Position = Vector3.new(-1, 4, 0), Transparency = 1 })
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

local function scarf(model, color, trim)
	local ut = model.UpperTorso
	local prev = ut
	for i = 1, 3 do
		local seg = part({ Name = "Scarf" .. i, Size = Vector3.new(0.6, 0.75, 0.2), Color = color,
			Material = Enum.Material.Fabric, Anchored = false, Massless = true }, model)
		local m = Instance.new("Motor6D")
		m.Name = "ScarfJoint" .. i
		m.Part0, m.Part1 = prev, seg
		if i == 1 then
			m.C0 = CFrame.new(0, ut.Size.Y * 0.5 - 0.15, ut.Size.Z * 0.5 + 0.1)
		else
			m.C0 = CFrame.new(0, -0.37, 0)
		end
		m.C1 = CFrame.new(0, 0.37, 0)
		m.Parent = seg
		prev = seg
		if i == 3 then
			local tip = part({ Size = Vector3.new(0.62, 0.1, 0.22), Color = trim, Material = Enum.Material.Neon, Anchored = false, Massless = true }, model)
			weld(tip, seg, CFrame.new(0, -0.38, 0))
		end
	end
	-- neck wrap
	accessory(model, "UpperTorso", Vector3.new(1.9, 0.5, 1.3), CFrame.new(0, ut.Size.Y * 0.5 - 0.1, 0), color, Enum.Material.Fabric)
end

local function hair(model, color, count, height, lean)
	local head = model:FindFirstChild("Head")
	for k = 1, count do
		local a = (k / count) * math.pi * 2
		accessory(model, "Head", Vector3.new(0.5, height, 0.5),
			CFrame.new(math.cos(a) * 0.4, 0.68, math.sin(a) * 0.4) * CFrame.Angles(math.sin(a) * lean, 0, -math.cos(a) * lean), color)
	end
	accessory(model, "Head", Vector3.new(0.7, height * 1.25, 0.7), CFrame.new(0, 0.85, 0.05) * CFrame.Angles(-0.25, 0, 0), color)
	accessory(model, "Head", Vector3.new(1.25, 0.4, 1.25), CFrame.new(0, 0.5, 0.02), color)
	accessory(model, "Head", Vector3.new(1.0, 0.3, 0.3), CFrame.new(0, 0.34, -0.55), color)  -- fringe
	local dark = Color3.fromRGB(10, 10, 14)
	accessory(model, "Head", Vector3.new(0.3, 0.09, 0.05), CFrame.new(-0.27, 0.06, -0.62) * CFrame.Angles(0, 0, 0.35), dark)
	accessory(model, "Head", Vector3.new(0.3, 0.09, 0.05), CFrame.new(0.27, 0.06, -0.62) * CFrame.Angles(0, 0, -0.35), dark)
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
	return m
end

local function buildBlue()
	local m = newRig("Blue", { skin = Color3.fromRGB(240, 205, 175), torso = Color3.fromRGB(28, 30, 44),
		arm = Color3.fromRGB(34, 36, 52), leg = Color3.fromRGB(16, 17, 24) })
	local dark, navy, black = Color3.fromRGB(22, 24, 36), Color3.fromRGB(30, 36, 62), Color3.fromRGB(10, 10, 14)
	hair(m, black, 9, 1.2, 0.7)
	scarf(m, Color3.fromRGB(14, 14, 22), BLUE)
	-- layered outfit: jacket shell, lapels, hem, belt, shoulder pads, knee wraps
	accessory(m, "UpperTorso", Vector3.new(2.15, 1.45, 1.12), CFrame.new(0, -0.05, 0.02), navy, Enum.Material.Fabric)
	accessory(m, "UpperTorso", Vector3.new(0.45, 1.4, 0.16), CFrame.new(-0.35, 0, -0.6) * CFrame.Angles(0, 0, 0.12), dark, Enum.Material.Fabric)
	accessory(m, "UpperTorso", Vector3.new(0.45, 1.4, 0.16), CFrame.new(0.35, 0, -0.6) * CFrame.Angles(0, 0, -0.12), dark, Enum.Material.Fabric)
	accessory(m, "UpperTorso", Vector3.new(0.12, 1.35, 0.1), CFrame.new(0, 0, -0.64), BLUE, Enum.Material.Neon)
	accessory(m, "LowerTorso", Vector3.new(2.15, 0.34, 1.12), CFrame.new(0, 0.05, 0), black)
	accessory(m, "LowerTorso", Vector3.new(0.4, 0.22, 0.12), CFrame.new(0, 0.05, -0.58), BLUE, Enum.Material.Neon)
	accessory(m, "LowerTorso", Vector3.new(1.9, 1.0, 0.14), CFrame.new(0, -0.45, 0.55) * CFrame.Angles(0.08, 0, 0), navy, Enum.Material.Fabric)
	for _, n in ipairs({ "RightUpperArm", "LeftUpperArm" }) do
		accessory(m, n, Vector3.new(1.3, 0.4, 1.3), CFrame.new(0, 0.5, 0), black)
		accessory(m, n, Vector3.new(1.1, 0.07, 1.1), CFrame.new(0, 0.05, 0), BLUE, Enum.Material.Neon)
	end
	for _, n in ipairs({ "RightLowerArm", "LeftLowerArm" }) do
		accessory(m, n, Vector3.new(1.1, 0.07, 1.1), CFrame.new(0, -0.1, 0), BLUE, Enum.Material.Neon)
	end
	for _, n in ipairs({ "RightLowerLeg", "LeftLowerLeg" }) do
		accessory(m, n, Vector3.new(1.12, 0.35, 1.12), CFrame.new(0, 0.45, 0), black)
	end
	accessory(m, "RightHand", Vector3.new(1.05, 0.5, 1.05), CFrame.new(0, 0, 0), black)
	accessory(m, "LeftHand", Vector3.new(1.05, 0.5, 1.05), CFrame.new(0, 0, 0), black)
	addTrail(m, "RightHand", BLUE); addTrail(m, "LeftHand", BLUE)
	return m
end

local function buildPurple()
	local m = newRig("Purple", { skin = Color3.fromRGB(245, 215, 190), torso = Color3.fromRGB(30, 26, 46),
		arm = Color3.fromRGB(32, 28, 50), leg = Color3.fromRGB(18, 16, 28) })
	local dark, plum, black = Color3.fromRGB(24, 20, 38), Color3.fromRGB(44, 34, 70), Color3.fromRGB(10, 9, 16)
	local silver = Color3.fromRGB(205, 208, 226)
	hair(m, silver, 9, 1.05, 0.6)
	-- dark high-collar outfit
	accessory(m, "UpperTorso", Vector3.new(2.12, 1.5, 1.1), CFrame.new(0, -0.05, 0.02), plum, Enum.Material.Fabric)
	accessory(m, "UpperTorso", Vector3.new(2.0, 1.1, 0.22), CFrame.new(0, 1.0, 0.62) * CFrame.Angles(-0.12, 0, 0), dark, Enum.Material.Fabric)
	accessory(m, "UpperTorso", Vector3.new(0.22, 1.0, 1.15), CFrame.new(-0.95, 0.95, 0.02), dark, Enum.Material.Fabric)
	accessory(m, "UpperTorso", Vector3.new(0.22, 1.0, 1.15), CFrame.new(0.95, 0.95, 0.02), dark, Enum.Material.Fabric)
	accessory(m, "UpperTorso", Vector3.new(1.9, 0.5, 0.2), CFrame.new(0, 0.85, -0.55), dark, Enum.Material.Fabric)
	accessory(m, "UpperTorso", Vector3.new(0.1, 1.2, 0.1), CFrame.new(0, -0.05, -0.62), VIOLET, Enum.Material.Neon)
	accessory(m, "LowerTorso", Vector3.new(2.15, 0.34, 1.12), CFrame.new(0, 0.05, 0), black)
	accessory(m, "LowerTorso", Vector3.new(0.4, 0.2, 0.12), CFrame.new(0, 0.05, -0.58), VIOLET, Enum.Material.Neon)
	for _, n in ipairs({ "RightUpperArm", "LeftUpperArm" }) do
		accessory(m, n, Vector3.new(1.3, 0.4, 1.3), CFrame.new(0, 0.5, 0), black)
		accessory(m, n, Vector3.new(1.1, 0.07, 1.1), CFrame.new(0, 0.05, 0), VIOLET, Enum.Material.Neon)
	end
	-- reinforced forearms (guard radius comes from the shared data so contact math matches the geometry)
	local gw = Data.contacts[1].guardRadius * 2
	for _, n in ipairs({ "RightLowerArm", "LeftLowerArm" }) do
		local la = m:FindFirstChild(n)
		local g = accessory(m, n, Vector3.new(gw, la.Size.Y * 0.85, gw), CFrame.new(0, 0, 0), black, Enum.Material.Metal)
		g.Name = (n == "LeftLowerArm") and "GuardL" or "GuardR"
		accessory(m, n, Vector3.new(gw + 0.04, 0.09, gw + 0.04), CFrame.new(0, la.Size.Y * 0.3, 0), VIOLET, Enum.Material.Neon)
		accessory(m, n, Vector3.new(gw + 0.04, 0.09, gw + 0.04), CFrame.new(0, -la.Size.Y * 0.3, 0), VIOLET, Enum.Material.Neon)
	end
	for _, n in ipairs({ "RightLowerLeg", "LeftLowerLeg" }) do
		accessory(m, n, Vector3.new(1.12, 0.35, 1.12), CFrame.new(0, 0.45, 0), black)
	end
	addTrail(m, "RightHand", VIOLET); addTrail(m, "LeftHand", VIOLET)
	return m
end

local blue = buildBlue()
local purple = buildPurple()
blue:PivotTo(CFrame.new(-4.6, 3, 0) * CFrame.Angles(0, math.rad(-90), 0))
purple:PivotTo(CFrame.new(1.3, 3, 0) * CFrame.Angles(0, math.rad(90), 0))
for _, m in ipairs({ blue, purple }) do
	m.HumanoidRootPart.Anchored = true     -- the Director positions it each frame
end

stage:SetAttribute("Ready", true)
print("[SHOWCASE] stage and fighters built. Press Play and watch the HUD (bottom left).")
