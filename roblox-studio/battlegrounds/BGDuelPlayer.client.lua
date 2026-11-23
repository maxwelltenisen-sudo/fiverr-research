-- BGDuelPlayer (LocalScript, StarterPlayer > StarterPlayerScripts): plays BGDuel (teen Gojo vs Toji, 4:00 + 0:20 epilogue).
-- Playback is by ELAPSED time. Every state (glasses, spear, chain, tiles, lighting, costume) is a pure function of the frame,
-- so selecting any chapter starts it correctly. Runs while stage Mode == "Cinematic"; Mode "Preview" is the neutral-light character preview.
--
--  1-9  jump to chapter    [ ]  previous / next chapter    R  full replay    Space  pause    , .  step a frame
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
	local fieldPart = mk(Enum.PartType.Cylinder, Vector3.new(0.06, 3.2, 3.2), Color3.fromRGB(200, 215, 255), Enum.Material.ForceField, 1)
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
local foldDisc = mk(Enum.PartType.Cylinder, Vector3.new(0.06, 1, 1), Color3.fromRGB(190, 205, 255), Enum.Material.ForceField, 1)
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
local streaks = {}
for i = 1, 120 do
	local col = ({ Color3.fromRGB(90, 160, 255), Color3.fromRGB(235, 240, 255), Color3.fromRGB(190, 110, 255), Color3.fromRGB(255, 120, 150) })[rng:NextInteger(1, 4)]
	streaks[i] = { part = mk(nil, Vector3.new(0.06, 0.06, rng:NextNumber(1, 5)), col, Enum.Material.Neon, 1), dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)).Unit,
		r = rng:NextNumber(4, 22), ph = rng:NextNumber(0, 6.28), sp = rng:NextNumber(0.4, 2.2) }
end
local dummy = Instance.new("Model"); dummy.Name = "TrainingDummy"; dummy.Parent = fxFolder
local dummyParts = {}
do
	local function dp(size, pos) local p = mk(nil, size, Color3.fromRGB(150, 150, 156), Enum.Material.SmoothPlastic, 1); p.Parent = dummy; table.insert(dummyParts, { part = p, off = pos }) end
	dp(Vector3.new(1.8, 2.0, 1.0), Vector3.new(0, 3.2, 0)); dp(Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 4.8, 0)); dp(Vector3.new(0.8, 2.2, 0.8), Vector3.new(-1.3, 3.1, 0)); dp(Vector3.new(0.8, 2.2, 0.8), Vector3.new(1.3, 3.1, 0))
	dp(Vector3.new(0.9, 2.2, 0.9), Vector3.new(-0.5, 1.1, 0)); dp(Vector3.new(0.9, 2.2, 0.9), Vector3.new(0.5, 1.1, 0))
end
local adultParts, teenParts, blindR = {}, {}, {}
for _, d in ipairs(fighters.Blue:GetDescendants()) do
	if d:IsA("BasePart") then
		if d:GetAttribute("Adult") then table.insert(adultParts, { part = d, trans = 0 }) end
		if d:GetAttribute("Teen") then table.insert(teenParts, { part = d, trans = d.Transparency }) end
		if d:GetAttribute("BlindfoldR") then table.insert(blindR, d) end
	end
end
local spearParts, curseParts = {}, {}
for _, d in ipairs(fighters.Purple:GetDescendants()) do if d:IsA("BasePart") and d:GetAttribute("Spear") then table.insert(spearParts, d) end end
local function updateCostumes(f)
	local adult = f >= D.duelFrames
	for _, p in ipairs(adultParts) do p.part.Transparency = adult and 0 or 1 end
	for _, p in ipairs(teenParts) do p.part.Transparency = adult and 1 or p.trans end
	for _, p in ipairs(blindR) do p.Transparency = (adult and f < 7401) and 0 or 1 end        -- one eye revealed
	for _, p in ipairs(spearParts) do p.Transparency = D.spearVisible(f) and 0 or 1 end
	rctEm.Rate = (state.fx and f >= D.fx.rct.f0 and f <= D.fx.rct.f1) and 10 or 0
end
local origLight = { ambient = Lighting.Ambient, out = Lighting.OutdoorAmbient }
local function updateVoid(f)
	local v = D.fx.void
	local on = f >= v.f0 and f <= v.f1
	local k = clamp01((f - v.f0) / 60)
	for _, p in ipairs(dummyParts) do
		p.part.Transparency = (on and mode() == "Cinematic") and 0 or 1
		p.part.CFrame = CFrame.new(Vector3.new(14, 0, 0) + p.off + Vector3.new(0, math.sin(f * 0.05) * 0.04, 0))
	end
	local c = snap.Blue and snap.Blue.out.cf.UpperTorso.Position or Vector3.new(6, 4, 0)
	for _, s in ipairs(streaks) do
		if not (on and state.fx) then s.part.Transparency = 1
		else
			s.part.Transparency = 1 - k * 0.85
			local a = s.ph + f / 30 * s.sp
			local pos = c + s.dir * (s.r + math.sin(a) * 2) + Vector3.new(0, math.cos(a) * 1.5, 0)
			s.part.CFrame = CFrame.lookAt(pos, pos + s.dir:Cross(Vector3.new(0, 1, 0)) + Vector3.new(0, 0.2, 0))
		end
	end
	-- the courtyard dissolves into the field
	if f >= v.f0 - 20 then
		for _, d in ipairs(stage:GetChildren()) do
			if d:IsA("BasePart") and not d:GetAttribute("Invisible") then
				d.Transparency = clamp01((f - (v.f0 - 20)) / 60)
			end
		end
	end
end
local function restoreStage()
	for _, d in ipairs(stage:GetChildren()) do
		if d:IsA("BasePart") and not d:GetAttribute("Invisible") then d.Transparency = 0 end
	end
	for _, t in ipairs(tiles) do t.part.Transparency = 0 end
end

local function updateScene(f)
	updatePebble(f); updateStops(f); updateBlue(f); updateFly(f); updateFold(f); updateRed(f); updatePurple(f); updateChain(f); updateVoid(f)
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
	if frame < D.fx.void.f0 - 20 then restoreStage() end
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
		if events[state.evIdx].f > state.lastFrame then playCue(events[state.evIdx].cue) end
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

---------------------------------------------------------------- controls
local CHAPTER_KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine }
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
