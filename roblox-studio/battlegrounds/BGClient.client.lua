-- BGClient (LocalScript, StarterPlayer > StarterPlayerScripts): the PLAYABLE mode.
-- Sends input to BGServer, poses both rigs from the server's snapshots with BGEngine + BGClips,
-- draws effects, power-form looks, the duel camera and the UI. Active only while stage attribute Mode == "Play"
-- (BGDirector owns the cinematic replay). All numbers that matter (damage, cooldowns, meter) come from the server.
--
-- Controls:  WASD move (W = toward the opponent)   LMB combo   Q/E/R/C skills   F hold guard   G counter / riposte
--            X first form (needs 50%)   Z final form (needs 100%)   T ultimate (final form only)   Tab playable <-> cinematic
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local Engine = require(ReplicatedStorage:WaitForChild("BGEngine"))
local Config = require(ReplicatedStorage:WaitForChild("BGConfig"))
local Clips = require(ReplicatedStorage:WaitForChild("BGClips"))
local Rig = require(ReplicatedStorage:WaitForChild("BGRig"))
local Cloth = require(ReplicatedStorage:WaitForChild("BGCloth"))
local Style = require(ReplicatedStorage:WaitForChild("BGStyle"))

local stage = Workspace:WaitForChild("Showcase")
while not stage:GetAttribute("Ready") do task.wait(0.1) end
local remotes = ReplicatedStorage:WaitForChild("BGRemotes")
local InputRE, ControlRE, SnapRE, EventRE = remotes:WaitForChild("Input"), remotes:WaitForChild("Control"), remotes:WaitForChild("Snap"), remotes:WaitForChild("Event")

local BLUE, CYAN, VIOLET = Color3.fromRGB(60, 150, 255), Color3.fromRGB(70, 215, 255), Color3.fromRGB(175, 90, 255)
local isStudio = RunService:IsStudio()
local function playing() return stage:GetAttribute("Mode") == "Play" end

---------------------------------------------------------------- rigs and clip tracks
local fighters = { Blue = stage:WaitForChild("Blue"), Purple = stage:WaitForChild("Purple") }
local rs, R = {}, nil
for id, model in pairs(fighters) do
	Rig.waitReady(model)
	local defs, sizes, motors = Rig.read(model)
	if not R then R = Engine.newRig(defs, sizes) end
	rs[id] = { id = id, model = model, motors = motors, cloth = Cloth.new(model), x = 0, z = 0, ang = 0, y = 0, snap = nil, snapT = 0,
		seq = -1, from = nil, blend = 1, blendDur = 0.1, lastP = nil, form = "Base", lastHand = nil, deco = nil }
end
local tracks = { Kael = (Engine.bake(R, Clips.engineData("Kael"))), Ren = (Engine.bake(R, Clips.engineData("Ren"))) }

local function lerpAny(a, b, w)
	local ta = typeof(a)
	if ta == "number" then return a + (b - a) * w
	elseif ta == "Vector3" then return a:Lerp(b, w)
	elseif ta == "table" then
		local r = {}
		for k, v in pairs(a) do r[k] = lerpAny(v, b[k], w) end
		return r
	end
	return b
end
local function wrapAngle(a)
	while a > math.pi do a -= 2 * math.pi end
	while a < -math.pi do a += 2 * math.pi end
	return a
end

---------------------------------------------------------------- decoration lookup (parts tagged by BGBuilder)
local function collectDeco(model)
	local d = { Seam = {}, Eye = {}, Lining = {}, Accent = {}, Hair = {}, Bracer = {}, PowerSegment = {}, base = {} }
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			for tag in pairs(d) do
				if tag ~= "base" and p:GetAttribute(tag) then
					table.insert(d[tag], p)
					d.base[p] = { Color = p.Color, Material = p.Material, Transparency = p.Transparency }
				end
			end
		end
	end
	return d
end
for _, r in pairs(rs) do r.deco = collectDeco(r.model) end

---------------------------------------------------------------- effects
local fxFolder = Instance.new("Folder")
fxFolder.Name = "BGEffects"
fxFolder.Parent = Workspace

local function anchorPart(pos, size)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Transparency = 1
	p.Size = size or Vector3.new(0.2, 0.2, 0.2)
	p.Position = pos
	p.Parent = fxFolder
	return p
end

local function sparks(pos, color, size, count)
	local a = anchorPart(pos)
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(color); pe.LightEmission = 1; pe.Rate = 0
	pe.Lifetime = NumberRange.new(0.1, 0.24)
	pe.Speed = NumberRange.new(7 * size, 16 * size)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Size = NumberSequence.new(0.45 * size, 0)
	pe.Transparency = NumberSequence.new(0, 1)
	pe.Parent = a
	pe:Emit(count or math.floor(14 * size))
	Debris:AddItem(a, 0.5)
end

local function groundRing(pos, color, d0, d1, dur)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CastShadow = true, false, false, false
	ring.Material, ring.Color, ring.Transparency = Enum.Material.Neon, color, 0.15
	ring.Size = Vector3.new(0.14, d0, d0)
	ring.CFrame = CFrame.new(pos.X, 0.12, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = fxFolder
	TweenService:Create(ring, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.14, d1, d1), Transparency = 1 }):Play()
	Debris:AddItem(ring, dur + 0.1)
end

local function pulseBall(pos, color, d0, d1, dur, t0)
	local b = Instance.new("Part")
	b.Shape = Enum.PartType.Ball
	b.Anchored, b.CanCollide, b.CanQuery, b.CastShadow = true, false, false, false
	b.Material, b.Color, b.Transparency = Enum.Material.Neon, color, t0 or 0.55
	b.Size = Vector3.new(d0, d0, d0)
	b.Position = pos
	b.Parent = fxFolder
	TweenService:Create(b, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(d1, d1, d1), Transparency = 1 }):Play()
	Debris:AddItem(b, dur + 0.1)
end

-- curved shield ripple: a thin shell segment in front of the defender
local function ripple(pos, dir, color)
	local b = Instance.new("Part")
	b.Shape = Enum.PartType.Ball
	b.Anchored, b.CanCollide, b.CanQuery, b.CastShadow = true, false, false, false
	b.Material, b.Color, b.Transparency = Enum.Material.ForceField, color, 0.3
	b.Size = Vector3.new(2, 2, 2)
	b.Position = pos + dir * 1.2
	b.Parent = fxFolder
	TweenService:Create(b, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(5.2, 5.2, 5.2), Transparency = 1 }):Play()
	Debris:AddItem(b, 0.45)
end

local function ghost(model, color)
	local clone = model:Clone()
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored, d.CanCollide, d.CanQuery, d.CastShadow = true, false, false, false
			d.Material, d.Color, d.Transparency = Enum.Material.ForceField, color, 0.35
			TweenService:Create(d, TweenInfo.new(0.35), { Transparency = 1 }):Play()
		elseif d:IsA("Humanoid") or d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Trail") or d:IsA("Highlight") or d:IsA("Decal") or d:IsA("ParticleEmitter") then
			d:Destroy()
		end
	end
	clone.Parent = fxFolder
	Debris:AddItem(clone, 0.5)
end

local shakeUntil, shakePower = 0, 0
local closeShot, camRoll, fovKick = nil, 0, 0     -- close-ups on big hits, a small tilt and a FOV punch
local function closeUp(pos, attId, dur)
	local fwd = Vector3.new(math.cos(rs[attId].ang), 0, math.sin(rs[attId].ang))
	local right = Vector3.new(-fwd.Z, 0, fwd.X)
	closeShot = { cf = CFrame.lookAt(pos + right * 3.4 + Vector3.new(0, 0.8, 0), pos), fov = 30, untilT = os.clock() + (dur or 0.32) }
	camRoll = (math.random() < 0.5 and -1 or 1) * 4
end
local function topDown(pos, dur)
	closeShot = { cf = CFrame.lookAt(pos + Vector3.new(0.5, 10, 2.5), pos), fov = 46, untilT = os.clock() + (dur or 0.55) }
end
local function shake(power, dur) shakePower, shakeUntil = power, os.clock() + dur end

local function partPos(id, name)
	local p = rs[id].model:FindFirstChild(name)
	return p and p.Position
end
local function chestPos(id) return partPos(id, "UpperTorso") or Vector3.new(rs[id].x, 3, rs[id].z) end
local function colorOf(id) return rs[id].model:GetAttribute("Character") == "Kael" and BLUE or VIOLET end
local function forward(id) local r = rs[id] return Vector3.new(math.cos(r.ang), 0, math.sin(r.ang)) end

---------------------------------------------------------------- toasts
local gui = Instance.new("ScreenGui")
gui.Name = "BGUI"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
local function mk(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent or gui
	return o
end
local toastLabel = mk("TextLabel", { BackgroundTransparency = 1, Position = UDim2.new(0.5, -200, 0.2, 0), Size = UDim2.new(0, 400, 0, 36),
	Font = Enum.Font.GothamBold, TextSize = 24, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.5, Text = "" })
local toastId = 0
local function toast(text, color)
	toastId += 1
	local my = toastId
	toastLabel.Text, toastLabel.TextColor3, toastLabel.TextTransparency = text, color or Color3.new(1, 1, 1), 0
	task.delay(0.9, function() if toastId == my then toastLabel.Text = "" end end)
end

---------------------------------------------------------------- power-form looks
local orbit = {}      -- Ren's fragments
local highlights = {}

local function clearOrbit(collapse)
	for _, f in ipairs(orbit) do
		if collapse then
			TweenService:Create(f.part, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = Vector3.new(0.05, 0.05, 0.05), Transparency = 1 }):Play()
			Debris:AddItem(f.part, 0.4)
		else
			f.part:Destroy()
		end
	end
	orbit = {}
end

local function setHighlight(id, on, color, outlineT)
	local h = highlights[id]
	if on then
		if not h then
			h = Instance.new("Highlight")
			h.FillTransparency = 1
			h.DepthMode = Enum.HighlightDepthMode.Occluded
			h.Parent = rs[id].model
			highlights[id] = h
		end
		h.OutlineColor, h.OutlineTransparency = color, outlineT
	elseif h then
		h:Destroy(); highlights[id] = nil
	end
end

local function handEmitters(id, rate, color)
	for _, n in ipairs({ "RightHand" }) do
		local p = rs[id].model:FindFirstChild(n)
		if p then
			local e = p:FindFirstChild("BGSpark")
			if rate > 0 then
				if not e then
					e = Instance.new("ParticleEmitter")
					e.Name = "BGSpark"
					e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
					e.LightEmission = 1; e.Lifetime = NumberRange.new(0.15, 0.3); e.Speed = NumberRange.new(1, 4)
					e.SpreadAngle = Vector2.new(180, 180); e.Size = NumberSequence.new(0.28, 0); e.Transparency = NumberSequence.new(0, 1)
					e.Parent = p
				end
				e.Rate, e.Color = rate, ColorSequence.new(color)
			elseif e then
				e:Destroy()
			end
		end
	end
end

-- body aura for power forms: rising sparks + a glow on the torso (rate 0 removes it)
local function aura(id, rate, color, brightness, range)
	local torso = rs[id].model:FindFirstChild("UpperTorso")
	if not torso then return end
	local e, l = torso:FindFirstChild("BGAura"), torso:FindFirstChild("BGGlow")
	if rate <= 0 then
		if e then e:Destroy() end
		if l then l:Destroy() end
		return
	end
	if not e then
		e = Instance.new("ParticleEmitter")
		e.Name = "BGAura"
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.LightEmission = 1; e.Lifetime = NumberRange.new(0.5, 0.9); e.Speed = NumberRange.new(3, 7)
		e.EmissionDirection = Enum.NormalId.Top; e.SpreadAngle = Vector2.new(35, 35)
		e.Size = NumberSequence.new(0.35, 0); e.Transparency = NumberSequence.new(0.1, 1)
		e.Parent = torso
	end
	if not l then
		l = Instance.new("PointLight")
		l.Name = "BGGlow"
		l.Parent = torso
	end
	e.Rate, e.Color = rate, ColorSequence.new(color)
	l.Color, l.Brightness, l.Range = color, brightness, range
end

local function setSeams(deco, color, transparency, material)
	for _, p in ipairs(deco.Seam) do
		p.Color, p.Transparency = color, transparency
		if material then p.Material = material end
	end
end

local function applyForm(id, form, prev)
	local r = rs[id]
	local d = r.deco
	local kael = r.model:GetAttribute("Character") == "Kael"
	if kael then
		if form == "Base" then
			setSeams(d, CYAN, 0.3)
			for _, p in ipairs(d.PowerSegment) do p.Transparency = 1 end
			for _, p in ipairs(d.Eye) do p.Color, p.Material = d.base[p].Color, d.base[p].Material end
			for _, p in ipairs(d.Bracer) do p.Color, p.Material = d.base[p].Color, d.base[p].Material end
			setHighlight(id, false); handEmitters(id, 0, CYAN); aura(id, 0)
		elseif form == "Form1" then
			setSeams(d, Color3.fromRGB(120, 235, 255), 0)
			for _, p in ipairs(d.PowerSegment) do p.Transparency = 0 end        -- scarf trails slightly longer
			setHighlight(id, false); handEmitters(id, 7, CYAN); aura(id, 22, CYAN, 1.6, 14)
		else
			setSeams(d, Color3.fromRGB(205, 240, 255), 0)
			for _, p in ipairs(d.PowerSegment) do p.Transparency = 0 end
			for _, p in ipairs(d.Eye) do p.Color, p.Material = Color3.fromRGB(215, 238, 255), Enum.Material.Neon end   -- blue-white eyes
			for _, p in ipairs(d.Bracer) do p.Color, p.Material = Color3.fromRGB(110, 130, 170), Enum.Material.Neon end -- brighter forearm guards
			setHighlight(id, true, Color3.fromRGB(170, 225, 255), 0.5)
			handEmitters(id, 16, Color3.fromRGB(190, 230, 255)); aura(id, 55, Color3.fromRGB(190, 230, 255), 3, 22)
		end
	else
		if form == "Base" then
			setSeams(d, VIOLET, 1)
			for _, p in ipairs(d.Lining) do p.Transparency = 0.55 end
			for _, p in ipairs(d.Accent) do p.Transparency = 1 end
			for _, p in ipairs(d.Eye) do p.Color, p.Material = d.base[p].Color, d.base[p].Material end
			for _, p in ipairs(d.Hair) do p.Color, p.Material = d.base[p].Color, d.base[p].Material end
			setHighlight(id, false); aura(id, 0)
		elseif form == "Form1" then
			setSeams(d, VIOLET, 0.05)                       -- violet lines illuminate across the bracers
			for _, p in ipairs(d.Lining) do p.Transparency = 0.1 end   -- coat lining glows during turns
			for _, p in ipairs(d.Accent) do p.Transparency = 1 end
			aura(id, 20, VIOLET, 1.5, 14)
		else
			setSeams(d, Color3.fromRGB(200, 150, 255), 0)
			aura(id, 50, Color3.fromRGB(205, 160, 255), 2.8, 22)
			for _, p in ipairs(d.Lining) do p.Transparency = 0.05 end
			for _, p in ipairs(d.Accent) do p.Transparency = 0.78 end   -- layered translucent accents on the bracers
			for _, p in ipairs(d.Eye) do p.Color, p.Material = Color3.fromRGB(175, 95, 255), Enum.Material.Neon end
			for _, p in ipairs(d.Hair) do p.Color = Color3.fromRGB(238, 238, 252) end    -- silver-white
			setHighlight(id, true, Color3.fromRGB(235, 232, 255), 0.45)                  -- hair / body rim light
			clearOrbit(false)
			for i = 1, 6 do
				local f = Instance.new("Part")
				f.Anchored, f.CanCollide, f.CanQuery, f.CastShadow = true, false, false, false
				f.Material, f.Color, f.Transparency = Enum.Material.Neon, VIOLET, 0.25
				f.Size = Vector3.new(0.22 + (i % 3) * 0.08, 0.5, 0.22)
				f.Parent = fxFolder
				orbit[i] = { part = f, a = i / 6 * math.pi * 2, h = (i % 3 - 1) * 0.7, id = id }
			end
		end
		if form ~= "Final" and (prev == "Final") then clearOrbit(true) end   -- fragments collapse back into the character
	end
	if kael and prev == "Final" and form == "Base" then
		sparks(chestPos(id), CYAN, 0.6, 12)      -- electricity fades from the hands and jacket seams
	end
end

for id in pairs(rs) do applyForm(id, "Base", nil) end    -- normalise the Base look

---------------------------------------------------------------- events from the server
local function handEvent(e)
	local r = rs[e.f]
	if e.hand then r.lastHand = e.hand end
end

local function contactPos(attId, tgtId)
	local r = rs[attId]
	local hp = r.lastHand and partPos(attId, r.lastHand)
	local c = chestPos(tgtId)
	if hp and (hp - c).Magnitude < 5 then return hp end
	return c
end

local function onEvent(e)
	if e.type == "marker" then
		local id = e.f
		handEvent(e)
		local n = e.name
		local hand = (e.hand and partPos(id, e.hand)) or chestPos(id)
		if n == "afterimage" then ghost(rs[id].model, CYAN)
		elseif n == "windup_charge" then sparks(hand, colorOf(id), 0.5, 10)
		elseif n == "pulse_gather" then pulseBall(chestPos(id), colorOf(id), 5, 0.6, 0.3, 0.7)
		elseif n == "pulse_chest" then pulseBall(chestPos(id), colorOf(id), 1, 7, 0.35, 0.5); shake(0.15, 0.25); Style.flash(colorOf(id), 0.12, 0.3); Style.ringSlash(chestPos(id), colorOf(id), 6, 90, 0.3, 0)
		elseif n == "pulse_forearms" then
			pulseBall(chestPos(id), colorOf(id), 1, 6, 0.35, 0.5)
			for _, h in ipairs({ "RightLowerArm", "LeftLowerArm" }) do local p = partPos(id, h); if p then pulseBall(p, colorOf(id), 0.5, 3, 0.3, 0.4) end end
		elseif n == "pulse_arms" then
			for _, h in ipairs({ "RightHand", "LeftHand" }) do local p = partPos(id, h); if p then pulseBall(p, colorOf(id), 0.5, 3.5, 0.3, 0.4) end end
		elseif n == "anchor_plant" then groundRing(Vector3.new(e.x, 0, e.z), VIOLET, 1, 6, 0.3)
		elseif n == "anchor_release" then groundRing(Vector3.new(e.x, 0, e.z), VIOLET, 2, 8, 0.35); sparks(chestPos(id), VIOLET, 0.8, 14)
		elseif n == "redirect_arc" then sparks(hand, VIOLET, 0.7, 12)
		elseif n == "slip_whoosh" then sparks(chestPos(id), CYAN, 0.4, 6)
		end
		if e.fx == "ring_ground" then
			local big = n == "contact_horizon_blast"
			local form = rs[id].form
			local d = big and (Config.horizon.radius * 2) or ((form == "Base") and Config.hits.ren_pulse.range * 2 or Config.hits.ren_pulse.range1 * 2)
			groundRing(Vector3.new(e.x, 0, e.z), colorOf(id), 1.5, d, big and 0.45 or 0.3)
			Style.crack(Vector3.new(e.x, 0, e.z), colorOf(id), big and 18 or 10, big and 12 or d / 2)
			if big then Style.speedLines(colorOf(id), 0.3, 30); Style.flash(Color3.new(1, 1, 1), 0.1, 0.5) end
			shake(big and 0.5 or 0.25, 0.3)
		end
	elseif e.type == "hit" then
		local pos = contactPos(e.by, e.f)
		local size = math.clamp(0.5 + e.dmg / 16, 0.5, 1.4)
		local col = e.armor and Color3.fromRGB(225, 225, 235) or colorOf(e.by)
		sparks(pos, col, size * 0.5, nil)
		local big = e.final or e.dmg >= 10
		if big then Style.impact(pos, col, 1.5); closeUp(pos, e.by); fovKick = 7; shake(0.3, 0.2)
		elseif e.dmg >= 5 then Style.impact(pos, col, 0.6); fovKick = math.max(fovKick, 3); shake(0.1, 0.12)
		else Style.shards(pos, col, 6, 7) end
	elseif e.type == "block" then
		sparks(contactPos(e.by, e.f), Color3.fromRGB(235, 235, 255), 0.5, nil)
		local kid = e.f
		local d = rs[kid].deco
		if rs[kid].model:GetAttribute("Character") == "Ren" and rs[kid].form == "Base" then
			for _, p in ipairs(d.Seam) do
				p.Transparency = 0.1
				TweenService:Create(p, TweenInfo.new(0.35), { Transparency = 1 }):Play()      -- bracers light up briefly while blocking
			end
		end
		if rs[kid].form ~= "Base" then ripple(chestPos(kid), forward(kid), VIOLET) end
	elseif e.type == "timed" then
		ripple(chestPos(e.f), forward(e.f), VIOLET)
		sparks(contactPos(e.by, e.f), VIOLET, 1.0, nil)
		Style.ringSlash(chestPos(e.f) + forward(e.f) * 1.2, VIOLET, 6, 90, 0.3, 0)
		Style.flash(Color3.new(1, 1, 1), 0.06, 0.3)
		for _, p in ipairs(rs[e.f].deco.Seam) do
			p.Transparency = 0.05
			if rs[e.f].form == "Base" then TweenService:Create(p, TweenInfo.new(0.6), { Transparency = 1 }):Play() end
		end
		toast(e.stored and "TIMED BLOCK - energy stored" or "TIMED BLOCK - press G", VIOLET)
		shake(0.2, 0.2)
	elseif e.type == "dodge" then
		ghost(rs[e.f].model, CYAN)
		toast("DODGE - press G to counter", CYAN)
	elseif e.type == "slam" then
		if e.big then
			groundRing(Vector3.new(e.x, 0, e.z), CYAN, 1.5, 22, 0.5)      -- the single expanding Thunderfall ring
			Style.ink(0.45); Style.crack(Vector3.new(e.x, 0, e.z), CYAN, 16, 12); topDown(Vector3.new(e.x, 1, e.z), 0.55)
			sparks(Vector3.new(e.x, 1, e.z), Color3.fromRGB(220, 240, 255), 1.4, 30)
			shake(0.7, 0.4)
		else
			groundRing(Vector3.new(e.x, 0, e.z), BLUE, 1, 6, 0.25)         -- compact follow-up impact
			Style.shards(Vector3.new(e.x, 0.6, e.z), BLUE, 10, 8, Vector3.new(0, 1, 0)); Style.crack(Vector3.new(e.x, 0, e.z), BLUE, 7, 4)
			sparks(Vector3.new(e.x, 0.8, e.z), BLUE, 0.9, nil)
			shake(0.25, 0.2)
		end
	elseif e.type == "field" then
		-- telegraphed Event Horizon floor field: disc + inward-collapsing rings, visible the whole time
		local diameter = e.radius * 2
		local disc = Instance.new("Part")
		disc.Shape = Enum.PartType.Cylinder
		disc.Anchored, disc.CanCollide, disc.CanQuery, disc.CastShadow = true, false, false, false
		disc.Material, disc.Color, disc.Transparency = Enum.Material.Neon, VIOLET, 0.82
		disc.Size = Vector3.new(0.1, diameter, diameter)
		disc.CFrame = CFrame.new(e.x, 0.1, e.z) * CFrame.Angles(0, 0, math.rad(90))
		disc.Parent = fxFolder
		local edge = disc:Clone()
		edge.Transparency = 0.25
		edge.Size = Vector3.new(0.14, diameter, diameter)
		edge.Parent = fxFolder
		local inner = edge:Clone()
		inner.Size = Vector3.new(0.14, 1, 1)
		inner.Parent = fxFolder
		TweenService:Create(inner, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { Size = Vector3.new(0.14, diameter * 0.6, diameter * 0.6), Transparency = 0.5 }):Play()
		task.spawn(function()
			local t0 = os.clock()
			while os.clock() - t0 < e.dur + 0.4 do
				local u = ((os.clock() - t0) % 0.6) / 0.6
				local d = diameter * (1 - u)
				inner.Size = Vector3.new(0.14, math.max(d, 0.5), math.max(d, 0.5))
				inner.Transparency = 0.2 + 0.7 * (1 - u)
				task.wait()
			end
			TweenService:Create(disc, TweenInfo.new(0.35), { Transparency = 1 }):Play()
			TweenService:Create(edge, TweenInfo.new(0.35), { Transparency = 1 }):Play()
			inner:Destroy()
			Debris:AddItem(disc, 0.5); Debris:AddItem(edge, 0.5)
		end)
	elseif e.type == "form" then
		toast(e.form == "Base" and "Back to Base" or (rs[e.f].model:GetAttribute("Character") == "Kael" and (e.form == "Form1" and "CHARGED MODE" or "THUNDER ASCENSION") or (e.form == "Form1" and "RIFT MODE" or "ECLIPSE FORM")), colorOf(e.f))
	elseif e.type == "open" then
		toast("Kael is open!", Color3.fromRGB(255, 200, 120))
	elseif e.type == "ko" then
		toast("KO", Color3.fromRGB(255, 120, 120))
	elseif e.type == "reset" then
		clearOrbit(false)
		for _, h in pairs(highlights) do h:Destroy() end
		highlights = {}
		for _, c in ipairs(fxFolder:GetChildren()) do c:Destroy() end
		for _, r in pairs(rs) do r.form = "Base"; applyForm(r.id, "Base", nil); r.from = nil; r.seq = -1 end
	end
end
EventRE.OnClientEvent:Connect(function(list) for _, e in ipairs(list) do onEvent(e) end end)

---------------------------------------------------------------- snapshots
local ctl, aiMode = "Blue", "Idle"
local lastSnap = nil
SnapRE.OnClientEvent:Connect(function(snap, controlled, ai)
	ctl, aiMode, lastSnap = controlled, ai, snap
	for id, s in pairs(snap) do
		local r = rs[id]
		if not r.snap then r.x, r.z, r.ang, r.y = s.x, s.z, s.ang, s.y end
		r.snap, r.snapT = s, os.clock()
	end
end)

---------------------------------------------------------------- per-frame pose
local function blendTimeFor(clip)
	if clip == "hit" or clip == "knock" or clip == "guard_hit" or clip == "timed_block" or clip == "air" then return 0.05 end
	if clip:sub(1, 3) == "m1_" or clip == "counter" or clip == "void_counter" or clip == "sky" or clip == "arc" or clip == "storm" then return 0.07 end
	return 0.12
end

local FASTCLIPS = { flash = true, flash_back = true, storm = true, arc = true, thunder = true, m1_4 = true, m1_2 = true, sky = true, void_counter = true, counter = true }
local trailSets = {}
local function updateTrails(r, meta, t)
	local want = {}
	if meta and meta.trail then
		for _, w in ipairs(meta.trail) do if t >= w.from and t <= w.to then want[w.hand] = true end end
	end
	for _, n in ipairs({ "RightHand", "LeftHand", "RightLowerArm", "LeftLowerArm" }) do
		local p = r.model:FindFirstChild(n)
		local tr = p and p:FindFirstChild("ShowcaseTrail")
		if tr then tr.Enabled = want[n] == true end
	end
end

RunService:BindToRenderStep("BGPose", Enum.RenderPriority.Camera.Value - 1, function(dt)
	if not playing() then return end
	dt = math.min(dt, 1 / 20)
	for id, r in pairs(rs) do
		local s = r.snap
		if s then
			local k = 1 - math.exp(-dt * 24)
			r.x += (s.x - r.x) * k; r.z += (s.z - r.z) * k; r.y += (s.y - r.y) * (1 - math.exp(-dt * 30))
			r.ang += wrapAngle(s.ang - r.ang) * (1 - math.exp(-dt * 18))
			if s.seq ~= r.seq then
				r.from = r.lastP
				r.blend = 0
				r.blendDur = blendTimeFor(s.clip)
				r.seq = s.seq
			end
			local meta = Clips[s.char][s.clip]
			local t = s.clipT + (os.clock() - r.snapT) * s.clipSpeed
			local tt
			if meta.loop then
				tt = t % meta.dur
				if s.back then tt = meta.dur - tt end
			else
				tt = math.min(t, meta.dur)
			end
			local P = Engine.eval(R, tracks[s.char][s.clip], tt)
			if r.from and r.blend < 1 then
				r.blend += dt / r.blendDur
				local w = math.min(r.blend, 1)
				w = w * w * (3 - 2 * w)
				P = lerpAny(r.from, P, w)
				if r.blend >= 1 then r.from = nil end
			end
			r.lastP = P
			local out = Engine.solve(R, P)
			local world = CFrame.new(r.x, r.y, r.z) * CFrame.Angles(0, -r.ang, 0)
			r.model.HumanoidRootPart.CFrame = world * out.hrp
			for jn, rt in pairs(out.rot) do r.motors[jn].Transform = rt end
			r.cloth:update(world * out.cf.UpperTorso, dt)
			updateTrails(r, meta, t)
			if r.form ~= "Base" and FASTCLIPS[s.clip] and os.clock() - (r.lastGhost or 0) > 0.07 then
				r.lastGhost = os.clock()
				ghost(r.model, colorOf(id))     -- speed afterimages in power forms
			end
			if s.form ~= r.form then
				local prev = r.form
				r.form = s.form
				applyForm(id, s.form, prev)
			end
		end
	end
	-- Rift Mode / form flourishes that need a frame loop: outline flicker, orbiting fragments
	local now = os.clock()
	for id, h in pairs(highlights) do
		h.OutlineTransparency = (rs[id].model:GetAttribute("Character") == "Kael") and (0.35 + 0.3 * math.abs(math.sin(now * 23))) or (0.4 + 0.1 * math.sin(now * 3))
	end
	for _, f in ipairs(orbit) do
		local r = rs[f.id]
		local a = f.a + now * 1.6
		f.part.CFrame = CFrame.new(r.x + math.cos(a) * 2.3, r.y + 3.4 + f.h + math.sin(now * 2 + f.a) * 0.15, r.z + math.sin(a) * 2.3) * CFrame.Angles(a, a * 0.7, 0)
	end
end)

---------------------------------------------------------------- duel camera: over the controlled fighter's shoulder, looking at the opponent
local camCF, camFov
RunService:BindToRenderStep("BGCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if not playing() then camCF = nil; return end
	local cam = Workspace.CurrentCamera
	if not cam then return end
	local me, op = rs[ctl], rs[ctl == "Blue" and "Purple" or "Blue"]
	if not me.snap then return end
	cam.CameraType = Enum.CameraType.Scriptable
	local mid = Vector3.new((me.x + op.x) / 2, 3.2, (me.z + op.z) / 2)
	local dir = Vector3.new(op.x - me.x, 0, op.z - me.z)
	local gap = dir.Magnitude
	dir = gap > 0.01 and dir.Unit or Vector3.new(1, 0, 0)
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local back = 8.5 + math.min(gap, 14) * 0.35
	local pos = Vector3.new(me.x, 0, me.z) - dir * back + right * 2.6 + Vector3.new(0, 5.2 + math.min(gap, 14) * 0.1, 0)
	local target = CFrame.lookAt(pos, mid)
	local fov = 52 - fovKick
	fovKick *= math.exp(-dt * 7)
	local a = 1 - math.exp(-dt * 8)
	if closeShot and os.clock() < closeShot.untilT then target, fov, a = closeShot.cf, closeShot.fov, 1 - math.exp(-dt * 22) end
	if not camCF then camCF, camFov = target, fov end
	camCF = camCF:Lerp(target, a)
	camFov += (fov - camFov) * a
	camRoll *= math.exp(-dt * 6)
	local cf = camCF * CFrame.Angles(0, 0, math.rad(camRoll))
	if os.clock() < shakeUntil then
		local s = shakePower
		cf = cf * CFrame.new((math.random() - 0.5) * s, (math.random() - 0.5) * s, 0)
	end
	cam.CFrame = cf
	cam.FieldOfView = camFov
end)

---------------------------------------------------------------- input
local held = { W = false, A = false, S = false, D = false }
local lastMove, lastMoveSent = Vector2.new(), 0
local function sendMove()
	local f = (held.W and 1 or 0) - (held.S and 1 or 0)
	local s = (held.D and 1 or 0) - (held.A and 1 or 0)
	local v = Vector2.new(f, s)
	if v ~= lastMove or os.clock() - lastMoveSent > 0.25 then
		lastMove, lastMoveSent = v, os.clock()
		InputRE:FireServer("move", f, s)
	end
end
RunService.Heartbeat:Connect(function() if playing() then sendMove() end end)

local function setMode(m) ControlRE:FireServer("mode", m) end
local SKILLKEY = { [Enum.KeyCode.Q] = 1, [Enum.KeyCode.E] = 2, [Enum.KeyCode.R] = 3, [Enum.KeyCode.C] = 4 }
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	local k = input.KeyCode
	if k == Enum.KeyCode.Tab then
		setMode(playing() and "Cinematic" or "Play")
		return
	end
	if not playing() then return end
	if k == Enum.KeyCode.W then held.W = true
	elseif k == Enum.KeyCode.A then held.A = true
	elseif k == Enum.KeyCode.S then held.S = true
	elseif k == Enum.KeyCode.D then held.D = true
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then InputRE:FireServer("m1")
	elseif SKILLKEY[k] then InputRE:FireServer("skill", SKILLKEY[k])
	elseif k == Enum.KeyCode.F then InputRE:FireServer("guard", true)
	elseif k == Enum.KeyCode.G then InputRE:FireServer("counter")
	elseif k == Enum.KeyCode.X then InputRE:FireServer("form1")
	elseif k == Enum.KeyCode.Z then InputRE:FireServer("final")
	elseif k == Enum.KeyCode.T then InputRE:FireServer("ult")
	end
end)
UserInputService.InputEnded:Connect(function(input)
	local k = input.KeyCode
	if k == Enum.KeyCode.W then held.W = false
	elseif k == Enum.KeyCode.A then held.A = false
	elseif k == Enum.KeyCode.S then held.S = false
	elseif k == Enum.KeyCode.D then held.D = false
	elseif k == Enum.KeyCode.F then InputRE:FireServer("guard", false)
	end
end)

---------------------------------------------------------------- UI
local function bar(parent, pos, size, fillColor)
	local back = mk("Frame", { Position = pos, Size = size, BackgroundColor3 = Color3.fromRGB(12, 12, 20), BackgroundTransparency = 0.25, BorderSizePixel = 0 }, parent)
	local fill = mk("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = fillColor, BorderSizePixel = 0 }, back)
	return back, fill
end

local panels = {}
local function fighterPanel(side)
	local left = side == "Blue"
	local p = mk("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0, 320, 0, 78),
		Position = left and UDim2.new(0, 16, 0, 12) or UDim2.new(1, -336, 0, 12) })
	local name = mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), Font = Enum.Font.GothamBlack, TextSize = 18,
		TextColor3 = left and BLUE or VIOLET, TextXAlignment = left and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right, Text = left and "KAEL" or "REN" }, p)
	local hpBack, hpFill = bar(p, UDim2.new(0, 0, 0, 22), UDim2.new(1, 0, 0, 14), left and BLUE or VIOLET)
	local pwBack, pwFill = bar(p, UDim2.new(0, 0, 0, 42), UDim2.new(1, 0, 0, 12), left and CYAN or Color3.fromRGB(200, 150, 255))
	for _, frac in ipairs({ 0.5, 1 }) do        -- visible thresholds at 50% and 100%
		mk("Frame", { Position = UDim2.new(frac, frac == 1 and -2 or -1, 0, -2), Size = UDim2.new(0, 2, 1, 4), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, pwBack)
	end
	mk("TextLabel", { BackgroundTransparency = 1, Position = UDim2.new(0.5, -12, 1, 0), Size = UDim2.new(0, 24, 0, 12), Font = Enum.Font.Gotham, TextSize = 10, TextColor3 = Color3.new(1, 1, 1), Text = "50" }, pwBack)
	mk("TextLabel", { BackgroundTransparency = 1, Position = UDim2.new(1, -26, 1, 0), Size = UDim2.new(0, 26, 0, 12), Font = Enum.Font.Gotham, TextSize = 10, TextColor3 = Color3.new(1, 1, 1), Text = "100" }, pwBack)
	local form = mk("TextLabel", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, 58), Size = UDim2.new(1, 0, 0, 16), Font = Enum.Font.GothamMedium, TextSize = 13,
		TextColor3 = Color3.new(1, 1, 1), TextXAlignment = left and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right, Text = "" }, p)
	panels[side] = { root = p, hp = hpFill, pw = pwFill, form = form, name = name }
end
fighterPanel("Blue"); fighterPanel("Purple")

-- move bar
local moveBar = mk("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.new(0, 760, 0, 66) })
local slots = {}
local SLOT = {
	Kael = { { "LMB", "Combo" }, { "Q", "Flash Step" }, { "E", "Arc Breaker" }, { "R", "Sky Current" }, { "C", "Static Slip" }, { "F", "Guard" }, { "G", "Counter" }, { "X", "Charged" }, { "Z", "Ascension" }, { "T", "Thunderfall" } },
	Ren = { { "LMB", "Combo" }, { "Q", "Anchor Step" }, { "E", "Gravity Pulse" }, { "F", "Rift Guard" }, { "G", "Void Counter" }, { "X", "Rift Mode" }, { "Z", "Eclipse Form" }, { "T", "Event Horizon" } },
}
local slotChar = nil
local function buildSlots(char)
	for _, s in ipairs(slots) do s.root:Destroy() end
	slots = {}
	local list = SLOT[char]
	local w = 72
	for i, def in ipairs(list) do
		local root = mk("Frame", { Position = UDim2.new(0, (i - 1) * (w + 2), 0, 0), Size = UDim2.new(0, w, 1, 0), BackgroundColor3 = Color3.fromRGB(14, 14, 24), BackgroundTransparency = 0.2, BorderSizePixel = 0 }, moveBar)
		mk("UICorner", { CornerRadius = UDim.new(0, 6) }, root)
		local stroke = mk("UIStroke", { Color = Color3.fromRGB(70, 70, 100), Thickness = 1 }, root)
		local cd = mk("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 0), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 2 }, root)
		mk("TextLabel", { BackgroundTransparency = 1, Position = UDim2.new(0, 4, 0, 2), Size = UDim2.new(1, -8, 0, 16), Font = Enum.Font.GothamBlack, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 240, 160), Text = def[1], ZIndex = 3 }, root)
		local label = mk("TextLabel", { BackgroundTransparency = 1, Position = UDim2.new(0, 2, 0, 22), Size = UDim2.new(1, -4, 0, 28), Font = Enum.Font.GothamMedium, TextSize = 11, TextWrapped = true, TextColor3 = Color3.new(1, 1, 1), Text = def[2], ZIndex = 3 }, root)
		local note = mk("TextLabel", { BackgroundTransparency = 1, Position = UDim2.new(0, 2, 1, -16), Size = UDim2.new(1, -4, 0, 14), Font = Enum.Font.Code, TextSize = 11, TextColor3 = Color3.fromRGB(190, 230, 255), Text = "", ZIndex = 3 }, root)
		slots[i] = { root = root, stroke = stroke, cd = cd, label = label, note = note, key = def[1], name = def[2] }
	end
	moveBar.Size = UDim2.new(0, #list * (w + 2), 0, 66)
	slotChar = char
end

-- left panel: preview controls + mode switch
local panel = mk("Frame", { BackgroundColor3 = Color3.fromRGB(10, 10, 18), BackgroundTransparency = 0.3, BorderSizePixel = 0, Position = UDim2.new(0, 16, 0.5, -150), Size = UDim2.new(0, 190, 0, 300) })
mk("UICorner", { CornerRadius = UDim.new(0, 8) }, panel)
mk("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, panel)
mk("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, panel)
local order = 0
local function header(text)
	order += 1
	mk("TextLabel", { LayoutOrder = order, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16), Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = Color3.fromRGB(190, 200, 255), TextXAlignment = Enum.TextXAlignment.Left, Text = text }, panel)
end
local function buttonRow(items, onClick, studioOnly, cinematicOnly)
	order += 1
	local row = mk("Frame", { LayoutOrder = order, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24) }, panel)
	mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 3) }, row)
	local btns = {}
	for _, it in ipairs(items) do
		local b = mk("TextButton", { Size = UDim2.new(1 / #items, -3, 1, 0), BackgroundColor3 = Color3.fromRGB(40, 44, 70), TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamMedium, TextSize = 12, Text = it[1], AutoButtonColor = true }, row)
		mk("UICorner", { CornerRadius = UDim.new(0, 5) }, b)
		b.MouseButton1Click:Connect(function() onClick(it[2], it[1]) end)
		btns[it[2]] = b
	end
	row:SetAttribute("StudioOnly", studioOnly or false)
	row:SetAttribute("CinematicOnly", cinematicOnly or false)
	return row, btns
end
local function cin(cmd) stage:SetAttribute("CinCmd", cmd .. ":" .. tostring(os.clock())) end
header("MODE  (Tab)")
buttonRow({ { "Playable", "Play" }, { "Cinematic", "Cinematic" } }, function(v) setMode(v) end)
header("CINEMATIC")
buttonRow({ { "Replay R", "replay" }, { "Slow B", "slow" } }, function(v) cin(v) end, false, true)
buttonRow({ { "VFX V", "vfx" }, { "Contact C", "inspect" } }, function(v) cin(v) end, false, true)
header("PLAY AS")
buttonRow({ { "Kael", "Blue" }, { "Ren", "Purple" } }, function(v) ControlRE:FireServer("select", v) end)
header("DUMMY")
buttonRow({ { "Idle", "Idle" }, { "Guard", "Guard" }, { "Attack", "Attack" } }, function(v) ControlRE:FireServer("ai", v) end)
header("FORM  (Studio preview)")
buttonRow({ { "Base", "Base" }, { "First", "Form1" }, { "Final", "Final" } }, function(v) ControlRE:FireServer("preview", v) end, true)
buttonRow({ { "Reset fight", "reset" } }, function() ControlRE:FireServer("reset") end)

local function updatePanelVisibility()
	local cinematic = not playing()
	panel.Visible = playing() or stage:GetAttribute("UIVisible") == true      -- hidden during cinematic playback; H shows it
	for _, c in ipairs(panel:GetChildren()) do
		if c:IsA("Frame") then
			local so, co = c:GetAttribute("StudioOnly"), c:GetAttribute("CinematicOnly")
			c.Visible = (not so or isStudio) and (not co or cinematic)
		end
	end
end

RunService.RenderStepped:Connect(function()
	local play = playing()
	updatePanelVisibility()
	moveBar.Visible, panels.Blue.root.Visible, panels.Purple.root.Visible = play, play, play
	if not play or not lastSnap then return end
	for side, p in pairs(panels) do
		local s = lastSnap[side]
		if s then
			p.hp.Size = UDim2.new(math.clamp(s.hp / Config.hpMax, 0, 1), 0, 1, 0)
			p.pw.Size = UDim2.new(math.clamp(s.meter / Config.meter.max, 0, 1), 0, 1, 0)
			local txt = s.form == "Base" and (s.meter >= Config.meter.final and "100% - press Z" or (s.meter >= Config.meter.form1 and "50% - press X" or "")) or
				(s.form == "Form1" and "FIRST FORM" or string.format("FINAL FORM  %.1fs%s", s.finalLeft, s.ultReady and "  - T ready" or ""))
			p.form.Text = txt
			p.name.Text = (s.char == "Kael" and "KAEL" or "REN") .. (side == ctl and "  (you)" or "  (dummy: " .. aiMode .. ")")
		end
	end
	local me = lastSnap[ctl]
	if not me then return end
	if slotChar ~= me.char then buildSlots(me.char) end
	local now = os.clock()
	for _, sl in ipairs(slots) do
		local left, note, hot, name = 0, "", false, sl.name
		local cd = me.cd
		if me.char == "Kael" then
			if sl.key == "Q" then left = (cd.flashCharges or 1) > 0 and 0 or (cd.flashNext or 0); note = "x" .. (cd.flashCharges or 0); name = "Flash Step"
			elseif sl.key == "E" then left = cd.arc or 0; name = me.form == "Final" and "Storm Pierce" or "Arc Breaker"
			elseif sl.key == "R" then left = (me.followLeft > 0) and 0 or (cd.sky or 0); if me.followLeft > 0 then note, hot = "again!", true end
			elseif sl.key == "C" then left = cd.slip or 0
			elseif sl.key == "G" then hot = me.counterLeft > 0; note = hot and string.format("%.1f", me.counterLeft) or ""
			end
		else
			if sl.key == "Q" then left = cd.anchor or 0
			elseif sl.key == "E" then left = cd.pulse or 0
			elseif sl.key == "F" then name = me.form == "Final" and "Eclipse Guard" or "Rift Guard"; hot = me.state == "block"; if me.stored then note = "stored" end
			elseif sl.key == "G" then hot = me.counterLeft > 0; note = hot and string.format("%.1f", me.counterLeft) or ""
			end
		end
		if sl.key == "X" then hot = me.form == "Base" and me.meter >= Config.meter.form1; left = hot and 0 or ((me.form == "Base") and 0 or 0)
		elseif sl.key == "Z" then hot = me.form ~= "Final" and me.meter >= Config.meter.final
		elseif sl.key == "T" then hot = me.ultReady end
		sl.label.Text = name
		sl.note.Text = note
		local maxCd = 1
		if left > 0 then
			local key = ({ Q = "flash", E = "arc", R = "sky", C = "slip" })[sl.key]
			maxCd = (me.char == "Kael") and (Config.cd.Kael[key or ""] or 5) or (Config.cd.Ren[({ Q = "anchor", E = "pulse" })[sl.key] or ""] or 8)
		end
		sl.cd.Size = UDim2.new(1, 0, left > 0 and math.clamp(left / maxCd, 0, 1) or 0, 0)
		sl.stroke.Color = hot and Color3.fromRGB(255, 235, 120) or Color3.fromRGB(70, 70, 100)
		sl.stroke.Thickness = hot and 2 or 1
	end
end)

-- first mode sync + camera hand-over notes
stage:GetAttributeChangedSignal("Mode"):Connect(function()
	if playing() then
		held.W, held.A, held.S, held.D = false, false, false, false
		Style.setEnabled(true)
	end
end)
print("[BG] client ready. Tab = playable / cinematic. In Studio: use the left panel to pick the fighter, dummy mode and form.")
