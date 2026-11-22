-- BGStyle (ModuleScript, ReplicatedStorage, client only): the anime-cinematic effect layer.
-- Palette stays electric blue vs violet on black / white / grey. Effects are SHAPED (shards, ring slashes, floor cracks,
-- speed lines, white impact flashes) instead of round sparks, and each one is short and tied to the action that fired it.
-- Every function is safe to call with effects off: pass nothing, or set Style.enabled = false.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local Style = { enabled = true }
local fx, gui, flash, ink, lines, vignette = nil, nil, nil, nil, {}, {}
local rng = Random.new(5)

local function ensure()
	if gui then return end
	fx = Workspace:FindFirstChild("BGStyleFX") or Instance.new("Folder")
	fx.Name = "BGStyleFX"
	fx.Parent = Workspace
	gui = Instance.new("ScreenGui")
	gui.Name = "BGStyleOverlay"
	gui.IgnoreGuiInset, gui.ResetOnSpawn, gui.DisplayOrder = true, false, 50
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	-- soft dark vignette made of four gradient bars
	for i, spec in ipairs({
		{ UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0.18, 0), 90 }, { UDim2.new(0, 0, 0.82, 0), UDim2.new(1, 0, 0.18, 0), 270 },
		{ UDim2.new(0, 0, 0, 0), UDim2.new(0.12, 0, 1, 0), 0 }, { UDim2.new(0.88, 0, 0, 0), UDim2.new(0.12, 0, 1, 0), 180 } }) do
		local f = Instance.new("Frame")
		f.Position, f.Size, f.BorderSizePixel = spec[1], spec[2], 0
		f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.BackgroundTransparency = 0
		local g = Instance.new("UIGradient")
		g.Rotation = spec[3]
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		g.Parent = f
		f.Parent = gui
		vignette[i] = f
	end
	flash = Instance.new("Frame")
	flash.Size, flash.BorderSizePixel, flash.BackgroundColor3, flash.BackgroundTransparency, flash.ZIndex = UDim2.new(1, 0, 1, 0), 0, Color3.new(1, 1, 1), 1, 20
	flash.Parent = gui
	ink = Instance.new("Frame")
	ink.Size, ink.BorderSizePixel, ink.BackgroundColor3, ink.BackgroundTransparency, ink.ZIndex = UDim2.new(1, 0, 1, 0), 0, Color3.new(1, 1, 1), 1, 18
	ink.Parent = gui
	for i = 1, 40 do
		local l = Instance.new("Frame")
		l.AnchorPoint = Vector2.new(0, 0.5)
		l.Position = UDim2.new(0.5, 0, 0.5, 0)
		l.BorderSizePixel = 0
		l.BackgroundTransparency = 1
		l.ZIndex = 19
		local g = Instance.new("UIGradient")        -- only the middle band of each line shows: streaks radiate from the centre
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.35, 1), NumberSequenceKeypoint.new(0.6, 0),
			NumberSequenceKeypoint.new(0.85, 0.3), NumberSequenceKeypoint.new(1, 1) })
		g.Parent = l
		l.Parent = gui
		lines[i] = l
	end
end

function Style.setEnabled(on)
	Style.enabled = on
	ensure()
	for _, f in ipairs(vignette) do f.Visible = on end
end

-- full-screen white (or coloured) flash, e.g. 0.05 s on every hard hit
function Style.flash(color, dur, strength)
	if not Style.enabled then return end
	ensure()
	flash.BackgroundColor3 = color or Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1 - (strength or 0.5)
	TweenService:Create(flash, TweenInfo.new(dur or 0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
end

-- radiating speed lines (colour = accent, or black on the ink flash)
function Style.speedLines(color, dur, count)
	if not Style.enabled then return end
	ensure()
	dur = dur or 0.25
	for i = 1, math.min(count or 28, #lines) do
		local l = lines[i]
		l.Rotation = (i / (count or 28)) * 360 + rng:NextNumber(-5, 5)
		l.Size = UDim2.new(rng:NextNumber(0.55, 0.95), 0, 0, rng:NextInteger(2, 6))
		l.BackgroundColor3 = color
		l.BackgroundTransparency = 0.15
		TweenService:Create(l, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1, Size = UDim2.new(1.1, 0, 0, 1) }):Play()
	end
end

-- the finishing "ink" frame: a white flash with black speed lines (big slams and ultimates)
function Style.ink(dur)
	if not Style.enabled then return end
	ensure()
	dur = dur or 0.4
	ink.BackgroundTransparency = 0.05
	TweenService:Create(ink, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 }):Play()
	Style.speedLines(Color3.new(0, 0, 0), dur * 0.9, 36)
end

local function neon(size, cframe, color, transparency)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material, p.Color, p.Transparency = Enum.Material.Neon, color, transparency or 0
	p.Size, p.CFrame = size, cframe
	p.Parent = fx
	return p
end

-- sharp shards flying out of a point (replaces round sparks on hits)
function Style.shards(pos, color, count, speed, axis)
	if not Style.enabled then return end
	ensure()
	speed = speed or 9
	for i = 1, count or 10 do
		local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.3, 1), rng:NextNumber(-1, 1))
		if axis then dir = (dir + axis * 1.2) end
		dir = dir.Magnitude > 0.01 and dir.Unit or Vector3.new(0, 1, 0)
		local len = rng:NextNumber(0.5, 1.3)
		local p = neon(Vector3.new(0.07, 0.07, len), CFrame.lookAt(pos, pos + dir), (i % 3 == 0) and Color3.new(1, 1, 1) or color)
		local dist = rng:NextNumber(0.6, 1.0) * speed * 0.35
		TweenService:Create(p, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = CFrame.lookAt(pos + dir * dist, pos + dir * (dist + 1)), Size = Vector3.new(0.02, 0.02, len * 0.3), Transparency = 1 }):Play()
		Debris:AddItem(p, 0.4)
	end
end

-- thin expanding ring slash; tilt = degrees of roll so rings can cross each other
function Style.ringSlash(pos, color, diameter, tilt, dur, axisYaw)
	if not Style.enabled then return end
	ensure()
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CastShadow = true, false, false, false
	ring.Material, ring.Color, ring.Transparency = Enum.Material.Neon, color, 0.05
	ring.Size = Vector3.new(0.05, 0.6, 0.6)
	ring.CFrame = CFrame.new(pos) * CFrame.Angles(0, math.rad(axisYaw or 0), math.rad(tilt or 90))
	ring.Parent = fx
	TweenService:Create(ring, TweenInfo.new(dur or 0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.05, diameter, diameter), Transparency = 1 }):Play()
	Debris:AddItem(ring, (dur or 0.28) + 0.1)
end

-- cracked-glass lines racing across the floor from a point
function Style.crack(center, color, count, length)
	if not Style.enabled then return end
	ensure()
	for i = 1, count or 10 do
		local a = (i / (count or 10)) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local len = length * rng:NextNumber(0.55, 1.0)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local p = neon(Vector3.new(0.14, 0.05, 0.2), CFrame.lookAt(Vector3.new(center.X, 0.13, center.Z), Vector3.new(center.X, 0.13, center.Z) + dir), color, 0.05)
		TweenService:Create(p, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = Vector3.new(0.14, 0.05, len), CFrame = CFrame.lookAt(Vector3.new(center.X, 0.13, center.Z) + dir * len / 2, Vector3.new(center.X, 0.13, center.Z) + dir * (len / 2 + 1)) }):Play()
		task.delay(0.5, function() if p.Parent then TweenService:Create(p, TweenInfo.new(0.6), { Transparency = 1 }):Play() end end)
		Debris:AddItem(p, 1.2)
		if rng:NextNumber() < 0.6 then            -- a short branch off the main crack
			local b = a + rng:NextNumber(-0.6, 0.6)
			local bd = Vector3.new(math.cos(b), 0, math.sin(b))
			local start = Vector3.new(center.X, 0.13, center.Z) + dir * len * 0.6
			local bl = len * 0.35
			local q = neon(Vector3.new(0.1, 0.05, 0.1), CFrame.lookAt(start, start + bd), color, 0.1)
			TweenService:Create(q, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = Vector3.new(0.1, 0.05, bl), CFrame = CFrame.lookAt(start + bd * bl / 2, start + bd * (bl / 2 + 1)) }):Play()
			task.delay(0.5, function() if q.Parent then TweenService:Create(q, TweenInfo.new(0.6), { Transparency = 1 }):Play() end end)
			Debris:AddItem(q, 1.2)
		end
	end
end

-- one call for a hard hit: shards + crossing ring slashes + white flash (+ lines/cracks when it is big)
function Style.impact(pos, color, power)
	if not Style.enabled then return end
	power = power or 1
	Style.shards(pos, color, math.floor(8 + 6 * power), 8 + 4 * power)
	Style.ringSlash(pos, Color3.new(1, 1, 1), 2.5 + 2.5 * power, 90, 0.18, 0)
	Style.ringSlash(pos, color, 3.5 + 3 * power, 60, 0.26, 40)
	Style.flash(Color3.new(1, 1, 1), 0.07, 0.25 + 0.2 * power)
	if power >= 1.3 then
		Style.speedLines(color, 0.22, 26)
		Style.crack(pos, color, 10, 5 + 2 * power)
	end
end

return Style
