-- ONE-PASTE INSTALLER: teen Gojo vs Toji four-minute fan duel (+ the playable battlegrounds mode).
-- Paste this whole file into Roblox Studio's Command Bar (View > Command Bar) or the Output window's command line, press Enter.
-- Creates 10 ModuleScripts (ReplicatedStorage), 2 Scripts (ServerScriptService), 2 LocalScripts (StarterPlayerScripts).
-- Your older story / showcase scripts are DISABLED, not deleted (re-enable them in Properties if you want them back).
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local SP = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")
local function put(parent, class, name, src)
	local old = parent:FindFirstChild(name)
	if old then old:Destroy() end
	local o = Instance.new(class)
	o.Name = name
	o.Source = src
	o.Parent = parent
	print("created " .. o:GetFullName())
end
for _, container in ipairs({ SSS, SP }) do
	for _, c in ipairs(container:GetChildren()) do
		if (c:IsA("Script") or c:IsA("LocalScript")) and c.Name:sub(1, 2) ~= "BG" and c.Name:sub(1, 3) ~= "Rbx" then
			c.Enabled = false
			print("disabled (re-enable in Properties if you want it back): " .. c:GetFullName())
		end
	end
end
put(RS, "ModuleScript", "BGEngine", [====[
-- ShowcaseEngine (ModuleScript, ReplicatedStorage): pose solver for R15 rigs.
-- Forward kinematics + two-bone IK, keyframe expansion, contact baking. Pure math, no instances.
local Engine = {}
local V3, CF = Vector3, CFrame
local rad = math.rad

local function clamp(x, a, b) return math.max(a, math.min(b, x)) end
local function deepcopy(t)
	if type(t) ~= "table" then return t end
	local r = {}
	for k, v in pairs(t) do r[k] = deepcopy(v) end
	return r
end
local function rotOnly(cf) return cf - cf.Position end
local function lerp(a, b, e) return a + (b - a) * e end
local function lerpT(a, b, e)
	local r = {}
	for k, v in pairs(a) do r[k] = lerp(v, b[k] or v, e) end
	return r
end

local EASE = {
	linear = function(u) return u end,
	inout = function(u) return u * u * (3 - 2 * u) end,
	in2 = function(u) return u * u end,
	in3 = function(u) return u * u * u end,
	out2 = function(u) return 1 - (1 - u) * (1 - u) end,
	out3 = function(u) return 1 - (1 - u) ^ 3 end,
}

local JOINTS = { "Root", "Waist", "Neck",
	"RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow", "LeftWrist",
	"RightHip", "RightKnee", "RightAnkle", "LeftHip", "LeftKnee", "LeftAnkle" }
Engine.JOINTS = JOINTS

-------------------------------------------------------------------------- rig description
-- defs[jointName] = { c0 = CFrame, c1 = CFrame }; sizes = { footY, footZ }
function Engine.newRig(defs, sizes)
	local R = { j = {}, footY = sizes.footY, footZ = sizes.footZ }
	for _, n in ipairs(JOINTS) do
		local d = defs[n]
		R.j[n] = { c0 = d.c0, c1 = d.c1, c1inv = d.c1:Inverse(), c1rot = rotOnly(d.c1) }
	end
	local j = R.j
	R.bone = {}
	for _, side in ipairs({ "Right", "Left" }) do
		R.bone[side] = {
			leg1 = j[side .. "Knee"].c0.Position - j[side .. "Hip"].c1.Position,
			leg2 = j[side .. "Ankle"].c0.Position - j[side .. "Knee"].c1.Position,
			arm1 = j[side .. "Elbow"].c0.Position - j[side .. "Shoulder"].c1.Position,
			arm2 = j[side .. "Wrist"].c0.Position - j[side .. "Elbow"].c1.Position,
		}
	end
	local b = R.bone.Right
	R.legLen = b.leg1.Magnitude + b.leg2.Magnitude
	R.armLen = b.arm1.Magnitude + b.arm2.Magnitude
	R.handOff = j.RightWrist.c1.Position.Magnitude
	R.armReach = R.armLen + R.handOff
	R.ankleH = R.footY / 2 + j.RightAnkle.c1.Position.Y
	R.hipStand = R.legLen * 0.97 + R.ankleH                  -- hip pivot height, nearly straight legs
	local ltY = R.hipStand - j.RightHip.c0.Position.Y
	R.chestStand = ltY + j.Waist.c0.Position.Y - j.Waist.c1.Position.Y   -- upper torso centre height
	return R
end

-------------------------------------------------------------------------- IK helpers
local function perpTo(v, axis)
	local p = v - axis * v:Dot(axis)
	if p.Magnitude < 1e-4 then
		p = V3.new(0, 1, 0) - axis * axis.Y
		if p.Magnitude < 1e-4 then p = V3.new(1, 0, 0) - axis * axis.X end
	end
	return p.Unit
end

local function twoBone(S, T, L1, L2, pole)
	local d = T - S
	local dist = d.Magnitude
	local dir = d.Unit
	local maxR = (L1 + L2) * 0.9995
	local minR = math.max(math.abs(L1 - L2) + 0.02, 0.9)    -- tighter folds flip the bend plane (and look impossible)
	local reachedDist = clamp(dist, minR, maxR)
	local a = (L1 * L1 - L2 * L2 + reachedDist * reachedDist) / (2 * reachedDist)
	local h = math.sqrt(math.max(L1 * L1 - a * a, 0))
	local perp = perpTo(pole, dir)
	local E = S + dir * a + perp * h
	return E, S + dir * reachedDist, dist - reachedDist
end

-- world orientation of a part whose local bone vector must point along worldDir,
-- with its local +Z axis leaning toward sign*hint.
local function align(localBone, worldDir, hint, sign)
	local yl = localBone.Unit
	local zl = V3.new(0, 0, 1) - yl * yl.Z
	if zl.Magnitude < 1e-3 then zl = V3.new(1, 0, 0) - yl * yl.X end
	zl = zl.Unit
	local xl = yl:Cross(zl)
	local L = CF.fromMatrix(V3.new(0, 0, 0), xl, yl, zl)
	local yw = worldDir.Unit
	local zw = perpTo(hint, yw) * sign
	local xw = yw:Cross(zw)
	local W = CF.fromMatrix(V3.new(0, 0, 0), xw, yw, zw)
	return W * L:Inverse()
end

local function limb(parentCF, jp, jm, jd, v1, v2, target, pole, sign, endRd)
	local c0p = parentCF * jp.c0
	local S = c0p.Position
	local E, reached, miss = twoBone(S, target, v1.Magnitude, v2.Magnitude, pole)
	-- roll reference = the direction the joint bulges out of the shoulder-to-target line.
	-- It lies in the bend plane for both bones, so it can never line up with either bone (no flips).
	pole = perpTo(pole, (reached - S).Unit)
	local Rd1 = align(v1, E - S, pole, sign)
	local rt1 = rotOnly(c0p):Inverse() * Rd1 * jp.c1rot
	local cf1 = parentCF * jp.c0 * rt1 * jp.c1inv
	local c0m = cf1 * jm.c0
	local Em = c0m.Position
	local Rd2 = align(v2, reached - Em, pole, sign)
	local rt2 = rotOnly(c0m):Inverse() * Rd2 * jm.c1rot
	local cf2 = cf1 * jm.c0 * rt2 * jm.c1inv
	local c0d = cf2 * jd.c0
	local rt3 = rotOnly(c0d):Inverse() * (endRd or Rd2) * jd.c1rot
	local cf3 = cf2 * jd.c0 * rt3 * jd.c1inv
	return { rt1, rt2, rt3 }, { cf1, cf2, cf3 }, S, Em, c0d.Position, miss
end

-------------------------------------------------------------------------- pose solve
-- P: rx,rz,yaw,pyaw,crouch,lean,twist,roll,headYaw,headPitch,
--    feet.R/L = {g=Vector3 ground point (y=lift), yaw, pitch}, hands.R/L = {t=Vector3, pole=Vector3}
function Engine.solve(R, P)
	local j = R.j
	local out = { rot = {}, cf = {}, piv = {}, miss = {} }
	local hipPivotY = R.hipStand - P.crouch + (P.gy or 0)
	local ltY = hipPivotY - j.RightHip.c0.Position.Y
	local LT = CF.new(P.rx, ltY, P.rz) * CF.Angles(0, rad(P.yaw + P.pyaw), 0)
	out.cf.LowerTorso = LT
	out.hrp = LT * j.Root.c1 * j.Root.c0:Inverse()
	out.rot.Root = CF.new()

	local wRt = CF.Angles(-rad(P.lean), rad(P.twist), rad(P.roll))
	out.rot.Waist = wRt
	local UT = LT * j.Waist.c0 * wRt * j.Waist.c1inv
	out.cf.UpperTorso = UT

	local nYaw = P.headYaw - 0.85 * (P.pyaw + P.twist)
	local nRt = CF.Angles(-rad(P.headPitch), rad(nYaw), 0)
	out.rot.Neck = nRt
	out.cf.Head = UT * j.Neck.c0 * nRt * j.Neck.c1inv

	for _, side in ipairs({ "Right", "Left" }) do
		local k = side:sub(1, 1)
		-- arm
		local sh, el, wr = j[side .. "Shoulder"], j[side .. "Elbow"], j[side .. "Wrist"]
		local bn = R.bone[side]
		local h = P.hands[k]
		local S0 = (UT * sh.c0).Position
		-- a fist passing through the shoulder makes the arm direction swing wildly and the elbow flip:
		-- keep it at least MINHAND away, and blend the direction toward body-forward as it gets close.
		local ht = h.t
		local v0 = ht - S0
		local dm = v0.Magnitude
		if dm < 0.9 then
			local fb = UT:VectorToWorldSpace(V3.new(0, 0, -1))
			local dirv = (v0 + fb * math.max(0, 0.75 - dm)).Unit
			ht = S0 + dirv * 0.9
		end
		h = { t = ht, pole = h.pole }
		local W = h.t - (h.t - S0).Unit * R.handOff
		local rts, cfs, S, E, Wp, miss
		for _ = 1, 2 do
			rts, cfs, S, E, Wp, miss = limb(UT, sh, el, wr, bn.arm1, bn.arm2, W, h.pole, 1, nil)
			W = h.t - (h.t - E).Unit * R.handOff
		end
		out.rot[side .. "Shoulder"], out.rot[side .. "Elbow"], out.rot[side .. "Wrist"] = rts[1], rts[2], rts[3]
		out.cf[side .. "UpperArm"], out.cf[side .. "LowerArm"], out.cf[side .. "Hand"] = cfs[1], cfs[2], cfs[3]
		out.piv[side .. "Shoulder"], out.piv[side .. "Elbow"], out.piv[side .. "Wrist"] = S, E, Wp
		out.miss[side .. "Hand"] = miss
		-- leg
		local f = P.feet[k]
		local hip, kn, an = j[side .. "Hip"], j[side .. "Knee"], j[side .. "Ankle"]
		local yawR = rad(f.yaw)
		local Ryaw = CF.Angles(0, yawR, 0)
		local Rfoot = Ryaw * CF.Angles(-rad(f.pitch), 0, 0)
		local fwd = Ryaw:VectorToWorldSpace(V3.new(0, 0, -1))
		local toeW = f.g + fwd * (R.footZ / 2)
		local toeL = V3.new(0, -R.footY / 2, -R.footZ / 2)
		local footC = toeW - Rfoot:VectorToWorldSpace(toeL)
		local ankleW = footC + Rfoot:VectorToWorldSpace(an.c1.Position)
		local pelvisFwd = CF.Angles(0, rad(P.yaw + P.pyaw), 0):VectorToWorldSpace(V3.new(0, 0, -1))
		local pole = (fwd * 0.6 + pelvisFwd * 0.4)
		local lrts, lcfs, LS, LE, LW, lmiss = limb(LT, hip, kn, an, bn.leg1, bn.leg2, ankleW, pole, -1, Rfoot)
		out.rot[side .. "Hip"], out.rot[side .. "Knee"], out.rot[side .. "Ankle"] = lrts[1], lrts[2], lrts[3]
		out.cf[side .. "UpperLeg"], out.cf[side .. "LowerLeg"], out.cf[side .. "Foot"] = lcfs[1], lcfs[2], lcfs[3]
		out.piv[side .. "Hip"], out.piv[side .. "Knee"], out.piv[side .. "Ankle"] = LS, LE, LW
		out.miss[side .. "Foot"] = lmiss
		out.toe = out.toe or {}
		out.toe[side] = lcfs[3]:PointToWorldSpace(toeL)
	end
	return out
end

-------------------------------------------------------------------------- keyframes
local function bodyCF(px, pz, yaw) return CF.new(px, 0, pz) * CF.Angles(0, rad(yaw), 0) end
Engine.bodyCF = bodyCF

function Engine.expand(def)
	local cur = deepcopy(def.base)
	local list = {}
	for i, k in ipairs(def.keys) do
		local ex = { rf = false, lf = false }
		for name, v in pairs(k) do
			if name ~= "t" and name ~= "name" and name ~= "ease" then
				cur[name] = deepcopy(v)
				if name == "rf" or name == "lf" then ex[name] = true end
			end
		end
		if i == 1 then ex.rf, ex.lf = true, true end
		local nk = deepcopy(cur)
		nk.t, nk.name, nk.ease, nk.explicit = k.t, k.name or ("key" .. i), k.ease or "inout", ex
		list[i] = nk
	end
	return list
end

local function place(track)
	for _, k in ipairs(track.keys) do
		k.px = track.anchor.x + k.dx
		k.pz = track.anchor.z + k.dz
	end
end

local function bakeFeet(track)
	place(track)
	local last = {}
	for _, k in ipairs(track.keys) do
		local b = bodyCF(k.px, k.pz, track.def.baseYaw + k.yaw)
		for _, side in ipairs({ "R", "L" }) do
			local key = side:lower() .. "f"
			if k.explicit[key] then
				local s = k[key]
				local w = b:PointToWorldSpace(V3.new(s.s, 0, -s.f))
				k["w" .. side] = V3.new(w.X, (k.gy or 0) + (s.lift or 0), w.Z)
			else
				k["w" .. side] = last[side]
			end
			last[side] = k["w" .. side]
		end
	end
end

local function findKey(track, t)
	for i, k in ipairs(track.keys) do
		if math.abs(k.t - t) < 1e-6 then return i, k end
	end
	error("no keyframe at t=" .. tostring(t) .. " for " .. tostring(track.def.name))
end

function Engine.eval(R, track, t)
	local keys = track.keys
	local i = 1
	while i < #keys and keys[i + 1].t <= t do i = i + 1 end
	local a = keys[i]
	local b = keys[math.min(i + 1, #keys)]
	local u = 0
	if b ~= a and b.t > a.t then u = clamp((t - a.t) / (b.t - a.t), 0, 1) end
	local e = EASE[b.ease](u)
	local function n(f) return lerp(a[f] or 0, b[f] or 0, e) end
	local P = {
		rx = n("px"), rz = n("pz"), yaw = track.def.baseYaw + n("yaw"), pyaw = n("pyaw"),
		crouch = n("crouch"), lean = n("lean"), twist = n("twist"), roll = n("roll"),
		headYaw = n("headYaw"), headPitch = n("headPitch"), gy = n("gy"),
	}
	local body = bodyCF(P.rx, P.rz, P.yaw)
	local chestY = R.chestStand - P.crouch + P.gy
	local function hand(spec, pspec)
		return {
			t = body:PointToWorldSpace(V3.new(spec.s, chestY + spec.y, -spec.f)),
			pole = body:VectorToWorldSpace(V3.new(pspec.s, pspec.y, -pspec.f)),
		}
	end
	P.hands = {
		R = hand(lerpT(a.rh, b.rh, e), lerpT(a.rp, b.rp, e)),
		L = hand(lerpT(a.lh, b.lh, e), lerpT(a.lp, b.lp, e)),
	}
	P.feet = {}
	for _, side in ipairs({ "R", "L" }) do
		local ls = side:lower()
		P.feet[side] = {
			g = a["w" .. side]:Lerp(b["w" .. side], e),
			yaw = track.def.baseYaw + n(ls .. "fYaw"),
			pitch = n(ls .. "fPitch"),
		}
	end
	return P
end

-------------------------------------------------------------------------- contact baking
local function setHandLocal(track, keyIdx, side, worldPoint)
	local k = track.keys[keyIdx]
	local b = bodyCF(k.px, k.pz, track.def.baseYaw + k.yaw)
	local l = b:PointToObjectSpace(worldPoint)
	local spec = { f = -l.Z, s = l.X, y = l.Y - (track.R.chestStand - k.crouch + (k.gy or 0)) }
	k[side:lower() .. "h"] = spec
	-- keep following keys that inherited the old value in sync is the data author's job
end

local function flat(v) return V3.new(v.X, 0, v.Z) end

-- data.fighters[name] = { baseYaw, anchor={x,z}, base, keys }, data.contacts = { ... }
function Engine.bake(R, data)
	local tracks = {}
	for name, def in pairs(data.fighters) do
		def.name = name
		tracks[name] = { def = def, R = R, keys = Engine.expand(def), anchor = { x = def.anchor.x, z = def.anchor.z } }
		bakeFeet(tracks[name])
	end
	local info = {}
	for ci, c in ipairs(data.contacts) do
		local att, def_ = tracks[c.attacker], tracks[c.defender]
		local ai = findKey(att, c.t)
		local aSide = c.hand == "R" and "Right" or "Left"
		local Hc
		local n
		if c.kind == "guard" then
			-- defender's raised forearm meets the attacker's fist
			local dside = c.arm == "R" and "Right" or "Left"
			local P = Engine.eval(R, def_, c.t)
			local out = Engine.solve(R, P)
			local E, W = out.piv[dside .. "Elbow"], out.piv[dside .. "Wrist"]
			n = flat(V3.new(att.anchor.x - def_.anchor.x, 0, att.anchor.z - def_.anchor.z)).Unit
			local M = (E + W) * 0.5
			local axis = (W - E).Unit
			n = perpTo(n, axis)                      -- direction from the forearm axis toward the attacker
			local C = M + n * c.guardRadius          -- point on the forearm surface
			Hc = C + n * c.fist                      -- fist centre just outside it
			info[ci] = { C = C, Hc = Hc, E = E, W = W, n = n }
			-- solve the attacker's anchor so the shoulder sits at a comfortable distance
			for _ = 1, 24 do
				bakeFeet(att)
				local Pa = Engine.eval(R, att, c.t)
				Pa.hands[c.hand].t = Hc
				local oa = Engine.solve(R, Pa)
				local S = oa.piv[aSide .. "Shoulder"]
				local dy = Hc.Y - S.Y
				local d0 = c.reach * R.armReach
				local hx = math.sqrt(math.max(d0 * d0 - dy * dy, 0))
				local want = flat(Hc) + n * hx
				att.anchor.x = att.anchor.x - (S.X - want.X)
				att.anchor.z = att.anchor.z - (S.Z - want.Z)
			end
			bakeFeet(att)
			setHandLocal(att, ai, c.hand, Hc)
		elseif c.kind == "hover" then
			-- attacker's fist stops `gap` studs short of the defender's open palm (the impossible stop)
			bakeFeet(att)
			local P = Engine.eval(R, def_, c.t)
			local palm
			if c.dpart == "head" then palm = Engine.solve(R, P).cf.Head.Position + V3.new(0, c.dy or 0, 0) else palm = P.hands[c.dhand].t end
			local k = att.keys[ai]
			local nn = flat(V3.new(k.px - palm.X, 0, k.pz - palm.Z)).Unit
			Hc = palm + nn * (c.gap + c.fist)
			info[ci] = { C = palm, Hc = Hc, n = nn, plane = Hc + nn * c.fist, gap = c.gap, fist = c.fist }
			setHandLocal(att, ai, c.hand, Hc)
		elseif c.kind == "point" then
			-- fist/wrist placed at an offset from an earlier contact's point (e.g. the bracer touching the field)
			bakeFeet(att)
			local ref = info[c.ref]
			Hc = ref.Hc + V3.new(c.dx or 0, c.dy or 0, c.dz or 0)
			info[ci] = { C = Hc, Hc = Hc, n = ref.n }
			setHandLocal(att, ai, c.hand, Hc)
		else
			-- chest contact: strike the defender's upper torso front
			local P = Engine.eval(R, def_, c.t)
			local out = Engine.solve(R, P)
			local ut = out.cf.UpperTorso
			local fwd = ut:VectorToWorldSpace(V3.new(0, 0, -1))
			Hc = ut.Position + fwd * (c.surface or 0.55) + V3.new(0, c.up or 0.2, 0)
			info[ci] = { Hc = Hc, C = Hc }
			setHandLocal(att, ai, c.hand, Hc)
		end
	end
	return tracks, info
end

-------------------------------------------------------------------------- measurements
function Engine.segmentDistance(p, a, b)
	local ab = b - a
	local t = clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1)
	return (p - (a + ab * t)).Magnitude, a + ab * t
end

return Engine
]====])
put(RS, "ModuleScript", "BGConfig", [====[
-- BGConfig (ModuleScript, ReplicatedStorage): every tunable number. Times in seconds, distances in studs.
-- Nothing in BGCore or the clips hard-codes a damage, range, cooldown, threshold or timer: change them here.
local C = {}

C.arena = { radius = 15, minGap = 2.1, spawn = 4.2 }
C.hpMax = 100
C.koRefill = 1.6                 -- seconds after reaching 0 HP before the practice fighter refills

C.meter = {
	max = 100,
	form1 = 50,                  -- Charged Mode / Rift Mode threshold
	final = 100,                 -- Thunder Ascension / Eclipse Form threshold
	drain = 4,                   -- meter per second drained toward 50 while in the first form
	form1Surge = 25,             -- activating the first form lifts the meter to at least form1 + this, so it does not end instantly
	finalDuration = 12,          -- seconds the final form lasts
}

C.guard = {
	arc = 110,                   -- degrees in front of the defender that a block covers
	blockMult = 0.15,            -- damage kept when blocked
	timedWindow = 0.25,          -- seconds after pressing guard that count as a timed block (Ren only)
	riposteWindow = 1.0,         -- seconds Ren has to press the counter after a timed block
	timedStagger = { Base = 0.55, Form1 = 0.95, Final = 0.95 },   -- stagger put on the attacker
	blockPush = 0.6,
}

C.slip = { counterWindow = 1.1 } -- seconds Kael can press the counter after a clean dodge
C.openDamageMult = 1.25          -- damage multiplier while "open" (after a missed Arc Breaker / Storm Pierce)
C.eclipseCounterMult = 1.6       -- stored Eclipse Guard energy multiplies the next Void Counter
C.combo = { reset = 0.8, buffer = 0.45 }   -- a press this long before the chain point still counts (forgiving spam)

-- meter gains
C.gain = { block = 3, timedBlock = 12, dodge = 10, counterLanded = 6 }

C.char = {
	Kael = { walk = 10.0, backWalk = 7.0, guardWalk = 3.6, turn = 900 },
	Ren  = { walk = 8.2, backWalk = 5.8, guardWalk = 3.0, turn = 720 },
}

-- Cooldowns (seconds) for each skill id.
C.cd = {
	Kael = { flash = 4.0, arc = 7.0, sky = 9.0, slip = 5.0, ult = 0 },
	Ren  = { anchor = 8.0, pulse = 9.0, ult = 0 },
}
C.flash = { charges = 1, chargesForm = 2 }   -- Flash Step charges in base / Charged Mode

-- Hits. range = centre-to-centre distance, arc = total cone in degrees (360 = all around).
-- stagger1 overrides stagger while the attacker is in a power form. mg = meter gained when it lands.
C.hits = {
	kael_jab    = { dmg = 4,  range = 3.5, arc = 100, stagger = 0.28, mg = 4 },
	kael_cross  = { dmg = 5,  range = 3.6, arc = 100, stagger = 0.30, mg = 4 },
	kael_hook   = { dmg = 6,  range = 3.5, arc = 110, stagger = 0.34, mg = 5 },
	kael_palm   = { dmg = 8,  range = 3.7, arc = 100, stagger = 0.60, push = 7.0, mg = 7 },   -- final hit pushes
	kael_arc    = { dmg = 12, range = 5.4, arc = 90,  stagger = 0.90, stagger1 = 1.25, mg = 10 },
	kael_sky    = { dmg = 7,  range = 3.7, arc = 100, launch = true, airTime = 1.0, airH = 3.6, mg = 8 },
	kael_skyfollow = { dmg = 10, mg = 8, stagger = 0.8 },
	kael_counter = { dmg = 9, range = 4.0, arc = 120, stagger = 0.7, mg = 8 },
	kael_pierce = { dmg = 15, range = 6.5, arc = 80,  stagger = 1.0, push = 3.5, mg = 12 },
	kael_thunder_launch = { dmg = 8, range = 5.5, arc = 130, launch = true, airTime = 1.5, airH = 5.0, unblockable = true, mg = 0 },
	kael_thunder_slam = { dmg = 30, range = 5.5, arc = 360, stagger = 1.3, area = true, unblockable = true, mg = 0 },

	ren_jab     = { dmg = 4,  range = 3.4, arc = 100, stagger = 0.28, mg = 4 },
	ren_elbow   = { dmg = 5,  range = 3.2, arc = 110, stagger = 0.30, mg = 4 },
	ren_backfist = { dmg = 6, range = 3.6, arc = 120, stagger = 0.34, mg = 5 },
	ren_palm    = { dmg = 11, range = 3.6, arc = 100, stagger = 0.75, push = 6.0, mg = 8 },
	ren_pulse   = { dmg = 6,  range = 5.5, range1 = 6.8, arc = 360, push = 6.0, stagger = 0.5, area = true, mg = 8 },
	ren_counter = { dmg = 12, range = 6.5, arc = 180, stagger = 1.0, push = 3.0, mg = 8 },
	ren_horizon_blast = { dmg = 28, range = 12, arc = 360, push = 7.0, stagger = 1.3, area = true, unblockable = true, mg = 0 },
}
C.horizon = { radius = 12, pullSpeed = 6 }    -- Event Horizon field radius and inward pull (studs per second)

-- Power forms make the fighter hit harder, move faster and swing faster (tempo scales the action clock).
C.form = {
	Form1 = { dmg = 1.15, tempo = 1.15, speed = 1.12 },
	Final = { dmg = 1.4,  tempo = 1.3,  speed = 1.25 },
}
-- Hit-stop: both fighters freeze for a few frames on a landed hit (this is most of what makes a punch feel heavy).
C.hitstop = { light = 0.05, big = 0.095, block = 0.03 }

C.transformInvuln = 1.0
C.knocked = 0.55                  -- getting-up time after a launch lands

-- Practice dummy behaviour.
C.ai = { interval = 2.6, approachRange = 3.6 }

return C
]====])
put(RS, "ModuleScript", "BGClips", [====[
-- BGClips (ModuleScript, ReplicatedStorage): EDITABLE ANIMATION SOURCE for Kael and Ren.
-- Each clip = keyframes (same format as ShowcaseData: keys inherit the previous key, only list what changes)
-- plus gameplay metadata the server reads: dur, loop, chain, markers, move, lift, win, openOnMiss.
--   Pose axes (the fighter faces +X, so f = forward, s = + to the fighter's right, y = height above chest centre):
--   rh/lh hands {f,s,y}; rf/lf feet {f,s,lift}; rp/lp elbow pole; dx/dz body shift; pyaw/twist/lean/crouch/roll/headYaw/headPitch.
--   Angles are degrees, + yaw/pyaw/twist turns LEFT. ease: linear|inout|in2|in3|out2|out3.
-- Markers: { t, name, op = "hit" | "follow" | "slam" | "field" | "pull" | "formset" | "leap", hit = <BGConfig.hits id>, hand = <part> }.
--   Any marker without an op is a pure cue for the client (sparks, rings, afterimage, trail windows ...).
-- move = { from, to, dist, dir = "fwd"|"input"|"side"|"back" } travels the fighter while the clip plays.
-- win  = { kind = "dodge" | "invuln" | "armor", from, to } windows measured from the clip start.
local Clips = {}

local function H(f, s, y) return { f = f, s = s, y = y } end
local function F(f, s, lift) return { f = f, s = s, lift = lift or 0 } end

---------------------------------------------------------------------------------------------- bases
local KBASE = {
	dx = 0, dz = 0, yaw = 0, pyaw = -22, twist = -8, lean = 6, roll = 0, crouch = 0.35,
	headYaw = 0, headPitch = 3, rfYaw = -38, lfYaw = -8, rfPitch = 0, lfPitch = 0,
	rf = F(-0.55, 0.55), lf = F(0.75, -0.35),
	rh = H(0.85, 0.5, 0.8), lh = H(1.15, -0.5, 0.85),
	rp = H(0.2, 0.9, -0.6), lp = H(0.2, -0.9, -0.6),
}
local RBASE = {
	dx = 0, dz = 0, yaw = 0, pyaw = -18, twist = -6, lean = 3, roll = 0, crouch = 0.5,
	headYaw = 0, headPitch = 2, rfYaw = -30, lfYaw = -6, rfPitch = 0, lfPitch = 0,
	rf = F(-0.5, 0.6), lf = F(0.55, -0.4),
	rh = H(0.78, 0.35, 0.95), lh = H(0.95, -0.4, 1.0),               -- elbows tucked, hands near the centreline
	rp = H(0.0, 0.55, -0.85), lp = H(0.0, -0.55, -0.85),
}
Clips.bases = { Kael = KBASE, Ren = RBASE }

---------------------------------------------------------------------------------------------- helpers
local function clip(dur, keys, meta)
	meta = meta or {}
	meta.dur, meta.keys = dur, keys
	meta.markers = meta.markers or {}
	return meta
end
local function hit(t, id, hand, name) return { t = t, name = name or ("contact_" .. id), op = "hit", hit = id, hand = hand } end

-- shared reaction clips, scaled per fighter weight (k = 1 light, 0.7 heavy)
local function reactions(base, k)
	local r = {}
	r.hit = clip(0.5, {
		{ t = 0 },
		{ t = 0.07, ease = "out2", lean = base.lean - 14 * k, headPitch = -12, dx = -0.25 * k, lh = H(0.75, -0.5, 0.55), rh = H(0.6, 0.5, 0.55), crouch = base.crouch - 0.05 },
		{ t = 0.26, ease = "inout", lean = base.lean - 8 * k, dx = -0.15 * k, headPitch = -6 },
		{ t = 0.5, ease = "inout", lean = base.lean - 3, dx = -0.05, headPitch = 0, lh = base.lh, rh = base.rh },
	}, { clamp = true })
	r.knock = clip(0.7, {
		{ t = 0 },
		{ t = 0.1, ease = "out2", lean = base.lean - 24 * k, headPitch = -18, dx = -0.5 * k, crouch = base.crouch - 0.12,
			rh = H(0.2, 1.15, 0.2), lh = H(0.2, -1.15, 0.2), rp = H(0.0, 0.9, -0.2), lp = H(0.0, -0.9, -0.2), rf = F(-0.8, 0.6, 0.25) },
		{ t = 0.4, ease = "inout", lean = base.lean - 14 * k, dx = -0.35 * k, rf = F(-0.8, 0.6, 0) },
		{ t = 0.7, ease = "inout", lean = base.lean - 8, rh = H(0.6, 0.6, 0.5), lh = H(0.7, -0.6, 0.5), rp = base.rp, lp = base.lp },
	}, { clamp = true })
	r.air = clip(0.6, {
		{ t = 0 },
		{ t = 0.12, ease = "out2", lean = -16, crouch = 0.0, headPitch = -14, roll = 6,
			rh = H(0.0, 1.25, 1.2), lh = H(0.0, -1.25, 1.2), rp = H(0.0, 0.9, 0.2), lp = H(0.0, -0.9, 0.2),
			rf = F(-0.4, 0.6, 0.55), lf = F(0.3, -0.4, 0.35) },
		{ t = 0.6, ease = "inout", lean = -30, headPitch = -22, roll = 10, rf = F(-0.6, 0.6, 0.7), lf = F(0.5, -0.4, 0.5) },
	}, { clamp = true })
	r.getup = clip(0.6, {
		{ t = 0, lean = 28, crouch = 0.9, headPitch = 10, lh = H(0.6, -0.6, -0.2), rh = H(0.6, 0.6, -0.2) },
		{ t = 0.35, ease = "out2", lean = 14, crouch = 0.65, headPitch = 4 },
		{ t = 0.6, ease = "inout", lean = base.lean, crouch = base.crouch, headPitch = base.headPitch, lh = base.lh, rh = base.rh },
	})
	r.open = clip(0.5, {
		{ t = 0 },
		{ t = 0.12, ease = "out2", lean = base.lean + 12, crouch = base.crouch - 0.12, lh = H(0.7, -0.6, 0.2), rh = H(0.7, 0.6, 0.2), headPitch = 8 },
		{ t = 0.5, ease = "inout", lean = base.lean + 8, crouch = base.crouch - 0.08 },
	}, { clamp = true })
	r.guard_hit = clip(0.26, {
		{ t = 0 },
		{ t = 0.05, ease = "out2", dx = -0.22 * k, lean = base.lean - 4, headPitch = -3 },
		{ t = 0.26, ease = "inout", dx = 0, lean = base.lean, headPitch = base.headPitch },
	})
	return r
end

local function walk(stride, bob)
	local s = stride
	local keys = {
		{ t = 0,    ease = "linear", lf = F(s, -0.35, 0),    rf = F(-s, 0.55, 0) },
		{ t = 0.15, ease = "linear", lf = F(0, -0.35, 0),    rf = F(0, 0.55, 0.38) },
		{ t = 0.30, ease = "linear", lf = F(-s, -0.35, 0),   rf = F(s, 0.55, 0) },
		{ t = 0.45, ease = "linear", lf = F(0, -0.35, 0.38), rf = F(0, 0.55, 0) },
		{ t = 0.60, ease = "linear", lf = F(s, -0.35, 0),    rf = F(-s, 0.55, 0) },
	}
	return keys
end

---------------------------------------------------------------------------------------------- KAEL
local K = {}
K.idle = clip(2.4, {
	{ t = 0 },
	{ t = 1.2, ease = "inout", crouch = 0.40, lean = 7, dx = 0.05, lh = H(1.15, -0.5, 0.9), headPitch = 2 },
	{ t = 2.4, ease = "inout", crouch = 0.35, lean = 6, dx = 0, lh = H(1.15, -0.5, 0.85), headPitch = 3 },
}, { loop = true })
K.walk = clip(0.6, walk(1.05), { loop = true, walkStride = 2.1 })
K.guard = clip(0.2, {
	{ t = 0 },
	{ t = 0.12, ease = "out2", crouch = 0.45, lean = 4, lh = H(1.0, -0.3, 1.1), rh = H(0.8, 0.3, 1.05), rp = H(0.0, 0.6, -0.8), lp = H(0.0, -0.6, -0.8) },
	{ t = 0.2, ease = "linear" },
}, { clamp = true })

K.m1_1 = clip(0.42, {
	{ t = 0 },
	{ t = 0.06, ease = "out2", lh = H(1.05, -0.45, 0.9), lean = 8 },
	{ t = 0.15, ease = "in2", lh = H(2.0, -0.35, 0.95), twist = -2, lean = 9 },
	{ t = 0.3, ease = "out2", lh = H(1.15, -0.5, 0.85), twist = -8, lean = 6 },
	{ t = 0.42, ease = "inout" },
}, { chain = 0.27, move = { { from = 0.04, to = 0.16, dist = 1.5, dir = "fwd" } },
	markers = { hit(0.15, "kael_jab", "LeftHand", "contact_jab") } })
K.m1_2 = clip(0.5, {
	{ t = 0 },
	{ t = 0.1, ease = "out2", pyaw = -34, twist = -20, crouch = 0.45, rh = H(0.5, 0.75, 0.6) },
	{ t = 0.2, ease = "in2", pyaw = 12, twist = 14, lean = 14, rh = H(2.0, 0.6, 0.9), rfPitch = 25, rfYaw = -16 },
	{ t = 0.35, ease = "out2", pyaw = -18, twist = -8, lean = 8, rh = H(0.9, 0.5, 0.85), rfPitch = 0, rfYaw = -38 },
	{ t = 0.5, ease = "inout", pyaw = -22, lean = 6, rh = H(0.85, 0.5, 0.8) },
}, { chain = 0.3, move = { { from = 0.06, to = 0.2, dist = 1.4, dir = "fwd" } },
	markers = { hit(0.2, "kael_cross", "RightHand", "contact_cross") } })
K.m1_3 = clip(0.58, {
	{ t = 0 },
	{ t = 0.12, ease = "out2", crouch = 0.62, lean = 12, pyaw = -30, twist = -22, lh = H(0.95, -1.2, 0.05), lp = H(0.0, -1.0, -0.2) },
	{ t = 0.22, ease = "in2", crouch = 0.58, lean = 18, pyaw = 6, twist = 10, lh = H(1.55, 0.3, -0.35), lp = H(0.3, -0.7, -0.6) },
	{ t = 0.38, ease = "out2", crouch = 0.42, lean = 9, pyaw = -22, twist = -8, lh = H(1.15, -0.5, 0.85), lp = H(0.2, -0.9, -0.6) },
	{ t = 0.58, ease = "inout", crouch = 0.35, lean = 6 },
}, { chain = 0.34, move = { { from = 0.08, to = 0.22, dist = 1.2, dir = "fwd" } },
	markers = { hit(0.22, "kael_hook", "LeftHand", "contact_hook") } })
K.m1_4 = clip(0.78, {
	{ t = 0 },
	{ t = 0.13, ease = "out2", crouch = 0.68, lean = 10, pyaw = -34, twist = -22, rh = H(0.9, 0.6, -0.5) },
	{ t = 0.26, ease = "in2", crouch = 0.22, lean = 4, pyaw = 10, twist = 12, rh = H(1.9, 0.45, 1.15), rfPitch = 30, rfYaw = -18 },
	{ t = 0.5, ease = "out2", crouch = 0.38, lean = 8, rh = H(1.2, 0.5, 0.9), rfPitch = 8 },
	{ t = 0.78, ease = "inout", pyaw = -22, twist = -8, lean = 6, crouch = 0.35, rh = H(0.85, 0.5, 0.8), rfPitch = 0, rfYaw = -38 },
}, { move = { { from = 0.1, to = 0.28, dist = 1.9, dir = "fwd" } },
	trail = { { from = 0.2, to = 0.4, hand = "RightHand" } },
	markers = { hit(0.26, "kael_palm", "RightHand", "contact_palm") } })

K.flash = clip(0.42, {
	{ t = 0 },
	{ t = 0.06, ease = "out2", crouch = 0.58, lean = 16, headPitch = 8 },
	{ t = 0.16, ease = "linear", crouch = 0.62, lean = 22, lf = F(1.5, -0.35, 0.25), rf = F(-1.2, 0.55, 0.25) },
	{ t = 0.3, ease = "out2", crouch = 0.5, lean = 10, lf = F(0.9, -0.35, 0), rf = F(-0.6, 0.55, 0) },
	{ t = 0.42, ease = "inout" },
}, { move = { { from = 0.06, to = 0.2, dist = 10.0, dir = "input" } },
	markers = { { t = 0.06, name = "afterimage" } } })
K.flash_back = clip(0.42, {
	{ t = 0 },
	{ t = 0.06, ease = "out2", crouch = 0.55, lean = -6 },
	{ t = 0.16, ease = "linear", crouch = 0.6, lean = -12, lf = F(0.2, -0.35, 0.25), rf = F(-1.5, 0.55, 0.25) },
	{ t = 0.3, ease = "out2", crouch = 0.5, lean = 2, lf = F(0.7, -0.35, 0), rf = F(-0.6, 0.55, 0) },
	{ t = 0.42, ease = "inout" },
}, { move = { { from = 0.06, to = 0.2, dist = 7.0, dir = "input" } },
	markers = { { t = 0.06, name = "afterimage" } } })

K.arc = clip(1.0, {
	{ t = 0 },
	{ t = 0.2, ease = "inout", crouch = 0.6, lean = 4, pyaw = -48, twist = -32, rfYaw = -50, rh = H(0.2, 0.9, 0.3), lh = H(1.0, -0.5, 1.0) },
	{ t = 0.45, ease = "linear", crouch = 0.68, pyaw = -52, twist = -36 },
	{ t = 0.62, ease = "in3", crouch = 0.45, lean = 22, pyaw = 20, twist = 22, rfYaw = -8, rfPitch = 35,
		rh = H(2.1, 0.6, 0.85), dx = 0.4, lf = F(1.25, -0.35, 0), rf = F(-0.85, 0.55, 0) },
	{ t = 0.8, ease = "out2", crouch = 0.5, lean = 16, dx = 0.35, rh = H(1.6, 0.5, 0.85), lf = F(1.2, -0.35, 0), rf = F(-0.7, 0.55, 0) },
	{ t = 1.0, ease = "inout", dx = 0, crouch = 0.35, lean = 6, pyaw = -22, twist = -8, rfYaw = -38, rfPitch = 0, rh = H(0.85, 0.5, 0.8),
		lf = F(0.75, -0.35, 0), rf = F(-0.55, 0.55, 0) },
}, { move = { { from = 0.45, to = 0.65, dist = 4.4, dir = "fwd" } }, openOnMiss = 0.6,
	trail = { { from = 0.5, to = 0.8, hand = "RightHand" } },
	markers = { { t = 0.2, name = "windup_charge" }, hit(0.62, "kael_arc", "RightHand", "contact_arc") } })

K.storm = clip(0.95, {
	{ t = 0 },
	{ t = 0.18, ease = "inout", crouch = 0.66, lean = 10, pyaw = -50, twist = -34, rfYaw = -52, rh = H(0.3, 0.7, 0.0), lh = H(1.0, -0.5, 1.0) },
	{ t = 0.4, ease = "linear", crouch = 0.72, pyaw = -54 },
	{ t = 0.54, ease = "in3", crouch = 0.5, lean = 24, pyaw = 18, twist = 25, rfYaw = -8, rfPitch = 35,
		rh = H(2.25, 0.3, 0.8), dx = 0.45, lf = F(1.25, -0.35, 0), rf = F(-0.9, 0.55, 0) },
	{ t = 0.75, ease = "out2", crouch = 0.5, lean = 18, dx = 0.4, rh = H(1.8, 0.3, 0.8), lf = F(1.2, -0.35, 0), rf = F(-0.7, 0.55, 0) },
	{ t = 0.95, ease = "inout", dx = 0, crouch = 0.35, lean = 6, pyaw = -22, twist = -8, rfYaw = -38, rfPitch = 0, rh = H(0.85, 0.5, 0.8),
		lf = F(0.75, -0.35, 0), rf = F(-0.55, 0.55, 0) },
}, { move = { { from = 0.4, to = 0.56, dist = 14.0, dir = "fwd" } }, openOnMiss = 0.7,
	trail = { { from = 0.4, to = 0.8, hand = "RightHand" } },
	markers = { { t = 0.18, name = "windup_charge" }, hit(0.54, "kael_pierce", "RightHand", "contact_pierce") } })

K.sky = clip(0.85, {
	{ t = 0 },
	{ t = 0.12, ease = "out2", crouch = 0.75, lean = 6, pyaw = -30, twist = -18, rh = H(0.7, 0.6, -0.7), lh = H(1.0, -0.5, 0.95) },
	{ t = 0.28, ease = "in2", crouch = 0.15, lean = -4, pyaw = 12, twist = 14, rh = H(1.4, 0.5, 1.6), rfPitch = 30, rfYaw = -18, headPitch = -6 },
	{ t = 0.5, ease = "out2", crouch = 0.3, lean = 2, rh = H(1.1, 0.5, 1.3), headPitch = 0 },
	{ t = 0.85, ease = "inout", crouch = 0.35, lean = 6, pyaw = -22, twist = -8, rh = H(0.85, 0.5, 0.8), rfPitch = 0, rfYaw = -38 },
}, { move = { { from = 0.1, to = 0.3, dist = 1.2, dir = "fwd" } },
	trail = { { from = 0.2, to = 0.45, hand = "RightHand" } },
	markers = { hit(0.28, "kael_sky", "RightHand", "contact_sky") } })
K.sky_follow = clip(0.95, {
	{ t = 0 },
	{ t = 0.14, ease = "out2", crouch = 0.3, lean = -4, rh = H(0.2, 0.4, 1.6), lh = H(0.2, -0.4, 1.6), rp = H(0.0, 0.9, 0.3), lp = H(0.0, -0.9, 0.3),
		lf = F(0.9, -0.35, 0.8), rf = F(-0.1, 0.55, 0.9) },
	{ t = 0.34, ease = "linear", lean = -6 },
	{ t = 0.46, ease = "in3", crouch = 0.2, lean = 22, rh = H(1.4, 0.3, -0.5), lh = H(1.4, -0.3, -0.5), rp = H(0.3, 0.8, -0.2), lp = H(0.3, -0.8, -0.2) },
	{ t = 0.58, ease = "out2", crouch = 0.62, lean = 14, lf = F(1.1, -0.35, 0), rf = F(-0.3, 0.55, 0) },
	{ t = 0.95, ease = "inout", crouch = 0.35, lean = 6, rh = H(0.85, 0.5, 0.8), lh = H(1.15, -0.5, 0.85), rp = H(0.2, 0.9, -0.6), lp = H(0.2, -0.9, -0.6),
		lf = F(0.75, -0.35, 0), rf = F(-0.55, 0.55, 0) },
}, { lift = { { from = 0.08, to = 0.5, h = 2.0 } },
	trail = { { from = 0.36, to = 0.56, hand = "RightHand" } },
	markers = { { t = 0.46, name = "contact_skyfollow", op = "follow", hit = "kael_skyfollow", hand = "RightHand" } } })

K.slip = clip(0.6, {
	{ t = 0 },
	{ t = 0.08, ease = "out2", lean = -10, crouch = 0.55, pyaw = -40, twist = -14, headYaw = 8, dz = 0.2, lh = H(0.9, -0.5, 1.0), rh = H(0.7, 0.5, 0.95) },
	{ t = 0.22, ease = "inout", lean = -14, crouch = 0.6, roll = 8, dz = 0.35 },
	{ t = 0.4, ease = "inout", lean = 4, crouch = 0.45, roll = 0, dz = 0.1, headYaw = 0 },
	{ t = 0.6, ease = "inout", lean = 6, crouch = 0.35, pyaw = -22, twist = -8, dz = 0, lh = H(1.15, -0.5, 0.85), rh = H(0.85, 0.5, 0.8) },
}, { move = { { from = 0.04, to = 0.24, dist = 2.4, dir = "side" } }, win = { { kind = "dodge", from = 0.03, to = 0.34 } },
	markers = { { t = 0.06, name = "slip_whoosh" } } })
K.counter = clip(0.6, {
	{ t = 0 , pyaw = -34, twist = -14, crouch = 0.5, lean = -4, rh = H(0.6, 0.8, 0.8), lh = H(1.0, -0.6, 0.9) },
	{ t = 0.08, ease = "out2", pyaw = -46, twist = -26, lean = 2 },
	{ t = 0.18, ease = "in2", pyaw = 14, twist = 18, lean = 16, crouch = 0.42, rh = H(2.0, 0.6, 0.9), rfPitch = 28, rfYaw = -16 },
	{ t = 0.34, ease = "out2", lean = 10, rh = H(1.2, 0.5, 0.85), rfPitch = 6 },
	{ t = 0.6, ease = "inout", pyaw = -22, twist = -8, lean = 6, crouch = 0.35, rh = H(0.85, 0.5, 0.8), rfPitch = 0, rfYaw = -38 },
}, { move = { { from = 0.08, to = 0.2, dist = 1.0, dir = "fwd" } },
	trail = { { from = 0.12, to = 0.3, hand = "RightHand" } },
	markers = { hit(0.18, "kael_counter", "RightHand", "contact_counter") } })

K.form1_on = clip(1.0, {
	{ t = 0 },
	{ t = 0.2, ease = "inout", crouch = 0.62, lean = 5, rh = H(0.5, 0.2, 0.2), lh = H(0.5, -0.2, 0.2), rp = H(0.0, 0.6, -0.9), lp = H(0.0, -0.6, -0.9), headPitch = 8 },
	{ t = 0.45, ease = "out3", crouch = 0.25, lean = -2, rh = H(0.9, 1.3, 0.5), lh = H(0.9, -1.3, 0.5), rp = H(0.0, 1.0, -0.4), lp = H(0.0, -1.0, -0.4), headPitch = -4 },
	{ t = 0.75, ease = "inout", crouch = 0.4, lean = 5, headPitch = 2 },
	{ t = 1.0, ease = "inout", crouch = 0.35, lean = 6, rh = H(0.85, 0.5, 0.8), lh = H(1.15, -0.5, 0.85), rp = H(0.2, 0.9, -0.6), lp = H(0.2, -0.9, -0.6), headPitch = 3 },
}, { win = { { kind = "invuln", from = 0, to = 1.0 } },
	markers = { { t = 0.2, name = "pulse_gather" }, { t = 0.45, name = "pulse_chest", op = "formset", form = "Form1" }, { t = 0.6, name = "pulse_arms" } } })
K.final_on = clip(1.6, {
	{ t = 0 },
	{ t = 0.3, ease = "inout", crouch = 0.72, lean = 6, rh = H(0.5, 0.2, 0.0), lh = H(0.5, -0.2, 0.0), rp = H(0.0, 0.6, -0.9), lp = H(0.0, -0.6, -0.9) },
	{ t = 0.65, ease = "out3", crouch = 0.1, lean = -8, headPitch = -14, rh = H(0.5, 1.45, 0.9), lh = H(0.5, -1.45, 0.9), rp = H(0.0, 1.0, -0.2), lp = H(0.0, -1.0, -0.2), rf = F(-0.7, 0.8, 0), lf = F(0.7, -0.8, 0) },
	{ t = 1.0, ease = "inout", crouch = 0.2, lean = -3, headPitch = -6 },
	{ t = 1.6, ease = "inout", crouch = 0.35, lean = 6, headPitch = 3, rh = H(0.85, 0.5, 0.8), lh = H(1.15, -0.5, 0.85), rp = H(0.2, 0.9, -0.6), lp = H(0.2, -0.9, -0.6),
		rf = F(-0.55, 0.55, 0), lf = F(0.75, -0.35, 0) },
}, { win = { { kind = "invuln", from = 0, to = 1.6 } },
	markers = { { t = 0.3, name = "pulse_gather" }, { t = 0.65, name = "pulse_chest", op = "formset", form = "Final" }, { t = 0.95, name = "pulse_arms" } } })

K.thunder = clip(2.4, {
	{ t = 0 },
	{ t = 0.4, ease = "inout", crouch = 0.75, lean = 10, pyaw = -34, twist = -20, rh = H(0.6, 0.6, -0.4), lh = H(0.9, -0.5, 0.6) },
	{ t = 0.55, ease = "in2", crouch = 0.2, lean = -2, pyaw = 10, twist = 14, rh = H(1.5, 0.5, 1.65), lh = H(0.9, -0.6, 0.9), rfPitch = 30 },
	{ t = 0.75, ease = "out2", crouch = 0.3, lean = -6, rh = H(0.3, 0.5, 1.7), lh = H(0.3, -0.5, 1.7), rp = H(0.0, 0.9, 0.3), lp = H(0.0, -0.9, 0.3),
		lf = F(0.9, -0.35, 0.8), rf = F(-0.1, 0.55, 0.9), pyaw = -22, twist = -8 },
	{ t = 1.1, ease = "linear", lean = -8 },
	{ t = 1.28, ease = "in3", crouch = 0.2, lean = 26, rh = H(1.4, 0.3, -0.6), lh = H(1.4, -0.3, -0.6), rp = H(0.3, 0.8, -0.2), lp = H(0.3, -0.8, -0.2) },
	{ t = 1.45, ease = "out2", crouch = 0.8, lean = 18, lf = F(1.2, -0.35, 0), rf = F(-0.4, 0.55, 0) },
	{ t = 2.4, ease = "inout", crouch = 0.35, lean = 6, rh = H(0.85, 0.5, 0.8), lh = H(1.15, -0.5, 0.85), rp = H(0.2, 0.9, -0.6), lp = H(0.2, -0.9, -0.6),
		lf = F(0.75, -0.35, 0), rf = F(-0.55, 0.55, 0), pyaw = -22, twist = -8, rfPitch = 0 },
}, { move = { { from = 0.4, to = 0.56, dist = 7.0, dir = "fwd" } }, lift = { { from = 0.6, to = 1.3, h = 4.2 } },
	win = { { kind = "armor", from = 0.3, to = 1.6 } }, ult = true,
	trail = { { from = 0.45, to = 0.75, hand = "RightHand" }, { from = 1.1, to = 1.4, hand = "RightHand" } },
	markers = { { t = 0.3, name = "windup_charge" }, hit(0.55, "kael_thunder_launch", "RightHand", "contact_thunder_launch"),
		{ t = 0.6, name = "leap", op = "leap" },
		{ t = 1.28, name = "contact_thunder_slam", op = "slam", hit = "kael_thunder_slam", hand = "RightHand" } } })
do
	local r = reactions(KBASE, 1)
	for n, c in pairs(r) do K[n] = c end
end

---------------------------------------------------------------------------------------------- REN
local R = {}
R.idle = clip(3.2, {
	{ t = 0 },
	{ t = 1.6, ease = "inout", lean = 4.5, crouch = 0.53, headPitch = 1.5, rh = H(0.78, 0.35, 0.99) },
	{ t = 3.2, ease = "inout", lean = 3, crouch = 0.5, headPitch = 2, rh = H(0.78, 0.35, 0.95) },
}, { loop = true })
R.walk = clip(0.6, walk(0.85), { loop = true, walkStride = 1.7 })
R.guard = clip(0.22, {
	{ t = 0 },
	{ t = 0.13, ease = "out2", crouch = 0.6, lean = 2, lh = H(0.9, -0.2, 1.35), rh = H(0.75, 0.25, 1.2), lp = H(0.0, -0.3, -1.0), rp = H(0.0, 0.3, -1.0) },
	{ t = 0.22, ease = "linear" },
}, { clamp = true })
R.timed_block = clip(0.45, {
	{ t = 0, crouch = 0.6, lean = 2, lh = H(0.9, -0.2, 1.35), rh = H(0.75, 0.25, 1.2), lp = H(0.0, -0.3, -1.0), rp = H(0.0, 0.3, -1.0) },
	{ t = 0.06, ease = "out3", dx = -0.1, lh = H(1.35, 0.1, 1.3), rh = H(1.1, 0.35, 1.25), headPitch = 0 },
	{ t = 0.3, ease = "inout", dx = 0, lh = H(0.9, -0.2, 1.35), rh = H(0.75, 0.25, 1.2) },
	{ t = 0.45, ease = "linear" },
}, { markers = { { t = 0.05, name = "timed_ripple" } } })

R.m1_1 = clip(0.5, {
	{ t = 0 },
	{ t = 0.08, ease = "out2", lh = H(1.0, -0.35, 0.95), lean = 5 },
	{ t = 0.17, ease = "in2", lh = H(1.9, -0.25, 0.95), lean = 6, twist = -4 },
	{ t = 0.32, ease = "out2", lh = H(0.95, -0.4, 1.0), lean = 3, twist = -6 },
	{ t = 0.5, ease = "inout" },
}, { chain = 0.3, move = { { from = 0.05, to = 0.18, dist = 1.2, dir = "fwd" } },
	markers = { hit(0.17, "ren_jab", "LeftHand", "contact_jab") } })
R.m1_2 = clip(0.52, {
	{ t = 0 },
	{ t = 0.1, ease = "out2", pyaw = -30, twist = -16, crouch = 0.56, rh = H(0.5, 0.5, 0.8) },
	{ t = 0.19, ease = "in2", pyaw = 16, twist = 20, lean = 10, rh = H(1.35, 0.45, 1.0), rp = H(0.5, 0.9, -0.2) },
	{ t = 0.34, ease = "out2", pyaw = -18, twist = -6, lean = 3, rh = H(0.8, 0.35, 0.95), rp = H(0.0, 0.55, -0.85) },
	{ t = 0.52, ease = "inout", crouch = 0.5 },
}, { chain = 0.32, move = { { from = 0.06, to = 0.2, dist = 1.1, dir = "fwd" } },
	markers = { hit(0.19, "ren_elbow", "RightHand", "contact_elbow") } })
R.m1_3 = clip(0.66, {
	{ t = 0 },
	{ t = 0.14, ease = "out2", pyaw = -34, twist = -22, crouch = 0.58, rh = H(0.3, 1.0, 1.0), rp = H(0.0, 0.9, -0.5) },
	{ t = 0.29, ease = "in2", pyaw = 40, twist = 30, lean = 8, crouch = 0.5, rh = H(1.6, -0.35, 1.05), rp = H(0.3, 0.8, -0.4), headYaw = 6 },
	{ t = 0.46, ease = "out2", pyaw = -4, twist = 0, lean = 4, rh = H(1.0, 0.2, 1.0) },
	{ t = 0.66, ease = "inout", pyaw = -18, twist = -6, lean = 3, rh = H(0.78, 0.35, 0.95), headYaw = 0, rp = H(0.0, 0.55, -0.85) },
}, { chain = 0.4, move = { { from = 0.1, to = 0.3, dist = 1.3, dir = "fwd" } },
	trail = { { from = 0.2, to = 0.4, hand = "RightHand" } },
	markers = { hit(0.29, "ren_backfist", "RightHand", "contact_backfist") } })
R.m1_4 = clip(1.2, {
	{ t = 0 },
	{ t = 0.35, ease = "inout", crouch = 0.78, lean = 2, pyaw = -40, twist = -28, rh = H(0.3, 0.7, 0.4), lh = H(0.9, -0.5, 1.0) },
	{ t = 0.55, ease = "linear", crouch = 0.84, pyaw = -44 },
	{ t = 0.65, ease = "in3", crouch = 0.52, lean = 16, pyaw = 22, twist = 24, rh = H(2.0, 0.45, 1.0), lf = F(1.3, -0.4, 0), rfPitch = 25 },
	{ t = 0.85, ease = "out2", crouch = 0.62, lean = 12, rh = H(1.7, 0.4, 1.0) },
	{ t = 1.2, ease = "inout", crouch = 0.5, lean = 3, pyaw = -18, twist = -6, rh = H(0.78, 0.35, 0.95), lf = F(0.55, -0.4, 0), rfPitch = 0 },
}, { move = { { from = 0.45, to = 0.67, dist = 2.2, dir = "fwd" } }, anticipation = { 0.2, 0.6 },
	trail = { { from = 0.58, to = 0.85, hand = "RightHand" } },
	markers = { { t = 0.3, name = "anticipation_set" }, hit(0.65, "ren_palm", "RightHand", "contact_palm") } })

R.anchor = clip(2.3, {
	{ t = 0 },
	{ t = 0.22, ease = "out2", crouch = 0.92, lean = 0, pyaw = 0, twist = 0, rfYaw = 0, lfYaw = 0, headPitch = 4,
		lf = F(0.8, -0.65, 0), rf = F(-0.8, 0.85, 0), rh = H(0.8, 0.8, 0.5), lh = H(0.9, -0.8, 0.5), rp = H(0.0, 0.9, -0.5), lp = H(0.0, -0.9, -0.5) },
	{ t = 1.75, ease = "linear", crouch = 0.95 },
	{ t = 1.9, ease = "out3", crouch = 0.55, lean = 14, rh = H(1.75, 0.45, 0.95), lh = H(1.75, -0.45, 0.95), rp = H(0.3, 0.8, -0.3), lp = H(0.3, -0.8, -0.3) },
	{ t = 2.3, ease = "inout", crouch = 0.5, lean = 3, pyaw = -18, twist = -6, rfYaw = -30, lfYaw = -6, headPitch = 2,
		lf = F(0.55, -0.4, 0), rf = F(-0.5, 0.6, 0), rh = H(0.78, 0.35, 0.95), lh = H(0.95, -0.4, 1.0), rp = H(0.0, 0.55, -0.85), lp = H(0.0, -0.55, -0.85) },
}, { win = { { kind = "armor", from = 0.2, to = 1.75 } }, noMove = true,
	markers = { { t = 0.22, name = "anchor_plant" }, { t = 1.9, name = "anchor_release" } } })
R.pulse = clip(1.05, {
	{ t = 0 },
	{ t = 0.28, ease = "out2", crouch = 0.4, lean = -2, rh = H(0.5, 0.6, 1.55), rp = H(0.0, 0.8, -0.3) },
	{ t = 0.5, ease = "in3", crouch = 0.88, lean = 22, rh = H(1.4, 0.3, -0.9), lh = H(0.9, -0.5, 0.5), rp = H(0.3, 0.7, -0.3) },
	{ t = 0.7, ease = "linear", crouch = 0.9 },
	{ t = 1.05, ease = "inout", crouch = 0.5, lean = 3, rh = H(0.78, 0.35, 0.95), lh = H(0.95, -0.4, 1.0), rp = H(0.0, 0.55, -0.85) },
}, { trail = { { from = 0.36, to = 0.56, hand = "RightHand" } },
	markers = { { t = 0.28, name = "pulse_raise" }, { t = 0.5, name = "contact_pulse", op = "hit", hit = "ren_pulse", hand = "RightHand", fx = "ring_ground" } } })
R.void_counter = clip(0.85, {
	{ t = 0, crouch = 0.6, lean = 2, lh = H(0.9, -0.2, 1.35), rh = H(0.75, 0.25, 1.2), lp = H(0.0, -0.3, -1.0), rp = H(0.0, 0.3, -0.9) },
	{ t = 0.1, ease = "out2", pyaw = -30, twist = -20, lh = H(1.0, -0.95, 1.1), crouch = 0.55, rh = H(0.5, 0.6, 0.9) },
	{ t = 0.24, ease = "in2", pyaw = 20, twist = 24, lean = 14, crouch = 0.5, rh = H(1.95, 0.3, 1.0), lh = H(0.8, -0.4, 1.0) },
	{ t = 0.4, ease = "out2", lean = 8, rh = H(1.3, 0.35, 1.0) },
	{ t = 0.85, ease = "inout", pyaw = -18, twist = -6, lean = 3, crouch = 0.5, rh = H(0.78, 0.35, 0.95), lh = H(0.95, -0.4, 1.0) },
}, { move = { { from = 0.12, to = 0.26, dist = 1.2, dir = "fwd" } },
	trail = { { from = 0.1, to = 0.32, hand = "LeftHand" }, { from = 0.18, to = 0.38, hand = "RightHand" } },
	markers = { { t = 0.1, name = "redirect_arc" }, hit(0.24, "ren_counter", "RightHand", "contact_counter") } })

R.rift_on = clip(1.1, {
	{ t = 0 },
	{ t = 0.22, ease = "inout", crouch = 0.88, pyaw = 0, twist = 0, lean = 0, rh = H(0.6, -0.2, 0.9), lh = H(0.6, 0.2, 0.9), rp = H(0.0, 0.5, -0.8), lp = H(0.0, -0.5, -0.8) },
	{ t = 0.5, ease = "out3", crouch = 0.92, rh = H(0.7, 1.1, 0.4), lh = H(0.7, -1.1, 0.4), rp = H(0.0, 1.0, -0.4), lp = H(0.0, -1.0, -0.4) },
	{ t = 0.8, ease = "inout", crouch = 0.7 },
	{ t = 1.1, ease = "inout", crouch = 0.5, lean = 3, pyaw = -18, twist = -6, rh = H(0.78, 0.35, 0.95), lh = H(0.95, -0.4, 1.0), rp = H(0.0, 0.55, -0.85), lp = H(0.0, -0.55, -0.85) },
}, { win = { { kind = "invuln", from = 0, to = 1.1 } }, noMove = true,
	markers = { { t = 0.22, name = "pulse_gather" }, { t = 0.5, name = "pulse_forearms", op = "formset", form = "Form1" } } })
R.eclipse_on = clip(1.7, {
	{ t = 0 },
	{ t = 0.4, ease = "inout", crouch = 0.95, pyaw = 0, twist = 0, lean = 0, rh = H(0.5, 0.5, 0.2), lh = H(0.5, -0.5, 0.2), rp = H(0.0, 0.6, -0.9), lp = H(0.0, -0.6, -0.9) },
	{ t = 0.85, ease = "out3", crouch = 0.4, lean = -4, headPitch = -10, rh = H(0.5, 1.25, 1.4), lh = H(0.5, -1.25, 1.4), rp = H(0.0, 1.0, 0.0), lp = H(0.0, -1.0, 0.0) },
	{ t = 1.1, ease = "inout", crouch = 0.55, headPitch = -4 },
	{ t = 1.7, ease = "inout", crouch = 0.5, lean = 3, pyaw = -18, twist = -6, headPitch = 2, rh = H(0.78, 0.35, 0.95), lh = H(0.95, -0.4, 1.0), rp = H(0.0, 0.55, -0.85), lp = H(0.0, -0.55, -0.85) },
}, { win = { { kind = "invuln", from = 0, to = 1.7 } }, noMove = true,
	markers = { { t = 0.4, name = "pulse_gather" }, { t = 0.85, name = "pulse_forearms", op = "formset", form = "Final" }, { t = 1.1, name = "pulse_orbit" } } })

R.horizon = clip(3.4, {
	{ t = 0 },
	{ t = 0.5, ease = "out2", crouch = 0.45, lean = -2, rh = H(0.5, 1.25, 1.5), lh = H(0.5, -1.25, 1.5), rp = H(0.0, 1.0, 0.0), lp = H(0.0, -1.0, 0.0) },
	{ t = 1.7, ease = "linear", crouch = 0.4, lean = -3 },
	{ t = 1.85, ease = "in3", crouch = 0.92, lean = 22, rh = H(1.2, 0.4, -0.9), lh = H(1.2, -0.4, -0.9), rp = H(0.3, 0.7, -0.3), lp = H(0.3, -0.7, -0.3) },
	{ t = 2.2, ease = "linear", crouch = 0.95 },
	{ t = 3.4, ease = "inout", crouch = 0.5, lean = 3, pyaw = -18, twist = -6, rh = H(0.78, 0.35, 0.95), lh = H(0.95, -0.4, 1.0), rp = H(0.0, 0.55, -0.85), lp = H(0.0, -0.55, -0.85) },
}, { noMove = true, ult = true, win = { { kind = "armor", from = 0.2, to = 2.2 } },
	markers = {
		{ t = 0.3, name = "field_open", op = "field", dur = 1.5 },
		{ t = 0.6, name = "pull1", op = "pull" }, { t = 0.8, name = "pull2", op = "pull" }, { t = 1.0, name = "pull3", op = "pull" },
		{ t = 1.2, name = "pull4", op = "pull" }, { t = 1.4, name = "pull5", op = "pull" }, { t = 1.6, name = "pull6", op = "pull" },
		{ t = 1.85, name = "contact_horizon_blast", op = "hit", hit = "ren_horizon_blast", hand = "RightHand", fx = "ring_ground" },
	} })
do
	local r = reactions(RBASE, 0.7)
	for n, c in pairs(r) do R[n] = c end
end

Clips.Kael, Clips.Ren = K, R

-- SPEED: the keyframes above are authored at "1.0"; the game plays them faster (k < 1 shortens every non-looping clip:
-- keys, markers, move / lift / window times). Change DEFAULT_SPEED to taste, or call Clips.setSpeed(1) for the authored timing.
Clips.DEFAULT_SPEED = 0.78
local function deep(t)
	if type(t) ~= "table" then return t end
	local r = {}
	for k, v in pairs(t) do r[k] = deep(v) end
	return r
end
local ORIG = { Kael = deep(K), Ren = deep(R) }
local function scaleClip(c, k)
	c.dur = c.dur * k
	for _, key in ipairs(c.keys) do key.t = key.t * k end
	for _, mk in ipairs(c.markers) do mk.t = mk.t * k end
	if c.chain then c.chain = c.chain * k end
	for _, list in ipairs({ c.move or {}, c.lift or {}, c.win or {}, c.trail or {} }) do
		for _, x in ipairs(list) do x.from, x.to = x.from * k, x.to * k end
	end
	if c.anticipation then c.anticipation = { c.anticipation[1] * k, c.anticipation[2] * k } end
end
function Clips.setSpeed(k)
	for char, set in pairs(ORIG) do
		for name, c in pairs(set) do
			local n = deep(c)
			if not n.loop and k ~= 1 then scaleClip(n, k) end
			Clips[char][name] = n
		end
	end
	Clips.speed = k
end
Clips.setSpeed(Clips.DEFAULT_SPEED)

-- Engine data for one fighter (what BGEngine.bake wants): every clip becomes a named track.
function Clips.engineData(char)
	local fighters = {}
	for name, c in pairs(Clips[char]) do
		fighters[name] = { baseYaw = -90, anchor = { x = 0, z = 0 }, base = Clips.bases[char], keys = c.keys }
	end
	return { fighters = fighters, contacts = {} }
end

return Clips
]====])
put(RS, "ModuleScript", "BGCore", [====[
-- BGCore (ModuleScript, ReplicatedStorage): authoritative combat rules, no Roblox instances.
-- The server script owns one Core, feeds it player input and reads back snapshots + events.
-- Everything here (hits, blocks, dodges, meter, forms, ultimates, cooldowns) is decided on the server only.
local Core = {}
Core.__index = Core

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end   -- Luau has atan2, Lua 5.4 only has two-argument atan
local function clamp(x, a, b) return math.max(a, math.min(b, x)) end
local function hyp(x, z) return math.sqrt(x * x + z * z) end
local function wrap(a) while a > math.pi do a = a - 2 * math.pi end while a < -math.pi do a = a + 2 * math.pi end return a end

local ULT = { Kael = "thunder", Ren = "horizon" }
local FORM1 = { Kael = "form1_on", Ren = "rift_on" }
local FINAL = { Kael = "final_on", Ren = "eclipse_on" }

---------------------------------------------------------------------------------------------- setup
local function newFighter(id, char, x, z, ang)
	return {
		id = id, char = char, x = x, z = z, ang = ang, y = 0, hp = 0, meter = 0, form = "Base",
		state = "idle", act = nil, guardHeld = false, guardStart = -9, inF = 0, inS = 0, moving = false, moveBack = false,
		cd = {}, charges = 1, flashNext = nil, comboIdx = 0, comboLast = -9, bufM1 = -9,
		staggerUntil = 0, staggerClip = "hit", knockedUntil = 0, openUntil = 0, air = nil,
		counterUntil = -1, riposteUntil = -1, riposteTarget = nil, stored = false, followUntil = -1, followFrom = -1,
		finalUntil = 0, ultUsed = false, push = nil, react = nil, lift = 0,
		clip = "idle", clipT0 = 0, clipSpeed = 1, seq = 0, koAt = nil,
	}
end

function Core.new(cfg, clips, opts)
	opts = opts or {}
	local w = setmetatable({ cfg = cfg, clips = clips, t = 0, freeze = 0, events = {}, rng = opts.rng or math.random }, Core)
	w.f = {
		Blue = newFighter("Blue", "Kael", -cfg.arena.spawn, 0, 0),
		Purple = newFighter("Purple", "Ren", cfg.arena.spawn, 0, math.pi),
	}
	w.ai = {}
	w:reset()
	return w
end

function Core:reset()
	local cfg = self.cfg
	for id, f in pairs(self.f) do
		local keepChar = f.char
		local nf = newFighter(id, keepChar, id == "Blue" and -cfg.arena.spawn or cfg.arena.spawn, 0, id == "Blue" and 0 or math.pi)
		nf.hp = cfg.hpMax
		nf.clipT0 = self.t
		self.f[id] = nf
	end
	for _, ai in pairs(self.ai) do ai.queue = {}; ai.nextAt = self.t + 1.5 end
	self.freeze = 0
	self:emit("reset", {})
end

function Core:emit(kind, t)
	t.type, t.t = kind, self.t
	self.events[#self.events + 1] = t
end
function Core:drain()
	local e = self.events
	self.events = {}
	return e
end
function Core:other(f) return self.f[f.id == "Blue" and "Purple" or "Blue"] end
function Core:meta(f, name) return self.clips[f.char][name] end

---------------------------------------------------------------------------------------------- helpers
local function fwdVec(f) return math.cos(f.ang), math.sin(f.ang) end
local function rightVec(f) return -math.sin(f.ang), math.cos(f.ang) end

function Core:tempo(f)
	local fm = self.cfg.form[f.form]
	return fm and fm.tempo or 1
end

function Core:setClip(f, name, speed)
	f.clip, f.clipT0, f.clipSpeed, f.seq = name, self.t, speed or 1, f.seq + 1
end

function Core:win(f, kind)
	local a = f.act
	if not a then return false end
	local w = a.meta.win
	if not w then return false end
	for _, x in ipairs(w) do
		if x.kind == kind and a.t >= x.from and a.t <= x.to then return true end
	end
	return false
end

function Core:canAct(f)
	return f.act == nil and (f.state == "idle" or f.state == "block") and f.hp > 0
end

function Core:clampPos(f)
	local r = self.cfg.arena.radius
	local d = hyp(f.x, f.z)
	if d > r then f.x, f.z = f.x * r / d, f.z * r / d end
end

-- move without stepping through the other fighter (unless airborne) and stay in the arena
function Core:moveBy(f, dx, dz)
	local o = self:other(f)
	local nx, nz = f.x + dx, f.z + dz
	if f.lift < 0.3 and o.y < 0.3 and o.lift < 0.3 then
		local gap = self.cfg.arena.minGap
		local ox, oz = nx - o.x, nz - o.z
		local d = hyp(ox, oz)
		if d < gap then
			if d < 1e-4 then ox, oz, d = -math.cos(f.ang), -math.sin(f.ang), 1 end
			nx, nz = o.x + ox / d * gap, o.z + oz / d * gap
		end
	end
	f.x, f.z = nx, nz
	self:clampPos(f)
end

function Core:faceOpponent(f, dt, rate)
	local o = self:other(f)
	local want = atan2(o.z - f.z, o.x - f.x)
	local diff = wrap(want - f.ang)
	if rate then
		local step = math.rad(rate) * dt
		f.ang = wrap(f.ang + clamp(diff, -step, step))
	else
		f.ang = want
	end
end

function Core:addMeter(f, n)
	if n <= 0 then return end
	if f.form == "Final" then f.meter = self.cfg.meter.max; return end
	f.meter = math.min(self.cfg.meter.max, f.meter + n)
	self:emit("meter", { f = f.id, v = f.meter })
end

function Core:cooldownReady(f, key) return (f.cd[key] or 0) <= self.t end
function Core:startCd(f, key) f.cd[key] = self.t + (self.cfg.cd[f.char][key] or 0) end

function Core:maxCharges(f) return f.form == "Base" and self.cfg.flash.charges or self.cfg.flash.chargesForm end

---------------------------------------------------------------------------------------------- actions
function Core:startAct(f, name, extra)
	local m = self:meta(f, name)
	assert(m, "no clip " .. tostring(name) .. " for " .. f.char)
	f.state = "act"
	f.guardHeld = f.guardHeld   -- keep the held key; guard resumes after the action
	f.react = nil
	self:faceOpponent(f, 0)
	local a = { clip = name, t = 0, meta = m, fired = {}, landed = false, blocked = false }
	if extra then for k, v in pairs(extra) do a[k] = v end end
	-- movement direction for input-directed dashes
	local fx, fz = fwdVec(f)
	local rx, rz = rightVec(f)
	local vx, vz = fx * f.inF + rx * f.inS, fz * f.inF + rz * f.inS
	if hyp(vx, vz) < 0.2 then vx, vz = fx, fz end
	local l = hyp(vx, vz)
	a.dirx, a.dirz = vx / l, vz / l
	a.sideSign = (f.inS < -0.3) and -1 or 1
	f.act = a
	self:setClip(f, name, self:tempo(f))
	self:emit("act", { f = f.id, clip = name })
	return a
end

function Core:endForm(f, why)
	if f.form == "Base" then return end
	if f.form == "Final" then f.meter = 0 else f.meter = math.min(f.meter, self.cfg.meter.form1) end   -- the first form ends AT 50%; the final form resets to 0
	f.form = "Base"
	f.ultUsed = false
	f.stored = false
	f.charges = math.min(f.charges, 1)
	f.flashNext = nil
	self:emit("form", { f = f.id, form = "Base", why = why })
end

function Core:cancelAct(f, interrupted)
	local a = f.act
	if not a then return end
	f.act = nil
	f.lift = 0
	if a.meta.ult and interrupted then self:endForm(f, "interrupted") end
end

function Core:endAct(f)
	local a = f.act
	f.act = nil
	f.lift = 0
	f.state = "idle"
	if a.clip:sub(1, 3) == "m1_" then f.comboLast = self.t end
	if a.clip == "m1_4" then f.comboIdx = 0 end
	if a.meta.openOnMiss and not a.landed and not a.blocked then
		f.openUntil = self.t + a.meta.openOnMiss
		f.state = "open"
		self:emit("open", { f = f.id })
	end
	if a.meta.ult then self:endForm(f, "ultimate") end
	if f.state == "idle" and f.guardHeld then f.state, f.guardStart = "block", self.t end
end

---------------------------------------------------------------------------------------------- hit resolution
function Core:damage(f, n, src)
	if n <= 0 then return end
	f.hp = math.max(0, f.hp - n)
	if f.hp <= 0 and not f.koAt then
		f.koAt = self.t
		self:emit("ko", { f = f.id })
	end
end

function Core:applyPush(f, dirx, dirz, dist, dur)
	if dist <= 0 then return end
	f.push = { vx = dirx * dist / (dur or 0.25), vz = dirz * dist / (dur or 0.25), left = dur or 0.25 }
end

-- returns "hit" | "block" | "timed" | "dodged" | "armor" | "miss"
function Core:resolveHit(att, hid, a, opts)
	opts = opts or {}
	local cfg = self.cfg
	local h = cfg.hits[hid]
	local tgt = self:other(att)
	local dx, dz = tgt.x - att.x, tgt.z - att.z
	local dist = hyp(dx, dz)
	local range = h.range
	if h.range1 and att.form ~= "Base" then range = h.range1 end
	if opts.range then range = opts.range end
	if dist > range then return "miss" end
	local ux, uz = 1, 0
	if dist > 1e-4 then ux, uz = dx / dist, dz / dist end
	if (h.arc or 360) < 360 then
		local fx, fz = fwdVec(att)
		if ux * fx + uz * fz < math.cos(math.rad(h.arc / 2)) then return "miss" end
	end
	if tgt.state == "air" and not opts.airOK then return "miss" end
	if self:win(tgt, "invuln") then return "miss" end
	if tgt.hp <= 0 then return "miss" end
	local pos = { x = tgt.x, z = tgt.z }

	-- Static Slip dodge
	if self:win(tgt, "dodge") and not h.area then
		tgt.counterUntil = self.t + cfg.slip.counterWindow
		self:addMeter(tgt, cfg.gain.dodge)
		self:emit("dodge", { f = tgt.id, by = att.id, hit = hid, x = pos.x, z = pos.z })
		return "dodged"
	end

	local dmg = h.dmg
	-- block
	if tgt.state == "block" and not h.unblockable then
		local tx, tz = fwdVec(tgt)
		if -ux * tx + -uz * tz >= math.cos(math.rad(cfg.guard.arc / 2)) then
			local timed = tgt.char == "Ren" and (self.t - tgt.guardStart) <= cfg.guard.timedWindow
			self:damage(tgt, dmg * cfg.guard.blockMult, att)
			self.freeze = math.max(self.freeze, cfg.hitstop.block)
			a.blocked = true
			self:applyPush(tgt, ux, uz, cfg.guard.blockPush, 0.15)
			if timed then
				self:addMeter(tgt, cfg.gain.timedBlock)
				tgt.riposteUntil = self.t + cfg.guard.riposteWindow
				tgt.riposteTarget = att.id
				if tgt.form == "Final" then tgt.stored = true end
				local st = cfg.guard.timedStagger[tgt.form] or 0.55
				self:cancelAct(att, false)
				att.state, att.staggerUntil, att.staggerClip = "stagger", self.t + st, "hit"
				self:setClip(att, "hit")
				tgt.react = { clip = "timed_block", untilT = self.t + 0.45 }
				self:setClip(tgt, "timed_block")
				self:emit("timed", { f = tgt.id, by = att.id, hit = hid, x = pos.x, z = pos.z, stored = tgt.stored })
				return "timed"
			end
			self:addMeter(tgt, cfg.gain.block)
			tgt.react = { clip = "guard_hit", untilT = self.t + 0.26 }
			self:setClip(tgt, "guard_hit")
			self:emit("block", { f = tgt.id, by = att.id, hit = hid, x = pos.x, z = pos.z })
			return "block"
		end
	end

	local fm = cfg.form[att.form]
	if fm then dmg = dmg * fm.dmg end
	if tgt.state == "open" then dmg = dmg * cfg.openDamageMult end
	if opts.dmgMult then dmg = dmg * opts.dmgMult end
	self:damage(tgt, dmg, att)
	self.freeze = math.max(self.freeze, ((h.push or 0) > 0 or dmg >= 10) and cfg.hitstop.big or cfg.hitstop.light)
	a.landed = true
	self:addMeter(att, h.mg or 0)

	-- armour (Anchor Step, ultimate wind-ups): damage lands, no stagger or push
	if self:win(tgt, "armor") then
		self:emit("hit", { f = tgt.id, by = att.id, hit = hid, armor = true, dmg = dmg, x = pos.x, z = pos.z })
		return "armor"
	end

	if tgt.act then self:cancelAct(tgt, true) end
	tgt.react = nil
	tgt.guardHeld = tgt.guardHeld
	if h.launch then
		tgt.air = { t0 = self.t, dur = h.airTime or 1.0, h = h.airH or 3.5 }
		tgt.state, tgt.y = "air", 0
		self:setClip(tgt, "air")
		if hid == "kael_sky" then
			att.followFrom = self.t + 0.15
			att.followUntil = self.t + tgt.air.dur - 0.05
		end
	else
		local st = h.stagger or 0.3
		if h.stagger1 and att.form ~= "Base" then st = h.stagger1 end
		if opts.staggerMult then st = st * opts.staggerMult end
		local push = (opts.push or h.push or 0)
		tgt.state = "stagger"
		tgt.staggerUntil = math.max(tgt.staggerUntil, self.t + st)
		tgt.staggerClip = (push > 0 or st >= 0.8) and "knock" or "hit"
		self:setClip(tgt, tgt.staggerClip)
		self:applyPush(tgt, ux, uz, push, 0.25)
	end
	self:emit("hit", { f = tgt.id, by = att.id, hit = hid, dmg = dmg, x = pos.x, z = pos.z, launch = h.launch, final = (h.push or 0) > 0 })
	return "hit"
end

---------------------------------------------------------------------------------------------- markers
function Core:marker(f, a, mk)
	local o = self:other(f)
	self:emit("marker", { f = f.id, clip = a.clip, name = mk.name, hand = mk.hand, fx = mk.fx, op = mk.op, x = f.x, z = f.z, ang = f.ang })
	if mk.op == "hit" then
		local opts
		if a.clip == "void_counter" and a.stored then opts = { dmgMult = self.cfg.eclipseCounterMult, push = (self.cfg.hits.ren_counter.push or 0) * 1.5 } end
		local res = self:resolveHit(f, mk.hit, a, opts)
		if a.clip == "void_counter" and a.stored and res == "hit" then f.stored = false end
		if a.clip == "counter" and res == "hit" then self:addMeter(f, self.cfg.gain.counterLanded) end
		self:emit("result", { f = f.id, hit = mk.hit, result = res })
	elseif mk.op == "follow" then
		if o.state == "air" then
			local res = self:resolveHit(f, mk.hit, a, { airOK = true, range = 7 })
			if res == "hit" or res == "armor" then
				-- bring the opponent back down with a compact impact
				o.air = nil
				o.y = 0
				o.state, o.staggerUntil, o.staggerClip = "stagger", self.t + (self.cfg.hits.kael_skyfollow.stagger or 0.8), "knock"
				self:setClip(o, "knock")
				self:emit("slam", { f = o.id, x = o.x, z = o.z, small = true })
			end
			self:emit("result", { f = f.id, hit = mk.hit, result = res })
		else
			self:emit("result", { f = f.id, hit = mk.hit, result = "miss" })
		end
	elseif mk.op == "slam" then
		local res = self:resolveHit(f, mk.hit, a, { airOK = true })
		if o.state == "air" then
			o.air = nil
			o.y = 0
			o.state, o.staggerUntil, o.staggerClip = "stagger", self.t + (self.cfg.hits[mk.hit].stagger or 1.0), "knock"
			self:setClip(o, "knock")
		end
		self:emit("slam", { f = o.id, x = f.x, z = f.z, big = true })
		self:emit("result", { f = f.id, hit = mk.hit, result = res })
	elseif mk.op == "field" then
		a.field = { x = f.x, z = f.z }
		self:emit("field", { f = f.id, x = f.x, z = f.z, radius = self.cfg.horizon.radius, dur = mk.dur or 1.5 })
	elseif mk.op == "pull" then
		local fl = a.field
		if fl and o.state ~= "air" and not self:win(o, "invuln") then
			local dx, dz = fl.x - o.x, fl.z - o.z
			local d = hyp(dx, dz)
			if d <= self.cfg.horizon.radius and d > 1e-3 then
				local step = math.min(self.cfg.horizon.pullSpeed * 0.2, math.max(0, d - self.cfg.arena.minGap))
				self:applyPush(o, dx / d, dz / d, step, 0.19)
				self:emit("pull", { f = o.id })
			end
		end
	elseif mk.op == "formset" then
		f.form = mk.form
		if mk.form == "Final" then
			f.meter = self.cfg.meter.max
			f.finalUntil = self.t + self.cfg.meter.finalDuration
			f.ultUsed = false
		else
			f.meter = math.max(f.meter, self.cfg.meter.form1 + self.cfg.meter.form1Surge)
		end
		f.charges = self:maxCharges(f)
		self:emit("form", { f = f.id, form = mk.form })
	end
end

---------------------------------------------------------------------------------------------- input
function Core:input(id, kind, a, b)
	local f = self.f[id]
	if not f then return false end
	local cfg = self.cfg
	if kind == "move" then
		f.inF, f.inS = clamp(tonumber(a) or 0, -1, 1), clamp(tonumber(b) or 0, -1, 1)
		return true
	elseif kind == "guard" then
		f.guardHeld = a and true or false
		if f.guardHeld and self:canAct(f) and f.state ~= "block" then
			f.state, f.guardStart = "block", self.t
		elseif not f.guardHeld and f.state == "block" then
			f.state = "idle"
		end
		return true
	end
	if f.hp <= 0 then return false end
	if kind == "m1" then
		local act = f.act
		if act and act.clip:sub(1, 3) == "m1_" and act.meta.chain then f.bufM1 = self.t; return true end
		if not self:canAct(f) then return false end
		local idx = 1
		if f.comboIdx > 0 and f.comboIdx < 4 and self.t - f.comboLast < cfg.combo.reset then idx = f.comboIdx + 1 end
		f.comboIdx = idx
		self:startAct(f, "m1_" .. idx)
		return true
	elseif kind == "skill" then
		return self:skill(f, a)
	elseif kind == "counter" then
		if f.char == "Kael" then
			local ok = f.counterUntil > self.t and (self:canAct(f) or (f.act and f.act.clip == "slip" and f.act.t >= 0.12))
			if not ok then return false end
			f.counterUntil = -1
			self:cancelAct(f, false)
			self:startAct(f, "counter")
			return true
		else
			if not (f.riposteUntil > self.t and (self:canAct(f) or (f.act and f.act.clip == "timed_block"))) then return false end
			f.riposteUntil = -1
			self:cancelAct(f, false)
			self:startAct(f, "void_counter", { stored = f.stored })
			return true
		end
	elseif kind == "ult" then
		if f.form ~= "Final" or f.ultUsed or not self:canAct(f) then return false end
		f.ultUsed = true
		self:startAct(f, ULT[f.char])
		return true
	elseif kind == "form1" then
		if f.form ~= "Base" or f.meter < cfg.meter.form1 or not self:canAct(f) then return false end
		self:startAct(f, FORM1[f.char])
		return true
	elseif kind == "final" then
		if f.form == "Final" or f.meter < cfg.meter.final or not self:canAct(f) then return false end
		self:startAct(f, FINAL[f.char])
		return true
	end
	return false
end

function Core:skill(f, id)
	if f.char == "Kael" then
		if id == 1 then
			if not self:canAct(f) or f.charges < 1 then return false end
			f.charges = f.charges - 1
			if not f.flashNext then f.flashNext = self.t + self.cfg.cd.Kael.flash end
			self:startAct(f, f.inF < -0.3 and math.abs(f.inS) < 0.6 and "flash_back" or "flash")
			return true
		elseif id == 2 then
			if not self:canAct(f) or not self:cooldownReady(f, "arc") then return false end
			self:startCd(f, "arc")
			self:startAct(f, f.form == "Final" and "storm" or "arc")
			return true
		elseif id == 3 then
			local o = self:other(f)
			local cancelOk = f.act and f.act.clip == "sky" and f.act.t >= 0.3
			if o.state == "air" and self.t >= f.followFrom and self.t <= f.followUntil and (self:canAct(f) or cancelOk) then
				f.followUntil = -1
				self:cancelAct(f, false)
				self:startAct(f, "sky_follow")
				return true
			end
			if not self:canAct(f) or not self:cooldownReady(f, "sky") then return false end
			self:startCd(f, "sky")
			self:startAct(f, "sky")
			return true
		elseif id == 4 then
			if not self:canAct(f) or not self:cooldownReady(f, "slip") then return false end
			self:startCd(f, "slip")
			self:startAct(f, "slip")
			return true
		end
	else
		if id == 1 then
			if not self:canAct(f) or not self:cooldownReady(f, "anchor") then return false end
			self:startCd(f, "anchor")
			self:startAct(f, "anchor")
			return true
		elseif id == 2 then
			if not self:canAct(f) or not self:cooldownReady(f, "pulse") then return false end
			self:startCd(f, "pulse")
			self:startAct(f, "pulse")
			return true
		end
	end
	return false
end

-- Studio-only preview: jump straight to a form (the server script refuses this outside Studio).
function Core:forceForm(id, form)
	local f = self.f[id]
	local cfg = self.cfg
	self:cancelAct(f, false)
	f.state, f.air, f.y, f.staggerUntil, f.openUntil, f.push, f.react = "idle", nil, 0, 0, 0, nil, nil
	if form == "Base" then
		f.form = "Base"; f.meter = 0; f.ultUsed = false; f.stored = false; f.charges = 1
		self:setClip(f, "idle")
		self:emit("form", { f = f.id, form = "Base", why = "preview" })
	elseif form == "Form1" then
		if f.form == "Final" then f.form = "Base" end
		f.meter = 75
		self:startAct(f, FORM1[f.char])
	elseif form == "Final" then
		f.meter = cfg.meter.max
		self:startAct(f, FINAL[f.char])
	end
end

function Core:setAI(id, mode)
	if mode == nil or mode == "Off" then self.ai[id] = nil; return end
	self.ai[id] = { mode = mode, queue = {}, nextAt = self.t + 1.0 }
end

---------------------------------------------------------------------------------------------- update
function Core:updateAI(f, dt)
	local ai = self.ai[f.id]
	if not ai then return end
	local o = self:other(f)
	local dist = hyp(o.x - f.x, o.z - f.z)
	if ai.mode == "Guard" then
		if not f.guardHeld then self:input(f.id, "guard", true) end
		self:input(f.id, "move", 0, 0)
		return
	end
	if f.guardHeld then self:input(f.id, "guard", false) end
	if ai.mode == "Idle" then self:input(f.id, "move", 0, 0); return end
	-- Attack: approach, then throw a short sequence so dodges and timed blocks can be tested
	if not self:canAct(f) then return end
	if dist > self.cfg.ai.approachRange + 0.6 then self:input(f.id, "move", 1, 0) else self:input(f.id, "move", 0, 0) end
	if #ai.queue > 0 and self.t >= ai.queue[1].at then
		local q = table.remove(ai.queue, 1)
		if q.kind == "m1" then self:input(f.id, "m1") else self:input(f.id, "skill", q.id) end
	elseif #ai.queue == 0 and self.t >= ai.nextAt and dist <= self.cfg.ai.approachRange + 0.8 then
		local r = self.rng()
		if r < 0.5 then
			for i = 0, 3 do ai.queue[#ai.queue + 1] = { at = self.t + i * 0.3, kind = "m1" } end
		else
			ai.queue[1] = { at = self.t, kind = "skill", id = 2 }
		end
		ai.nextAt = self.t + self.cfg.ai.interval * (0.8 + 0.4 * self.rng())
	end
end

function Core:updateFighter(f, dt)
	local cfg = self.cfg
	local o = self:other(f)

	-- meter, forms, charges
	if f.form == "Form1" then
		f.meter = f.meter - cfg.meter.drain * dt
		if f.meter <= cfg.meter.form1 then f.meter = cfg.meter.form1; self:endForm(f, "drained") end
	elseif f.form == "Final" and self.t >= f.finalUntil and not (f.act and f.act.meta.ult) then
		self:endForm(f, "timeout")
	end
	if f.flashNext and self.t >= f.flashNext then
		f.charges = math.min(self:maxCharges(f), f.charges + 1)
		f.flashNext = f.charges < self:maxCharges(f) and (self.t + cfg.cd.Kael.flash) or nil
	end

	-- KO refill
	if f.koAt and self.t - f.koAt >= cfg.koRefill then f.hp, f.koAt = cfg.hpMax, nil; self:emit("refill", { f = f.id }) end

	-- timed reactions
	if f.react and self.t >= f.react.untilT then f.react = nil end

	-- pushes
	if f.push then
		local step = math.min(dt, f.push.left)
		self:moveBy(f, f.push.vx * step, f.push.vz * step)
		f.push.left = f.push.left - step
		if f.push.left <= 1e-6 then f.push = nil end
	end

	-- airborne
	if f.air then
		local u = (self.t - f.air.t0) / f.air.dur
		if u >= 1 then
			f.air, f.y = nil, 0
			f.state, f.knockedUntil = "knocked", self.t + cfg.knocked
			self:setClip(f, "getup")
			self:emit("land", { f = f.id, x = f.x, z = f.z })
		else
			f.y = f.air.h * 4 * u * (1 - u)
		end
	end

	-- states that end on a timer
	if f.state == "stagger" and self.t >= f.staggerUntil then f.state = "idle" end
	if f.state == "knocked" and self.t >= f.knockedUntil then f.state = "idle" end
	if f.state == "open" and self.t >= f.openUntil then f.state = "idle" end
	if f.state == "idle" and f.guardHeld and f.hp > 0 then f.state, f.guardStart = "block", self.t end

	-- action
	local a = f.act
	if a then
		local prev = a.t
		a.t = a.t + dt * self:tempo(f)
		local m = a.meta
		if m.move and not m.noMove then
			for _, mv in ipairs(m.move) do
				local ov = clamp(a.t, mv.from, mv.to) - clamp(prev, mv.from, mv.to)
				if ov > 0 then
					local d = mv.dist * ov / (mv.to - mv.from)
					local fx, fz = fwdVec(f)
					local rx, rz = rightVec(f)
					local dx, dz = fx, fz
					if mv.dir == "input" then dx, dz = a.dirx, a.dirz
					elseif mv.dir == "side" then dx, dz = rx * a.sideSign, rz * a.sideSign
					elseif mv.dir == "back" then dx, dz = -fx, -fz end
					self:moveBy(f, dx * d, dz * d)
				end
			end
		end
		f.lift = 0
		if m.lift then
			for _, lf in ipairs(m.lift) do
				if a.t >= lf.from and a.t <= lf.to then
					f.lift = math.max(f.lift, lf.h * math.sin(math.pi * (a.t - lf.from) / (lf.to - lf.from)))
				end
			end
		end
		for _, mk in ipairs(m.markers) do
			if not a.fired[mk] and mk.t <= a.t then
				a.fired[mk] = true
				self:marker(f, a, mk)
				if f.act ~= a then return end     -- the marker interrupted us
			end
		end
		-- combo chain
		if m.chain and a.t >= m.chain and self.t - f.bufM1 <= cfg.combo.buffer and a.clip ~= "m1_4" then
			local n = tonumber(a.clip:sub(4)) + 1
			f.bufM1 = -9
			f.comboIdx = n
			self:startAct(f, "m1_" .. n)
			return
		end
		if a.t >= m.dur then self:endAct(f) end
	elseif f.state == "idle" or f.state == "block" then
		-- walking
		local fx, fz = fwdVec(f)
		local rx, rz = rightVec(f)
		local vx, vz = fx * f.inF + rx * f.inS, fz * f.inF + rz * f.inS
		local l = hyp(vx, vz)
		f.moving, f.moveBack = false, false
		if l > 0.05 then
			if l > 1 then vx, vz, l = vx / l, vz / l, 1 end
			local ch = cfg.char[f.char]
			local fmv = cfg.form[f.form]
			local base = (f.state == "block") and ch.guardWalk or ((f.inF < -0.3 and math.abs(f.inS) < 0.6) and ch.backWalk or ch.walk)
			local sp = base * (fmv and fmv.speed or 1)
			self:moveBy(f, vx / l * sp * l * dt, vz / l * sp * l * dt)
			f.moving, f.moveBack = true, f.inF < -0.3 and math.abs(f.inS) < 0.6
			f.moveSpeed = sp * l
		end
	end

	-- facing
	if f.act == nil and f.state ~= "air" and f.state ~= "knocked" then self:faceOpponent(f, dt, cfg.char[f.char].turn) end

	-- displayed clip
	local want
	if f.act then want = nil
	elseif f.state == "stagger" then want = nil
	elseif f.state == "air" or f.state == "knocked" then want = nil
	elseif f.state == "open" then want = "open"
	elseif f.react and f.state == "block" then want = f.react.clip
	elseif f.state == "block" then want = "guard"
	elseif f.moving then want = "walk"
	else want = "idle" end
	if want and want ~= f.clip then self:setClip(f, want) end
	if want == "walk" then
		local stride = self:meta(f, "walk").walkStride
		f.clipSpeed = clamp((f.moveSpeed or 0) / (stride / 0.3), 0.4, 1.8)
	end
end

function Core:update(dt)
	self.t = self.t + dt
	if self.freeze > 0 then            -- hit-stop: clips, actions and timers hold still for a few frames
		self.freeze = self.freeze - dt
		for _, f in pairs(self.f) do
			f.clipT0 = f.clipT0 + dt
			f.staggerUntil = f.staggerUntil + dt
			f.openUntil = f.openUntil + dt
			f.knockedUntil = f.knockedUntil + dt
			if f.air then f.air.t0 = f.air.t0 + dt end
			if f.push then f.push.left = f.push.left + 0 end
		end
		return
	end
	for _, id in ipairs({ "Blue", "Purple" }) do self:updateAI(self.f[id], dt) end
	for _, id in ipairs({ "Blue", "Purple" }) do self:updateFighter(self.f[id], dt) end
	-- overlap separation (grounded fighters only)
	local a, b = self.f.Blue, self.f.Purple
	if a.lift < 0.3 and b.lift < 0.3 and a.y < 0.3 and b.y < 0.3 then
		local dx, dz = b.x - a.x, b.z - a.z
		local d = hyp(dx, dz)
		local gap = self.cfg.arena.minGap
		if d < gap and d > 1e-4 then
			local push = (gap - d) / 2
			a.x, a.z = a.x - dx / d * push, a.z - dz / d * push
			b.x, b.z = b.x + dx / d * push, b.z + dz / d * push
		end
	end
end

---------------------------------------------------------------------------------------------- snapshot for clients / UI
function Core:snapshot()
	local out = {}
	for id, f in pairs(self.f) do
		local cd = {}
		for k, v in pairs(f.cd) do cd[k] = math.max(0, v - self.t) end
		cd.flashCharges = f.charges
		cd.flashNext = f.flashNext and math.max(0, f.flashNext - self.t) or 0
		out[id] = {
			char = f.char, x = f.x, z = f.z, ang = f.ang, y = f.y + f.lift,
			clip = f.clip, clipT = (self.t - f.clipT0) * f.clipSpeed, clipSpeed = f.clipSpeed, seq = f.seq,
			back = f.moveBack and f.clip == "walk", hp = f.hp, meter = f.meter, form = f.form, state = f.state,
			cd = cd, finalLeft = f.form == "Final" and math.max(0, f.finalUntil - self.t) or 0, ultReady = f.form == "Final" and not f.ultUsed,
			counterLeft = math.max(f.counterUntil - self.t, f.riposteUntil - self.t, 0), stored = f.stored,
			followLeft = math.max(0, f.followUntil - self.t),
		}
	end
	return out
end

return Core
]====])
put(RS, "ModuleScript", "BGCloth", [====[
-- BGCloth (ModuleScript, ReplicatedStorage): lets hanging cloth (scarf tails, coat hem) follow the body with a slight delay.
-- BGBuilder makes the chains: Motor6Ds with attributes Chain (name) and Depth (1 = nearest the body).
local Cloth = {}
Cloth.__index = Cloth

local RATES = { 14, 9, 6.5, 5 }      -- deeper segments react slower => visible lag

local function wrapAngle(a)
	while a > math.pi do a = a - 2 * math.pi end
	while a < -math.pi do a = a + 2 * math.pi end
	return a
end

function Cloth.new(model)
	local self = setmetatable({ chains = {}, prevPos = nil }, Cloth)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") and d:GetAttribute("Chain") then
			local name = d:GetAttribute("Chain")
			local c = self.chains[name]
			if not c then
				c = { joints = {}, yaw = {}, pitch = {}, phase = math.random() * 6 }
				self.chains[name] = c
			end
			c.joints[d:GetAttribute("Depth")] = d
		end
	end
	return self
end

function Cloth:reset() self.prevPos = nil end

-- utCF = world CFrame of the UpperTorso (or LowerTorso for hems); dt = simulated seconds this frame (0 when paused)
-- wind = extra forward-velocity-like push in studs/s (positive streams the cloth backward, e.g. a pull from behind)
function Cloth:update(utCF, dt, wind)
	local fwd = utCF:VectorToWorldSpace(Vector3.new(0, 0, -1))
	local yaw = math.atan2(-fwd.X, -fwd.Z)
	local pos = utCF.Position
	if not self.prevPos then
		self.prevPos = pos
		for _, c in pairs(self.chains) do for i = 1, #c.joints do c.yaw[i], c.pitch[i] = yaw, 0 end end
	end
	local vf, vl = 0, 0
	if dt > 1e-4 then
		local v = (pos - self.prevPos) / dt
		vf = v:Dot(Vector3.new(fwd.X, 0, fwd.Z))
		vl = v:Dot(Vector3.new(-fwd.Z, 0, fwd.X))
	end
	vf = vf + (wind or 0)
	self.prevPos = pos
	local now = os.clock()
	for _, c in pairs(self.chains) do
		for i = 1, #c.joints do
			local j = c.joints[i]
			if dt > 0 then
				local k = 1 - math.exp(-dt * (RATES[i] or 4))
				c.yaw[i] = (c.yaw[i] or yaw) + wrapAngle(yaw - (c.yaw[i] or yaw)) * k
				local want = math.clamp(-vf * 3.0, -40, 40)
				c.pitch[i] = (c.pitch[i] or 0) + (want - (c.pitch[i] or 0)) * k
			end
			local roll = math.clamp(math.deg(wrapAngle(yaw - (c.yaw[i] or yaw))) * 0.9 + vl * -1.5, -42, 42)
			local sway = math.sin(now * 1.6 + c.phase + i * 0.7) * 1.5
			j.Transform = CFrame.Angles(math.rad(-6 + (c.pitch[i] or 0) * (0.6 + 0.2 * i) * 0.5 + sway), 0, math.rad(roll))
		end
	end
end

return Cloth
]====])
put(RS, "ModuleScript", "BGRig", [====[
-- BGRig (ModuleScript, ReplicatedStorage): reads the joint layout of an R15 rig built by BGBuilder.
-- Joints are found by the part they move (Part1), so it works whatever the Motor6D is named.
local Engine = require(script.Parent:WaitForChild("BGEngine"))
local Rig = {}

local PART1 = { Root = "LowerTorso", Waist = "UpperTorso", Neck = "Head",
	RightShoulder = "RightUpperArm", RightElbow = "RightLowerArm", RightWrist = "RightHand",
	LeftShoulder = "LeftUpperArm", LeftElbow = "LeftLowerArm", LeftWrist = "LeftHand",
	RightHip = "RightUpperLeg", RightKnee = "RightLowerLeg", RightAnkle = "RightFoot",
	LeftHip = "LeftUpperLeg", LeftKnee = "LeftLowerLeg", LeftAnkle = "LeftFoot" }

local function findJoint(model, n)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") and d.Part1 and d.Part1.Name == PART1[n] and d.Part0 and not d:GetAttribute("Chain") then return d end
	end
end

function Rig.waitReady(model)
	model:WaitForChild("HumanoidRootPart"); model:WaitForChild("RightFoot"); model:WaitForChild("UpperTorso"); model:WaitForChild("LowerTorso")
end

-- returns defs (c0/c1/motor per joint), sizes, motors[jointName]
function Rig.read(model)
	local defs, motors = {}, {}
	for _, n in ipairs(Engine.JOINTS) do
		local m = findJoint(model, n)
		local waited = 0
		while not m and waited < 10 do task.wait(0.1); waited += 0.1; m = findJoint(model, n) end
		assert(m, "BGRig: no joint for " .. n .. " on " .. model.Name)
		defs[n] = { c0 = m.C0, c1 = m.C1, motor = m }
		motors[n] = m
	end
	return defs, { footY = model.RightFoot.Size.Y, footZ = model.RightFoot.Size.Z }, motors
end

return Rig
]====])
put(RS, "ModuleScript", "BGStyle", [====[
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
]====])
put(RS, "ModuleScript", "BGCinematicData", [====[
-- BGCinematicData (ModuleScript, ReplicatedStorage): THE EDITABLE ANIMATION SOURCE.
-- Times are seconds. Keys inherit everything from the previous key; list only what changes.
-- Axes: stage X runs Blue -> Purple. Angles in degrees. yaw/pyaw/twist: + = turn left (counter-clockwise from above).
-- Hands rh/lh = {f=forward, s=side (+ = fighter's right), y=height above chest centre}.
-- Feet rf/lf  = {f, s, lift}. A foot only moves when its key lists rf/lf; otherwise it stays planted.
-- Poles rp/lp = direction the elbow points (same axes). ease: linear | inout | in2 | in3 | out2 | out3.
local D = {}

D.duration = 10.4

D.fighters = {
	Blue = {
		baseYaw = -90, anchor = { x = -1.5, z = -0.2 },       -- anchor is re-solved at the clash
		base = {
			dx = -1.9, dz = 0, yaw = 0, pyaw = -22, twist = -8, lean = 6, roll = 0, crouch = 0.35,
			headYaw = 0, headPitch = 3,
			rfYaw = -38, lfYaw = -8, rfPitch = 0, lfPitch = 0,
			rf = { f = -0.55, s = 0.55, lift = 0 }, lf = { f = 0.75, s = -0.35, lift = 0 },
			rh = { f = 0.85, s = 0.5, y = 0.8 }, lh = { f = 1.15, s = -0.5, y = 0.85 },
			rp = { f = 0.2, s = 0.9, y = -0.6 }, lp = { f = 0.2, s = -0.9, y = -0.6 },
		},
		keys = {
			{ t = 0.0,  name = "guard" },
			{ t = 0.55, name = "guard_shift_a", dx = -1.83, crouch = 0.42, lean = 7, lh = { f = 1.15, s = -0.5, y = 0.92 } },
			{ t = 1.1,  name = "guard_shift_b", dx = -1.96, crouch = 0.3, lean = 5, lh = { f = 1.15, s = -0.5, y = 0.8 } },
			{ t = 1.5,  name = "stepIn_lead_lift", dx = -1.55, lean = 10, crouch = 0.4,
				lf = { f = 0.9, s = -0.35, lift = 0.4 } },
			{ t = 1.8,  name = "stepIn_lead_plant", dx = -1.2, lf = { f = 1.3, s = -0.35, lift = 0 } },
			{ t = 2.05, name = "stepIn_rear_lift_jab_load", dx = -0.9, lh = { f = 0.9, s = -0.5, y = 0.85 },
				rf = { f = -0.2, s = 0.55, lift = 0.35 } },
			{ t = 2.3,  name = "jab", ease = "in2", dx = -0.5, twist = -2, rf = { f = -0.5, s = 0.55, lift = 0 },
				lh = { f = 2.0, s = -0.35, y = 0.95 } },
			{ t = 2.6,  name = "jab_retract", ease = "out2", twist = -8, lh = { f = 1.15, s = -0.5, y = 0.85 } },
			{ t = 2.9,  name = "rear_load", pyaw = -42, twist = -26, crouch = 0.55, lean = 8, dx = -0.62,
				rfYaw = -46, rh = { f = 0.5, s = 0.75, y = 0.45 } },
			{ t = 3.5,  name = "rear_drive", ease = "in2", pyaw = -6, twist = 4, crouch = 0.42, lean = 14, dx = -0.22,
				rfYaw = -16, rfPitch = 22, rh = { f = 1.2, s = 0.6, y = 0.8 } },
			{ t = 4.0,  name = "CONTACT", ease = "in3", pyaw = 14, twist = 18, lean = 18, dx = 0, rfYaw = -4, rfPitch = 34,
				headPitch = 6, lh = { f = 1.0, s = -0.7, y = 0.8 }, rh = { f = 2.0, s = 0.6, y = 0.9 } },    -- rh is baked from the defender's forearm
			{ t = 4.12, name = "contact_absorb", ease = "out2", lean = 15, dx = -0.07, twist = 15, headPitch = 8,
				lh = { f = 1.0, s = -0.7, y = 0.8 }, rh = { f = 1.9, s = 0.6, y = 0.9 } },
			{ t = 4.6,  name = "clash_hold_end", ease = "linear" },
			{ t = 4.95, name = "pull_back", ease = "out2", pyaw = -10, twist = 0, lean = 10, dx = -0.16, rfYaw = -20, rfPitch = 10,
				headPitch = 3, rh = { f = 0.85, s = 0.55, y = 0.85 } },
			{ t = 5.15, name = "HIT_REACT", ease = "in2", pyaw = 8, twist = -16, lean = 1, dx = -0.12, headPitch = -14, headYaw = 12,
				crouch = 0.3, lh = { f = 0.8, s = -0.7, y = 0.6 }, rh = { f = 0.7, s = 0.7, y = 0.6 } },
			{ t = 5.55, name = "recoil", ease = "out2", pyaw = -4, twist = -10, lean = -3, dx = -0.9, crouch = 0.25,
				headPitch = -8, headYaw = 4, lh = { f = 0.95, s = -0.6, y = 0.75 }, rh = { f = 0.85, s = 0.55, y = 0.8 } },
			{ t = 5.8,  name = "recover_step_lift", dx = -1.0, rf = { f = -0.35, s = 0.55, lift = 0.35 }, rfPitch = 0, rfYaw = -30 },
			{ t = 6.1,  name = "recover_step_plant", dx = -1.1, lean = 6, pyaw = -18, twist = -8,
				rf = { f = -0.65, s = 0.55, lift = 0 }, rfYaw = -38, headPitch = 3, headYaw = 0 },
			{ t = 6.4,  name = "return_lead_lift", dx = -1.55, lf = { f = 0.55, s = -0.35, lift = 0.3 } },
			{ t = 6.7,  name = "return_lead_plant", dx = -1.9, pyaw = -22, crouch = 0.35, lf = { f = 0.75, s = -0.35, lift = 0 } },
			{ t = 7.0,  name = "return_rear_lift", rf = { f = -0.2, s = 0.55, lift = 0.3 } },
			{ t = 7.3,  name = "return_guard", rf = { f = -0.55, s = 0.55, lift = 0 },
				rh = { f = 0.85, s = 0.5, y = 0.8 }, lh = { f = 1.15, s = -0.5, y = 0.85 } },
			{ t = 8.6,  name = "guard_shift_c", dx = -1.94, crouch = 0.4, lean = 7 },
			{ t = 10.4, name = "guard_end", dx = -1.9, crouch = 0.35, lean = 6 },
		},
	},
	Purple = {
		baseYaw = 90, anchor = { x = 1.3, z = 0.0 },
		base = {
			dx = 0, dz = 0, yaw = 0, pyaw = -18, twist = -6, lean = 3, roll = 0, crouch = 0.5,
			headYaw = 0, headPitch = 2,
			rfYaw = -30, lfYaw = -6, rfPitch = 0, lfPitch = 0,
			rf = { f = -0.5, s = 0.6, lift = 0 }, lf = { f = 0.55, s = -0.4, lift = 0 },
			rh = { f = 0.85, s = 0.5, y = 0.95 }, lh = { f = 1.0, s = -0.55, y = 1.0 },
			rp = { f = 0.2, s = 0.9, y = -0.6 }, lp = { f = 0.2, s = -0.9, y = -0.6 },
		},
		keys = {
			{ t = 0.0,  name = "guard" },
			{ t = 0.55, name = "guard_shift_a", dx = 0.05, crouch = 0.56, lean = 4 },
			{ t = 1.1,  name = "guard_shift_b", dx = -0.04, crouch = 0.46, lean = 3 },
			{ t = 1.8,  name = "tighten", crouch = 0.54, lean = 4, headYaw = 0 },
			{ t = 2.3,  name = "jab_slip", ease = "out2", dx = 0.12, lean = 1, headYaw = -8, headPitch = 4, crouch = 0.58 },
			{ t = 2.8,  name = "jab_reset", ease = "inout", dx = 0, lean = 3, headYaw = 0, headPitch = 2, crouch = 0.5 },
			{ t = 3.5,  name = "block_set", pyaw = -24, twist = -10, crouch = 0.58, lean = 4,
				lh = { f = 0.75, s = -0.75, y = 0.8 }, lp = { f = 0.7, s = -0.3, y = -0.7 } },
			{ t = 4.0,  name = "CONTACT", ease = "out2", dx = 0.04, twist = -12 },
			{ t = 4.12, name = "block_absorb", ease = "out2", dx = 0.2, twist = -22, pyaw = -30, lean = 1, headYaw = 6, crouch = 0.62 },
			{ t = 4.6,  name = "clash_hold_end", ease = "linear" },
			{ t = 4.85, name = "counter_load", ease = "inout", pyaw = -38, twist = -20, dx = 0.1,
				rfYaw = -42, rh = { f = 0.6, s = 0.7, y = 0.75 }, lh = { f = 0.95, s = -0.7, y = 0.9 } },
			{ t = 5.15, name = "COUNTER_HIT", ease = "in2", pyaw = 32, twist = 24, lean = 17, dx = -0.7, crouch = 0.46,
				rfYaw = -8, rfPitch = 12, headYaw = 0, headPitch = 4,
				rh = { f = 1.8, s = 0.4, y = 0.8 }, lh = { f = 0.9, s = -0.8, y = 0.8 } },
			{ t = 5.4,  name = "counter_follow", ease = "out2", dx = -0.55, lean = 14, rh = { f = 2.75, s = 0.2, y = 0.5 } },
			{ t = 6.0,  name = "counter_recover", ease = "inout", pyaw = -18, twist = -6, lean = 3, dx = 0, crouch = 0.5,
				rfYaw = -30, rfPitch = 0, rh = { f = 0.85, s = 0.5, y = 0.95 }, lh = { f = 1.0, s = -0.55, y = 1.0 } },
			{ t = 8.6,  name = "guard_shift_c", dx = 0.04, crouch = 0.55, lean = 4 },
			{ t = 10.4, name = "guard_end", dx = 0, crouch = 0.5, lean = 3 },
		},
	},
}

-- Contacts. "guard": the attacker's fist meets the defender's raised forearm (attacker anchor is solved).
-- "chest": the attacker's fist lands on the defender's upper torso front.
D.contacts = {
	{ id = "clash", kind = "guard", t = 4.0, attacker = "Blue", hand = "R", defender = "Purple", arm = "L",
		guardRadius = 0.62, fist = 0.3, reach = 0.52 },
	{ id = "counter", kind = "chest", t = 5.15, attacker = "Purple", hand = "R", defender = "Blue",
		surface = 0.45, up = 0.35 },
}

-- Animation markers (named events the Director fires; also the VFX cues).
D.markers = {
	{ t = 0.0,  name = "start" },
	{ t = 1.5,  name = "step_in" },
	{ t = 2.3,  name = "jab_peak" },
	{ t = 3.5,  name = "rear_drive_start" },
	{ t = 4.0,  name = "contact" },
	{ t = 4.6,  name = "clash_release" },
	{ t = 5.15, name = "counter_contact" },
	{ t = 6.1,  name = "recover_step" },
	{ t = 7.3,  name = "back_in_guard" },
}

-- VFX windows and bursts (all skipped when VFX is off).
D.vfx = {
	trails = {
		{ fighter = "Blue", part = "LeftHand",  from = 2.05, to = 2.65 },
		{ fighter = "Blue", part = "RightHand", from = 3.3,  to = 4.15 },
	},
	bursts = {
		{ marker = "contact",         contact = 1, color = Color3.fromRGB(175, 90, 255), size = 1.0 },
		{ marker = "counter_contact", contact = 2, color = Color3.fromRGB(175, 90, 255), size = 0.55 },
	},
}

-- Cameras. rel = "contact1" places the camera relative to the clash point.
D.cameras = {
	{ t = 0.0,  pos = Vector3.new(-0.4, 3.6, 12.5), look = Vector3.new(-0.4, 3.0, 0),  fov = 36 },
	{ t = 1.5,  pos = Vector3.new(-3.4, 3.0, 8.5),  look = Vector3.new(-1.9, 3.0, 0),  fov = 38 },
	{ t = 2.6,  pos = Vector3.new(-5.4, 2.4, 5.6),  look = Vector3.new(-1.8, 3.4, 0),  fov = 40, roll = -3 },
	{ t = 3.5,  pos = Vector3.new(-1.0, 3.4, 8.0),  look = Vector3.new(-0.8, 3.4, 0),  fov = 34 },
	{ t = 3.95, rel = "contact1", off = Vector3.new(0.2, 0.1, 6.0), fov = 24 },            -- angle A: side
	{ t = 4.3,  rel = "contact1", off = Vector3.new(0.6, 5.6, 2.6), fov = 30 },            -- angle B: high
	{ t = 4.6,  pos = Vector3.new(-0.2, 2.6, 8.0),  look = Vector3.new(-0.2, 3.4, 0),  fov = 36, roll = 2 },
	{ t = 5.5,  pos = Vector3.new(-3.0, 3.2, 7.5),  look = Vector3.new(-2.3, 3.2, 0),  fov = 36 },
	{ t = 7.0,  pos = Vector3.new(-0.4, 3.6, 12.5), look = Vector3.new(-0.4, 3.0, 0),  fov = 36 },
}

-- Verification cameras for the contact inspector (key C).
D.verifyCameras = {
	A = { rel = "contact1", off = Vector3.new(0, 0, 5.5), fov = 20 },     -- side: checks X and height alignment
	B = { rel = "contact1", off = Vector3.new(0, 5.5, 0.01), fov = 20 },  -- top-down: checks X and Z alignment
}

D.colors = {
	blue = Color3.fromRGB(60, 150, 255),
	violet = Color3.fromRGB(175, 90, 255),
}

return D
]====])
put(RS, "ModuleScript", "BGDuel", [====[
-- BGDuel (ModuleScript, ReplicatedStorage): THE FOUR-MINUTE TIMELINE. Teen Gojo ("Blue" rig) vs Toji ("Purple" rig), original choreography.
-- 30 fps. Frames 0-7199 are the duel (4:00); 7200-7799 is the optional epilogue. Everything that has a time lives here:
-- fighter keys, camera shots, effects, costume states, sound cues, slow motion. Poses are macros; footwork is generated automatically.
-- Every state (glasses, spear, chain, tiles, lighting) is a pure function of the frame, so any chapter starts correctly when selected.
--   Axes: +X is screen-right. Gojo faces -X (toward the gate), Toji faces +X. Heights: gy = ground height under the fighter.
local D = {}
D.fps, D.duelFrames, D.frames = 30, 7200, 10290
D.duration = D.frames / D.fps

local function sec(m, s) return math.floor((m * 60 + s) * D.fps) end
D.chapters = {
	{ id = 1, name = "Who moved first?",      f0 = sec(0, 0),   f1 = sec(0, 20),  q = "Who moved first?" },
	{ id = 2, name = "Infinity",              f0 = sec(0, 20),  f1 = sec(0, 50),  q = "Can he be touched at all?" },
	{ id = 3, name = "Blue",                  f0 = sec(0, 50),  f1 = sec(1, 20),  q = "Can he beat the pull?" },
	{ id = 4, name = "Toji takes control",    f0 = sec(1, 20),  f1 = sec(1, 55),  q = "What is the one thing Infinity cannot stop?" },
	{ id = 5, name = "Awakening",             f0 = sec(1, 55),  f1 = sec(2, 20),  q = "Is it over?" },
	{ id = 6, name = "Red",                   f0 = sec(2, 20),  f1 = sec(2, 55),  q = "Can he be hit now?" },
	{ id = 7, name = "Toji's full arsenal",   f0 = sec(2, 55),  f1 = sec(3, 35),  q = "Can speed and steel win?" },
	{ id = 8, name = "Hollow Purple",         f0 = sec(3, 35),  f1 = sec(4, 0),   q = "What happens when both forces meet?" },
	{ id = 9,  name = "Adult Gojo: Infinity, Maximum Output Blue, movement", f0 = 7200, f1 = 8400, q = "What does the strongest do with a free hand?", adult = true },
	{ id = 10, name = "Unlimited Void",                     f0 = 8400, f1 = 9300, q = "What does it feel like to be understood all at once?", adult = true },
	{ id = 11, name = "Unlimited Void: the 0.2-second application", f0 = 9300, f1 = 9540, q = "How little time is enough?", adult = true },
	{ id = 12, name = "Shibuya Toji: Playful Cloud",        f0 = 9540, f1 = 10290, q = "Who is in control of the body?", shibuya = true },
}
function D.chapterAt(frame) local c = D.chapters[1] for _, ch in ipairs(D.chapters) do if frame >= ch.f0 then c = ch end end return c end

---------------------------------------------------------------------------------------------- arena landmarks
D.arena = {
	gate = { x = -20 }, pillar = { x = -4 },
	stair = { x0 = 10, x1 = 15.5, topY = 3.2 },      -- 4 steps from x0 to x1
	walkway = { x0 = 15.5, x1 = 34, y = 3.2 },
	step = { x = 12.2, y = 1.6 },                    -- the broken step the glasses end on
}
local function groundAt(x)           -- ground height for placing fighters
	local s = D.arena.stair
	if x >= D.arena.walkway.x0 then return s.topY end
	if x >= s.x0 then return s.topY * (x - s.x0) / (s.x1 - s.x0) end
	return 0
end
D.groundAt = groundAt

---------------------------------------------------------------------------------------------- poses (field tables; keys inherit)
local function H(f, s, y) return { f = f, s = s, y = y } end
local function F(f, s, lift) return { f = f, s = s, lift = lift or 0 } end
local function merge(a, b) local r = {} for k, v in pairs(a) do r[k] = v end if b then for k, v in pairs(b) do r[k] = v end end return r end

-- Gojo: tall, slender, hands in pockets, weight easy
local G = {}
G.base = { dx = 0, dz = 0, yaw = 0, pyaw = -6, twist = 0, lean = 0, roll = 0, crouch = 0.0, headYaw = 0, headPitch = 0, gy = 0,
	rfYaw = -8, lfYaw = -4, rfPitch = 0, lfPitch = 0, rf = F(-0.2, 0.5), lf = F(0.2, -0.45),
	rh = H(0.1, 0.72, -1.0), lh = H(0.1, -0.72, -1.0), rp = H(0.0, 0.5, -0.9), lp = H(0.0, -0.5, -0.9) }
G.stand = {}
G.shift = { roll = 2, lean = 1.5, pyaw = -2 }
G.tilt = { roll = -3, headPitch = -3, lean = -1 }                   -- amused head tilt
G.watch = { lean = -2, pyaw = -10 }
G.point = { pyaw = -22, twist = -10, lean = 2, rh = H(1.7, 0.2, 0.55), rp = H(0.3, 0.3, 0.2) }                    -- Blue: arm out, finger at a point
G.pointHold = { pyaw = -22, twist = -10, lean = 4, rh = H(1.75, 0.2, 0.6) }
G.dodgeA = { lean = -12, roll = 6, pyaw = -30, headYaw = 6, rh = H(0.1, 0.7, -0.9) }                                 -- minimal lean away
G.dodgeB = { lean = 8, roll = -6, pyaw = 10, headYaw = -8 }
G.hit = { lean = -22, crouch = 0.2, headPitch = -16, rh = H(0.3, 1.0, 0.0), lh = H(0.3, -1.0, 0.0), rp = H(0.0, 0.9, 0.0), lp = H(0.0, -0.9, 0.0) }
G.down = { crouch = 1.2, lean = -16, pyaw = -14, headPitch = 12, lh = H(0.95, -0.55, -1.7), rh = H(0.4, 0.7, -1.2), rf = F(-0.3, 0.7), lf = F(0.7, -0.5) }  -- seated against the floor, left hand flat on a tile
G.breathe1 = { lean = -14, crouch = 1.18 }
G.breathe2 = { lean = -17, crouch = 1.24 }
G.rise1 = { crouch = 1.2, lean = 6, headPitch = 6, lh = H(0.9, -0.55, -1.4), rh = H(0.5, 0.7, -1.0) }
G.rise2 = { crouch = 0.4, lean = 4, headPitch = 0, lh = H(0.1, -0.72, -1.0), rh = H(0.1, 0.72, -1.0) }
G.red = { pyaw = -30, twist = -14, lean = -4, rh = H(1.6, 0.15, 0.7), rp = H(0.3, 0.4, 0.1) }                         -- palm out
G.purple = { pyaw = -14, twist = -6, lean = 2, rh = H(1.45, 0.35, 0.65), lh = H(1.45, -0.35, 0.65), rp = H(0.2, 0.5, 0.0), lp = H(0.2, -0.5, 0.0) }
G.crossArms = { rh = H(1.0, 0.1, 0.5), lh = H(1.0, -0.1, 0.5) }
G.sidestep = { roll = 8, lean = -4 }
G.run = { lean = 14, crouch = 0.4, rh = H(0.3, 0.8, -0.8), lh = H(0.3, -0.8, -0.8) }

-- Toji: broad, loose, shoulders slack until the instant he moves
local J = {}
J.base = { dx = 0, dz = 0, yaw = 0, pyaw = -12, twist = -4, lean = 3, roll = 0, crouch = 0.3, headYaw = 0, headPitch = 3, gy = 0,
	rfYaw = -20, lfYaw = -8, rfPitch = 0, lfPitch = 0, rf = F(-0.5, 0.6), lf = F(0.5, -0.45),
	rh = H(0.15, 0.82, -1.0), lh = H(0.15, -0.82, -1.0), rp = H(0.0, 0.6, -0.9), lp = H(0.0, -0.6, -0.9) }
J.loose = {}
J.settle = { roll = -2, lean = 2, headPitch = 5 }
J.coil = { crouch = 0.8, lean = 22, pyaw = -26, twist = -18, headPitch = 6, rh = H(0.2, 0.8, -0.2), lh = H(0.6, -0.7, 0.1) }    -- anticipation: weight drops, shoulders finally engage
J.dash = { crouch = 0.65, lean = 30, pyaw = -6, twist = 6, headPitch = 4, rh = H(-0.1, 0.8, -0.3), lh = H(0.4, -0.7, -0.2) }
J.land = { crouch = 1.0, lean = 16, pyaw = -12, rh = H(0.5, 0.8, -0.4), lh = H(0.6, -0.8, -0.4) }
J.strike = { crouch = 0.6, lean = 20, pyaw = 16, twist = 18, rh = H(2.0, 0.4, 1.1), rp = H(0.3, 0.7, 0.0), lh = H(0.4, -0.8, 0.2) }
J.strikeLoad = { crouch = 0.75, lean = 12, pyaw = -34, twist = -22, rh = H(0.3, 0.9, 0.3), lh = H(0.9, -0.5, 0.5) }
J.watchHand = { lean = 6, headPitch = 12, rh = H(0.9, 0.3, 0.5), rp = H(0.2, 0.5, 0.0) }      -- studies his own hand
J.crouchLow = { crouch = 1.1, lean = 18, rh = H(0.7, 0.8, -0.5), lh = H(0.7, -0.8, -0.5) }
J.air = { crouch = -0.4, lean = 24, rh = H(0.8, 0.7, 0.3), lh = H(0.8, -0.7, 0.3) }
J.airSpear = { crouch = -0.3, lean = 20, pyaw = 12, twist = 14, rh = H(1.5, 0.4, 0.5), lh = H(0.6, -0.8, 0.2) }
J.spearHold = { crouch = 0.5, lean = 10, pyaw = -10, rh = H(1.0, 0.6, 0.1), rp = H(0.2, 0.7, -0.2), lh = H(0.5, -0.8, -0.3) }
J.spearThrust = { crouch = 0.55, lean = 24, pyaw = 18, twist = 22, rh = H(2.1, 0.3, 0.7), lh = H(0.3, -0.8, 0.0) }
J.sweep = { crouch = 0.5, lean = 14, pyaw = 30, twist = 30, rh = H(1.4, 1.1, 0.4), lh = H(0.5, -0.9, 0.1) }
J.sweepBack = { crouch = 0.55, lean = 8, pyaw = -40, twist = -30, rh = H(0.5, 1.0, 0.4) }
J.pull = { crouch = 0.6, lean = -8, pyaw = -30, twist = -20, rh = H(0.6, 0.7, 0.4), lh = H(0.5, -0.7, 0.4) }     -- hauling the chain
J.flick = { rh = H(0.9, 0.5, 0.2), headPitch = 4 }
J.stagger = { lean = -24, crouch = 0.5, headPitch = -14, rh = H(0.4, 1.0, 0.3), lh = H(0.4, -1.0, 0.3) }
J.turnBack = { headYaw = 70, twist = 20, pyaw = 10 }                                          -- hears a footstep behind him
J.guard = { crouch = 0.8, lean = 6, rh = H(1.0, 0.5, 0.7), lh = H(1.0, -0.5, 0.7) }
J.p = { stand = {}, }

---------------------------------------------------------------------------------------------- sequence builder + compiler
-- seq:add(frame, poseNames, {x, z, yaw, gy, ease, <any pose field overrides>})   poseNames = one table or a list merged in order
local Seq = {}
Seq.__index = Seq
local function newSeq(base, baseYaw, x0, z0) return setmetatable({ base = base, baseYaw = baseYaw, keys = {}, x0 = x0, z0 = z0 }, Seq) end
function Seq:add(f, poses, o)
	o = o or {}
	local fields = {}
	if poses then
		if poses.rh or poses.crouch or poses.lean or poses.pyaw or poses.lh or poses.roll or poses.headYaw or poses.headPitch or poses.twist or poses.gy or next(poses) == nil then poses = { poses } end
		for _, p in ipairs(poses) do fields = merge(fields, p) end
	end
	local k = { f = f, fields = fields, x = o.x, z = o.z, yaw = o.yaw, gy = o.gy, ease = o.ease, move = o.move }
	for a, b in pairs(o) do if not ({ x = 1, z = 1, yaw = 1, gy = 1, ease = 1, move = 1 })[a] then k.fields[a] = b end end
	table.insert(self.keys, k)
	return self
end

local function lastPos(seq, i)
	for j = i - 1, 1, -1 do
		local k = seq.keys[j]
		if k.rx then return k end
	end
end

-- numeric-aware linear blend of two pose-field tables (hands/feet are small tables of numbers)
local function lerpFields(a, b, u)
	local r = {}
	for k, v in pairs(b) do
		local av = a[k]
		if type(v) == "number" then r[k] = (type(av) == "number") and (av + (v - av) * u) or v
		elseif type(v) == "table" then
			local t = {}
			for kk, vv in pairs(v) do
				local avv = type(av) == "table" and av[kk] or nil
				t[kk] = (type(vv) == "number" and type(avv) == "number") and (avv + (vv - avv) * u) or vv
			end
			r[k] = t
		else r[k] = v end
	end
	return r
end

-- Resolve absolute positions, add intermediate footsteps on every long move, generate feet (walk steps, dash trails, plants), emit Engine data.
function Seq:compile()
	table.sort(self.keys, function(a, b) return a.f < b.f end)
	local px, pz, pyaw, pgy, pf = self.x0, self.z0, 0, 0, 0
	local cur = merge(self.base, {})                  -- cumulative pose fields (what the Engine will have inherited so far)
	local flip, prevMoving = false, false
	local out = {}
	local function emit(f, rx, rz, ryaw, rgy, fields, ease, feet)
		local ek = { t = f / D.fps, ease = ease, dx = rx - self.x0, dz = rz - self.z0, yaw = ryaw, gy = rgy }
		for a, b in pairs(fields) do ek[a] = b end
		if feet then ek.lf, ek.rf = feet[1], feet[2] end
		out[#out + 1] = ek
	end
	for i, k in ipairs(self.keys) do
		local rx, rz = k.x or px, k.z or pz
		local ryaw = k.yaw or pyaw
		local rgy = k.gy or groundAt(rx)
		local nxt = merge(cur, k.fields)
		if i == 1 then
			emit(k.f, rx, rz, ryaw, rgy, nxt, k.ease, { nxt.lf or self.base.lf, nxt.rf or self.base.rf })
		else
			local dxw, dzw = rx - px, rz - pz
			local dist = math.sqrt(dxw * dxw + dzw * dzw)
			local df = k.f - pf
			local dt = math.max(df / D.fps, 1e-3)
			local speed = dist / dt
			local explicitFeet = k.fields.lf ~= nil or k.fields.rf ~= nil
			local y = math.rad(self.baseYaw + ryaw)
			local fx, fz = -math.sin(y), -math.cos(y)
			local rx_, rz_ = math.cos(y), -math.sin(y)
			local mf, ms = 0, 0
			if dist > 1e-3 then mf, ms = (dxw * fx + dzw * fz) / dist, (dxw * rx_ + dzw * rz_) / dist end
			if explicitFeet or dist < 0.35 then
				local feet
				if not explicitFeet and prevMoving then feet = { F(0.35, -0.45, 0), F(-0.35, 0.55, 0) }; prevMoving = false end
				emit(k.f, rx, rz, ryaw, rgy, k.fields, k.ease, feet)
			elseif speed >= 7 then
				emit(k.f, rx, rz, ryaw, rgy, k.fields, k.ease, { F(0.4 + 0.8 * mf, -0.4 + 0.8 * ms, 0.6), F(-0.5 - 0.8 * mf, 0.5 - 0.8 * ms, 0.7) })
				prevMoving = true
			else
				-- walk: one footstep per ~0.9 studs, sub-keys along the path
				local n = math.max(1, math.ceil(dist / 0.9))
				for j = 1, n do
					local u = j / n
					local last = (j == n)
					local sx, sz, sy = px + dxw * u, pz + dzw * u, pyaw + (ryaw - pyaw) * u
					local sg = last and rgy or (k.gy and (pgy + (rgy - pgy) * u) or groundAt(sx))
					flip = not flip
					local s = flip and 1 or -1
					local feet = { F(0.45 + s * mf * 0.75, -0.42 + s * ms * 0.75, flip and 0 or 0.22), F(-0.45 - s * mf * 0.75, 0.55 - s * ms * 0.75, flip and 0.22 or 0) }
					local f = pf + df * u
					local fields = last and k.fields or lerpFields(cur, nxt, u)
					if last and speed < 7 then feet = nil end
					emit(f, sx, sz, sy, sg, fields, last and k.ease or "linear", feet)
				end
				-- plant on arrival
				out[#out].lf, out[#out].rf = F(0.35, -0.45, 0), F(-0.35, 0.55, 0)
				prevMoving = false
			end
		end
		cur = nxt
		px, pz, pyaw, pgy, pf = rx, rz, ryaw, rgy, k.f
	end
	return { baseYaw = self.baseYaw, anchor = { x = self.x0, z = self.z0 }, base = self.base, keys = out }
end

local Gj = newSeq(G.base, 90, 6.0, 0.0)        -- Gojo faces -X
local Tj = newSeq(J.base, -90, -20.0, 0.0)     -- Toji faces +X
D.seq = { Blue = Gj, Purple = Tj }

---------------------------------------------------------------------------------------------- CHAPTER 1: Who moved first? (0-600)
Gj:add(0,   G.stand, { x = 6.0, z = 0.0 })
Gj:add(40,  G.shift)
Gj:add(50,  { G.shift, { headYaw = 0 } })
Gj:add(78,  { G.watch, { headYaw = -26 } }, { ease = "out2" })                -- head follows AFTER the eyes found Toji
Gj:add(150, { G.watch, { headYaw = -26 } })
Gj:add(160, { G.watch, { headYaw = -30, headPitch = 2 } })
Gj:add(236, G.tilt)
Gj:add(300, { G.tilt, { headYaw = -18 } })
Gj:add(420, G.stand, { x = 6.2 })
Gj:add(560, { G.shift, { headYaw = -12 } })
Gj:add(599, { G.stand })
Tj:add(0,   J.loose, { x = -20.0, z = 0.0 })
Tj:add(60,  J.loose, { x = -20.0 })
Tj:add(120, J.settle, { x = -19.8 })
Tj:add(150, J.coil, { x = -19.8, ease = "in2" })                              -- 5 frames anticipation: the shoulders stay loose until here
Tj:add(155, J.dash, { x = -19.2, ease = "in3" })
Tj:add(159, J.land, { x = -4.2, z = 0.4, ease = "linear" })                   -- 4 frames across the courtyard, gate to pillar
Tj:add(166, J.land, { x = -4.0, ease = "out3" })
Tj:add(190, J.settle, { x = -3.6, ease = "inout" })
Tj:add(236, J.loose, { x = -3.4 })
Tj:add(300, { J.loose, { headPitch = 6 } })
Tj:add(330, J.loose, { x = -3.2 })
Tj:add(420, J.loose, { x = -1.4, z = 0.2 })                                   -- walks toward him
Tj:add(500, J.settle, { x = 0.6, z = 0.3 })
Tj:add(599, J.loose, { x = 1.2, z = 0.3 })

---------------------------------------------------------------------------------------------- CHAPTER 2: Infinity (600-1500)
-- attempt 1: a flicked pebble slows beside Gojo's cheek (pebble path in D.fx)
Tj:add(600, J.flick, { x = 1.2 })
Tj:add(612, { J.flick, { rh = H(1.5, 0.5, 0.9) } }, { ease = "in2" })
Tj:add(622, J.loose, { x = 1.2 })
Gj:add(612, G.stand)
Gj:add(655, { G.watch, { headYaw = -8, headPitch = 4 } })
Gj:add(700, G.tilt)
-- attempt 2: an ordinary strike decelerates a visible gap short of Gojo's face (slow motion 905-960)
Tj:add(760, J.settle, { x = 1.4 })
Tj:add(840, J.loose, { x = 2.6, z = 0.3 })
Tj:add(895, J.strikeLoad, { x = 3.2, ease = "in2" })
Tj:add(900, J.strikeLoad, { x = 3.2 })
Tj:add(906, J.strike, { x = 3.5, ease = "in3" })                              -- contact baked: hover short of the face
Tj:add(960, J.strike, { x = 3.5, ease = "linear" })
Tj:add(985, J.settle, { x = 3.0, ease = "out2" })
Gj:add(840, G.stand)
Gj:add(900, { G.watch, { headPitch = 2 } })
Gj:add(906, { G.dodgeA, { rh = H(0.1, 0.72, -1.0) } }, { ease = "out2" })     -- he barely moves: a tiny lean while Infinity does the work
Gj:add(960, { G.dodgeA })
Gj:add(1000, G.tilt)
-- attempt 3: Toji changes direction midway and watches when Gojo turns
Tj:add(1040, J.coil, { x = 3.0, ease = "in2" })
Tj:add(1046, J.dash, { x = 3.0, ease = "in2" })
Tj:add(1050, J.dash, { x = 4.6, z = 2.8, ease = "linear" })                   -- feints to the near side
Tj:add(1055, J.strikeLoad, { x = 5.0, z = 2.8 })
Tj:add(1058, J.dash, { x = 7.8, z = -2.4, yaw = 20, ease = "linear" })        -- cuts back across behind Gojo's head
Tj:add(1066, J.strike, { x = 8.4, z = -2.4, yaw = 20 })
Tj:add(1100, J.watchHand, { x = 7.6, z = -2.0, yaw = 20 })
Tj:add(1180, J.watchHand, { x = 6.4, z = -2.3, yaw = 10 })
Tj:add(1260, J.settle, { x = 5.0, z = -0.4, yaw = 0 })
Tj:add(1380, J.settle, { x = 2.4, z = 0.2 })
Tj:add(1499, J.loose, { x = 1.0, z = 0.2 })
Gj:add(1040, { G.watch, { headYaw = -22 } })
Gj:add(1058, { G.watch, { headYaw = 10 } }, { ease = "linear" })              -- Gojo turns to follow; Toji's head tracks that turn
Gj:add(1090, { G.tilt, { headYaw = 18 } })
Gj:add(1200, { G.stand, { headYaw = 8 } })
Gj:add(1400, G.stand)
Gj:add(1499, G.shift)

---------------------------------------------------------------------------------------------- CHAPTER 3: Blue (1500-2400)
Gj:add(1500, G.stand)
Gj:add(1530, G.pointHold, { ease = "out2" })
Gj:add(1620, G.pointHold)
Gj:add(1690, { G.pointHold, { lean = -6 } })
Gj:add(1780, G.stand, { ease = "inout" })
Gj:add(1900, { G.watch, { headYaw = 40 } }, { yaw = 0 })
Gj:add(2000, { G.watch, { headYaw = 55 } })
Gj:add(2100, G.shift, { x = 6.2 })
Gj:add(2160, { G.watch, { headYaw = 60 } })
Gj:add(2250, G.stand, { x = 9.2 })                                            -- follows up toward the stair, then the walkway
Gj:add(2340, G.stand, { x = 16.6 })
Gj:add(2399, G.stand, { x = 18.0 })
-- Toji: trousers pull sideways (cloth wind), footing gives, he rides the slab up and over, lands on the stair, then the walkway
Tj:add(1530, J.loose, { x = 1.0, z = 0.2 })
Tj:add(1590, { J.crouchLow, { roll = 8 } }, { x = 0.6, z = 0.4 })              -- being pulled: footing gives
Tj:add(1640, J.crouchLow, { x = -1.6, z = 0.4, ease = "linear" })              -- dragged toward the point; slab arrives
Tj:add(1690, { J.coil, { crouch = 0.9 } }, { x = -2.2 })                       -- he steps onto the slab
Tj:add(1700, J.dash, { x = -1.0, gy = 0.4, ease = "in2" })
Tj:add(1708, J.air, { x = 3.0, gy = 2.3, ease = "linear", lf = F(0.4, -0.4, 0.8), rf = F(-0.4, 0.5, 0.8) })                    -- rides the tilting slab upward
Tj:add(1722, J.air, { x = 8.0, gy = 4.4, ease = "linear", lf = F(0.5, -0.4, 0.9), rf = F(-0.3, 0.5, 0.9) })                    -- over Gojo
Tj:add(1736, J.airSpear, { x = 11.2, gy = 4.0, ease = "in2", lf = F(0.6, -0.4, 0.6), rf = F(-0.3, 0.5, 0.5) })
Tj:add(1744, J.land, { x = 11.8, gy = 1.9, ease = "out2" })                    -- lands on the stair
Tj:add(1770, J.settle, { x = 12.0 })
Tj:add(1900, J.loose, { x = 13.5 })
Tj:add(2100, J.loose, { x = 15.0 })
Tj:add(2200, J.settle, { x = 19.0 })
Tj:add(2399, J.loose, { x = 24.0 })

---------------------------------------------------------------------------------------------- CHAPTER 4: Toji takes control (2400-3450)
Tj:add(2400, J.loose, { x = 24.0, z = 0.0 })
Tj:add(2480, J.spearHold, { x = 24.0 })                                       -- the curse uncoils and produces the Inverted Spear of Heaven
Tj:add(2560, J.spearHold, { x = 24.0 })
Tj:add(2640, J.spearHold, { x = 24.2, z = 0.3 })
Tj:add(2700, J.coil, { x = 24.2, ease = "in2" })
Tj:add(2705, J.dash, { x = 24.4, ease = "in2" })
Tj:add(2711, J.air, { x = 18.0, z = 1.8, ease = "linear" })                    -- crosses behind the swarm while Gojo watches the empty stair
Tj:add(2716, J.spearThrust, { x = 17.0, z = 1.0, ease = "linear" })           -- contact baked on Gojo's torso
Tj:add(2722, J.spearThrust, { x = 17.0, z = 1.0 })
Tj:add(2760, J.spearHold, { x = 16.4, z = 1.0, ease = "out2" })
Tj:add(2900, J.settle, { x = 17.6, z = 0.8 })
Tj:add(3000, J.loose, { x = 20.0, z = 0.4 })
Tj:add(3100, J.loose, { x = 17.0, z = -0.8 })                                  -- leaves: down the stair, out of frame
Tj:add(3200, J.dash, { x = 13.0, z = -0.6 })
Tj:add(3260, J.dash, { x = 5.0 })
Tj:add(3340, J.dash, { x = -8.0 })
Tj:add(3449, J.loose, { x = -12.0 })
Gj:add(2400, G.stand, { x = 18.0 })
Gj:add(2500, { G.watch, { headYaw = 10 } })
Gj:add(2600, { G.stand, { headYaw = -10 } })
Gj:add(2680, { G.watch, { headYaw = -34 } })                                  -- eyes tracking the swarm
Gj:add(2710, { G.watch, { headYaw = -50, headPitch = 6 } })
Gj:add(2716, G.hit, { x = 18.0, ease = "in3" })                                -- spear contact (Infinity folds inward)
Gj:add(2740, { G.hit, { lean = -26 } }, { x = 18.6, ease = "out2" })
Gj:add(2800, G.down, { x = 19.4, ease = "out2" })
Gj:add(3449, G.down, { x = 19.4 })

---------------------------------------------------------------------------------------------- CHAPTER 5: Awakening (3450-4200)
Gj:add(3450, G.down, { x = 19.4 })
Gj:add(3560, G.breathe1)
Gj:add(3640, G.breathe2)
Gj:add(3720, G.breathe1)
Gj:add(3780, { G.breathe2, { lh = H(0.95, -0.55, -1.75) } })                  -- fingers regain tension: the hand presses the tile
Gj:add(3850, G.rise1, { ease = "inout" })
Gj:add(3930, G.rise2, { ease = "inout" })
Gj:add(3990, G.stand, { x = 19.2 })
Gj:add(4060, G.stand, { x = 17.2 })                                            -- walks to the top of the stair
Gj:add(4130, G.stand, { x = 14.0, z = 0.6 })
Gj:add(4199, G.stand, { x = 11.0, z = 0.6 })
Tj:add(3450, J.loose, { x = -12.0 })
Tj:add(3900, J.settle, { x = -9.0, yaw = 180 })
Tj:add(4040, J.loose, { x = -9.0, yaw = 180 })                                 -- hears a footstep behind him
Tj:add(4060, { J.loose, { headYaw = -40 } }, { yaw = 180 })
Tj:add(4090, { J.turnBack }, { x = -9.0, yaw = 180 })
Tj:add(4150, J.settle, { x = -9.0, yaw = 0, ease = "out2" })
Tj:add(4199, J.loose, { x = -9.0, yaw = 0 })

---------------------------------------------------------------------------------------------- CHAPTER 6: Red (4200-5250)
Gj:add(4200, G.stand, { x = 11.0, z = 0.6 })
Gj:add(4260, G.stand, { x = 6.2, z = 0.0, ease = "inout" })
Gj:add(4330, { G.watch, { headYaw = -34 } })                                    -- already looking at the landing point
Gj:add(4380, G.red, { ease = "out2" })
Gj:add(4460, G.red)
Gj:add(4530, { G.stand, { headYaw = -20 } })
Gj:add(4620, G.dodgeA, { x = 6.0 })
Gj:add(4670, G.sidestep, { x = 5.6, z = -0.4 })
Gj:add(4740, G.dodgeB, { x = 6.0, z = 0.2 })
Gj:add(4800, { G.sidestep, { lean = -2 } }, { x = 5.8, z = -0.3 })
Gj:add(4900, G.dodgeA, { x = 6.2, z = 0.0 })
Gj:add(5000, { G.watch }, { x = 6.0 })
Gj:add(5120, { G.tilt }, { x = 6.0 })
Gj:add(5249, G.stand, { x = 6.0 })
Tj:add(4200, J.loose, { x = -9.0 })
Tj:add(4290, J.settle, { x = -17.0, yaw = 0 })
Tj:add(4330, J.coil, { x = -19.8, ease = "in2" })
Tj:add(4336, J.dash, { x = -19.2, ease = "in3" })
Tj:add(4340, J.dash, { x = -9.0, z = 0.2, ease = "linear" })
Tj:add(4342, { J.strike, { lean = 10 } }, { x = -5.4, z = 0.3, ease = "in2" })      -- the Red core repels him: reversed travel
Tj:add(4350, J.stagger, { x = -9.2, ease = "out2" })
Tj:add(4372, J.stagger, { x = -15.0, ease = "out2" })
Tj:add(4390, J.land, { x = -15.8, ease = "out2" })
Tj:add(4460, J.settle, { x = -15.0 })
Tj:add(4500, J.coil, { x = -14.8, ease = "in2" })
Tj:add(4506, J.dash, { x = -10.0, ease = "in2" })
Tj:add(4510, J.air, { x = -4.0, gy = 1.4, ease = "linear" })                     -- fast exchange: Toji changes height
Tj:add(4514, J.strike, { x = 3.0, gy = 0.0, ease = "in2" })
Tj:add(4522, J.land, { x = 3.4 })
Tj:add(4560, J.dash, { x = 8.5, z = -1.0 })
Tj:add(4565, J.strike, { x = 6.8, z = -1.2, ease = "in2" })
Tj:add(4590, J.crouchLow, { x = 6.0, z = 1.4 })
Tj:add(4640, J.dash, { x = 2.0, z = 1.6 })
Tj:add(4646, { J.strike, { rh = H(1.6, 0.4, 0.9) } }, { x = 4.2, z = 1.0, ease = "in2" })
Tj:add(4700, J.land, { x = 3.2, z = 0.8 })
Tj:add(4780, J.air, { x = 6.8, z = -0.2, gy = 1.8, ease = "in2" })
Tj:add(4786, J.airSpear, { x = 7.4, z = 0.2, gy = 1.9 })
Tj:add(4800, J.land, { x = 4.6, z = 0.4, gy = 0.0 })
Tj:add(4900, J.crouchLow, { x = 4.0, z = -0.2 })
Tj:add(4960, J.dash, { x = 8.4, z = 0.3 })
Tj:add(4966, J.strike, { x = 7.6, z = 0.0, ease = "in2" })
Tj:add(5020, J.settle, { x = 3.4, z = 0.2 })
Tj:add(5249, J.loose, { x = 3.0, z = 0.2 })

---------------------------------------------------------------------------------------------- CHAPTER 7: Toji's full arsenal (5250-6450)
Tj:add(5250, J.loose, { x = 3.0, z = 0.2 })
Tj:add(5340, J.spearHold, { x = 2.6 })                                          -- chain revealed: spear + chain, far end hidden in the curse
Tj:add(5460, J.coil, { x = 2.4, ease = "in2" })
Tj:add(5466, J.sweepBack, { x = 2.4 })
Tj:add(5474, J.sweep, { x = 3.4, ease = "in3" })                                -- exchange 1: a broad sweep that changes the available space
Tj:add(5486, J.sweep, { x = 3.8, ease = "out2" })
Tj:add(5530, J.settle, { x = 3.6 })
Tj:add(5680, J.dash, { x = 8.0 })
Tj:add(5686, J.strike, { x = 6.6, ease = "in2" })
Tj:add(5700, J.land, { x = 6.8 })
Tj:add(5780, J.pull, { x = 6.8 })                                               -- exchange 2: sudden return interrupts the approach
Tj:add(5800, J.pull, { x = 6.2, ease = "in2" })
Tj:add(5812, J.spearHold, { x = 6.2 })
Tj:add(5950, J.coil, { x = 3.8, ease = "in2" })
Tj:add(5956, J.air, { x = 7.0, gy = 2.0, ease = "in2" })                         -- exchange 3: airborne crossing, the chain divides the frame
Tj:add(5966, J.airSpear, { x = 12.0, gy = 2.6, z = -0.3, ease = "linear" })
Tj:add(5976, J.air, { x = 17.0, gy = 3.4, ease = "linear" })
Tj:add(5984, J.land, { x = 18.4, ease = "out2" })
Tj:add(6050, J.settle, { x = 17.0 })
Tj:add(6120, J.dash, { x = 10.0 })
Tj:add(6126, J.strike, { x = 8.0, z = 0.0, ease = "in2" })                       -- he nearly reclaims the advantage
Tj:add(6180, J.crouchLow, { x = 7.0, z = 0.4 })
Tj:add(6300, J.settle, { x = 6.0 })
Tj:add(6449, J.loose, { x = 2.0 })
Gj:add(5250, G.stand, { x = 6.0 })
Gj:add(5340, { G.watch, { headYaw = -28 } })
Gj:add(5474, G.dodgeA, { x = 6.0 })
Gj:add(5486, G.sidestep, { x = 7.8, z = -0.5, ease = "out2" })
Gj:add(5560, { G.watch, { headYaw = -20 } }, { x = 8.0 })
Gj:add(5640, G.stand, { x = 6.4, z = 0.0 })                                       -- steps in: the return interrupts him
Gj:add(5680, G.run, { x = 3.2 })
Gj:add(5800, G.hit, { x = 3.6, ease = "out2" })
Gj:add(5840, G.sidestep, { x = 7.2 })
Gj:add(5950, { G.watch, { headYaw = -16 } }, { x = 7.0 })
Gj:add(5976, G.dodgeA, { x = 9.4, ease = "out2" })
Gj:add(6060, G.sidestep, { x = 11.0 })
Gj:add(6130, G.dodgeB, { x = 11.6, z = 0.4 })
Gj:add(6220, G.sidestep, { x = 12.4 })
Gj:add(6449, { G.watch, { headYaw = -20 } }, { x = 12.4 })

---------------------------------------------------------------------------------------------- CHAPTER 8: Hollow Purple (6450-7200)
Gj:add(6450, { G.watch }, { x = 12.4, z = 0.0 })
Gj:add(6530, G.pointHold, { x = 12.4 })                                           -- Blue
Gj:add(6600, G.red, { x = 12.4 })                                                 -- Red
Gj:add(6700, G.purple, { x = 12.4, ease = "inout" })                              -- brings the two together
Gj:add(6870, G.purple, { x = 12.4 })
Gj:add(6900, { G.purple, { lean = -4 } }, { ease = "in3" })                       -- release
Gj:add(6960, { G.purple, { lean = -8 } })
Gj:add(7050, G.stand, { x = 12.4 })
Gj:add(7160, { G.tilt, { headPitch = 6 } })
Gj:add(7199, { G.tilt, { headPitch = 6 } })
Tj:add(6450, J.loose, { x = 2.0 })
Tj:add(6600, J.settle, { x = 2.4 })
Tj:add(6700, { J.guard }, { x = 2.4 })
Tj:add(6790, { J.guard, { headPitch = 0 } }, { x = 2.4 })                         -- recognises an unfamiliar technique
Tj:add(6860, J.dash, { x = 3.4 })
Tj:add(6900, { J.guard, { lean = 16 } }, { x = 3.4 })
Tj:add(6960, J.stagger, { x = 2.0, ease = "out2" })
Tj:add(7100, J.settle, { x = 1.4 })
Tj:add(7199, J.loose, { x = 1.4 })

---------------------------------------------------------------------------------------------- ADULT GOJO CHAPTERS (7200-9539) and SHIBUYA TOJI (9540-10289)
G.sign = { crouch = 0.1, lean = 2, rh = H(1.1, 0.15, 0.9), lh = H(1.0, -0.2, 0.85), rp = H(0.2, 0.4, 0.2), lp = H(0.2, -0.4, 0.2), pyaw = -10 }     -- the hand sign for the domain
G.uncover = { lean = -2, rh = H(0.5, 0.4, 1.5), rp = H(0.0, 0.5, 0.6), headPitch = -4 }                                                              -- fingers at the blindfold
G.blink = { crouch = 0.3, lean = 6 }
J.slack = { crouch = 0.15, lean = 12, headPitch = 22, rh = H(0.1, 0.8, -1.2), lh = H(0.1, -0.8, -1.2) }                                               -- body without its owner
J.takeover = { crouch = 0.3, lean = 0, headPitch = -6, rh = H(0.5, 0.7, -0.4), lh = H(0.5, -0.7, -0.4) }
J.cloud = { crouch = 0.55, lean = 10, pyaw = -14, rh = H(1.0, 0.5, 0.2), lh = H(0.7, -0.6, 0.1) }                                                     -- Playful Cloud held in two hands
J.cloudSwing = { crouch = 0.6, lean = 22, pyaw = 26, twist = 28, rh = H(1.9, 0.5, 0.4), lh = H(1.3, -0.4, 0.3) }
J.cloudWind = { crouch = 0.7, lean = 8, pyaw = -34, twist = -26, rh = H(0.4, 0.9, 0.4), lh = H(0.5, -0.4, 0.3) }
-- Gojo (adult): 7200 infinity filter / 7500 maximum-output Blue / 7950 spatial movement / 8400 unlimited void / 9300 the 0.2 s application
Gj:add(7200, G.stand, { x = 6.0, z = 0.0, gy = 0, yaw = 0 })
Gj:add(7300, { G.watch, { headYaw = -16 } })
Gj:add(7344, { G.tilt })                                                      -- the stone stops; the leaf already passed through
Gj:add(7440, G.shift)
Gj:add(7500, G.stand)
Gj:add(7560, G.pointHold, { ease = "out2" })
Gj:add(7680, G.pointHold)
Gj:add(7760, { G.pointHold, { lean = -6 } })
Gj:add(7900, G.stand, { ease = "inout" })
Gj:add(7980, G.stand, { x = 6.0 })
Gj:add(8040, G.blink, { x = 6.0, ease = "in2" })                              -- short reposition: three studs in four frames
Gj:add(8044, G.blink, { x = 9.0, ease = "out2" })
Gj:add(8100, G.stand, { x = 9.0 })
Gj:add(8140, G.stand, { x = -16.0, z = 0.0, lf = F(0.3, -0.45, 0), rf = F(-0.3, 0.55, 0) })     -- long-distance: departs at the gate ...
Gj:add(8200, G.stand, { x = -16.0 })
Gj:add(8203, G.blink, { x = 26.0, gy = 3.2, lf = F(0.3, -0.45, 0), rf = F(-0.3, 0.55, 0) })    -- ... arrives on the walkway
Gj:add(8300, G.stand, { x = 26.0 })
Gj:add(8399, G.stand, { x = 26.0 })
Gj:add(8400, G.dodgeA, { x = 6.0, z = 0.0, gy = 0, lf = F(0.2, -0.45, 0), rf = F(-0.2, 0.5, 0) })   -- unlimited void: the action is already underway
Gj:add(8440, G.dodgeB, { x = 6.0 })
Gj:add(8480, G.uncover, { ease = "out2" })
Gj:add(8540, G.uncover)
Gj:add(8570, G.sign, { ease = "out2" })
Gj:add(9040, G.sign)
Gj:add(9060, G.stand, { ease = "out2" })                                       -- the domain releases
Gj:add(9200, { G.uncover, { rh = H(0.6, 0.4, 1.3) } }, { ease = "inout" })
Gj:add(9299, G.stand)
Gj:add(9300, G.stand, { x = 6.0 })
Gj:add(9390, G.stand)
Gj:add(9412, G.sign, { ease = "in2" })                                         -- the 0.2 s application: anticipation, six frames, aftermath
Gj:add(9426, G.sign)
Gj:add(9440, G.stand, { ease = "out2" })
Gj:add(9539, G.tilt)
Gj:add(9540, G.stand, { x = -70.0, z = -60.0 })                                -- parked while Shibuya Toji has the stage
Gj:add(10289, G.stand, { x = -70.0, z = -60.0 })
Tj:add(7200, J.loose, { x = -60.0, z = -60.0 })                                -- parked through the adult chapters
Tj:add(9539, J.loose, { x = -60.0, z = -60.0 })
Tj:add(9540, J.slack, { x = -12.0, z = 0.0 })                                  -- Shibuya: the body stands slack, mist gathers
Tj:add(9660, J.slack, { x = -12.0 })
Tj:add(9690, J.takeover, { x = -12.0, ease = "out2" })                          -- the soul takes control: head lifts, eyes snap open
Tj:add(9750, J.cloud, { x = -12.0 })
Tj:add(9800, J.coil, { x = -12.0, ease = "in2" })
Tj:add(9806, J.dash, { x = -11.0, ease = "in3" })
Tj:add(9814, J.cloudSwing, { x = 3.2, z = 0.3, ease = "linear" })              -- speed across the water
Tj:add(9820, J.cloudSwing, { x = 3.6, ease = "out3" })
Tj:add(9880, J.cloud, { x = 3.0 })
Tj:add(9960, J.cloudWind, { x = 3.0, ease = "in2" })
Tj:add(9968, J.cloudSwing, { x = 3.6, z = 0.0, ease = "in3" })
Tj:add(10040, J.cloud, { x = 3.0 })
Tj:add(10100, J.dash, { x = -4.0, z = 1.0 })
Tj:add(10106, J.air, { x = 0.0, z = 0.6, gy = 1.6, ease = "linear" })
Tj:add(10116, J.cloudSwing, { x = 6.0, z = 0.0, gy = 0.0, ease = "in3" })
Tj:add(10200, J.cloud, { x = 5.0 })
Tj:add(10289, J.loose, { x = 5.0 })

---------------------------------------------------------------------------------------------- contacts (solved by BGEngine.bake)
D.contacts = {
	{ id = "fist-stop", kind = "hover", f = 906, attacker = "Purple", hand = "R", defender = "Blue", dpart = "head", dy = 0.0, gap = 0.5, fist = 0.3 },
	{ id = "spear-fold", kind = "chest", f = 2716, attacker = "Purple", hand = "R", defender = "Blue", surface = 0.5, up = 0.1 },
}

---------------------------------------------------------------------------------------------- eyes (Gojo's eyes find Toji before his head turns)
D.eyes = {
	Blue = { { f = 0, x = 0, y = 0 }, { f = 50, x = 0, y = 0 }, { f = 58, x = -0.075, y = 0 }, { f = 300, x = -0.075, y = 0 }, { f = 1058, x = 0.07, y = 0 },
		{ f = 1400, x = -0.05, y = 0 }, { f = 2680, x = -0.075, y = 0.02 }, { f = 3800, x = 0, y = 0 }, { f = 3880, x = 0.0, y = 0 },
		{ f = 4330, x = -0.075, y = 0 }, { f = 7000, x = 0, y = 0 }, { f = 7199, x = 0, y = -0.03 } },
	Purple = { { f = 0, x = 0, y = 0 }, { f = 4040, x = 0, y = 0 }, { f = 4052, x = 0.06, y = 0 }, { f = 4150, x = 0, y = 0 }, { f = 9660, x = 0, y = 0.08 }, { f = 9692, x = 0, y = 0 } },
}

---------------------------------------------------------------------------------------------- camera
-- pos/look = {x, y, z} or { rel = "Blue"|"Purple", o = {x, y, z} } (relative to that fighter's head). cut = true jumps on that frame; otherwise it blends from the previous key.
local function cam(f, pos, look, fov, extra)
	local c = { f = f, pos = pos, look = look, fov = fov }
	if extra then for k, v in pairs(extra) do c[k] = v end end
	return c
end
local function rel(who, x, y, z) return { rel = who, o = { x, y, z } } end
local WIDE_A = { { -4.0, 3.6, 17.5 }, { -4.0, 2.6, 0 }, 44 }                -- the opening wide: gate, pillar and Gojo, repeated in chapter 6
D.camera = {
	-- 1: glasses close-up, wide, Toji's landing, Gojo's eyes, Toji's scar
	cam(0,    rel("Blue", -0.1, 0.05, -1.6), rel("Blue", 0, 0.05, 0), 18, { cut = true, name = "1 glasses CU" }),
	cam(59,   rel("Blue", -0.1, 0.05, -1.6), rel("Blue", 0, 0.05, 0), 18),
	cam(60,   WIDE_A[1], WIDE_A[2], WIDE_A[3], { cut = true, name = "1 wide: gate, pillar, stair" }),
	cam(235,  WIDE_A[1], WIDE_A[2], WIDE_A[3]),
	cam(236,  rel("Blue", -0.4, 0.15, -2.4), rel("Blue", 0, 0.05, 0), 22, { cut = true, name = "1 Gojo CU: eyes first" }),
	cam(268,  rel("Blue", -0.4, 0.15, -2.4), rel("Blue", 0, 0.05, 0), 22),
	cam(269,  rel("Purple", 0.9, 0.1, 2.1), rel("Purple", 0, 0.0, 0), 20, { cut = true, name = "1 Toji CU: scar" }),
	cam(300,  rel("Purple", 0.9, 0.1, 2.1), rel("Purple", 0, 0.0, 0), 20),
	cam(301,  { -1.0, 3.2, 12.0 }, { 1.2, 2.8, 0 }, 40, { cut = true, name = "1 two-shot" }),
	cam(599,  { -0.6, 3.2, 11.4 }, { 1.6, 2.8, 0 }, 40),
	-- 2: pebble, fist stop (slow motion), feint
	cam(600,  { 4.0, 3.6, 7.0 }, { 5.6, 3.6, 0 }, 28, { cut = true, name = "2 pebble by the cheek" }),
	cam(700,  { 4.4, 3.6, 6.4 }, { 5.8, 3.6, 0 }, 26),
	cam(701,  { 2.0, 3.2, 11.0 }, { 4.2, 2.8, 0 }, 40, { cut = true, name = "2 two-shot" }),
	cam(900,  { 2.0, 3.2, 11.0 }, { 4.2, 2.8, 0 }, 40),
	cam(901,  { 4.2, 3.6, 5.6 }, { 5.0, 3.7, 0 }, 24, { cut = true, name = "2 the gap (slow)" }),
	cam(985,  { 4.4, 3.6, 5.2 }, { 5.0, 3.7, 0 }, 24),
	cam(986,  { 3.0, 3.2, 12.0 }, { 5.0, 2.8, 0 }, 40, { cut = true, name = "2 feint wide" }),
	cam(1260, { 3.4, 3.2, 12.0 }, { 5.0, 2.8, 0 }, 40),
	cam(1261, rel("Purple", 0.6, 0.15, 2.0), rel("Purple", 0, 0, 0), 22, { cut = true, name = "2 Toji studies" }),
	cam(1360, rel("Purple", 0.6, 0.15, 2.0), rel("Purple", 0, 0, 0), 22),
	cam(1361, { 3.0, 3.2, 12.0 }, { 3.8, 2.8, 0 }, 42, { cut = true }),
	-- 3: Blue: one continuous full-body shot of the maneuver, then the stair
	cam(1500, { 0.5, 3.4, 15.5 }, { 2.0, 2.6, 0 }, 46, { cut = true, name = "3 Gojo picks the point" }),
	cam(1680, { 0.5, 3.4, 15.5 }, { 2.0, 2.6, 0 }, 46),
	cam(1681, { 3.0, 4.2, 20.0 }, { 5.0, 3.0, 0 }, 52, { cut = true, name = "3 full-body maneuver (continuous)" }),
	cam(1790, { 4.0, 4.2, 20.0 }, { 7.0, 3.0, 0 }, 52),
	cam(1791, { 11.0, 4.0, 17.0 }, { 13.0, 3.0, 0 }, 46, { cut = true, name = "3 stair" }),
	cam(2399, { 16.0, 5.5, 18.0 }, { 20.0, 4.0, 0 }, 46),
	-- 4: walkway, swarm, Gojo's POV, wide reveal, the fold, Gojo down
	cam(2400, { 20.0, 5.4, 15.0 }, { 21.5, 4.4, 0 }, 44, { cut = true, name = "4 walkway: the curse uncoils" }),
	cam(2599, { 21.0, 5.4, 14.0 }, { 22.5, 4.4, 0 }, 42),
	cam(2600, { 17.0, 5.6, 13.0 }, { 18.0, 4.4, 0 }, 40, { cut = true, name = "4 the swarm" }),
	cam(2670, { 17.0, 5.6, 13.0 }, { 18.0, 4.4, 0 }, 40),
	cam(2671, rel("Blue", 0.0, 0.0, 0.5), { 13.0, 2.0, 0 }, 55, { cut = true, name = "4 Gojo POV: the empty stair" }),
	cam(2705, rel("Blue", 0.0, 0.0, 0.5), { 13.0, 2.0, 0 }, 55),
	cam(2706, { 19.0, 6.0, 15.0 }, { 18.0, 4.4, 0 }, 44, { cut = true, name = "4 wide: where he actually went" }),
	cam(2722, { 18.2, 5.6, 9.0 }, { 18.0, 4.6, 0 }, 28),
	cam(2760, { 19.0, 5.4, 12.0 }, { 19.0, 4.2, 0 }, 40, { name = "4 Gojo down" }),
	cam(3100, { 19.0, 5.2, 12.0 }, { 19.0, 4.0, 0 }, 40),
	cam(3101, { 14.0, 5.0, 16.0 }, { 14.0, 3.0, 0 }, 46, { cut = true, name = "4 Toji leaves frame" }),
	cam(3449, { 4.0, 4.0, 18.0 }, { 4.0, 2.0, 0 }, 46),
	-- 5: awakening (quiet): hand on tile, eyes, footstep, discovery
	cam(3450, rel("Blue", 0.4, -2.6, -1.6), rel("Blue", 0.8, -3.0, 0), 20, { cut = true, name = "5 hand on the tile" }),
	cam(3790, rel("Blue", 0.4, -2.6, -1.6), rel("Blue", 0.8, -3.0, 0), 18),
	cam(3791, rel("Blue", -0.2, 0.1, -2.2), rel("Blue", 0, 0.0, 0), 20, { cut = true, name = "5 eyes, no glasses" }),
	cam(3890, rel("Blue", -0.2, 0.1, -2.0), rel("Blue", 0, 0.0, 0), 18),
	cam(3891, { -5.0, 3.0, 11.0 }, { -9.0, 2.6, 0 }, 40, { cut = true, name = "5 Toji hears a footstep" }),
	cam(4090, { -5.0, 3.0, 11.0 }, { -9.0, 2.6, 0 }, 40),
	cam(4091, { -2.0, 3.4, 14.0 }, { 4.0, 3.0, 0 }, 46, { cut = true, name = "5 discovered: standing" }),
	cam(4199, { -1.0, 3.4, 14.0 }, { 5.0, 3.0, 0 }, 44),
	-- 6: Red: the opening angle again
	cam(4200, WIDE_A[1], WIDE_A[2], WIDE_A[3], { cut = true, name = "6 opening angle repeated" }),
	cam(4520, WIDE_A[1], WIDE_A[2], WIDE_A[3]),
	cam(4521, { -3.0, 4.0, 17.0 }, { 0.5, 2.8, 0 }, 46, { cut = true, name = "6 fast exchange wide" }),
	cam(5249, { 0.0, 4.0, 16.5 }, { 3.5, 2.8, 0 }, 46),
	-- 7: arsenal
	cam(5250, { 2.0, 3.6, 14.0 }, { 4.0, 2.8, 0 }, 44, { cut = true, name = "7 chain revealed" }),
	cam(5470, { 2.0, 3.6, 14.0 }, { 4.0, 2.8, 0 }, 44),
	cam(5471, { 3.0, 4.2, 18.0 }, { 4.6, 2.8, 0 }, 48, { cut = true, name = "7 the sweep" }),
	cam(5679, { 3.0, 4.2, 18.0 }, { 4.6, 2.8, 0 }, 48),
	cam(5680, { 5.0, 3.6, 13.0 }, { 5.2, 2.8, 0 }, 42, { cut = true, name = "7 the return" }),
	cam(5949, { 5.0, 3.6, 13.0 }, { 5.2, 2.8, 0 }, 42),
	cam(5950, { 10.0, 4.4, 20.0 }, { 11.0, 3.2, 0 }, 52, { cut = true, name = "7 airborne crossing (chain divides frame)" }),
	cam(6120, { 10.5, 4.4, 20.0 }, { 11.0, 3.2, 0 }, 52),
	cam(6121, { 7.0, 3.8, 14.0 }, { 8.0, 2.8, 0 }, 44, { cut = true, name = "7 nearly his" }),
	cam(6449, { 5.0, 3.8, 14.0 }, { 7.0, 2.8, 0 }, 44),
	-- 8: purple
	cam(6450, { 8.0, 3.4, 13.0 }, { 8.0, 2.8, 0 }, 42, { cut = true, name = "8 Gojo gathers" }),
	cam(6780, { 8.0, 3.4, 13.0 }, { 8.0, 2.8, 0 }, 42),
	cam(6781, rel("Purple", 0.5, 0.1, 2.0), rel("Purple", 0, 0, 0), 22, { cut = true, name = "8 Toji recognises it" }),
	cam(6860, rel("Purple", 0.5, 0.1, 2.0), rel("Purple", 0, 0, 0), 20),
	cam(6861, { -1.0, 4.4, 24.0 }, { 3.0, 2.8, 0 }, 56, { cut = true, name = "8 wide release: both + the pillar" }),
	cam(7010, { -1.0, 4.4, 24.0 }, { 3.0, 2.8, 0 }, 56),
	cam(7011, { 4.0, 3.2, 16.0 }, { 2.0, 1.2, 0 }, 40, { cut = true, name = "8 the cleared path" }),
	cam(7120, { 6.0, 2.6, 12.0 }, { 11.0, 1.8, 0 }, 40),
	cam(7121, rel("Blue", -0.2, 0.1, -2.4), rel("Blue", 0, 0.0, 0), 20, { cut = true, name = "8 Gojo's expression" }),
	cam(7199, rel("Blue", -0.2, 0.1, -2.4), rel("Blue", 0, 0.0, 0), 18),
	-- epilogue
}
local function addCams(list) for _, c in ipairs(list) do table.insert(D.camera, c) end end
addCams({
	cam(2440, rel("Purple", -1.5, -0.2, 2.4), rel("Purple", -0.8, -0.3, 0), 20, { cut = true, name = "4 the curse opens its mouth" }),
	cam(2496, { 21.0, 5.4, 14.0 }, { 22.5, 4.4, 0 }, 42, { cut = true, name = "4 walkway (spear out)" }),
	cam(7200, { 6.0, 3.4, 13.0 }, { 6.0, 3.0, 0 }, 40, { cut = true, name = "9 Infinity filters two objects" }),
	cam(7335, rel("Blue", -1.6, -0.2, 2.0), rel("Blue", -0.8, 0.0, 0), 24, { cut = true, name = "9 the stone stops" }),
	cam(7420, { 6.0, 3.4, 13.0 }, { 6.0, 3.0, 0 }, 40, { cut = true }),
	cam(7500, { 0.0, 7.0, 32.0 }, { 0.0, 2.0, 0 }, 60, { cut = true, name = "9 Maximum Output Blue (wide)" }),
	cam(7899, { 0.0, 7.0, 32.0 }, { 0.0, 2.0, 0 }, 60),
	cam(7900, { 7.0, 3.4, 13.0 }, { 7.0, 3.0, 0 }, 40, { cut = true, name = "9 reposition" }),
	cam(8110, { 5.0, 7.0, 44.0 }, { 5.0, 3.0, 0 }, 56, { cut = true, name = "9 long transport: gate to walkway" }),
	cam(8399, { 5.0, 7.0, 44.0 }, { 5.0, 3.0, 0 }, 56),
	cam(8400, { 6.0, 3.6, 14.0 }, { 7.0, 3.0, 0 }, 40, { cut = true, name = "10 Unlimited Void: action underway" }),
	cam(8480, rel("Blue", -0.2, 0.1, -2.2), rel("Blue", 0, 0.0, 0), 20, { cut = true, name = "10 uncovering his eyes" }),
	cam(8566, rel("Blue", -1.0, -0.8, -2.6), rel("Blue", -0.3, -0.7, 0), 22, { cut = true, name = "10 the hand sign" }),
	cam(8620, { 8.0, 9.0, 36.0 }, { 8.0, 3.0, 0 }, 55, { cut = true, name = "10 the barrier closes (wide)" }),
	cam(8700, { 6.0, 3.6, 11.0 }, { 8.0, 3.2, 0 }, 40, { cut = true, name = "10 inside the domain" }),
	cam(8830, { 5.0, 3.0, 8.0 }, { 6.0, 3.6, 0 }, 34),
	cam(8900, { 10.4, 3.4, 0.4 }, { 6.0, 3.4, 0 }, 50, { cut = true, name = "10 the opponent's view" }),
	cam(9050, { 8.0, 6.0, 34.0 }, { 8.0, 3.0, 0 }, 55, { cut = true, name = "10 release (outside)" }),
	cam(9200, rel("Blue", -0.2, 0.1, -2.2), rel("Blue", 0, 0.0, 0), 20, { cut = true, name = "10 the same eye framing" }),
	cam(9300, { 6.0, 4.0, 22.0 }, { 8.0, 3.0, 0 }, 46, { cut = true, name = "11 the 0.2 s application: setup" }),
	cam(9395, rel("Blue", -1.0, -0.8, -2.6), rel("Blue", -0.3, -0.7, 0), 22, { cut = true, name = "11 hands" }),
	cam(9418, { 8.0, 4.0, 22.0 }, { 8.0, 3.0, 0 }, 46, { cut = true, name = "11 six frames" }),
	cam(9432, { 8.0, 4.0, 22.0 }, { 8.0, 3.0, 0 }, 46, { name = "11 aftermath" }),
	cam(9540, { -4.0, 4.0, 22.0 }, { -2.0, 2.0, 0 }, 50, { cut = true, name = "12 Shibuya: the body" }),
	cam(9760, rel("Purple", 0.5, 0.1, 2.2), rel("Purple", 0, 0, 0), 22, { cut = true, name = "12 eyes snap open" }),
	cam(9790, { -2.0, 4.0, 24.0 }, { 0.0, 2.0, 0 }, 52, { cut = true, name = "12 speed across the water" }),
	cam(9960, { 2.0, 3.6, 16.0 }, { 3.5, 2.6, 0 }, 44, { cut = true, name = "12 Playful Cloud: sweep" }),
	cam(10095, { 0.0, 4.2, 22.0 }, { 1.5, 2.4, 0 }, 50, { cut = true, name = "12 leap" }),
	cam(10200, { 3.0, 3.6, 16.0 }, { 5.0, 2.6, 0 }, 44, { cut = true, name = "12 finish" }),
})
table.sort(D.camera, function(a, b) return a.f < b.f end)
D.shake = { { f = 159, amp = 0.35, frames = 5 }, { f = 1744, amp = 0.3, frames = 5 }, { f = 2722, amp = 0.35, frames = 5 }, { f = 4342, amp = 0.4, frames = 6 }, { f = 6900, amp = 0.6, frames = 8 } }
D.slowmo = { { f0 = 906, f1 = 960, scale = 0.25 }, { f0 = 6860, f1 = 6900, scale = 0.3 }, { f0 = 9414, f1 = 9440, scale = 0.2 } }      -- the first Infinity stop, and the beat before Purple

---------------------------------------------------------------------------------------------- state as functions of frame
function D.glassesState(f)       -- "face" | "flying" | "step" | "settling" | "settled" | "none"
	if f >= 7200 then return "none" end
	if f < 2716 then return "face" end
	if f < 2790 then return "flying" end
	if f < 7040 then return "step" end
	if f < 7125 then return "settling" end
	return "settled"
end
function D.spearVisible(f) return (f >= 2494 and f < 3460) or (f >= 4330 and f < 7200) end
function D.chainVisible(f) return f >= 5340 and f < 6449 end
function D.curseUncoiled(f) return f >= 2450 and f < 3460 or f >= 5300 and f < 6449 end

---------------------------------------------------------------------------------------------- effects (frames only; the player draws them)
D.fx = {
	reflection = { f0 = 30, f1 = 50 },
	pebble = { f0 = 612, f1 = 700, startOff = { -3.6, 0.2, 0.1 }, stopGap = 0.35 },
	infinityStops = { { id = "fist-stop", f0 = 906, f1 = 1020 } },
	blue = { f0 = 1500, f1 = 1740, point = { -5.0, 2.2, 0.0 }, tilt0 = 1560, slab0 = 1600, slab1 = 1700 },
	flyHeads = { f0 = 2600, f1 = 2760, count = 26 },
	fold = { f = 2716, dur = 24 },
	rct = { f0 = 3540, f1 = 3900 },
	red = { f0 = 4342, f1 = 4372, point = { -5.2, 2.0, 0.3 } },
	chain = { f0 = 5340, f1 = 6449 },
	purple = { blue0 = 6530, red0 = 6600, merge = 6820, release = 6900, beam1 = 7010, laneZ = 0.0 },
	filter = { leaf = { f0 = 7230, f1 = 7330 }, stone = { f0 = 7300, f1 = 7480 } },
	maxBlue = { f0 = 7560, f1 = 7900, point = { 0.0, 7.0, 0.0 }, radius = 26 },
	blink = { { f = 8040, to = { 9.0, 0 } }, { f = 8203, to = { 26.0, 3.2 } } },
	curtain = { f0 = 8240, f1 = 8399 },
	emerge = { f0 = 2440, f1 = 2494 },
	uv = { f0 = 8400, closeStart = 8620, closeEnd = 8700, inside0 = 8700, opp0 = 8900, release = 9050, restored = 9200 },
	uv02 = { f = 9420, frames = 6 },
	water = { f0 = 9540, f1 = 10289 },
	construct = { { f0 = 8400, f1 = 9300, x = 10.0 }, { f0 = 9300, f1 = 9540, x = 10.5 }, { f0 = 9740, f1 = 10289, x = 9.0 } },
}
D.sound = {  -- cues (ids in D.soundIds; blank = silence). music is a separate envelope
	{ f = 30, cue = "glass_shadow" }, { f = 158, cue = "burst" }, { f = 625, cue = "pebble_stop" }, { f = 909, cue = "infinity_stop" },
	{ f = 1560, cue = "blue" }, { f = 1745, cue = "land" }, { f = 2716, cue = "spear_fold" }, { f = 4045, cue = "footstep" },
	{ f = 4342, cue = "red" }, { f = 2444, cue = "curse_open" }, { f = 7340, cue = "infinity_stop" }, { f = 7560, cue = "blue" }, { f = 8203, cue = "transport" }, { f = 8620, cue = "barrier" }, { f = 8700, cue = "void_in" }, { f = 9050, cue = "void_out" }, { f = 9420, cue = "void_flash" }, { f = 9692, cue = "seance" }, { f = 9814, cue = "splash" }, { f = 5474, cue = "chain" }, { f = 6900, cue = "purple" }, { f = 7125, cue = "glasses" }, { f = 7440, cue = "void" },
}
D.soundIds = {
	burst = "rbxasset://sounds/swordlunge.wav", land = "rbxasset://sounds/impact_water.mp3", spear_fold = "rbxasset://sounds/impact_explosion_03.mp3",
	blue = "rbxasset://sounds/bass.mp3", red = "rbxasset://sounds/swordslash.wav", chain = "rbxasset://sounds/swordslash.wav", purple = "rbxasset://sounds/impact_explosion_03.mp3",
	footstep = "rbxasset://sounds/snap.mp3", infinity_stop = "rbxasset://sounds/electronicpingshort.wav", pebble_stop = "rbxasset://sounds/electronicpingshort.wav",
	glasses = "rbxasset://sounds/snap.mp3", void = "rbxasset://sounds/bass.mp3", curse_open = "rbxasset://sounds/impact_water.mp3", transport = "rbxasset://sounds/swordlunge.wav", barrier = "rbxasset://sounds/bass.mp3", void_in = "rbxasset://sounds/bass.mp3", void_out = "rbxasset://sounds/impact_explosion_03.mp3", void_flash = "rbxasset://sounds/electronicpingshort.wav", seance = "rbxasset://sounds/bass.mp3", splash = "rbxasset://sounds/impact_water.mp3", glass_shadow = "",
}
D.music = {  -- master volume envelope (frame, volume): music drops for the awakening, falls silent for Purple's aftermath
	{ 0, 0.5 }, { 3420, 0.5 }, { 3450, 0 }, { 4090, 0 }, { 4200, 0.5 }, { 6850, 0.5 }, { 6860, 0 }, { 7120, 0 }, { 7200, 0.4 }, { 8690, 0.4 }, { 8700, 0.05 }, { 9040, 0.05 }, { 9060, 0.5 }, { 9412, 0.5 }, { 9418, 0 }, { 9434, 0 }, { 9450, 0.5 }, { 10289, 0.5 },
}

---------------------------------------------------------------------------------------------- engine data
local function copy(t) local r = {} for k, v in pairs(t) do r[k] = v end return r end
function D.engineData()
	local out = { fighters = {}, contacts = {} }
	for name, s in pairs(D.seq) do out.fighters[name] = s:compile() end
	for i, c in ipairs(D.contacts) do
		local nc = copy(c)
		nc.t, nc.f = c.f / D.fps, nil
		out.contacts[i] = nc
	end
	return out
end
function D.playRate(frame)       -- slow-motion scale at this frame (1 = normal)
	for _, s in ipairs(D.slowmo) do if frame >= s.f0 and frame < s.f1 then return s.scale end end
	return 1
end
return D
]====])
put(RS, "ModuleScript", "BGLook", [====[
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
		for _, e in ipairs({ bloom, cc, dof }) do if e then e.Enabled = false end end
		if atmo then atmo.Density = 0 end      -- Atmosphere has no Enabled property: zero density turns the haze off
	else
		Lighting.ClockTime = 0
		Lighting.Brightness = 1.3
		Lighting.ExposureCompensation = 0
		Lighting.Ambient = Color3.fromRGB(60, 66, 100)
		Lighting.OutdoorAmbient = Color3.fromRGB(70, 76, 112)
		if bloom then bloom.Enabled = true; bloom.Intensity = 0.25; bloom.Size = 12; bloom.Threshold = 1.9 end   -- only tiny, very bright effect geometry blooms
		if cc then cc.Enabled = true; cc.Contrast = 0.08; cc.Saturation = -0.05; cc.TintColor = Color3.fromRGB(235, 238, 255) end
		if dof then dof.Enabled = false end
		if atmo then atmo.Density = 0.18; atmo.Offset = 0.1; atmo.Color = Color3.fromRGB(95, 105, 160); atmo.Decay = Color3.fromRGB(40, 45, 90); atmo.Haze = 0; atmo.Glare = 0 end
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
		elseif c:IsA("Atmosphere") then print(string.format("[LOOK]   Atmosphere density %.2f", c.Density))
		elseif c:IsA("SunRaysEffect") or c:IsA("BlurEffect") or c:IsA("DepthOfFieldEffect") then print("[LOOK]   " .. c.ClassName .. " enabled=" .. tostring(c.Enabled)) end
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
]====])
put(SSS, "Script", "BGBuilder", [====[
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
]====])
put(SSS, "Script", "BGServer", [====[
-- BGServer (Script, ServerScriptService): runs the authoritative fight (BGCore) and talks to clients.
-- Clients send INPUT only (move, m1, skill, guard ...). Damage, cooldowns, meter, form changes and ability eligibility
-- are all decided here in BGCore. Studio-only preview buttons are refused outside Studio.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("BGConfig"))
local Clips = require(ReplicatedStorage:WaitForChild("BGClips"))
local Core = require(ReplicatedStorage:WaitForChild("BGCore"))

local stage = Workspace:WaitForChild("Showcase")
while not stage:GetAttribute("Ready") do task.wait(0.1) end

local remotes = ReplicatedStorage:FindFirstChild("BGRemotes")
if remotes then remotes:Destroy() end
remotes = Instance.new("Folder")
remotes.Name = "BGRemotes"
local function remote(name)
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local InputRE, ControlRE, SnapRE, EventRE = remote("Input"), remote("Control"), remote("Snap"), remote("Event")
remotes.Parent = ReplicatedStorage

local world = Core.new(Config, Clips)
local state = { controlled = "Blue", aiMode = "Idle" }
local isStudio = RunService:IsStudio()

local function applyAI()
	world:setAI(state.controlled, nil)
	local other = state.controlled == "Blue" and "Purple" or "Blue"
	world:setAI(other, state.aiMode)
end
applyAI()

---------------------------------------------------------------- validation
local INPUT_KINDS = { move = true, m1 = true, skill = true, guard = true, counter = true, ult = true, form1 = true, final = true }
local buckets = {}
local function allow(plr)
	local b = buckets[plr]
	local now = os.clock()
	if not b then b = { tokens = 60, last = now }; buckets[plr] = b end
	b.tokens = math.min(60, b.tokens + (now - b.last) * 60)
	b.last = now
	if b.tokens < 1 then return false end
	b.tokens -= 1
	return true
end
Players.PlayerRemoving:Connect(function(p) buckets[p] = nil end)

InputRE.OnServerEvent:Connect(function(plr, kind, a, b)
	if typeof(kind) ~= "string" or not INPUT_KINDS[kind] or not allow(plr) then return end
	if stage:GetAttribute("Mode") ~= "Play" then return end
	if kind == "move" then
		if typeof(a) ~= "number" or typeof(b) ~= "number" then return end
	elseif kind == "skill" then
		if typeof(a) ~= "number" or a < 1 or a > 4 or a % 1 ~= 0 then return end
	elseif kind == "guard" then
		if typeof(a) ~= "boolean" then return end
	end
	world:input(state.controlled, kind, a, b)
end)

ControlRE.OnServerEvent:Connect(function(plr, kind, a)
	if typeof(kind) ~= "string" or not allow(plr) then return end
	if kind == "mode" and (a == "Play" or a == "Cinematic") then
		if stage:GetAttribute("Mode") ~= a then
			stage:SetAttribute("Mode", a)
			if a == "Play" then world:reset(); applyAI() end
		end
	elseif kind == "select" and (a == "Blue" or a == "Purple") then
		state.controlled = a
		world:reset()
		applyAI()
	elseif kind == "ai" and (a == "Idle" or a == "Guard" or a == "Attack") then
		state.aiMode = a
		applyAI()
	elseif kind == "reset" then
		world:reset()
		applyAI()
	elseif kind == "preview" and isStudio and (a == "Base" or a == "Form1" or a == "Final") then
		if stage:GetAttribute("Mode") == "Play" then world:forceForm(state.controlled, a) end
	end
end)

---------------------------------------------------------------- loop
local acc = 0
RunService.Heartbeat:Connect(function(dt)
	if stage:GetAttribute("Mode") ~= "Play" then return end
	dt = math.min(dt, 1 / 20)
	world:update(dt)
	local ev = world:drain()
	if #ev > 0 then EventRE:FireAllClients(ev) end
	acc += dt
	if acc >= 1 / 30 then
		acc = 0
		SnapRE:FireAllClients(world:snapshot(), state.controlled, state.aiMode, isStudio)
	end
end)
print("[BG] server ready. Studio preview controls:", isStudio and "enabled" or "disabled")
]====])
put(SP, "LocalScript", "BGClient", [====[
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
]====])
put(SP, "LocalScript", "BGDuelPlayer", [====[
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
local centerBall = mk(Enum.PartType.Ball, Vector3.new(4, 4, 4), Color3.fromRGB(255, 255, 255), Enum.Material.Neon, 1)
local streams = {}
for i = 1, 260 do
	local layer = (i % 3) + 1
	local col = ({ Color3.fromRGB(90, 160, 255), Color3.fromRGB(240, 244, 255), Color3.fromRGB(185, 110, 255), Color3.fromRGB(255, 140, 170) })[rng:NextInteger(1, 4)]
	streams[i] = { part = mk(nil, Vector3.new(0.05 * layer, 0.05 * layer, 1.5 + layer * 1.6), col, Enum.Material.Neon, 1), layer = layer,
		x = rng:NextNumber(-34, 34), y = rng:NextNumber(-4, 18), z0 = rng:NextNumber(-60, 12), speed = (4 - layer) * 4 + rng:NextNumber(2, 7), born = rng:NextInteger(0, 330) }
end
local domeShell = mk(Enum.PartType.Ball, Vector3.new(36, 36, 36), Color3.fromRGB(70, 80, 120), Enum.Material.SmoothPlastic, 1)
local function updateDomain(f)
	local k = envHide(f)
	-- courtyard dissolves; light falls with it
	for _, d in ipairs(stage:GetChildren()) do
		if d:IsA("BasePart") and not d:GetAttribute("Invisible") and d.Name ~= "PillarJag" then d.Transparency = (f >= D.fx.water.f0) and 1 or k end
	end
	local dark = math.min(1, uvK(f) + (f >= D.fx.uv02.f and f < D.fx.uv02.f + D.fx.uv02.frames and 1 or 0))
	if mode() == "Cinematic" and not state.neutral then
		Lighting.Ambient = DUSK.amb:Lerp(Color3.fromRGB(8, 8, 14), dark)
		Lighting.OutdoorAmbient = DUSK.out:Lerp(Color3.fromRGB(8, 8, 14), dark)
		Lighting.Brightness = DUSK.bright * (1 - 0.85 * dark)
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
	local grow = clamp01(((f >= D.fx.uv02.f and f < D.fx.uv02.f + D.fx.uv02.frames) and 330 or (f - u.inside0)) / 330)
	local nShow = math.floor(40 + 220 * grow)                       -- information keeps accumulating while the opponent is stalled
	local rateMul = (f >= u.opp0 and f < u.release) and 1.8 or 1
	for i, s in ipairs(streams) do
		if not inside or i > nShow then s.part.Transparency = 1
		else
			s.part.Transparency = 0.1 + 0.1 * s.layer
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
]====])
print("[BG] installed. Press Test > Play. It opens in the cinematic replay; press Tab or the Playable button to fight.")
