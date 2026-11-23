-- BGDuelPlayer (LocalScript, StarterPlayer > StarterPlayerScripts): plays BGDuel (teen Gojo vs Toji, 4:00 + 0:20 epilogue).
-- Playback is by ELAPSED time. Every state (glasses, spear, chain, tiles, lighting, costume) is a pure function of the frame,
-- so selecting any chapter starts it correctly. Runs while stage Mode == "Cinematic"; Mode "Preview" is the neutral-light character preview.
--
--  1-9, 0, -, =  jump to chapter 1-12 (10 = Unlimited Void, 11 = its 0.2 s application, 12 = Shibuya Toji)    [ ]  previous / next chapter    R  full replay    Space  pause    , .  step a frame
--  B    slow motion (also automatic on the first Infinity stop and before Purple)    V  effects on/off
--  F    fixed wide camera (animation check)    N  neutral light    H  show/hide HUD + panel    C  contact checks    P  character preview
--  Preview: Left/Right = front / profile / fight camera / close-ups, G = glasses on/off, N = neutral light.   Tab = playable mode.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local Engine = require(ReplicatedStorage:WaitForChild("BGEngine"))
local D = require(ReplicatedStorage:WaitForChild("BGDuel"))
local Cloth = require(ReplicatedStorage:WaitForChild("BGCloth"))
local Rig = require(ReplicatedStorage:WaitForChild("BGRig"))
local Style = require(ReplicatedStorage:WaitForChild("BGStyle"))
local Look = require(ReplicatedStorage:WaitForChild("BGLook"))

local stage = Workspace:WaitForChild("Showcase")
while not stage:GetAttribute("Ready") do task.wait(0.1) end
local function mode() return stage:GetAttribute("Mode") end
local function active() local m = mode() return m == "Cinematic" or m == "Preview" end

local BLUE, RED, VIOLET = Color3.fromRGB(70, 150, 255), Color3.fromRGB(255, 70, 70), Color3.fromRGB(170, 90, 255)
local fighters = { Blue = stage:WaitForChild("Blue"), Purple = stage:WaitForChild("Purple") }
local motors, cloth, eyeMotors = {}, {}, { Blue = {}, Purple = {} }
local R
for id, model in pairs(fighters) do
	Rig.waitReady(model)
	local defs, sizes, m = Rig.read(model)
	if not R then R = Engine.newRig(defs, sizes) end
	motors[id], cloth[id] = m, Cloth.new(model)
	for _, d in ipairs(model:GetDescendants()) do if d:IsA("Motor6D") and d:GetAttribute("EyeJoint") then table.insert(eyeMotors[id], d) end end
end
local tracks, info = Engine.bake(R, D.engineData())
local stopC, spearC = info[1], info[2]
print(string.format("[DUEL] baked %d frames (%.1f s). fist-stop plane at x=%.2f", D.frames, D.duration, stopC.plane.X))

---------------------------------------------------------------- state
local state = { t = 0, playing = true, speed = 1, fx = true, fixed = false, neutral = false, evIdx = 1, lastFrame = -1, wall0 = os.clock(), loops = 0, view = 1, glasses = true, chapter = 1 }
local hudOn = false
local fxFolder = Workspace:FindFirstChild("BGDuelFX")
if fxFolder then fxFolder:Destroy() end
fxFolder = Instance.new("Folder"); fxFolder.Name = "BGDuelFX"; fxFolder.Parent = Workspace
local rng = Random.new(7)
local snap = {}
local function headOf(id) return snap[id] and snap[id].off:PointToWorldSpace(snap[id].out.cf.Head.Position) or Vector3.new(0, 4, 0) end
local function bodyAt(id, f) local P = Engine.eval(R, tracks[id], f / D.fps) return P end
local function headAt(id, f) local P = Engine.eval(R, tracks[id], f / D.fps) return Engine.solve(R, P).cf.Head.Position end

local function applyPose(t, shift)
	for id, model in pairs(fighters) do
		local P = Engine.eval(R, tracks[id], t)
		local out = Engine.solve(R, P)
		local off = (shift and shift[id]) or CFrame.new()
		model.HumanoidRootPart.CFrame = off * out.hrp
		for jn, rt in pairs(out.rot) do motors[id][jn].Transform = rt end
		snap[id] = { P = P, out = out, off = off }
	end
end
local function keyLerp(keys, frame, field)
	local a, b = keys[1], keys[#keys]
	for i, k in ipairs(keys) do if k.f <= frame then a = k; b = keys[math.min(i + 1, #keys)] end end
	if b.f == a.f then return a[field] end
	local u = math.clamp((frame - a.f) / (b.f - a.f), 0, 1)
	u = u * u * (3 - 2 * u)
	return a[field] + (b[field] - a[field]) * u
end

---------------------------------------------------------------- helper builders
local function mk(shape, size, color, material, transparency)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material, p.Color, p.Transparency, p.Size = material or Enum.Material.SmoothPlastic, color, transparency or 0, size
	if shape then p.Shape = shape end
	p.Parent = fxFolder
	return p
end
local function ease(u) return u * u * (3 - 2 * u) end
local function easeOut(u) return 1 - (1 - u) ^ 3 end
local function easeIn(u) return u * u end
local function clamp01(x) return math.clamp(x, 0, 1) end

---------------------------------------------------------------- scene objects (stateless functions of the frame)
-- pebble (chapter 2, attempt 1)
local pebble = mk(Enum.PartType.Ball, Vector3.new(0.16, 0.16, 0.16), Color3.fromRGB(110, 108, 114), Enum.Material.Slate)
local function updatePebble(f)
	local p = D.fx.pebble
	if not state.fx or f < p.f0 or f > p.f1 + 60 then pebble.Transparency = 1; return end
	pebble.Transparency = 0
	local hg = headAt("Blue", p.f0 + 28)
	local target = hg + Vector3.new(-0.5 - p.stopGap, -0.12, 0.55)
	local start = hg + Vector3.new(p.startOff[1], p.startOff[2], p.startOff[3] + 0.4)
	local u = clamp01((f - p.f0) / 28)
	local pos = start:Lerp(target, easeOut(u))                                  -- decelerates and stops beside the cheek
	if f > p.f1 + 8 then local k = (f - p.f1 - 8) / 30; pos = Vector3.new(target.X, math.max(0.1, target.Y - 0.5 * 22 * k * k), target.Z) end
	pebble.Position = pos
end

-- Infinity stops: the field disc, a ripple and the dust suspended at the boundary
local stopObjs = {}
do
	local c = stopC
	local n = c.n
	local fieldPart = mk(Enum.PartType.Cylinder, Vector3.new(0.06, 3.2, 3.2), Color3.fromRGB(200, 215, 255), Enum.Material.SmoothPlastic, 1)
	local ripple = mk(Enum.PartType.Cylinder, Vector3.new(0.04, 1, 1), Color3.fromRGB(225, 232, 255), Enum.Material.SmoothPlastic, 1)
	local dust = {}
	for i = 1, 16 do
		local hover = c.plane + Vector3.new(0, rng:NextNumber(-0.9, 0.9), 0) + Vector3.new(-n.Z, 0, n.X) * rng:NextNumber(-0.9, 0.9) - n * rng:NextNumber(0, 0.4)
		dust[i] = { part = mk(nil, Vector3.new(0.1, 0.08, 0.1) * rng:NextNumber(0.8, 1.6), Color3.fromRGB(176, 172, 164), Enum.Material.Slate), hover = hover,
			from = hover + n * rng:NextNumber(2.5, 4), arrive = D.fx.infinityStops[1].f0 - 6 + rng:NextInteger(0, 8), fall = rng:NextNumber(0, 18) }
	end
	stopObjs = { field = fieldPart, ripple = ripple, dust = dust, n = n, c = c }
end
local function updateStops(f)
	local s = D.fx.infinityStops[1]
	local o = stopObjs
	local on = state.fx and f >= s.f0 - 8 and f <= s.f1
	local center = o.c.plane
	o.field.Transparency = on and 0.85 or 1
	o.field.CFrame = CFrame.lookAt(center, center + o.n) * CFrame.Angles(0, math.rad(90), 0)
	local ph = ((f - s.f0) % 20) / 20
	o.ripple.Size = Vector3.new(0.04, 0.5 + 2.8 * ph, 0.5 + 2.8 * ph)
	o.ripple.CFrame = o.field.CFrame
	o.ripple.Transparency = on and (0.4 + 0.6 * ph) or 1
	for _, d in ipairs(o.dust) do
		if not on then d.part.Transparency = 1
		else
			d.part.Transparency = 0
			if f < d.arrive then
				local u = clamp01((f - (s.f0 - 14)) / math.max(d.arrive - (s.f0 - 14), 1))
				d.part.Position = d.from:Lerp(d.hover, easeOut(u))
			elseif f < s.f1 - 20 + d.fall then
				d.part.Position = d.hover + Vector3.new(0, math.sin((f - d.arrive) * 0.1) * 0.015, 0)
			else
				local k = (f - (s.f1 - 20 + d.fall)) / 30
				d.part.Position = Vector3.new(d.hover.X, math.max(0.1, d.hover.Y - 0.5 * 22 * k * k), d.hover.Z)
			end
		end
	end
end

-- tiles, slab, Blue
local tiles = {}
for _, t in ipairs(stage:WaitForChild("Tiles"):GetChildren()) do
	table.insert(tiles, { part = t, home = t.CFrame, x = t.Position.X, z = t.Position.Z, col = t:GetAttribute("Col"), row = t:GetAttribute("Row"), j = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) })
end
local slabTile
for _, t in ipairs(tiles) do if t.col == 1 and t.row == 0 then slabTile = t end end
local bluePt = Vector3.new(D.fx.blue.point[1], D.fx.blue.point[2], D.fx.blue.point[3])
local pt1 = mk(Enum.PartType.Ball, Vector3.new(0.5, 0.5, 0.5), BLUE, Enum.Material.Neon, 1)
local grit = {}
for i = 1, 16 do
	grit[i] = { part = mk(nil, Vector3.new(0.12, 0.09, 0.11) * rng:NextNumber(0.8, 1.6), Color3.fromRGB(150, 146, 140), Enum.Material.Slate),
		home = Vector3.new(rng:NextNumber(-8, 3), 0.12, rng:NextNumber(-3.5, 3.5)), delay = rng:NextNumber(0, 18), swirl = rng:NextNumber(-1, 1) }
end
local function tileTilt(t, f)
	local b = D.fx.blue
	if f < b.tilt0 then return CFrame.new() end
	local u = clamp01((f - b.tilt0) / 40)
	local toPt = Vector3.new(bluePt.X - t.x, 0, bluePt.Z - t.z)
	local dist = toPt.Magnitude
	if dist > 14 or dist < 0.01 then return CFrame.new() end
	local axis = Vector3.new(-toPt.Z, 0, toPt.X).Unit
	local settle = f > b.f1 - 20 and clamp01(1 - (f - (b.f1 - 20)) / 40) or 1
	return CFrame.fromAxisAngle and CFrame.fromAxisAngle(axis, math.rad(9) * u * settle * (1 - dist / 14)) or CFrame.new()
end
local function updateBlue(f)
	local b = D.fx.blue
	local on = state.fx
	-- grit first
	for _, g in ipairs(grit) do
		if not on or f < b.f0 or f > b.f1 + 20 then g.part.Transparency = 1; g.part.Position = g.home
		else
			g.part.Transparency = 0
			local u = clamp01((f - b.f0 - g.delay) / 50)
			local mid = bluePt:Lerp(g.home, 1 - easeIn(u)) 
			local perp = Vector3.new(-(bluePt.Z - g.home.Z), 0, bluePt.X - g.home.X).Unit * g.swirl * (1 - u) * u * 2
			local pos = g.home:Lerp(bluePt, easeIn(u) * 0.85) + perp
			if f > b.f1 - 10 then local k = clamp01((f - (b.f1 - 10)) / 20); pos = pos:Lerp(Vector3.new(pos.X, 0.1, pos.Z), k) end
			g.part.Position = pos
		end
	end
	-- loose tiles tilt toward the point, a larger slab slides in and carries Toji up
	for _, t in ipairs(tiles) do
		local cf = t.home
		if on then cf = t.home * tileTilt(t, f) end
		if on and t == slabTile and f >= b.slab0 then
			local tj = bodyAt("Purple", 1690)
			local pTj = Vector3.new(tj.rx, 0.3, tj.rz)
			local pos
			if f < 1690 then pos = t.home.Position:Lerp(pTj, easeOut(clamp01((f - b.slab0) / (1690 - b.slab0))))
			elseif f <= 1744 then local p = bodyAt("Purple", f); pos = Vector3.new(p.rx, math.max(0.3, p.gy - 0.25), p.rz)
			else local k = clamp01((f - 1744) / 40); local p = bodyAt("Purple", 1744); pos = Vector3.new(p.rx, 0.3, p.rz):Lerp(bluePt * Vector3.new(1, 0, 1) + Vector3.new(0, 0.3, 0), easeOut(k)) end
			local tilt = (f >= 1690 and f <= 1744) and math.rad(-18) or 0
			cf = CFrame.new(pos) * CFrame.Angles(0, 0, tilt)
		end
		t.part.CFrame = cf
	end
	pt1.Transparency = (on and f >= b.f0 + 10 and f <= b.f1 - 20) and 0 or 1
	pt1.Position = bluePt
	local s = 0.5 + 0.08 * math.sin(f * 0.4)
	pt1.Size = Vector3.new(s, s, s)
end

-- Fly Heads, spear fold, RCT, red core, purple, void
local fly = {}
for i = 1, D.fx.flyHeads.count do
	fly[i] = { part = mk(Enum.PartType.Ball, Vector3.new(0.3, 0.26, 0.3), Color3.fromRGB(96, 82, 112), Enum.Material.SmoothPlastic, 1), r = rng:NextNumber(1.6, 4.2), a = rng:NextNumber(0, 6.28), s = rng:NextNumber(1.2, 3.2), h = rng:NextNumber(-1.2, 1.8) }
end
local function updateFly(f)
	local fh = D.fx.flyHeads
	local on = state.fx and f >= fh.f0 and f <= fh.f1
	local c = headOf("Blue")
	for _, p in ipairs(fly) do
		if not on then p.part.Transparency = 1
		else
			local ramp = math.min((f - fh.f0) / 12, (fh.f1 - f) / 12, 1)
			p.part.Transparency = 1 - clamp01(ramp)
			local a = p.a + f / 30 * p.s
			p.part.Position = c + Vector3.new(math.cos(a) * p.r, p.h + math.sin(a * 1.7) * 0.5, math.sin(a) * p.r * 0.7)
		end
	end
end
local foldRing = mk(Enum.PartType.Cylinder, Vector3.new(0.05, 1, 1), Color3.fromRGB(240, 244, 255), Enum.Material.Neon, 1)
local foldDisc = mk(Enum.PartType.Cylinder, Vector3.new(0.06, 1, 1), Color3.fromRGB(190, 205, 255), Enum.Material.SmoothPlastic, 1)
local function updateFold(f)
	local fo = D.fx.fold
	if not state.fx or f < fo.f or f > fo.f + fo.dur + 10 then foldRing.Transparency, foldDisc.Transparency = 1, 1; return end
	local u = clamp01((f - fo.f) / fo.dur)
	local hc = spearC.Hc
	local cf = CFrame.new(hc) * CFrame.Angles(0, 0, math.rad(0))
	local d = 3.2 * (1 - easeOut(u)) + 0.4                      -- a small section folds inward
	foldRing.Size = Vector3.new(0.05, d, d); foldRing.CFrame = cf; foldRing.Transparency = 0.1 + 0.9 * u
	foldDisc.Size = Vector3.new(0.06, 3.0, 3.0); foldDisc.CFrame = cf * CFrame.new(-0.25 * (1 - u), 0, 0); foldDisc.Transparency = 0.5 + 0.5 * u
end
local rctEm
do
	local torso = fighters.Blue:FindFirstChild("UpperTorso")
	rctEm = Instance.new("ParticleEmitter")
	rctEm.Name = "BGRct"
	rctEm.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	rctEm.Color = ColorSequence.new(Color3.fromRGB(215, 255, 232)); rctEm.LightEmission = 0.8; rctEm.Rate = 0
	rctEm.Lifetime = NumberRange.new(0.8, 1.4); rctEm.Speed = NumberRange.new(0.6, 1.6); rctEm.EmissionDirection = Enum.NormalId.Top
	rctEm.Size = NumberSequence.new(0.14, 0); rctEm.Transparency = NumberSequence.new(0.3, 1)
	rctEm.Parent = torso
end
local redCore = mk(Enum.PartType.Ball, Vector3.new(0.4, 0.4, 0.4), RED, Enum.Material.Neon, 1)
local redDust = {}
for i = 1, 24 do redDust[i] = { part = mk(nil, Vector3.new(0.14, 0.1, 0.12), Color3.fromRGB(150, 146, 140), Enum.Material.Slate, 1), dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0, 0.6), rng:NextNumber(-1, 1)).Unit, d = rng:NextNumber(1.5, 5) } end
local function updateRed(f)
	local r = D.fx.red
	local on = state.fx and f >= r.f0 - 12 and f <= r.f1 + 30
	local p = Vector3.new(r.point[1], r.point[2], r.point[3])
	local u = clamp01((f - (r.f0 - 6)) / 14)
	redCore.Transparency = (on and f >= r.f0 - 8 and f <= r.f1) and 0 or 1
	local s = 0.3 + 0.5 * math.sin(math.pi * clamp01((f - (r.f0 - 8)) / (r.f1 - r.f0 + 8)))
	redCore.Size = Vector3.new(s, s, s); redCore.Position = p
	for _, d in ipairs(redDust) do        -- dust runs AWAY from the core: the reverse of Blue's inward pull
		if not on or f < r.f0 - 2 then d.part.Transparency = 1
		else
			d.part.Transparency = 0
			local k = easeOut(clamp01((f - (r.f0 - 2)) / 26))
			d.part.Position = p * Vector3.new(1, 0, 1) + Vector3.new(0, 0.2, 0) + d.dir * d.d * k * Vector3.new(1, 0.4, 1)
		end
	end
end

local ptBlue = mk(Enum.PartType.Ball, Vector3.new(0.5, 0.5, 0.5), BLUE, Enum.Material.Neon, 1)
local ptRed = mk(Enum.PartType.Ball, Vector3.new(0.5, 0.5, 0.5), RED, Enum.Material.Neon, 1)
local core = mk(Enum.PartType.Ball, Vector3.new(0.4, 0.4, 0.4), VIOLET, Enum.Material.Neon, 1)
local beam = mk(Enum.PartType.Cylinder, Vector3.new(1, 0.6, 0.6), VIOLET, Enum.Material.Neon, 1)
local beamCore = mk(Enum.PartType.Cylinder, Vector3.new(1, 0.2, 0.2), Color3.new(1, 1, 1), Enum.Material.Neon, 1)
local function updatePurple(f)
	local P = D.fx.purple
	local on = state.fx
	local g = snap.Blue and snap.Blue.out.cf.UpperTorso.Position or Vector3.new(12.4, 4.5, 0)
	local gp = Engine.solve(R, bodyAt("Blue", math.min(f, 6900)))
	local center = gp.cf.UpperTorso.Position + Vector3.new(-2.6, 0.7, 0)
	local show = on and f >= P.blue0 and f < P.merge
	ptBlue.Transparency, ptRed.Transparency = show and 0 or 1, show and 0 or 1
	if show then
		local u = clamp01((f - P.red0) / (P.merge - P.red0))
		local bu = clamp01((f - P.blue0) / 60)
		ptBlue.Position = (center + Vector3.new(0.5, 0.2, 1.8)):Lerp(center, ease(u)) * bu + center * (1 - bu)
		ptRed.Position = (center + Vector3.new(0.5, 0.2, -1.8)):Lerp(center, ease(u))
		ptRed.Transparency = f >= P.red0 and 0 or 1
	end
	core.Transparency = (on and f >= P.merge and f < P.beam1 + 20) and 0 or 1
	local cs = 0.5 + 0.35 * clamp01((f - P.merge) / (P.release - P.merge)); if f > P.release then cs = 0.9 * (1 - clamp01((f - P.release) / 25)) end
	core.Size = Vector3.new(cs, cs, cs); core.Position = center
	if on and f >= P.release and f < P.beam1 + 20 then
		local grow = easeOut(clamp01((f - P.release) / 6))
		local len = 42 * grow
		local thick = (f < P.beam1) and 0.9 or 0.9 * (1 - clamp01((f - P.beam1) / 20))
		local cx = center.X - len / 2
		beam.Size = Vector3.new(math.max(len, 0.1), math.max(thick, 0.02), math.max(thick, 0.02)); beam.CFrame = CFrame.new(cx, center.Y, P.laneZ); beam.Transparency = 0.1
		beamCore.Size = Vector3.new(math.max(len, 0.1), math.max(thick * 0.32, 0.01), math.max(thick * 0.32, 0.01)); beamCore.CFrame = beam.CFrame; beamCore.Transparency = 0
		-- the clean path: tiles along the lane and the pillar's jagged top are erased as the beam passes
		for _, t in ipairs(tiles) do
			if math.abs(t.z - P.laneZ) < 2.6 and t.x > center.X - len then t.part.Transparency = 1 end
		end
		local jag = stage:FindFirstChild("PillarJag")
		if jag and center.X - len < -4 then jag.Transparency = 1 end
	else
		beam.Transparency, beamCore.Transparency = 1, 1
	end
end
local function resetLane()
	for _, t in ipairs(tiles) do t.part.Transparency = 0 end
	local jag = stage:FindFirstChild("PillarJag"); if jag then jag.Transparency = 0 end
end

-- chain of a thousand miles (spear tip to the curse's mouth), glasses prop, void field, dummy
local links = {}
for i = 1, 20 do links[i] = mk(nil, Vector3.new(0.2, 0.1, 0.4), Color3.fromRGB(58, 60, 70), Enum.Material.Metal, 1) end
local function spearTip()
	local hand = fighters.Purple:FindFirstChild("RightHand")
	return hand and (hand.CFrame * CFrame.new(0, -0.1, -1.5)).Position or Vector3.new()
end
local function curseMouth()
	for _, c in ipairs(fighters.Purple:GetChildren()) do
		if c:IsA("BasePart") and c.Name == "CurseHead3" then return c.Position end
	end
	local ut = fighters.Purple:FindFirstChild("UpperTorso")
	return ut and ut.Position + Vector3.new(0, 0, 0.7) or Vector3.new()
end
local function updateChain(f)
	local ch = D.fx.chain
	local on = state.fx and D.chainVisible(f)
	if not on then for _, l in ipairs(links) do l.Transparency = 1 end return end
	local p0, p2 = spearTip(), curseMouth()
	local off = Vector3.new(0, -1.6, 0)
	if f >= 5466 and f < 5520 then local u = math.sin(math.pi * clamp01((f - 5466) / 54)); off = Vector3.new(-3.2 * u, 0.4, 3.4 * u)               -- the sweep
	elseif f >= 5800 and f < 5830 then off = Vector3.new(0, 0.1, 0)                                                                                   -- the return: taut
	elseif f >= 5956 and f < 5992 then off = Vector3.new(-2.5, 2.8, 0.5) end                                                                          -- airborne: a long arc across the frame
	local mid = (p0 + p2) / 2 + off
	local prev
	for i, l in ipairs(links) do
		local s = (i - 1) / (#links - 1)
		local a = p0:Lerp(mid, s * 2); local b = mid:Lerp(p2, math.max(s * 2 - 1, 0))
		local pos = s < 0.5 and a or b
		l.Transparency = 0
		local nextS = i / (#links - 1)
		local nxt = nextS < 0.5 and p0:Lerp(mid, nextS * 2) or mid:Lerp(p2, math.max(nextS * 2 - 1, 0))
		l.CFrame = CFrame.lookAt(pos, nxt == pos and pos + Vector3.new(0, 0, 1) or nxt) * CFrame.Angles(0, 0, (i % 2) * math.pi / 2)
	end
end

local glassesParts, glassesProp = {}, {}
for _, d in ipairs(fighters.Blue:GetDescendants()) do if d:IsA("BasePart") and d:GetAttribute("Glasses") then table.insert(glassesParts, { part = d, trans = d.Transparency }) end end
do
	local function addProp(size, off, color, shape, trans) local p = mk(shape, size, color, Enum.Material.SmoothPlastic, 1); table.insert(glassesProp, { part = p, off = off, trans = trans or 0 }) end
	for _, ex in ipairs({ -0.29, 0.29 }) do
		addProp(Vector3.new(0.05, 0.36, 0.36), CFrame.new(ex, 0, 0) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(10, 10, 12), Enum.PartType.Cylinder)
		addProp(Vector3.new(0.05, 0.28, 0.28), CFrame.new(ex, 0, -0.025) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(22, 24, 30), Enum.PartType.Cylinder, 0.3)
	end
	addProp(Vector3.new(0.2, 0.04, 0.05), CFrame.new(0, 0.02, 0), Color3.fromRGB(10, 10, 12))
end
local function setGlasses(f)
	local gs = D.glassesState(f)
	local showFace = (gs == "face") and state.glasses and mode() ~= "Preview" or (mode() == "Preview" and state.glasses)
	for _, g in ipairs(glassesParts) do g.part.Transparency = showFace and g.trans or 1 end
	local root
	local A = D.arena
	if gs == "flying" then
		local u = clamp01((f - 2716) / 74)
		local h0 = headAt("Blue", 2716)
		local to = Vector3.new(A.step.x - 0.2, A.step.y + 0.3, 1.6)
		local pos = h0:Lerp(to, easeOut(u)) + Vector3.new(0, 1.6 * math.sin(math.pi * u), 0)
		root = CFrame.new(pos) * CFrame.Angles(u * 9, u * 5, u * 3)
	elseif gs == "step" then root = CFrame.new(A.step.x - 0.2, A.step.y + 0.32, 1.6) * CFrame.Angles(-1.35, 0.4, 0.1)
	elseif gs == "settling" then
		local u = clamp01((f - 7040) / 85)
		root = CFrame.new(A.step.x - 0.2 + 0.5 * easeOut(u), A.step.y + 0.32 - 0.12 * u, 1.6) * CFrame.Angles(-1.35 + 0.5 * u, 0.4 + 0.5 * u, 0.1 + 0.6 * u)
	elseif gs == "settled" then root = CFrame.new(A.step.x + 0.3, A.step.y + 0.2, 1.6) * CFrame.Angles(-0.85, 0.9, 0.7) end
	for _, g in ipairs(glassesProp) do
		g.part.Transparency = (root and state.fx ~= nil and (gs ~= "none") and (gs ~= "face")) and g.trans or 1
		if root then g.part.CFrame = root * g.off end
	end
end

-- epilogue: adult outfit + blindfold, void streaks, a suspended dummy
local adultParts, teenParts, blindR = {}, {}, {}
for _, d in ipairs(fighters.Blue:GetDescendants()) do
	if d:IsA("BasePart") then
		if d:GetAttribute("Adult") then table.insert(adultParts, { part = d, trans = 0 }) end
		if d:GetAttribute("Teen") then table.insert(teenParts, { part = d, trans = d.Transparency }) end
		if d:GetAttribute("Blindfold") then table.insert(blindR, d) end
	end
end
local spearParts, curseParts = {}, {}
for _, d in ipairs(fighters.Purple:GetDescendants()) do if d:IsA("BasePart") and d:GetAttribute("Spear") then table.insert(spearParts, d) end end
local function updateCostumes(f)
	local adult = f >= D.duelFrames
	for _, p in ipairs(adultParts) do p.part.Transparency = adult and 0 or 1 end
	for _, p in ipairs(teenParts) do p.part.Transparency = adult and 1 or p.trans end
	local uncovered = (f >= 8500 and f < 9210) or (f >= 9400 and f < 9446)                      -- eyes uncovered for the domain and the 0.2 s application
	for _, p in ipairs(blindR) do p.Transparency = (adult and not uncovered) and 0 or 1 end
	for _, p in ipairs(spearParts) do p.Transparency = D.spearVisible(f) and 0 or 1 end
	rctEm.Rate = (state.fx and f >= D.fx.rct.f0 and f <= D.fx.rct.f1) and 10 or 0
end
local origLight = { ambient = Lighting.Ambient, out = Lighting.OutdoorAmbient }
local function restoreStage()
	for _, d in ipairs(stage:GetChildren()) do
		if d:IsA("BasePart") and not d:GetAttribute("Invisible") then d.Transparency = 0 end
	end
	for _, t in ipairs(tiles) do t.part.Transparency = 0 end
end


---------------------------------------------------------------- adult chapters, Unlimited Void, Shibuya (all stateless functions of the frame)
local DUSK = { amb = Color3.fromRGB(104, 104, 118), out = Color3.fromRGB(116, 116, 130), bright = 1.6 }
local function uvK(f)             -- 0 = courtyard, 1 = inside the domain
	local u = D.fx.uv
	if f < u.closeStart or f > u.restored then return 0 end
	if f < u.closeEnd then return (f - u.closeStart) / (u.closeEnd - u.closeStart) end
	if f < u.release then return 1 end
	return math.max(0, 1 - (f - u.release) / 20)
end
local function envHide(f)         -- how far the courtyard has dissolved (domain interior, 0.2 s application, Shibuya water)
	local k = uvK(f)
	local o = D.fx.uv02
	if f >= o.f and f < o.f + o.frames then k = 1 end
	local w = D.fx.water
	if f >= w.f0 then k = math.max(k, math.min(1, (f - w.f0) / 40)) end
	return k
end
-- construct: the "appropriate curse opponent" (a lumpy purple-grey body, big head, long arms)
local construct = Instance.new("Model"); construct.Name = "CurseConstruct"; construct.Parent = fxFolder
local cParts = {}
do
	local function cp(size, off, color, shape) local q = mk(shape, size, color, Enum.Material.SmoothPlastic, 1); q.Parent = construct; table.insert(cParts, { part = q, off = off }) return q end
	local body, skin = Color3.fromRGB(96, 80, 108), Color3.fromRGB(128, 110, 140)
	cp(Vector3.new(2.6, 3.2, 1.8), CFrame.new(0, 3.0, 0), body)
	cp(Vector3.new(1.9, 1.6, 1.6), CFrame.new(0, 5.2, -0.2), skin)
	cp(Vector3.new(0.5, 0.3, 0.1), CFrame.new(-0.4, 5.3, -1.05), Color3.fromRGB(240, 236, 220))
	cp(Vector3.new(0.5, 0.3, 0.1), CFrame.new(0.4, 5.3, -1.05), Color3.fromRGB(240, 236, 220))
	cp(Vector3.new(1.2, 0.3, 0.1), CFrame.new(0, 4.8, -1.05), Color3.fromRGB(50, 24, 44))
	cp(Vector3.new(0.9, 3.4, 0.9), CFrame.new(-1.9, 3.2, -0.3), skin)      -- arms
	cp(Vector3.new(0.9, 3.4, 0.9), CFrame.new(1.9, 3.2, -0.3), skin)
	cp(Vector3.new(1.0, 2.4, 1.0), CFrame.new(-0.7, 1.2, 0), body)
	cp(Vector3.new(1.0, 2.4, 1.0), CFrame.new(0.7, 1.2, 0), body)
end
local function constructX(f)
	for _, c in ipairs(D.fx.construct) do if f >= c.f0 and f < c.f1 then return c, c.x end end
end
local function updateConstruct(f)
	local c, x = constructX(f)
	local show = c and state.fx
	local u = D.fx.uv
	local root = CFrame.new((x or 10), 0, 0)
	local wob, stall = 0, 1
	if c and f >= u.f0 and f < u.f1 then
		root = CFrame.new(x - 3 * math.min(1, (f - 8400) / 80), 0, 0)                    -- it charges, then the domain closes on it
		stall = (f >= u.opp0 and f < u.release) and 0.04 or 1                              -- inside: its attempted movement stalls
		wob = math.sin(f * 0.35 * stall) * 0.25
	elseif c and f >= 9300 and f < 9540 then
		stall = (f >= 9420 and f < 9440) and 0.05 or 1
		wob = math.sin(f * 0.3 * stall) * 0.2
	elseif c and f >= 9740 then
		local k = f >= 9968 and math.min(1, (f - 9968) / 14) or 0                        -- Playful Cloud sweep knocks it back across the water
		root = CFrame.new(x + 7 * easeOut(k), 0.8 * math.sin(math.pi * math.min(1, k)), 0)
		wob = k > 0 and k < 1 and 0.3 or 0
	end
	for _, e in ipairs(cParts) do
		e.part.Transparency = show and 0 or 1
		if show then e.part.CFrame = root * CFrame.Angles(0, math.rad(0), wob) * e.off end
	end
end
-- the domain: far luminous centre + layered streams that keep accumulating
local centerBall = mk(Enum.PartType.Ball, Vector3.new(10, 10, 10), Color3.fromRGB(255, 255, 255), Enum.Material.Neon, 1)
local centerLight = Instance.new("PointLight"); centerLight.Range, centerLight.Brightness, centerLight.Color, centerLight.Shadows = 60, 3, Color3.fromRGB(210, 225, 255), false; centerLight.Parent = centerBall
local halos = {}      -- thin luminous rings (48 short Neon segments each), not solid discs
for i = 1, 3 do
	local r = 12 + 8 * i
	local col = (i == 2) and Color3.fromRGB(190, 110, 255) or Color3.fromRGB(110, 170, 255)
	local segs = {}
	for k = 1, 48 do segs[k] = mk(nil, Vector3.new(0.35, 2 * math.pi * r / 48 * 1.15, 0.35), col, Enum.Material.Neon, 1) end
	halos[i] = { r = r, segs = segs }
end
local streams = {}
for i = 1, 420 do
	local layer = (i % 3) + 1
	local col = ({ Color3.fromRGB(90, 160, 255), Color3.fromRGB(240, 244, 255), Color3.fromRGB(185, 110, 255), Color3.fromRGB(255, 140, 170) })[rng:NextInteger(1, 4)]
	streams[i] = { part = mk(nil, Vector3.new(0.05 * layer, 0.05 * layer, 1.5 + layer * 1.6), col, Enum.Material.Neon, 1), layer = layer,
		x = rng:NextNumber(-34, 34), y = rng:NextNumber(-4, 18), z0 = rng:NextNumber(-60, 12), speed = (4 - layer) * 4 + rng:NextNumber(2, 7), born = rng:NextInteger(0, 330) }
end
local domeShell = mk(Enum.PartType.Ball, Vector3.new(36, 36, 36), Color3.fromRGB(70, 80, 120), Enum.Material.SmoothPlastic, 1)
local atmoBase = {}
local function updateDomain(f)
	local k = envHide(f)
	-- courtyard dissolves; light falls with it
	for _, d in ipairs(stage:GetChildren()) do
		if d:IsA("BasePart") and not d:GetAttribute("Invisible") and d.Name ~= "PillarJag" then d.Transparency = (f >= D.fx.water.f0) and 1 or k end
	end
	local dark = math.min(1, uvK(f) + (f >= D.fx.uv02.f and f < D.fx.uv02.f + D.fx.uv02.frames and 1 or 0))
	local bl = Lighting:FindFirstChildOfClass("BloomEffect")
	if bl and mode() == "Cinematic" and not state.neutral then bl.Intensity = 0.2 + 0.9 * dark; bl.Threshold = 2.0 - 1.1 * dark; bl.Size = 12 + 20 * dark end
	if mode() == "Cinematic" and not state.neutral then
		Lighting.Ambient = DUSK.amb:Lerp(Color3.fromRGB(8, 8, 14), dark)
		Lighting.OutdoorAmbient = DUSK.out:Lerp(Color3.fromRGB(8, 8, 14), dark)
		Lighting.Brightness = DUSK.bright * (1 - 0.85 * dark)
		-- the void is black: night sky and no haze (the place's own Atmospheres are scaled down too)
		Lighting.ClockTime = 17.6 * (1 - dark)
		for _, a in ipairs(Lighting:GetChildren()) do
			if a:IsA("Atmosphere") then
				if atmoBase[a] == nil then atmoBase[a] = a.Density end
				a.Density = atmoBase[a] * (1 - dark)
			end
		end
		local bp = Workspace:FindFirstChild("Baseplate")             -- the place's grid floor dissolves with the courtyard
		if bp then
			bp.Transparency = dark
			for _, t in ipairs(bp:GetChildren()) do if t:IsA("Texture") or t:IsA("Decal") then t.Transparency = dark end end
		end
	end
	local u = D.fx.uv
	-- barrier: the shell closes in a wide shot (visible from outside only)
	local cl = (f >= u.closeStart and f < u.release) and ease(clamp01((f - u.closeStart) / (u.closeEnd - u.closeStart))) or 0
	local rel = f >= u.release and f < u.release + 14
	local shell = state.fx and ((cl > 0 and f < u.release) or rel)
	domeShell.Transparency = shell and (rel and (0.5 + 0.5 * (f - u.release) / 14) or (1 - 0.35 * cl)) or 1
	local sz = 52 - 16 * cl; if rel then sz = 36 + 30 * (f - u.release) / 14 end
	domeShell.Size = Vector3.new(sz, sz, sz); domeShell.Position = Vector3.new(7, 4, 0)
	-- interior
	local inside = state.fx and (uvK(f) > 0.5 or (f >= D.fx.uv02.f and f < D.fx.uv02.f + D.fx.uv02.frames))
	centerBall.Transparency = inside and 0.05 or 1
	centerBall.Position = Vector3.new(8, 4, -46)
	centerBall.Size = Vector3.new(10 + math.sin(f * 0.12) * 1.5, 10 + math.sin(f * 0.12) * 1.5, 10 + math.sin(f * 0.12) * 1.5)
	local haloOn = inside and f >= u.closeEnd or (f >= D.fx.uv02.f and f < D.fx.uv02.f + D.fx.uv02.frames)      -- only once the camera is inside the domain
	for i, h in ipairs(halos) do
		local base = CFrame.new(centerBall.Position) * CFrame.Angles(f * 0.01 * i, f * 0.007 * (4 - i), 0)
		for k, sgm in ipairs(h.segs) do
			sgm.Transparency = haloOn and 0.15 or 1
			if haloOn then
				local a = (k - 1) / 48 * 2 * math.pi
				sgm.CFrame = base * CFrame.new(h.r * math.cos(a), h.r * math.sin(a), 0) * CFrame.Angles(0, 0, a)
			end
		end
	end
	local grow = clamp01(((f >= D.fx.uv02.f and f < D.fx.uv02.f + D.fx.uv02.frames) and 330 or (f - u.inside0)) / 330)
	local nShow = math.floor(60 + 360 * grow)                       -- information keeps accumulating while the opponent is stalled
	local rateMul = (f >= u.opp0 and f < u.release) and 1.8 or 1
	for i, s in ipairs(streams) do
		if not inside or i > nShow then s.part.Transparency = 1
		else
			s.part.Transparency = 0.02 + 0.05 * s.layer
			local z = ((s.z0 + (f / 30) * s.speed * rateMul * s.layer * 0.8) % 80) - 62                    -- three depth layers at different speeds
			s.part.CFrame = CFrame.new(8 + s.x * (0.4 + 0.3 * s.layer), s.y * 0.7 + 3, z)
		end
	end
end
-- adult chapter effects: Infinity filter, Maximum Output Blue, blink, curtain
local leaf = mk(nil, Vector3.new(0.36, 0.03, 0.22), Color3.fromRGB(96, 150, 80), Enum.Material.Fabric, 1)
local stone = mk(Enum.PartType.Ball, Vector3.new(0.28, 0.28, 0.28), Color3.fromRGB(110, 108, 114), Enum.Material.Slate, 1)
local mbPoint = mk(Enum.PartType.Ball, Vector3.new(1, 1, 1), BLUE, Enum.Material.Neon, 1)
local curtain = mk(Enum.PartType.Ball, Vector3.new(70, 70, 70), Color3.fromRGB(20, 22, 34), Enum.Material.SmoothPlastic, 1)
local function updateAdult(f)
	local fl = D.fx.filter
	local gx = 6.0
	-- two visibly different incoming objects: the leaf is let through, the stone is stopped
	local lf = state.fx and f >= fl.leaf.f0 and f <= fl.leaf.f1 + 40
	leaf.Transparency = lf and 0 or 1
	if lf then
		local u = clamp01((f - fl.leaf.f0) / (fl.leaf.f1 - fl.leaf.f0))
		leaf.CFrame = CFrame.new(gx - 6 + 12 * u, 3.6 + math.sin(u * 9) * 0.3 - u * 1.0, 0.5 + math.sin(u * 6) * 0.3) * CFrame.Angles(u * 7, u * 3, u * 5)
	end
	local st = state.fx and f >= fl.stone.f0 and f <= fl.stone.f1 + 40
	stone.Transparency = st and 0 or 1
	if st then
		local u = clamp01((f - fl.stone.f0) / 40)
		local x = gx - 6 + (6 - 1.0) * easeOut(u)                        -- decelerates and stops a visible gap short of him
		local drop = f > fl.stone.f1 and (f - fl.stone.f1) / 30 or 0
		stone.Position = Vector3.new(x, math.max(0.15, 3.4 - 0.5 * 22 * drop * drop), 0.55)
	end
	-- Maximum Output Blue: a much larger area of displacement
	local mb = D.fx.maxBlue
	local on = state.fx and f >= mb.f0 and f <= mb.f1
	local pt = Vector3.new(mb.point[1], mb.point[2], mb.point[3])
	mbPoint.Transparency = on and 0 or 1
	mbPoint.Position = pt
	local ms = 1.2 + 0.5 * math.sin(f * 0.3); mbPoint.Size = Vector3.new(ms, ms, ms)
	for _, t in ipairs(tiles) do
		if on or (f > mb.f1 and f < mb.f1 + 30) then
			local ramp = on and math.min(clamp01((f - mb.f0) / 50), clamp01((mb.f1 - f) / 40)) or 0
			local dx, dz = pt.X - t.x, pt.Z - t.z
			local d = math.sqrt(dx * dx + dz * dz)
			if d < mb.radius and d > 0.5 then
				local fall = 1 - d / mb.radius
				local lift = 4.5 * ramp * fall
				t.part.CFrame = CFrame.new(t.x + dx / d * 2.5 * ramp * fall, 0.2 + lift, t.z + dz / d * 2.5 * ramp * fall) * CFrame.Angles(math.sin(t.col * 3) * 0.3 * ramp * fall, 0, math.cos(t.row * 2 + t.col) * 0.3 * ramp * fall)
			end
		end
	end
	local cu = D.fx.curtain
	local cOn = state.fx and f >= cu.f0 and f <= cu.f1
	curtain.Transparency = cOn and (0.72 + 0.28 * math.abs(math.sin(f * 0.15)) * 0) or 1
	curtain.Position = Vector3.new(6, 3, 0)
end
-- Shibuya: water, splashes along Toji's path, Playful Cloud (three sections)
local water = mk(nil, Vector3.new(220, 0.4, 120), Color3.fromRGB(70, 92, 118), Enum.Material.SmoothPlastic, 1)
local rings = {}
for i = 1, 14 do rings[i] = mk(Enum.PartType.Cylinder, Vector3.new(0.05, 1, 1), Color3.fromRGB(220, 232, 245), Enum.Material.SmoothPlastic, 1) end
local splashFrames = { 9806, 9808, 9810, 9812, 9814, 9816, 9818, 9820, 9968, 10106, 10110, 10116, 10124 }
local cloud = { mk(nil, Vector3.new(0.16, 0.16, 1.1), Color3.fromRGB(34, 34, 40), Enum.Material.Metal, 1), mk(nil, Vector3.new(0.16, 0.16, 1.1), Color3.fromRGB(34, 34, 40), Enum.Material.Metal, 1), mk(nil, Vector3.new(0.16, 0.16, 1.1), Color3.fromRGB(34, 34, 40), Enum.Material.Metal, 1) }
local function updateShibuya(f)
	local w = D.fx.water
	local on = f >= w.f0 and f <= w.f1
	water.Transparency = on and 0.15 or 1
	water.Position = Vector3.new(0, -0.15, 0)
	for i, r in ipairs(rings) do
		local sf = splashFrames[i]
		if on and state.fx and sf and f >= sf and f < sf + 22 then
			local u = (f - sf) / 22
			local p = bodyAt("Purple", sf)
			r.Size = Vector3.new(0.05, 0.6 + 5 * easeOut(u), 0.6 + 5 * easeOut(u))
			r.CFrame = CFrame.new(p.rx, 0.1, p.rz) * CFrame.Angles(0, 0, math.rad(90))
			r.Transparency = 0.2 + 0.8 * u
		else r.Transparency = 1 end
	end
	-- Playful Cloud: folded into three sections at rest, extended in a sweep
	local has = f >= 9750 and f <= w.f1
	local hand = fighters.Purple:FindFirstChild("RightHand")
	local open = 0
	if f >= 9960 and f <= 10040 then open = 1 elseif f >= 10112 and f <= 10200 then open = 1 elseif f >= 9806 and f <= 9830 then open = 0.7 end
	for i, c in ipairs(cloud) do
		c.Transparency = (has and hand) and 0 or 1
		if has and hand then
			local base = hand.CFrame * CFrame.new(0, -0.1, -0.3)
			local fold = (1 - open) * (i == 2 and 1.2 or (i == 3 and -1.0 or 0))
			c.CFrame = base * CFrame.new(0, 0, -(i - 1) * 1.15 * (0.55 + 0.45 * open)) * CFrame.Angles(fold, 0, 0)
		end
	end
end
-- curse mouth opens and the spear is drawn out of it (chapter 4 close-up)
local jawMotor
for _, d in ipairs(fighters.Purple:GetDescendants()) do if d:IsA("Motor6D") and d:GetAttribute("JawJoint") then jawMotor = d end end
local emergeProp = {}
for _, spec in ipairs({ { Vector3.new(0.14, 0.14, 1.0), Color3.fromRGB(28, 26, 30), 0 }, { Vector3.new(0.1, 0.26, 0.8), Color3.fromRGB(182, 186, 196), -0.9 } }) do
	table.insert(emergeProp, { part = mk(nil, spec[1], spec[2], Enum.Material.Metal, 1), z = spec[3] })
end
local function updateEmerge(f)
	local e = D.fx.emerge
	local k = 0
	if f >= e.f0 and f <= e.f1 + 10 then k = math.min(clamp01((f - e.f0) / 8), clamp01((e.f1 + 10 - f) / 8)) end
	if jawMotor then jawMotor.Transform = CFrame.Angles(0.75 * k, 0, 0) end
	local skull = fighters.Purple:FindFirstChild("CurseSkull")
	local hand = fighters.Purple:FindFirstChild("RightHand")
	local show = state.fx ~= nil and f >= e.f0 + 6 and f < e.f1 and skull and hand
	for _, p in ipairs(emergeProp) do
		p.part.Transparency = show and 0 or 1
		if show then
			local u = easeOut(clamp01((f - e.f0 - 6) / (e.f1 - e.f0 - 6)))
			local from = (skull.CFrame * CFrame.new(0, -0.35, -0.7)).Position
			local to = (hand.CFrame * CFrame.new(0, -0.1, -0.35)).Position
			local pos = from:Lerp(to, u)
			p.part.CFrame = CFrame.lookAt(pos, pos + (to - from).Unit + Vector3.new(0, 0.001, 0)) * CFrame.new(0, 0, p.z * 0.5)
		end
	end
end

local function updateScene(f)
	updatePebble(f); updateStops(f); updateBlue(f); updateFly(f); updateFold(f); updateRed(f); updatePurple(f); updateChain(f)
	updateEmerge(f); updateAdult(f); updateConstruct(f); updateDomain(f); updateShibuya(f)
end

---------------------------------------------------------------- sound
local master = Instance.new("SoundGroup"); master.Name = "BGDuelMaster"; master.Volume = 0.5; master.Parent = SoundService
local function playCue(name)
	local id = D.soundIds[name]
	if not id or id == "" then return end
	local s = Instance.new("Sound"); s.SoundId, s.Volume, s.SoundGroup, s.Parent = id, 0.7, master, fxFolder
	pcall(function() s:Play() end)
	Debris:AddItem(s, 3)
end
local function musicAt(f)
	local keys = D.music
	local a, b = keys[1], keys[#keys]
	for i, k in ipairs(keys) do if k[1] <= f then a = k; b = keys[math.min(i + 1, #keys)] end end
	if b[1] == a[1] then return a[2] end
	return a[2] + (b[2] - a[2]) * clamp01((f - a[1]) / (b[1] - a[1]))
end
local events = {}
for _, s in ipairs(D.sound) do table.insert(events, s) end
local function bigRing(pos, color, d, dur) Style.ringSlash(pos, color, d, 90, dur, 0); Style.ringSlash(pos, Color3.new(1, 1, 1), d * 0.7, 90, dur * 0.8, 0) end
local function addFn(f, fn) table.insert(events, { f = f, fn = fn }) end
addFn(8620, function() if state.fx then Style.flash(Color3.fromRGB(180, 210, 255), 0.25, 0.5); bigRing(Vector3.new(7, 0.2, 0), Color3.fromRGB(120, 170, 255), 60, 0.7) end end)          -- the barrier starts to close
addFn(8700, function() if state.fx then Style.ink(0.6); Style.speedLines(Color3.fromRGB(190, 220, 255), 0.5, 34); Style.flash(Color3.new(1, 1, 1), 0.45, 0.9) end end)                       -- the camera goes inside
addFn(9050, function() if state.fx then
	Style.ink(0.7); Style.flash(Color3.new(1, 1, 1), 0.8, 1.0); Style.speedLines(Color3.fromRGB(190, 160, 255), 0.7, 36)
	bigRing(Vector3.new(7, 0.2, 0), Color3.fromRGB(190, 150, 255), 90, 0.9); Style.shards(Vector3.new(7, 4, 0), Color3.fromRGB(210, 190, 255), 30, 18); Style.crack(Vector3.new(7, 0, 0), Color3.fromRGB(190, 150, 255), 18, 14)   -- release: shockwave, shards, cracks
end end)
addFn(9420, function() if state.fx then Style.flash(Color3.new(1, 1, 1), 0.3, 1.0); Style.speedLines(Color3.new(1, 1, 1), 0.3, 40); bigRing(Vector3.new(8, 0.2, 0), Color3.fromRGB(200, 220, 255), 50, 0.5) end end)   -- the 0.2 s application
table.sort(events, function(a, b) return a.f < b.f end)

---------------------------------------------------------------- camera
local function resolve(v)
	if v.rel then
		local h = headOf(v.rel)
		-- relative shots face the character: offsets are in the fighter's own frame (x = their right, z = forward toward camera side)
		local rootCF = fighters[v.rel].HumanoidRootPart.CFrame
		local yaw = select(2, rootCF:ToOrientation())
		return h + CFrame.Angles(0, yaw, 0):VectorToWorldSpace(Vector3.new(v.o[1], v.o[2], v.o[3]))
	end
	return Vector3.new(v[1], v[2], v[3])
end
local function camAt(frame)
	local keys = D.camera
	local a, b
	for i, k in ipairs(keys) do if k.f <= frame then a = k; b = keys[i + 1] end end
	a = a or keys[1]
	local pa, la, fa = resolve(a.pos), resolve(a.look), a.fov
	if b and not b.cut and b.f > a.f then
		local u = ease(clamp01((frame - a.f) / (b.f - a.f)))
		return pa:Lerp(resolve(b.pos), u), la:Lerp(resolve(b.look), u), fa + (b.fov - fa) * u, a.name
	end
	return pa, la, fa, a.name
end
local function shakeAt(frame)
	for _, s in ipairs(D.shake) do
		if frame >= s.f and frame < s.f + s.frames then
			local k = 1 - (frame - s.f) / s.frames
			return Vector3.new(math.sin(frame * 91) * s.amp * k, math.cos(frame * 77) * s.amp * k * 0.7, 0)
		end
	end
	return Vector3.zero
end
local fill = Look.fill()

---------------------------------------------------------------- preview (neutral light, front / profile / fight camera / close-ups)
local PREVIEW_VIEWS = { "front Gojo", "profile Gojo", "front Toji", "profile Toji", "fight camera (medium)", "Gojo close-up", "Toji close-up" }
local function previewCam()
	local gh, th = headOf("Blue"), headOf("Purple")
	local v = state.view
	if v == 1 then return gh + Vector3.new(-5, -0.8, 0), gh + Vector3.new(0, -0.8, 0), 30      -- Gojo faces -X: camera in front of him
	elseif v == 2 then return gh + Vector3.new(0, -0.8, 6), gh + Vector3.new(0, -0.8, 0), 30
	elseif v == 3 then return th + Vector3.new(5, -0.8, 0), th + Vector3.new(0, -0.8, 0), 30
	elseif v == 4 then return th + Vector3.new(0, -0.8, 6), th + Vector3.new(0, -0.8, 0), 30
	elseif v == 5 then return Vector3.new(-4, 3.6, 17.5), Vector3.new(-4, 2.6, 0), 44
	elseif v == 6 then return gh + Vector3.new(-1.9, 0, 0.9), gh, 18
	else return th + Vector3.new(1.4, 0.05, 1.7), th, 16 end
end

---------------------------------------------------------------- HUD (hidden unless H)
local gui = Instance.new("ScreenGui"); gui.Name = "BGDuelHUD"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
local hud = Instance.new("TextLabel")
hud.BackgroundColor3, hud.BackgroundTransparency = Color3.fromRGB(10, 10, 18), 0.35
hud.Position, hud.Size = UDim2.new(0, 12, 1, -112), UDim2.new(0, 760, 0, 100)
hud.TextXAlignment, hud.TextYAlignment, hud.Font, hud.TextSize = Enum.TextXAlignment.Left, Enum.TextYAlignment.Top, Enum.Font.Code, 14
hud.TextColor3, hud.Visible = Color3.fromRGB(235, 235, 255), false
hud.Parent = gui

---------------------------------------------------------------- playback
local function chapterStart(i) return D.chapters[math.clamp(i, 1, #D.chapters)].f0 end
local function resetEvents(frame)
	state.evIdx = 1
	while state.evIdx <= #events and events[state.evIdx].f <= frame do state.evIdx += 1 end
	state.lastFrame = frame
end
local function seekFrame(frame)
	frame = math.clamp(frame, 0, D.frames - 1)
	state.t = frame / D.fps
	resetEvents(frame)
	for _, id in ipairs({ "Blue", "Purple" }) do cloth[id]:reset() end
	resetLane()
	restoreStage()
end
local function cleanup()
	for _, name in ipairs({ "BGEffects", "BGStyleFX" }) do local f = Workspace:FindFirstChild(name); if f then for _, c in ipairs(f:GetChildren()) do c:Destroy() end end end
	for _, model in pairs(fighters) do
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("Highlight") or (d:IsA("ParticleEmitter") and (d.Name == "BGAura" or d.Name == "BGSpark")) or (d:IsA("PointLight") and d.Name == "BGGlow") then d:Destroy()
			elseif d:IsA("Trail") then d.Enabled = false end
		end
	end
end
local function applyLook()
	if state.neutral or mode() == "Preview" then Look.apply("neutral") else
		Look.apply("night")      -- (Look's night preset is the dusk look: restrained bloom, no reflective surfaces)
		Lighting.ClockTime = 17.6; Lighting.Brightness = 1.6; Lighting.Ambient = Color3.fromRGB(104, 104, 118); Lighting.OutdoorAmbient = Color3.fromRGB(116, 116, 130)
	end
end
local was = false
RunService:BindToRenderStep("BGDuelPose", Enum.RenderPriority.Camera.Value - 1, function(dt)
	if not active() then
		hud.Visible = false
		was = false
		return
	end
	if not was then
		was = true
		cleanup(); Style.setEnabled(state.fx); applyLook(); Look.audit()
		seekFrame(mode() == "Preview" and 0 or math.floor(state.t * D.fps))
	end
	if mode() == "Preview" then
		-- characters stand side by side in neutral light; Toji is moved next to Gojo for the stills
		applyPose(0, { Blue = CFrame.new(-6, 0, 0) * CFrame.new(0, 0, 0), Purple = CFrame.new(26, 0, 0) })
		for _, id in ipairs({ "Blue", "Purple" }) do for _, m in ipairs(eyeMotors[id]) do m.Transform = CFrame.new() end end
		updateCostumes(0)
		for _, g in ipairs(glassesParts) do g.part.Transparency = state.glasses and g.trans or 1 end
		hud.Visible = hudOn
		hud.Text = string.format(" PREVIEW (neutral light)  view %d/%d: %s | Left/Right change view, G glasses, N neutral/night, P back to the duel", state.view, #PREVIEW_VIEWS, PREVIEW_VIEWS[state.view])
		return
	end
	local frame0 = state.t * D.fps
	if state.playing then
		local rate = state.speed * D.playRate(frame0)
		state.t = math.min(state.t + dt * rate, D.duration)       -- elapsed time; slow motion only where the timeline asks for it
	end
	local frame = state.t * D.fps
	local f = math.floor(frame)
	applyPose(state.t)
	-- eyes: they move before the head does (keys in BGDuel.eyes)
	for _, id in ipairs({ "Blue", "Purple" }) do
		local ex, ey = keyLerp(D.eyes[id], frame, "x"), keyLerp(D.eyes[id], frame, "y")
		for _, m in ipairs(eyeMotors[id]) do m.Transform = CFrame.new(-ex, ey, 0) end
	end
	local wind = D.curseUncoiled(f) and 7 or 0
	cloth.Blue:update(snap.Blue.out.cf.UpperTorso, state.playing and dt or 0, 0)
	cloth.Purple:update(snap.Purple.out.cf.UpperTorso, state.playing and dt or 0, wind)
	updateCostumes(f); setGlasses(f)
	updateScene(f)
	-- one-shots
	if f < state.lastFrame then resetEvents(f) end
	while state.evIdx <= #events and events[state.evIdx].f <= f do
		if events[state.evIdx].f > state.lastFrame then
			local ev = events[state.evIdx]
			if ev.fn then pcall(ev.fn) else playCue(ev.cue) end
		end
		state.evIdx += 1
	end
	state.lastFrame = f
	master.Volume = musicAt(f)
	-- shock: Gojo's glasses leave his face with a flash on the spear contact (frame 2716), Purple's flash at the release
	if state.fx and (f == 2716 or f == 6900) and state.playing then Style.flash(Color3.new(1, 1, 1), 0.06, 0.25) end
	if state.playing and state.t >= D.duration then
		state.loops += 1
		if state.loops == 1 then print(string.format("[DUEL] first full playthrough: %.2f s of real time (timeline %.1f s, slow-motion windows included)", os.clock() - state.wall0, D.duration)) end
		state.playing = false
	end
	if hudOn then
		local ch = D.chapterAt(f)
		local _, _, _, shot = camAt(frame)
		hud.Visible = true
		hud.Text = string.format(" %d:%02d  frame %d/%d | chapter %d: %s\n question: %s\n shot: %s | fx %s | cam %s | light %s | speed %.2fx\n 1-9 chapter  [ ] prev/next  R replay  Space  , .  B slow  V fx  F fixed cam  N neutral  C checks  P preview  H hide",
			math.floor(state.t / 60), math.floor(state.t % 60), f, D.frames - 1, ch.id, ch.name, ch.q, shot or "", state.fx and "ON" or "OFF", state.fixed and "FIXED" or "SHOTS", state.neutral and "NEUTRAL" or "DUSK", state.speed)
	else
		hud.Visible = false
	end
end)

RunService:BindToRenderStep("BGDuelCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if not active() then return end
	local cam = Workspace.CurrentCamera
	if not cam then return end
	cam.CameraType = Enum.CameraType.Scriptable
	local pos, look, fov
	if mode() == "Preview" then pos, look, fov = previewCam()
	elseif state.fixed then pos, look, fov = Vector3.new(0, 5, 34), Vector3.new(0, 2.8, 0), 50
	else
		local frame = state.t * D.fps
		pos, look, fov = camAt(frame)
		pos = pos + shakeAt(frame)
	end
	cam.CFrame = CFrame.lookAt(pos, look)
	cam.FieldOfView = fov
	fill.Position = pos + cam.CFrame.LookVector * 2
end)

---------------------------------------------------------------- checks (key C)
local function runChecks()
	local keep = { state.fx, state.playing, state.t }
	state.fx, state.playing = false, false
	local function go(frame) state.t = frame / D.fps; for _ = 1, 3 do RunService.RenderStepped:Wait() end end
	go(906)
	local fist = fighters.Purple.RightHand.Position
	local gh = fighters.Blue.Head
	print(string.format("[DUEL CHECK] Infinity stop f906: fist centre to Gojo's head surface = %.2f studs (target gap %.2f + fist %.2f)", (fist - gh.Position).Magnitude - 0.6, stopC.gap, stopC.fist))
	go(2716)
	print(string.format("[DUEL CHECK] spear contact f2716: Toji fist to Gojo's torso centre = %.2f studs", (fighters.Purple.RightHand.Position - fighters.Blue.UpperTorso.Position).Magnitude))
	local low, at = 9, 0
	for f = 0, D.frames - 1, 6 do
		go(f)
		for _, id in ipairs({ "Blue", "Purple" }) do
			local gy = Engine.eval(R, tracks[id], f / D.fps).gy
			for _, n in ipairs({ "RightFoot", "LeftFoot" }) do
				local p = fighters[id][n]
				local y = p.Position.Y - p.Size.Y / 2 - gy
				if y < low then low, at = y, f end
			end
		end
	end
	print(string.format("[DUEL CHECK] lowest foot sole above its ground over the whole timeline = %.3f studs (frame %d)", low, at))
	state.fx, state.playing, state.t = keep[1], keep[2], keep[3]
end


---------------------------------------------------------------- shot audit: isolate what owns a stray flat rectangle (key X)
local isoStep, isoHidden = 0, {}
local ISO = { "BGDuelFX effect parts", "particle emitters", "decals / textures / surface GUIs", "ForceField + Glass material parts", "Neon parts", "all courtyard geometry" }
local function isoRestore()
	for inst, prop in pairs(isoHidden) do pcall(function() if prop.t ~= nil then inst.Transparency = prop.t elseif prop.e ~= nil then inst.Enabled = prop.e elseif prop.v ~= nil then inst.Visible = prop.v end end) end
	isoHidden = {}
end
local function isoApply(step)
	local n = 0
	for _, d in ipairs(Workspace:GetDescendants()) do
		local hit = false
		if step == 1 then hit = d:IsA("BasePart") and d:IsDescendantOf(fxFolder)
		elseif step == 2 then hit = d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail")
		elseif step == 3 then hit = d:IsA("Decal") or d:IsA("Texture") or d:IsA("SurfaceGui")
		elseif step == 4 then hit = d:IsA("BasePart") and (d.Material == Enum.Material.ForceField or d.Material == Enum.Material.Glass)
		elseif step == 5 then hit = d:IsA("BasePart") and d.Material == Enum.Material.Neon
		elseif step == 6 then hit = d:IsA("BasePart") and d:IsDescendantOf(stage) and not d:IsDescendantOf(fighters.Blue) and not d:IsDescendantOf(fighters.Purple) end
		if hit then
			n += 1
			if d:IsA("BasePart") then isoHidden[d] = { t = d.Transparency }; d.Transparency = 1
			elseif d:IsA("SurfaceGui") then isoHidden[d] = { e = d.Enabled }; d.Enabled = false
			elseif d:IsA("Decal") or d:IsA("Texture") then isoHidden[d] = { t = d.Transparency }; d.Transparency = 1
			else isoHidden[d] = { e = d.Enabled }; d.Enabled = false end
		end
	end
	return n
end
local function auditShot()
	print("[SHOT AUDIT] visible flat or large pale parts, textured parts and wide particle emitters in the scene:")
	local cam = Workspace.CurrentCamera
	local c = 0
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 0.95 and not d:IsDescendantOf(fighters.Blue) and not d:IsDescendantOf(fighters.Purple) then
			local s = d.Size
			local mn, mx = math.min(s.X, s.Y, s.Z), math.max(s.X, s.Y, s.Z)
			local col = d.Color
			local pale = (col.R + col.G + col.B) / 3 > 0.7
			if (mn < 0.4 and mx > 2 and pale) or d.Material == Enum.Material.ForceField or d.Material == Enum.Material.Glass then
				c += 1
				if c <= 12 then print(string.format("   %s  size %.1f x %.1f x %.1f  material %s  transparency %.2f", d:GetFullName(), s.X, s.Y, s.Z, d.Material.Name, d.Transparency)) end
			end
		elseif (d:IsA("Decal") or d:IsA("Texture") or d:IsA("SurfaceGui")) then print("   textured: " .. d:GetFullName())
		elseif d:IsA("ParticleEmitter") and d.Enabled then
			local mx = 0
			for _, k in ipairs(d.Size.Keypoints) do mx = math.max(mx, k.Value) end
			if mx > 2 then print(string.format("   wide emitter: %s  size %.1f", d:GetFullName(), mx)) end
		end
	end
	print("[SHOT AUDIT] " .. c .. " candidate parts. Press X (paused on the shot) to hide one category at a time; the rectangle disappears with its owner.")
end

---------------------------------------------------------------- controls
local CHAPTER_KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine, Enum.KeyCode.Zero, Enum.KeyCode.Minus, Enum.KeyCode.Equals }
local function gotoChapter(i) state.chapter = i; seekFrame(chapterStart(i)); state.playing = true end
local function currentChapter() return D.chapterAt(math.floor(state.t * D.fps)).id end
UserInputService.InputBegan:Connect(function(input, gp)
	if gp or not active() then return end
	local k = input.KeyCode
	if mode() == "Preview" then
		if k == Enum.KeyCode.Right then state.view = state.view % #PREVIEW_VIEWS + 1
		elseif k == Enum.KeyCode.Left then state.view = (state.view - 2) % #PREVIEW_VIEWS + 1
		elseif k == Enum.KeyCode.G then state.glasses = not state.glasses
		elseif k == Enum.KeyCode.N then state.neutral = not state.neutral; applyLook()
		elseif k == Enum.KeyCode.P then stage:SetAttribute("Mode", "Cinematic")
		elseif k == Enum.KeyCode.H then hudOn = not hudOn; stage:SetAttribute("UIVisible", hudOn) end
		return
	end
	for i, kc in ipairs(CHAPTER_KEYS) do if k == kc then gotoChapter(i) return end end
	if k == Enum.KeyCode.R then seekFrame(0); state.playing = true; state.loops = 0; state.wall0 = os.clock()
	elseif k == Enum.KeyCode.LeftBracket then gotoChapter(math.max(1, currentChapter() - 1))
	elseif k == Enum.KeyCode.RightBracket then gotoChapter(math.min(#D.chapters, currentChapter() + 1))
	elseif k == Enum.KeyCode.Space then state.playing = not state.playing
	elseif k == Enum.KeyCode.Comma then state.playing = false; state.t = math.max(0, state.t - 1 / D.fps)
	elseif k == Enum.KeyCode.Period then state.playing = false; state.t = math.min(D.duration, state.t + 1 / D.fps)
	elseif k == Enum.KeyCode.B then state.speed = (state.speed == 1) and 0.25 or 1
	elseif k == Enum.KeyCode.V then state.fx = not state.fx; Style.setEnabled(state.fx)
	elseif k == Enum.KeyCode.F then state.fixed = not state.fixed
	elseif k == Enum.KeyCode.N then state.neutral = not state.neutral; applyLook(); Look.audit()
	elseif k == Enum.KeyCode.H then hudOn = not hudOn; stage:SetAttribute("UIVisible", hudOn)
	elseif k == Enum.KeyCode.C then task.spawn(runChecks)
	elseif k == Enum.KeyCode.X then
		isoRestore()
		isoStep = isoStep % (#ISO + 1) + 1
		if isoStep > #ISO then isoStep = 0; print("[SHOT AUDIT] everything restored"); auditShot()
		else print(string.format("[SHOT AUDIT] hidden: %s (%d instances)", ISO[isoStep], isoApply(isoStep))) end
	elseif k == Enum.KeyCode.P then stage:SetAttribute("Mode", "Preview") end
end)
stage:GetAttributeChangedSignal("CinCmd"):Connect(function()
	if not active() then return end
	local cmd, arg = tostring(stage:GetAttribute("CinCmd")):match("^(%a+):?(%d*)")
	if cmd == "replay" then seekFrame(0); state.playing = true
	elseif cmd == "slow" then state.speed = (state.speed == 1) and 0.25 or 1
	elseif cmd == "vfx" then state.fx = not state.fx; Style.setEnabled(state.fx)
	elseif cmd == "chapter" and tonumber(arg) then gotoChapter(tonumber(arg))
	elseif cmd == "inspect" then task.spawn(runChecks) end
end)
stage:GetAttributeChangedSignal("Mode"):Connect(function() if active() then was = false end end)
print("[DUEL] ready: 4:00 duel + 0:20 epilogue. 1-9 chapters, P preview, H HUD, Tab playable.")
