-- BGCine (LocalScript, StarterPlayer > StarterPlayerScripts): plays the 6-second Kael vs Ren cinematic from BGTimeline.
-- ONE timeline drives everything: fighter poses, camera cuts, debris, field, power effects, camera shake and sound cues.
-- Playback uses ELAPSED time (not frame counts), so the scene lasts 6.0 s at any frame rate. It runs only while stage Mode == "Cinematic".
--
-- Keys:  R replay   Space pause   , .  step one frame   B slow motion   V effects on/off   F fixed wide camera (for checking animation)
--        N neutral light (all post effects off)   H show / hide the control panel + HUD   C run the contact checks (prints to Output)   Tab -> playable
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Engine = require(ReplicatedStorage:WaitForChild("BGEngine"))
local T = require(ReplicatedStorage:WaitForChild("BGTimeline"))
local Cloth = require(ReplicatedStorage:WaitForChild("BGCloth"))
local Rig = require(ReplicatedStorage:WaitForChild("BGRig"))
local Style = require(ReplicatedStorage:WaitForChild("BGStyle"))
local Look = require(ReplicatedStorage:WaitForChild("BGLook"))

local stage = Workspace:WaitForChild("Showcase")
while not stage:GetAttribute("Ready") do task.wait(0.1) end
local function active() return stage:GetAttribute("Mode") == "Cinematic" end

local BLUE, CYAN, VIOLET, RED = Color3.fromRGB(60, 150, 255), Color3.fromRGB(80, 220, 255), Color3.fromRGB(175, 90, 255), Color3.fromRGB(255, 70, 70)
local fighters = { Blue = stage:WaitForChild("Blue"), Purple = stage:WaitForChild("Purple") }
local motors, cloth, rigs = {}, {}, {}
local R
for id, model in pairs(fighters) do
	Rig.waitReady(model)
	local defs, sizes, m = Rig.read(model)
	if not R then R = Engine.newRig(defs, sizes) end
	motors[id], cloth[id] = m, Cloth.new(model)
end
local eyeMotors = {}
for _, d in ipairs(fighters.Purple:GetDescendants()) do
	if d:IsA("Motor6D") and d:GetAttribute("EyeJoint") then table.insert(eyeMotors, d) end
end

local tracks, info = Engine.bake(R, T.engineData())
local clashC, stopC, bracerC = info[1], info[2], info[3]
local PLANE_X, PLANE_Y, PLANE_Z = stopC.plane.X, stopC.Hc.Y, stopC.Hc.Z
print(string.format("[CINE] baked: Kael anchor x=%.2f | field plane x=%.2f y=%.2f | follow-up contact at (%.2f, %.2f, %.2f)", tracks.Blue.anchor.x, PLANE_X, PLANE_Y, clashC.C.X, clashC.C.Y, clashC.C.Z))

---------------------------------------------------------------- state
local state = { t = 0, playing = true, speed = 1, fx = true, fixed = false, neutral = false, hold = 0, evIdx = 1, lastFrame = -1, loops = 0, wallStart = os.clock() }
local hudOn = false
local fxFolder = Workspace:FindFirstChild("BGCineFX")
if fxFolder then fxFolder:Destroy() end
fxFolder = Instance.new("Folder"); fxFolder.Name = "BGCineFX"; fxFolder.Parent = Workspace

---------------------------------------------------------------- pose
local snapshot = {}
local function applyPose(t)
	for id, model in pairs(fighters) do
		local P = Engine.eval(R, tracks[id], t)
		local out = Engine.solve(R, P)
		model.HumanoidRootPart.CFrame = out.hrp
		for jn, rt in pairs(out.rot) do motors[id][jn].Transform = rt end
		snapshot[id] = { P = P, out = out }
	end
end

local function lerpKeys(keys, frame, field)
	local a, b = keys[1], keys[#keys]
	for i, k in ipairs(keys) do
		if k.f <= frame then a = k; b = keys[math.min(i + 1, #keys)] end
	end
	if b.f == a.f then return a[field] end
	local u = math.clamp((frame - a.f) / (b.f - a.f), 0, 1)
	u = u * u * (3 - 2 * u)
	return a[field] + (b[field] - a[field]) * u
end

local function windFor(frame)
	local w = 0
	for _, e in ipairs(T.fx.windKael) do
		if frame >= e.from - 3 and frame <= e.to + 3 then
			local ramp = math.min((frame - (e.from - 3)) / 6, ((e.to + 3) - frame) / 6, 1)
			w = math.max(w, e.wind * math.clamp(ramp, 0, 1))
		end
	end
	return w
end

---------------------------------------------------------------- deterministic scene objects (pure functions of the frame, so scrubbing works)
local rng = Random.new(12)
local function neon(parent, size, color, transparency, shape)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material, p.Color, p.Transparency = Enum.Material.Neon, color, transparency or 0
	if shape then p.Shape = shape end
	p.Size = size
	p.Parent = parent or fxFolder
	return p
end
local function matte(size, color, shape)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, true
	p.Material, p.Color, p.Size = Enum.Material.Slate, color, size
	if shape then p.Shape = shape end
	p.Parent = fxFolder
	return p
end

-- the field boundary disc, its ripple ring
local field = Instance.new("Part")
field.Anchored, field.CanCollide, field.CanQuery, field.CastShadow = true, false, false, false
field.Shape, field.Material, field.Color, field.Transparency = Enum.PartType.Cylinder, Enum.Material.ForceField, Color3.fromRGB(190, 200, 255), 1
field.Size = Vector3.new(0.08, 5.6, 5.6)
field.CFrame = CFrame.new(PLANE_X, PLANE_Y, PLANE_Z)
field.Parent = fxFolder
local ripple = neon(fxFolder, Vector3.new(0.05, 1, 1), Color3.fromRGB(210, 220, 255), 1, Enum.PartType.Cylinder)
local fold = neon(fxFolder, Vector3.new(0.05, 1, 1), CYAN, 1, Enum.PartType.Cylinder)

-- suspended grit: arrives slowing down, hangs at the boundary, falls when the field folds. Two pieces stop at the fist's plane.
local grit = {}
for i = 1, T.fx.grit.count do
	local special = i <= T.fx.grit.stopped
	local hover = Vector3.new(PLANE_X - (special and 0.03 or rng:NextNumber(0.1, 1.1)), PLANE_Y + (special and (i == 1 and 0.55 or -0.45) or rng:NextNumber(-1.1, 1.1)), PLANE_Z + (special and 0.1 * i or rng:NextNumber(-1.2, 1.2)))
	local g = { part = matte(Vector3.new(0.16, 0.12, 0.14) * rng:NextNumber(0.8, 1.4), Color3.fromRGB(150, 150, 160)), hover = hover,
		start = hover + Vector3.new(-rng:NextNumber(4, 7), rng:NextNumber(-0.8, 1.2), rng:NextNumber(-1.5, 1.5)),
		arrive = special and 33 + i or rng:NextInteger(27, 34), spin = Vector3.new(rng:NextNumber(-3, 3), rng:NextNumber(-3, 3), rng:NextNumber(-3, 3)),
		fallDelay = rng:NextNumber(0, 5), drift = Vector3.new(rng:NextNumber(-0.6, 0.2), 0, rng:NextNumber(-0.4, 0.4)) }
	grit[i] = g
end
local function gritCF(g, f)
	local fromF, fold_ = T.fx.grit.from, T.fx.field.fold
	if f < fromF then return nil end
	if f < g.arrive then
		local u = math.clamp((f - fromF) / (g.arrive - fromF), 0, 1)
		local e = 1 - (1 - u) ^ 3                       -- decelerates as it nears the palm
		return CFrame.new(g.start:Lerp(g.hover, e)) * CFrame.Angles(g.spin.X * u, g.spin.Y * u, g.spin.Z * u)
	elseif f < fold_ + g.fallDelay then
		local k = (f - g.arrive) / 30
		return CFrame.new(g.hover + Vector3.new(0, math.sin(k * 3 + g.arrive) * 0.012, 0)) * CFrame.Angles(g.spin.X, g.spin.Y, g.spin.Z)
	else
		local k = (f - (fold_ + g.fallDelay)) / 30
		local y = math.max(g.hover.Y - 0.5 * 24 * k * k, 0.08)
		return CFrame.new(g.hover.X + g.drift.X * k * 3, y, g.hover.Z + g.drift.Z * k * 3) * CFrame.Angles(g.spin.X + k * 4, g.spin.Y, g.spin.Z + k * 3)
	end
end

-- loose stones: roll toward the blue point (pull: curved, accelerating), then are thrown back away from Ren's palm (push: straight, fast)
local stones = {}
local function easeIn(u) return u * u end
local function easeOut(u) return 1 - (1 - u) ^ 3 end
for i = 1, T.fx.stones.count do
	stones[i] = { part = matte(Vector3.new(0.34, 0.26, 0.3) * rng:NextNumber(0.8, 1.5), Color3.fromRGB(96, 98, 110)),
		home = Vector3.new(rng:NextNumber(-7.5, 1.5), 0.15, rng:NextNumber(-3.2, 3.2)), swirl = rng:NextNumber(0.6, 1.4) * (rng:NextNumber() < 0.5 and -1 or 1),
		throw = Vector3.new(-rng:NextNumber(5, 11), 0, rng:NextNumber(-3, 3)), spin = rng:NextNumber(2, 6) }
end
local function bluePos(f)             -- the blue point behind Kael during the pull (frames 70-104)
	local k = tracks.Blue
	local P = Engine.eval(R, k, math.min(f, 106) / 30)
	return Vector3.new(P.rx - 2.4, 2.5, P.rz)
end
local function stoneCF(s, f)
	local st = T.fx.stones
	if f < st.pullFrom then return CFrame.new(s.home) end
	local target = bluePos(st.pullTo)
	if f < st.push then
		local u = math.clamp((f - st.pullFrom) / (st.pullTo - st.pullFrom), 0, 1)
		local e = easeIn(u)
		local flat = Vector3.new(target.X - s.home.X, 0, target.Z - s.home.Z)
		local perp = Vector3.new(-flat.Z, 0, flat.X).Unit * s.swirl * (1 - e) * u * 2.2   -- curved path toward the point
		local pos = s.home + flat * e * 0.82 + perp + Vector3.new(0, 0.15 + e * 1.8 * u, 0)
		return CFrame.new(pos) * CFrame.Angles(u * s.spin, u * 2, 0)
	end
	local base = s.home + Vector3.new(target.X - s.home.X, 0, target.Z - s.home.Z) * 0.82 + Vector3.new(0, 1.95, 0)
	local u = math.clamp((f - st.push) / (st.settle - st.push), 0, 1)
	local e = easeOut(u)
	local y = math.max(0.15, 1.95 * (1 - u) ^ 2 + math.sin(u * math.pi) * 0.6)
	return CFrame.new(base.X + s.throw.X * e, y, base.Z + s.throw.Z * e) * CFrame.Angles(u * s.spin * 3, 0.5, u * 4)
end

-- tiles
local tiles = {}
for _, t in ipairs(stage:WaitForChild("Tiles"):GetChildren()) do
	table.insert(tiles, { part = t, home = t.CFrame, x = t.Position.X, z = t.Position.Z, jx = rng:NextNumber(-1, 1), jz = rng:NextNumber(-1, 1), col = t:GetAttribute("Col"), row = t:GetAttribute("Row") })
end
local DROP_COL = 2
local function tileCF(t, f)
	local cf = t.home
	local y, dz, rx, rz = 0, 0, 0, 0
	for _, e in ipairs(T.fx.tiles) do
		if f >= e.f then
			if e.kind == "hop" or e.kind == "skid" then
				local cx = snapshot.Blue and snapshot.Blue.P.rx or 0
				local kp = tracks.Blue.keys
				local P = Engine.eval(R, tracks.Blue, e.f / 30)
				cx = P.rx
				local d = math.abs(t.x - cx)
				if d <= e.radius and not (e.kind == "hop" and e.f == 142 and t.col == DROP_COL and t.row == 0) then
					local delay = d / e.radius * 4
					local u = (f - e.f - delay) / 9
					if u > 0 then
						local fall = 1 - d / e.radius
						if u < 1 then y = y + e.h * fall * math.sin(math.pi * u) end
						rx = rx + t.jx * 0.05 * fall; rz = rz + t.jz * 0.05 * fall      -- stays slightly tilted after settling
						if e.kind == "skid" then dz = dz + t.jz * 0.25 * fall * math.min(u, 1) end
					end
				end
			elseif e.kind == "carve" and t.row == 0 then
				local arrive = e.f + math.abs(e.x0 - t.x) / e.speed * 30
				local u = (f - arrive) / 8
				if u > 0 and t.x < e.x0 and t.x > e.x1 then
					if u < 1 then y = y + 1.1 * math.sin(math.pi * u) end
					dz = dz + (t.col % 2 == 0 and 0.34 or -0.34) * math.min(u, 1)
					rz = rz + (t.col % 2 == 0 and 0.12 or -0.12) * math.min(u, 1)
				end
			end
		end
	end
	if t.col == DROP_COL and t.row == 0 then       -- the loose tile Kael's landing throws up: it drops between the fighters at ~156
		local f0, f1 = 142, 158
		if f >= f0 and f <= f1 then
			local u = (f - f0) / (f1 - f0)
			y = y + 4 * 4 * u * (1 - u) * 0.9
			rx = rx + u * 2.2; rz = rz + u * 1.4
		elseif f > f1 then
			local b = (f - f1) / 6
			if b < 1 then y = y + 0.18 * math.sin(math.pi * b) * (1 - b) end
			rx, rz = rx + 0.2, rz + 0.08
		end
	end
	return cf * CFrame.new(0, y, dz) * CFrame.Angles(rx, 0, rz)
end

-- the two points, the core and the discharge
local blueB = neon(fxFolder, Vector3.new(0.6, 0.6, 0.6), BLUE, 1, Enum.PartType.Ball)
local redB = neon(fxFolder, Vector3.new(0.6, 0.6, 0.6), RED, 1, Enum.PartType.Ball)
local coreB = neon(fxFolder, Vector3.new(0.5, 0.5, 0.5), VIOLET, 1, Enum.PartType.Ball)
local beam = neon(fxFolder, Vector3.new(1, 0.5, 0.5), VIOLET, 1, Enum.PartType.Cylinder)
local beamCore = neon(fxFolder, Vector3.new(1, 0.2, 0.2), Color3.new(1, 1, 1), 1, Enum.PartType.Cylinder)
local carveLine = neon(fxFolder, Vector3.new(1, 0.05, 0.3), VIOLET, 1)
local pulse = neon(fxFolder, Vector3.new(0.08, 1, 1), RED, 1, Enum.PartType.Cylinder)
local function renPalmWorld(f)
	local P = Engine.eval(R, tracks.Purple, f / 30)
	return P.hands.L.t, P
end

local function updateScene(f)
	local on = state.fx
	-- field
	local F = T.fx.field
	local vis = on and f >= F.show and f < F.gone
	local trans = 1
	if vis then
		trans = 0.82
		if f >= F.fold then trans = 0.82 + 0.18 * math.clamp((f - F.fold) / (F.gone - F.fold), 0, 1) end
		if f < F.show + 3 then trans = 1 - (1 - 0.82) * ((f - F.show) / 3) end
	end
	field.Transparency = trans
	-- boundary ripple: slow thin ring drifting across the disc while it is up; at 44-52 the contact ripple folds inward and flickers cyan
	local rp = 1
	if vis and f < F.fold then
		local ph = ((f - F.show) % 18) / 18
		local d = 0.8 + 4.8 * ph
		ripple.Size = Vector3.new(0.04, d, d)
		ripple.CFrame = CFrame.new(PLANE_X, PLANE_Y, PLANE_Z)
		rp = 0.55 + 0.45 * ph
	end
	ripple.Transparency = (on and vis) and rp or 1
	local fp = 1
	if on and f >= F.fold and f < F.gone then
		local u = (f - F.fold) / (F.gone - F.fold)
		local d = u < 0.35 and (0.5 + 5.0 * (u / 0.35)) or (5.5 * (1 - (u - 0.35) / 0.65))       -- spreads, then folds inward
		fold.Size = Vector3.new(0.05, math.max(d, 0.1), math.max(d, 0.1))
		local bp = bracerC.Hc
		fold.CFrame = CFrame.new(PLANE_X, bp.Y, bp.Z)
		fp = 0.1 + 0.8 * u
	end
	fold.Transparency = fp
	-- grit and stones
	for _, g in ipairs(grit) do
		local cf = on and gritCF(g, f)
		g.part.Transparency = cf and 0 or 1
		if cf then g.part.CFrame = cf end
	end
	for _, s in ipairs(stones) do s.part.CFrame = on and stoneCF(s, f) or CFrame.new(s.home) end
	-- tiles
	for _, t in ipairs(tiles) do t.part.CFrame = on and tileCF(t, f) or t.home end
	-- points
	local BP, CO, BM, RP = T.fx.bluePoint, T.fx.core, T.fx.beam, T.fx.redPulse
	local bpos, show = bluePos(f), 1
	if on and f >= BP.f and f <= BP.hold then
		blueB.Position = bpos
		local s = 0.7 * math.clamp((f - BP.f) / 5, 0, 1) * (f > BP.hold - 3 and (BP.hold - f) / 3 or 1)
		blueB.Size = Vector3.new(s, s, s)
		show = 0
	elseif on and f > BP.form and f < CO.form then
		local pc, P = renPalmWorld(CO.form)
		local ren = P.rx
		local core = Vector3.new(ren - 1.9, PLANE_Y + 0.35, P.rz + 0.1)
		local u = math.clamp((f - BP.form) / (CO.form - BP.form), 0, 1)
		blueB.Position = Vector3.new(ren - 6.5, 3.8, P.rz + 0.3):Lerp(core, easeIn(u) * 0.3 + u * 0.7)
		blueB.Size = Vector3.new(0.6, 0.6, 0.6)
		show = 0
	end
	blueB.Transparency = show
	local rshow = 1
	if on and f > BP.form and f < CO.form then
		local _, P = renPalmWorld(CO.form)
		local core = Vector3.new(P.rx - 1.9, PLANE_Y + 0.35, P.rz + 0.1)
		local start = Vector3.new(P.rx + 2.4, 5.4, P.rz + 0.3)
		local u = math.clamp((f - BP.form) / (CO.form - BP.form), 0, 1)
		local arc = Vector3.new(0, math.sin(u * math.pi) * 1.0, 0)
		redB.Position = start:Lerp(core, easeIn(u) * 0.3 + u * 0.7) + arc
		redB.Size = Vector3.new(0.6, 0.6, 0.6)
		rshow = 0
	end
	redB.Transparency = rshow
	-- red pulse: a thin ring leaves Ren's palm toward Kael (a straight push, opposite of the curved pull)
	local pshow = 1
	if on and f >= RP.f and f <= RP.f + 6 then
		local u = (f - RP.f) / 6
		local pc = renPalmWorld(RP.f)
		local d = 1.5 + 9 * u
		pulse.Size = Vector3.new(0.08, d, d)
		pulse.CFrame = CFrame.new(pc.X - 1.5 - 8 * easeOut(u), pc.Y, pc.Z)
		pshow = 0.1 + 0.9 * u
	end
	pulse.Transparency = pshow
	-- core and discharge
	local cshow, bshow, cr = 1, 1, 0
	local _, PR = renPalmWorld(CO.fire)
	local corePos = Vector3.new(PR.rx - 1.9, PLANE_Y + 0.35, PR.rz + 0.1)
	if on and f >= CO.form and f < CO.collapse then
		cshow = 0
		local u = math.clamp((f - CO.form) / (CO.fire - CO.form), 0, 1)
		cr = 0.45 + 0.35 * u
		if f >= CO.fire then cr = 0.8 * (1 - (f - CO.fire) / (CO.collapse - CO.fire)) + 0.05 end
		cr = cr * (1 + 0.1 * math.sin(f * 2.1))
		coreB.Position, coreB.Size = corePos, Vector3.new(cr, cr, cr)
	end
	coreB.Transparency = cshow
	if on and f >= BM.f and f < BM.gone then
		local grow = math.clamp((f - BM.f) / 3, 0, 1)
		local len = BM.len * easeOut(grow)
		local thick = 0.55
		if f > BM.hold then thick = 0.55 * (1 - (f - BM.hold) / (BM.gone - BM.hold)) end
		beam.Size = Vector3.new(math.max(len, 0.1), math.max(thick, 0.02), math.max(thick, 0.02))
		beam.CFrame = CFrame.new(corePos.X - len / 2, corePos.Y, BM.z)
		beamCore.Size = Vector3.new(math.max(len, 0.1), math.max(thick * 0.35, 0.01), math.max(thick * 0.35, 0.01))
		beamCore.CFrame = beam.CFrame
		beam.Transparency, beamCore.Transparency = 0.1, 0
		-- the single carved line on the floor, following the beam and fading
		local fade = f > BM.hold and (1 - (f - BM.hold) / (BM.gone - BM.hold)) or 1
		carveLine.Size = Vector3.new(math.max(len, 0.1), 0.05, 0.3)
		carveLine.CFrame = CFrame.new(corePos.X - len / 2, 0.1, BM.z)
		carveLine.Transparency = 0.2 + 0.8 * (1 - fade)
	else
		beam.Transparency, beamCore.Transparency, carveLine.Transparency = 1, 1, 1
	end
end

---------------------------------------------------------------- one-shot effects (fire when playback crosses their frame)
local function bodyPos(id, f) local P = Engine.eval(R, tracks[id], f / 30) return Vector3.new(P.rx, 0, P.rz) end
local function puff(pos, dirX, n)
	for i = 1, n do
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CastShadow = true, false, false, false
		p.Material, p.Color, p.Transparency = Enum.Material.SmoothPlastic, Color3.fromRGB(120, 120, 130), 0.4
		local s = rng:NextNumber(0.25, 0.55)
		p.Shape, p.Size = Enum.PartType.Ball, Vector3.new(s, s, s)
		p.Position = pos + Vector3.new(rng:NextNumber(-0.3, 0.3), 0.15, rng:NextNumber(-0.4, 0.4))
		p.Parent = fxFolder
		local to = p.Position + Vector3.new(dirX * rng:NextNumber(1.5, 3.2), rng:NextNumber(0.2, 0.9), rng:NextNumber(-0.6, 0.6))
		TweenService:Create(p, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = to, Transparency = 1, Size = Vector3.new(s * 2, s * 2, s * 2) }):Play()
		Debris:AddItem(p, 0.65)
	end
end
local function ghost(model)
	local clone = model:Clone()
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored, d.CanCollide, d.CanQuery, d.CastShadow = true, false, false, false
			d.Material, d.Color, d.Transparency = Enum.Material.ForceField, CYAN, 0.35
			TweenService:Create(d, TweenInfo.new(0.5), { Transparency = 1 }):Play()
		elseif not d:IsA("Motor6D") and not d:IsA("Attachment") and not d:IsA("WeldConstraint") and not d:IsA("Model") and not d:IsA("Folder") then
			pcall(function() d:Destroy() end)
		end
	end
	clone.Parent = fxFolder
	Debris:AddItem(clone, 0.6)
end

local sounds = {}
local master = Instance.new("SoundGroup"); master.Name = "BGCineMaster"; master.Volume = 1; master.Parent = SoundService
local function cue(name)
	if name == "duck_start" then master.Volume = 0; return end
	if name == "duck_end" then master.Volume = 1; return end
	local id = T.soundIds[name]
	if not id or id == "" then return end
	local s = Instance.new("Sound")
	s.SoundId, s.Volume, s.SoundGroup = id, 0.6, master
	s.Parent = fxFolder
	pcall(function() s:Play() end)
	Debris:AddItem(s, 3)
end

local events = {}
local function addEvent(f, fn) table.insert(events, { f = f, fn = fn }) end
for _, e in ipairs(T.fx.dust) do
	addEvent(e.f, function() if state.fx then puff(bodyPos(e.who, e.f) + Vector3.new(e.kind == "launch" and 0 or 0, 0, 0), -1, e.kind == "land" and 10 or 7); if e.kind == "land" then Style.crack(bodyPos(e.who, e.f), Color3.fromRGB(120, 120, 130), 8, 3) end end end)
end
for _, e in ipairs(T.fx.afterimage) do addEvent(e.f, function() if state.fx then ghost(fighters[e.who]) end end) end
addEvent(T.fx.field.fold + 2, function() if state.fx then Style.shards(Vector3.new(PLANE_X, bracerC.Hc.Y, bracerC.Hc.Z), CYAN, 12, 9) end end)   -- the bracer disrupts the field
addEvent(T.contacts[1].f, function() if state.fx then Style.impact(clashC.C, Color3.new(1, 1, 1), 1.0); Style.flash(Color3.new(1, 1, 1), 0.06, 0.3) end end)
addEvent(T.fx.redPulse.f, function() if state.fx then Style.flash(RED, 0.08, 0.2) end end)
addEvent(T.fx.core.fire, function() if state.fx then Style.flash(VIOLET, 0.1, 0.35) end end)
addEvent(T.fx.core.form, function() if state.fx then Style.ringSlash(Vector3.new(0, 0, 0) + Vector3.new(bodyPos("Purple", 121).X - 1.9, PLANE_Y + 0.35, 0.1), VIOLET, 3, 90, 0.3, 0) end end)
for _, s in ipairs(T.sound) do addEvent(s.f, function() cue(s.cue) end) end
table.sort(events, function(a, b) return a.f < b.f end)

---------------------------------------------------------------- camera
local cam = Workspace.CurrentCamera
local fill = Look.fill()
local function camAt(frame)
	local keys = T.camera
	local a, b = keys[1], nil
	for i, k in ipairs(keys) do if k.f <= frame then a = k; b = keys[i + 1] end end
	local function v(t) return Vector3.new(t[1], t[2], t[3]) end
	if b and not b.cut and b.f > a.f then
		local u = math.clamp((frame - a.f) / (b.f - a.f), 0, 1)
		u = u * u * (3 - 2 * u)
		return v(a.pos):Lerp(v(b.pos), u), v(a.look):Lerp(v(b.look), u), a.fov + (b.fov - a.fov) * u, a.name
	end
	return v(a.pos), v(a.look), a.fov, a.name
end
local function shakeAt(frame)
	for _, s in ipairs(T.shake) do
		if frame >= s.f and frame < s.f + s.frames then
			local k = 1 - (frame - s.f) / s.frames
			return Vector3.new(math.sin(frame * 91) * s.amp * k, math.cos(frame * 77) * s.amp * k * 0.7, 0)
		end
	end
	return Vector3.zero
end

---------------------------------------------------------------- HUD (hidden unless H)
local gui = Instance.new("ScreenGui")
gui.Name = "BGCineHUD"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
local hud = Instance.new("TextLabel")
hud.BackgroundColor3 = Color3.fromRGB(10, 10, 18); hud.BackgroundTransparency = 0.35
hud.Position = UDim2.new(0, 12, 1, -92); hud.Size = UDim2.new(0, 640, 0, 80)
hud.TextXAlignment, hud.TextYAlignment = Enum.TextXAlignment.Left, Enum.TextYAlignment.Top
hud.Font, hud.TextSize, hud.TextColor3, hud.Visible = Enum.Font.Code, 14, Color3.fromRGB(235, 235, 255), false
hud.Parent = gui

---------------------------------------------------------------- checks (key C): measured on the real parts
local function snapTo(frame)
	state.playing = false
	state.t = frame / T.fps
	for _ = 1, 3 do RunService.RenderStepped:Wait() end
end
local function runChecks()
	local keepFx, keepPlay, keepT = state.fx, state.playing, state.t
	state.fx = false
	snapTo(T.contacts[2].f)
	local kr, rl = fighters.Blue.RightHand, fighters.Purple.LeftHand
	local d = (kr.Position - rl.Position)
	local flat = Vector3.new(d.X, 0, d.Z).Magnitude
	print(string.format("[CINE CHECK] stopped fist (f%d): fist centre to palm centre = %.2f studs (solver %.2f). Visible strip between fist surface and palm ~ %.2f studs (target %.2f)",
		T.contacts[2].f, d.Magnitude, stopC.gap + stopC.fist, d.Magnitude - 0.3, stopC.gap))
	snapTo(T.contacts[3].f)
	local br = fighters.Blue:FindFirstChild("KaelBracer")
	if br then
		local front = br.Position.X + br.Size.X / 2
		print(string.format("[CINE CHECK] bracer vs field (f%d): bracer centre x=%.2f, front face x=%.2f, field plane x=%.2f -> offset %.2f studs",
			T.contacts[3].f, br.Position.X, front, PLANE_X, PLANE_X - front))
	else
		print("[CINE CHECK] KaelBracer part not found")
	end
	snapTo(T.contacts[1].f)
	local pur = fighters.Purple
	local E = (pur.LeftUpperArm.CFrame * motors.Purple.LeftElbow.C0).Position
	local W = (pur.LeftLowerArm.CFrame * motors.Purple.LeftWrist.C0).Position
	local dist = Engine.segmentDistance(fighters.Blue.RightHand.Position, E, W)
	print(string.format("[CINE CHECK] follow-up (f%d): fist-to-forearm gap = %.3f studs (0 = touching, negative = overlap)", T.contacts[1].f, dist - T.contacts[1].guardRadius - T.contacts[1].fist))
	-- feet: lowest sole point over the whole timeline
	local lowest, worstAt = 9, 0
	for f = 0, T.frames - 1, 2 do
		snapTo(f)
		for _, id in ipairs({ "Blue", "Purple" }) do
			for _, n in ipairs({ "RightFoot", "LeftFoot" }) do
				local part = fighters[id][n]
				local y = part.Position.Y - part.Size.Y / 2
				if y < lowest then lowest, worstAt = y, f end
			end
		end
	end
	print(string.format("[CINE CHECK] lowest foot sole over 6 s = %.3f studs (f%d); negative = sinking into the floor", lowest, worstAt))
	state.fx, state.t, state.playing = keepFx, keepT, keepPlay
end

---------------------------------------------------------------- loop
local keepSet = { [field] = true, [ripple] = true, [fold] = true, [blueB] = true, [redB] = true, [coreB] = true, [beam] = true, [beamCore] = true, [carveLine] = true, [pulse] = true }
for _, g in ipairs(grit) do keepSet[g.part] = true end
for _, st in ipairs(stones) do keepSet[st.part] = true end
local function resetPlayback()
	state.t, state.hold, state.evIdx, state.lastFrame, state.wallStart = 0, 0, 1, -1, os.clock()
	master.Volume = 1
	for _, c in ipairs(fxFolder:GetChildren()) do          -- remove transient one-shots (puffs, ghosts, sounds); keep the scene objects
		if not keepSet[c] then c:Destroy() end
	end
	for _, id in ipairs({ "Blue", "Purple" }) do cloth[id]:reset() end
end
local function hideScene()
	local keep = state.fx
	state.fx = false
	updateScene(0)
	state.fx = keep
end

local function cleanup()
	-- remove anything left over from playable mode that would wash out the picture or crowd the shot
	for _, name in ipairs({ "BGEffects", "BGStyleFX" }) do
		local f = Workspace:FindFirstChild(name)
		if f then for _, c in ipairs(f:GetChildren()) do c:Destroy() end end
	end
	for _, model in pairs(fighters) do
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("Highlight") or (d:IsA("ParticleEmitter") and (d.Name == "BGAura" or d.Name == "BGSpark")) or (d:IsA("PointLight") and d.Name == "BGGlow") then d:Destroy()
			elseif d:IsA("Trail") then d.Enabled = false end
		end
	end
end

local function fireEvents(frame)
	if frame < state.lastFrame then state.evIdx = 1 end        -- scrubbed backwards
	while state.evIdx <= #events and events[state.evIdx].f <= frame do
		if events[state.evIdx].f > state.lastFrame then pcall(events[state.evIdx].fn) end
		state.evIdx += 1
	end
	state.lastFrame = frame
end

local wasActive = false
RunService:BindToRenderStep("BGCinePose", Enum.RenderPriority.Camera.Value - 1, function(dt)
	if not active() then
		hud.Visible = false
		if wasActive then hideScene() end
		wasActive = false
		return
	end
	if not wasActive then
		wasActive = true
		cleanup()
		Style.setEnabled(state.fx)
		Look.apply(state.neutral and "neutral" or "night")
		Look.audit()
		resetPlayback()
	end
	if state.playing then
		if state.hold > 0 then
			state.hold -= dt
			if state.hold <= 0 then resetPlayback() end
		else
			state.t = math.min(state.t + dt * state.speed, T.duration)       -- real elapsed time, not frame counts
		end
	end
	local frame = state.t * T.fps
	applyPose(state.t)
	local f = math.floor(frame)
	fireEvents(frame)
	-- eyes, cloth
	local ex, ey = lerpKeys(T.eyes, frame, "x"), lerpKeys(T.eyes, frame, "y")
	for _, m in ipairs(eyeMotors) do m.Transform = CFrame.new(ex, ey, 0) end
	cloth.Blue:update(snapshot.Blue.out.cf.UpperTorso, state.playing and dt * state.speed or 0, windFor(frame))
	cloth.Purple:update(snapshot.Purple.out.cf.LowerTorso, state.playing and dt * state.speed or 0, 0)
	updateScene(frame)
	-- trails off in the cinematic (clean silhouettes)
	Style.enabled = state.fx
	if state.playing and state.t >= T.duration and state.hold <= 0 then
		state.loops += 1
		if state.loops == 1 then print(string.format("[CINE] first playthrough took %.2f s of real time (timeline %.2f s)", os.clock() - state.wallStart - 0, T.duration)) end
		state.hold = 0.8
	end
	if hudOn then
		local _, _, _, shot = camAt(frame)
		hud.Visible = true
		hud.Text = string.format(" frame %3d / %d  t=%.2fs  %s | shot: %s\n fx %s | camera %s | light %s | speed %.2fx %s\n R replay  Space pause  , . step  B slow  V fx  F fixed cam  N neutral light  C checks  H hide  Tab playable",
			f, T.frames - 1, state.t, state.playing and "PLAY" or "PAUSED", shot, state.fx and "ON" or "OFF", state.fixed and "FIXED" or "SHOTS", state.neutral and "NEUTRAL" or "NIGHT", state.speed, "")
	else
		hud.Visible = false
	end
end)

RunService:BindToRenderStep("BGCineCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if not active() then return end
	cam = Workspace.CurrentCamera
	if not cam then return end
	cam.CameraType = Enum.CameraType.Scriptable
	local frame = state.t * T.fps
	local pos, look, fov
	if state.fixed then
		pos, look, fov = Vector3.new(-1.5, 3.8, 18), Vector3.new(-1.5, 2.8, 0), 50
	else
		pos, look, fov = camAt(frame)
	end
	pos = pos + shakeAt(frame)
	cam.CFrame = CFrame.lookAt(pos, look)
	cam.FieldOfView = fov
	fill.Position = pos + cam.CFrame.LookVector * 2
end)

---------------------------------------------------------------- controls
UserInputService.InputBegan:Connect(function(input, gp)
	if gp or not active() then return end
	local k = input.KeyCode
	if k == Enum.KeyCode.R then resetPlayback(); state.playing = true
	elseif k == Enum.KeyCode.Space then state.playing = not state.playing
	elseif k == Enum.KeyCode.Comma then state.playing = false; state.t = math.max(0, state.t - 1 / T.fps)
	elseif k == Enum.KeyCode.Period then state.playing = false; state.t = math.min(T.duration, state.t + 1 / T.fps)
	elseif k == Enum.KeyCode.B then state.speed = (state.speed == 1) and 0.25 or 1
	elseif k == Enum.KeyCode.V then state.fx = not state.fx; Style.setEnabled(state.fx)
	elseif k == Enum.KeyCode.F then state.fixed = not state.fixed
	elseif k == Enum.KeyCode.N then state.neutral = not state.neutral; Look.apply(state.neutral and "neutral" or "night"); Look.audit()
	elseif k == Enum.KeyCode.H then hudOn = not hudOn; stage:SetAttribute("UIVisible", hudOn)
	elseif k == Enum.KeyCode.C then task.spawn(runChecks)
	end
end)

-- buttons from the control panel (BGClient) arrive as stage attribute CinCmd = "<command>:<time>"
stage:GetAttributeChangedSignal("CinCmd"):Connect(function()
	if not active() then return end
	local cmd = tostring(stage:GetAttribute("CinCmd")):match("^(%a+)")
	if cmd == "replay" then resetPlayback(); state.playing = true
	elseif cmd == "slow" then state.speed = (state.speed == 1) and 0.25 or 1
	elseif cmd == "vfx" then state.fx = not state.fx; Style.setEnabled(state.fx)
	elseif cmd == "inspect" then task.spawn(runChecks) end
end)
stage:GetAttributeChangedSignal("Mode"):Connect(function() if active() then wasActive = false end end)
print("[CINE] ready: 6.0 s timeline (180 frames @ 30 fps). H shows the HUD, Tab switches to playable.")
