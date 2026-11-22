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

local function hair(model, color, count, height, lean, brows)
	for k = 1, count do
		local a = (k / count) * math.pi * 2
		accessory(model, "Head", Vector3.new(0.5, height, 0.5),
			CFrame.new(math.cos(a) * 0.4, 0.68, math.sin(a) * 0.4) * CFrame.Angles(math.sin(a) * lean, 0, -math.cos(a) * lean), color)
	end
	accessory(model, "Head", Vector3.new(0.7, height * 1.25, 0.7), CFrame.new(0, 0.85, 0.05) * CFrame.Angles(-0.25, 0, 0), color)
	accessory(model, "Head", Vector3.new(1.25, 0.4, 1.25), CFrame.new(0, 0.5, 0.02), color)
	accessory(model, "Head", Vector3.new(1.0, 0.3, 0.3), CFrame.new(0, 0.34, -0.55), color)  -- fringe
	if brows then
		local dark = Color3.fromRGB(10, 10, 14)
		accessory(model, "Head", Vector3.new(0.3, 0.09, 0.05), CFrame.new(-0.27, 0.16, -0.62) * CFrame.Angles(0, 0, 0.3), dark)
		accessory(model, "Head", Vector3.new(0.3, 0.09, 0.05), CFrame.new(0.27, 0.16, -0.62) * CFrame.Angles(0, 0, -0.3), dark)
	end
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

-- BLUE = Satoru Gojo. Reference: tall lean build, snow-white spiky hair, black blindfold,
-- dark navy high-collar zip jacket, slim black pants and boots, glowing blue Six Eyes.
local function buildBlue()
	local m = newRig("Blue", { skin = Color3.fromRGB(246, 222, 200), torso = Color3.fromRGB(22, 28, 52),
		arm = Color3.fromRGB(22, 28, 52), leg = Color3.fromRGB(14, 14, 20) })
	m:SetAttribute("Character", "Gojo")
	local navy, deep, black = Color3.fromRGB(24, 30, 58), Color3.fromRGB(16, 20, 40), Color3.fromRGB(10, 10, 14)
	local white = Color3.fromRGB(248, 250, 255)
	hair(m, white, 11, 1.3, 0.75, false)
	-- black blindfold pushing the fringe up, with the Six Eyes glow along the lower edge
	accessory(m, "Head", Vector3.new(1.3, 0.36, 1.3), CFrame.new(0, 0.1, 0), black, Enum.Material.Fabric)
	accessory(m, "Head", Vector3.new(0.34, 0.05, 0.05), CFrame.new(-0.27, -0.1, -0.66), BLUE, Enum.Material.Neon)
	accessory(m, "Head", Vector3.new(0.34, 0.05, 0.05), CFrame.new(0.27, -0.1, -0.66), BLUE, Enum.Material.Neon)
	-- high wide collar and zip jacket
	accessory(m, "UpperTorso", Vector3.new(2.15, 1.45, 1.12), CFrame.new(0, -0.05, 0.02), navy, Enum.Material.Fabric)
	accessory(m, "UpperTorso", Vector3.new(2.05, 0.62, 1.3), CFrame.new(0, 0.82, 0.02), deep, Enum.Material.Fabric)
	accessory(m, "UpperTorso", Vector3.new(0.09, 1.9, 0.1), CFrame.new(0, 0.1, -0.62), Color3.fromRGB(150, 155, 175), Enum.Material.Metal)   -- zip
	accessory(m, "LowerTorso", Vector3.new(2.15, 0.45, 1.12), CFrame.new(0, 0.1, 0), navy, Enum.Material.Fabric)  -- jacket hem
	accessory(m, "LowerTorso", Vector3.new(2.1, 0.2, 1.1), CFrame.new(0, -0.18, 0), black)                         -- belt
	for _, n in ipairs({ "RightUpperLeg", "LeftUpperLeg" }) do
		accessory(m, n, Vector3.new(1.02, 1.15, 1.02), CFrame.new(0, 0, 0), black, Enum.Material.Fabric)
	end
	for _, n in ipairs({ "RightLowerLeg", "LeftLowerLeg" }) do
		accessory(m, n, Vector3.new(1.02, 1.0, 1.02), CFrame.new(0, 0.05, 0), black, Enum.Material.Fabric)
	end
	for _, n in ipairs({ "RightFoot", "LeftFoot" }) do
		accessory(m, n, Vector3.new(1.08, 0.7, 1.2), CFrame.new(0, 0.1, 0), black, Enum.Material.Leather)
	end
	for _, n in ipairs({ "RightHand", "LeftHand" }) do
		accessory(m, n, Vector3.new(1.0, 0.45, 1.0), CFrame.new(0, 0.15, 0), Color3.fromRGB(246, 222, 200))
	end
	-- cloth tail trailing from the collar: gives the scarf-lag cue without a costume gag
	scarf(m, Color3.fromRGB(14, 16, 30), BLUE)
	addTrail(m, "RightHand", BLUE); addTrail(m, "LeftHand", BLUE)
	return m
end

-- PURPLE = Toji Fushiguro. Reference: heavily muscled, short messy black hair, scar at the
-- corner of the mouth, tight half-sleeve dark shirt, black pants, bare forearms, cursed tool on the hip.
local function buildPurple()
	local skin = Color3.fromRGB(228, 186, 160)
	local m = newRig("Purple", { skin = skin, torso = Color3.fromRGB(26, 30, 34),
		arm = skin, leg = Color3.fromRGB(16, 16, 20) })
	m:SetAttribute("Character", "Toji")
	local shirt, black = Color3.fromRGB(26, 30, 36), Color3.fromRGB(12, 12, 16)
	hair(m, Color3.fromRGB(14, 12, 14), 8, 0.5, 0.35, true)
	-- scar at the right corner of the mouth
	accessory(m, "Head", Vector3.new(0.07, 0.24, 0.04), CFrame.new(0.2, -0.3, -0.62) * CFrame.Angles(0, 0, 0.35), Color3.fromRGB(170, 95, 95))
	-- tight half-sleeve shirt stretched over a broad chest and shoulders
	accessory(m, "UpperTorso", Vector3.new(2.3, 1.5, 1.18), CFrame.new(0, -0.05, 0.02), shirt, Enum.Material.Fabric)
	accessory(m, "UpperTorso", Vector3.new(2.34, 0.5, 1.22), CFrame.new(0, 0.32, -0.02), Color3.fromRGB(32, 37, 44), Enum.Material.Fabric)  -- chest
	accessory(m, "UpperTorso", Vector3.new(1.0, 0.3, 0.9), CFrame.new(0, 0.85, 0), skin)                                                    -- neck
	accessory(m, "LowerTorso", Vector3.new(2.1, 0.5, 1.1), CFrame.new(0, 0.05, 0), shirt, Enum.Material.Fabric)
	accessory(m, "LowerTorso", Vector3.new(2.1, 0.18, 1.12), CFrame.new(0, -0.15, 0), black, Enum.Material.Leather)                        -- belt
	for _, n in ipairs({ "RightUpperArm", "LeftUpperArm" }) do
		accessory(m, n, Vector3.new(1.28, 0.9, 1.28), CFrame.new(0, 0.2, 0), shirt, Enum.Material.Fabric)                                   -- half sleeve
		accessory(m, n, Vector3.new(1.12, 0.5, 1.12), CFrame.new(0, -0.3, 0), skin)                                                         -- bicep bulk
	end
	for _, n in ipairs({ "RightLowerArm", "LeftLowerArm" }) do
		accessory(m, n, Vector3.new(1.06, 0.34, 1.06), CFrame.new(0, 0.1, 0), skin)                                                         -- forearm bulk
		accessory(m, n, Vector3.new(1.08, 0.18, 1.08), CFrame.new(0, -0.35, 0), black, Enum.Material.Fabric)                                -- wrist strap
	end
	for _, n in ipairs({ "RightUpperLeg", "LeftUpperLeg" }) do
		accessory(m, n, Vector3.new(1.15, 1.15, 1.15), CFrame.new(0, 0, 0), black, Enum.Material.Fabric)
	end
	for _, n in ipairs({ "RightLowerLeg", "LeftLowerLeg" }) do
		accessory(m, n, Vector3.new(1.08, 1.0, 1.08), CFrame.new(0, 0.05, 0), black, Enum.Material.Fabric)
	end
	for _, n in ipairs({ "RightFoot", "LeftFoot" }) do
		accessory(m, n, Vector3.new(1.1, 0.7, 1.25), CFrame.new(0, 0.1, 0), black, Enum.Material.Leather)
	end
	-- Inverted Spear of Heaven worn on the back of the belt: black grip with a ring, short jitte-like blade
	accessory(m, "LowerTorso", Vector3.new(0.18, 0.7, 0.18), CFrame.new(0.55, 0.15, 0.6) * CFrame.Angles(0, 0, 0.5), black, Enum.Material.Leather)
	accessory(m, "LowerTorso", Vector3.new(0.22, 0.22, 0.05), CFrame.new(0.78, -0.2, 0.62), Color3.fromRGB(190, 190, 200), Enum.Material.Metal)
	accessory(m, "LowerTorso", Vector3.new(0.1, 0.9, 0.12), CFrame.new(0.2, 0.65, 0.6) * CFrame.Angles(0, 0, 0.5), Color3.fromRGB(190, 195, 205), Enum.Material.Metal)
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
