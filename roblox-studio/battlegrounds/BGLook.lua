-- BGLook (ModuleScript, ReplicatedStorage): lighting presets + an audit that prints what could blow out the picture.
--   Look.apply("night")    restrained moonlit grade (default for the cinematic)
--   Look.apply("neutral")  flat, even light with ALL post effects off: use it to judge skin, hair, clothes and stone
--   Look.audit()           prints exposure, bloom, colour correction, lights, Neon parts, Highlights, reflective parts
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local Look = {}

local function effect(class)
	for _, c in ipairs(Lighting:GetChildren()) do if c:IsA(class) then return c end end
end

function Look.apply(mode)
	local bloom, cc, dof, atmo = effect("BloomEffect"), effect("ColorCorrectionEffect"), effect("DepthOfFieldEffect"), effect("Atmosphere")
	if mode == "neutral" then
		Lighting.ClockTime = 14
		Lighting.Brightness = 2
		Lighting.ExposureCompensation = 0
		Lighting.Ambient = Color3.fromRGB(120, 120, 128)
		Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 136)
		Lighting.GlobalShadows = true
		for _, e in ipairs({ bloom, cc, dof, atmo }) do if e then e.Enabled = false end end
	else
		Lighting.ClockTime = 0
		Lighting.Brightness = 1.3
		Lighting.ExposureCompensation = 0
		Lighting.Ambient = Color3.fromRGB(60, 66, 100)
		Lighting.OutdoorAmbient = Color3.fromRGB(70, 76, 112)
		if bloom then bloom.Enabled = true; bloom.Intensity = 0.25; bloom.Size = 12; bloom.Threshold = 1.9 end   -- only tiny, very bright effect geometry blooms
		if cc then cc.Enabled = true; cc.Contrast = 0.08; cc.Saturation = -0.05; cc.TintColor = Color3.fromRGB(235, 238, 255) end
		if dof then dof.Enabled = false end
		if atmo then atmo.Enabled = true; atmo.Density = 0.18; atmo.Offset = 0.1; atmo.Color = Color3.fromRGB(95, 105, 160); atmo.Decay = Color3.fromRGB(40, 45, 90); atmo.Haze = 0; atmo.Glare = 0 end
	end
end

-- soft front fill that follows the camera so eyes and brows read at night; no shadows, low brightness
function Look.fill()
	local p = Workspace:FindFirstChild("BGFill")
	if not p then
		p = Instance.new("Part")
		p.Name = "BGFill"
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow, p.Transparency = true, false, false, false, false, 1
		p.Size = Vector3.new(1, 1, 1)
		local l = Instance.new("PointLight")
		l.Range, l.Brightness, l.Color, l.Shadows = 30, 0.55, Color3.fromRGB(255, 242, 232), false
		l.Parent = p
		p.Parent = Workspace
	end
	return p
end

function Look.audit()
	print(string.format("[LOOK] Lighting: Brightness %.2f  Exposure %.2f  ClockTime %.1f  Ambient %s  OutdoorAmbient %s",
		Lighting.Brightness, Lighting.ExposureCompensation, Lighting.ClockTime, tostring(Lighting.Ambient), tostring(Lighting.OutdoorAmbient)))
	for _, c in ipairs(Lighting:GetChildren()) do
		if c:IsA("BloomEffect") then print(string.format("[LOOK]   Bloom enabled=%s intensity %.2f threshold %.2f size %d", tostring(c.Enabled), c.Intensity, c.Threshold, c.Size))
		elseif c:IsA("ColorCorrectionEffect") then print(string.format("[LOOK]   ColorCorrection enabled=%s brightness %.2f contrast %.2f saturation %.2f", tostring(c.Enabled), c.Brightness, c.Contrast, c.Saturation))
		elseif c:IsA("SunRaysEffect") or c:IsA("BlurEffect") or c:IsA("DepthOfFieldEffect") or c:IsA("Atmosphere") then print("[LOOK]   " .. c.ClassName .. " enabled=" .. tostring(c.Enabled or c:IsA("Atmosphere"))) end
	end
	local neon, reflect, hl, lights, bright = 0, 0, 0, 0, {}
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Material == Enum.Material.Neon and d.Transparency < 0.9 then
				neon += 1
				if d.Size.Magnitude > 6 then table.insert(bright, d:GetFullName() .. " (large Neon, size " .. tostring(d.Size) .. ")") end
			end
			if d.Reflectance > 0.05 then reflect += 1; table.insert(bright, d:GetFullName() .. " reflectance " .. d.Reflectance) end
		elseif d:IsA("Highlight") then hl += 1
		elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then lights += 1 end
	end
	print(string.format("[LOOK] Workspace: %d visible Neon parts, %d reflective parts, %d Highlights, %d lights", neon, reflect, hl, lights))
	for i = 1, math.min(#bright, 8) do print("[LOOK]   suspect: " .. bright[i]) end
end

return Look
