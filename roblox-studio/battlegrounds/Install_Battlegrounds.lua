-- ONE-PASTE INSTALLER: Kael vs Ren battlegrounds showcase.
-- Paste this whole file into Roblox Studio's Command Bar (View > Command Bar) or the Output window's command line, press Enter.
-- Creates 8 ModuleScripts (ReplicatedStorage), 2 Scripts (ServerScriptService), 2 LocalScripts (StarterPlayerScripts).
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
	local hipPivotY = R.hipStand - P.crouch
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
				k["w" .. side] = V3.new(w.X, s.lift or 0, w.Z)
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
	local function n(f) return lerp(a[f], b[f], e) end
	local P = {
		rx = n("px"), rz = n("pz"), yaw = track.def.baseYaw + n("yaw"), pyaw = n("pyaw"),
		crouch = n("crouch"), lean = n("lean"), twist = n("twist"), roll = n("roll"),
		headYaw = n("headYaw"), headPitch = n("headPitch"),
	}
	local body = bodyCF(P.rx, P.rz, P.yaw)
	local chestY = R.chestStand - P.crouch
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
	local spec = { f = -l.Z, s = l.X, y = l.Y - (track.R.chestStand - k.crouch) }
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
		local di = findKey(def_, c.t)
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
function Cloth:update(utCF, dt)
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
put(SSS, "Script", "BGBuilder", [====[
-- BGBuilder (Script, ServerScriptService): builds the moonlit stone arena and the two R15 fighters (Kael = "Blue", Ren = "Purple").
-- It does not animate or fight: BGServer decides combat, BGClient / BGDirector pose the rigs.
-- Re-running is safe (the previous build is deleted first). Edit costume colours / parts in the two build functions below.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local Data = require(ReplicatedStorage:WaitForChild("BGCinematicData"))
local Config = require(ReplicatedStorage:WaitForChild("BGConfig"))

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

---------------------------------------------------------------- stage: moonlit stone arena
Lighting.ClockTime = 0
Lighting.Brightness = 1.7
Lighting.ExposureCompensation = 0.45
Lighting.Ambient = Color3.fromRGB(62, 66, 105)
Lighting.OutdoorAmbient = Color3.fromRGB(78, 82, 125)

local function fx(inst)
	inst:SetAttribute("ShowcaseFX", true)
	inst.Parent = Lighting
	return inst
end
local atmo = Instance.new("Atmosphere")
atmo.Density = 0.28; atmo.Offset = 0.2; atmo.Color = Color3.fromRGB(100, 110, 175); atmo.Decay = Color3.fromRGB(40, 45, 90)
fx(atmo)
local bloom = Instance.new("BloomEffect")
bloom.Intensity = 0.9; bloom.Size = 26; bloom.Threshold = 0.9
fx(bloom)
local cc = Instance.new("ColorCorrectionEffect")
cc.Contrast = 0.28; cc.Saturation = -0.2; cc.TintColor = Color3.fromRGB(225, 228, 255)   -- high contrast, desaturated world: blue and violet are the only colours
fx(cc)
local dof = Instance.new("DepthOfFieldEffect")
dof.FarIntensity = 0.12; dof.NearIntensity = 0; dof.FocusDistance = 14; dof.InFocusRadius = 28
fx(dof)

local R = Config.arena.radius
local STONE, STONE2, STONE3 = Color3.fromRGB(58, 60, 74), Color3.fromRGB(40, 42, 56), Color3.fromRGB(78, 80, 98)
part({ Name = "Ground", Size = Vector3.new(500, 1, 500), Position = Vector3.new(0, -0.5, 0), Color = Color3.fromRGB(28, 30, 42),
	Material = Enum.Material.Slate, CanCollide = true })
-- raised stone disc
part({ Name = "ArenaFloor", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, (R + 3) * 2, (R + 3) * 2),
	CFrame = CFrame.new(0, -0.55, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(30, 32, 44), Material = Enum.Material.Slate, Reflectance = 0.3, CanCollide = true })   -- dark glossy floor
part({ Size = Vector3.new(0.1, (R + 3.4) * 2, (R + 3.4) * 2), Shape = Enum.PartType.Cylinder,
	CFrame = CFrame.new(0, -0.02, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = STONE3, Material = Enum.Material.Slate })
part({ Size = Vector3.new(0.12, R * 2, R * 2), Shape = Enum.PartType.Cylinder,
	CFrame = CFrame.new(0, 0.0, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = STONE2, Material = Enum.Material.Cobblestone })
-- engraved rings: restrained, so fighters stay the brightest things in the frame
for _, spec in ipairs({ { R * 2 - 1, 0.5, BLUE }, { R * 1.3, 0.4, VIOLET }, { 7, 0.35, Color3.fromRGB(150, 160, 210) } }) do
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.06, spec[1], spec[1]), CFrame = CFrame.new(0, 0.05, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = spec[3], Material = Enum.Material.Neon, Transparency = 0.82 })
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.07, spec[1] - 0.35, spec[1] - 0.35), CFrame = CFrame.new(0, 0.06, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = STONE2, Material = Enum.Material.Cobblestone })
end
part({ Name = "Moon", Shape = Enum.PartType.Ball, Size = Vector3.new(70, 70, 70), Position = Vector3.new(-70, 140, -260),
	Color = Color3.fromRGB(225, 232, 255), Material = Enum.Material.Neon, Transparency = 0.05 })

math.randomseed(7)
-- broken wall ring and pillars
for i = 1, 20 do
	local a = (i / 20) * math.pi * 2
	local h = (i % 3 == 0) and 1.2 or 2.6
	if i % 5 ~= 0 then
		part({ Size = Vector3.new(4.2, h, 1.4), CFrame = CFrame.new(math.cos(a) * (R + 2.2), h / 2, math.sin(a) * (R + 2.2)) * CFrame.Angles(0, -a + math.pi / 2, 0),
			Color = STONE2, Material = Enum.Material.Cobblestone })
	end
end
for i = 1, 8 do
	local a = (i / 8) * math.pi * 2 + 0.2
	local h = 14 + (i % 3) * 5
	local r = R + 7
	part({ Size = Vector3.new(3, h, 3), CFrame = CFrame.new(math.cos(a) * r, h / 2, math.sin(a) * r) * CFrame.Angles(0, a, math.rad(math.random(-2, 2))),
		Color = STONE, Material = Enum.Material.Slate })
	part({ Size = Vector3.new(3.8, 0.8, 3.8), CFrame = CFrame.new(math.cos(a) * r, h + 0.4, math.sin(a) * r) * CFrame.Angles(0, a, 0), Color = STONE3, Material = Enum.Material.Slate })
end
-- far arch
part({ Size = Vector3.new(3.4, 18, 3.4), Position = Vector3.new(-8, 9, -34), Color = STONE, Material = Enum.Material.Slate })
part({ Size = Vector3.new(3.4, 18, 3.4), Position = Vector3.new(8, 9, -34), Color = STONE, Material = Enum.Material.Slate })
part({ Size = Vector3.new(21, 3, 4), Position = Vector3.new(0, 19.5, -34), Color = STONE3, Material = Enum.Material.Slate })
-- moon-cool and violet-warm lights
for _, spec in ipairs({ { Vector3.new(-10, 12, 10), Color3.fromRGB(110, 170, 255), 1.5 }, { Vector3.new(10, 12, 10), Color3.fromRGB(170, 120, 255), 1.3 },
	{ Vector3.new(0, 18, -6), Color3.fromRGB(215, 225, 255), 1.0 } }) do
	local lp = part({ Size = Vector3.new(1, 1, 1), Position = spec[1], Transparency = 1 })
	local l = Instance.new("PointLight")
	l.Color = spec[2]; l.Range = 48; l.Brightness = spec[3]
	l.Parent = lp
end
-- drifting motes (blue and violet) over the arena: a quiet particle layer that is always present
for i, col in ipairs({ BLUE, VIOLET }) do
	local mp = part({ Name = "Motes" .. i, Size = Vector3.new(34, 1, 34), Position = Vector3.new(0, 14, 0), Transparency = 1 })
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(col); pe.LightEmission = 1; pe.Rate = 7
	pe.Lifetime = NumberRange.new(7, 10); pe.Speed = NumberRange.new(0.4, 1.2)
	pe.EmissionDirection = Enum.NormalId.Bottom; pe.SpreadAngle = Vector2.new(20, 20)
	pe.Size = NumberSequence.new(0.16, 0.1); pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.45), NumberSequenceKeypoint.new(1, 1) })
	pe.Parent = mp
end
local focus = part({ Name = "FocusPoint", Size = Vector3.new(1, 1, 1), Position = Vector3.new(0, 4, 0), Transparency = 1 })
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
			local l = part({ Size = Vector3.new(size.X * 0.92, size.Y * 0.96, 0.05), Color = lining, Material = Enum.Material.Neon, Transparency = 0.55 }, model)
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

-- Blocky expressive face made of thin parts on the front of the head.
-- cfg: eye = {w,h}, pupil = {w,h}, brow = {w,h,tiltDeg,y}, mouth = {w,tiltDeg,y}, irisColor
local function face(model, cfg)
	local dark = Color3.fromRGB(18, 16, 20)
	for _, s in ipairs({ -1, 1 }) do
		local ex = s * 0.29
		accessory(model, "Head", Vector3.new(cfg.eye[1], cfg.eye[2], 0.04), CFrame.new(ex, 0.08, -0.61), Color3.fromRGB(246, 246, 250), Enum.Material.SmoothPlastic)
		accessory(model, "Head", Vector3.new(cfg.pupil[1], cfg.pupil[2], 0.05), CFrame.new(ex - s * 0.02, 0.07, -0.625), cfg.irisColor, Enum.Material.SmoothPlastic, "Eye")
		accessory(model, "Head", Vector3.new(cfg.pupil[1] * 0.45, cfg.pupil[2] * 0.45, 0.055), CFrame.new(ex - s * 0.02, 0.07, -0.63), dark)
		-- eyebrows tilt toward the nose and down = focused / stern
		accessory(model, "Head", Vector3.new(cfg.brow[1], cfg.brow[2], 0.05),
			CFrame.new(ex, cfg.brow[4], -0.615) * CFrame.Angles(0, 0, math.rad(-s * cfg.brow[3])), cfg.browColor or dark, Enum.Material.SmoothPlastic, "Brow")
	end
	accessory(model, "Head", Vector3.new(cfg.mouth[1], 0.05, 0.04), CFrame.new(0.02, cfg.mouth[3], -0.61) * CFrame.Angles(0, 0, math.rad(cfg.mouth[2])), dark)
end

-- KAEL (Blue): slightly leaner, dark swept-back spiky hair with one blue lock, warm tan face, navy fitted combat jacket with cyan piping,
-- short two-tail scarf, black belt with silver buckle, tapered dark pants, charcoal boots, fingerless gloves, slim right forearm guard.
local function buildKael()
	local m = newRig("Blue", { skin = Color3.fromRGB(222, 170, 124), torso = Color3.fromRGB(26, 34, 66),
		arm = Color3.fromRGB(26, 34, 66), leg = Color3.fromRGB(26, 28, 38) })
	m:SetAttribute("Character", "Kael")
	local navy, deep, black = Color3.fromRGB(26, 34, 66), Color3.fromRGB(18, 22, 44), Color3.fromRGB(14, 14, 18)
	local char = Color3.fromRGB(50, 52, 62)
	local hairC = Color3.fromRGB(22, 20, 30)
	-- hair: cap + swept-back spikes in layers, one blue lock near the fringe
	accessory(m, "Head", Vector3.new(1.3, 0.5, 1.3), CFrame.new(0, 0.62, 0.02), hairC, nil, "Hair")
	for i = 1, 7 do
		local x = (i - 4) * 0.3
		local h = 1.0 - math.abs(i - 4) * 0.1
		accessory(m, "Head", Vector3.new(0.34, h, 0.5), CFrame.new(x, 0.78, 0.22) * CFrame.Angles(0.75, 0, -x * 0.5), hairC, nil, "Hair")
	end
	accessory(m, "Head", Vector3.new(0.3, 0.7, 0.45), CFrame.new(-0.6, 0.45, 0.2) * CFrame.Angles(0.5, 0, 0.35), hairC, nil, "Hair")
	accessory(m, "Head", Vector3.new(0.3, 0.7, 0.45), CFrame.new(0.6, 0.45, 0.2) * CFrame.Angles(0.5, 0, -0.35), hairC, nil, "Hair")
	accessory(m, "Head", Vector3.new(0.2, 0.55, 0.3), CFrame.new(-0.3, 0.7, -0.45) * CFrame.Angles(-0.5, 0, 0.1), BLUE, Enum.Material.SmoothPlastic, "Accent")   -- the blue lock
	face(m, { eye = { 0.28, 0.2 }, pupil = { 0.16, 0.18 }, brow = { 0.36, 0.08, 16, 0.3 }, mouth = { 0.3, 5, -0.3 }, irisColor = Color3.fromRGB(38, 70, 120) })
	-- fitted jacket, collar and piping
	accessory(m, "UpperTorso", Vector3.new(2.05, 1.42, 1.08), CFrame.new(0, -0.05, 0.01), navy, Enum.Material.Fabric)
	accessory(m, "UpperTorso", Vector3.new(2.1, 0.5, 1.1), CFrame.new(0, 0.74, 0), deep, Enum.Material.Fabric)                   -- collar band
	accessory(m, "UpperTorso", Vector3.new(0.09, 1.3, 0.1), CFrame.new(0, -0.05, -0.58), Color3.fromRGB(170, 175, 195), Enum.Material.Metal)  -- zip
	accessory(m, "UpperTorso", Vector3.new(2.14, 0.07, 1.14), CFrame.new(0, 0.66, 0), CYAN, Enum.Material.Neon, "Seam")           -- shoulder line piping
	accessory(m, "UpperTorso", Vector3.new(0.07, 0.9, 0.07), CFrame.new(-0.5, -0.15, -0.58), CYAN, Enum.Material.Neon, "Seam")
	accessory(m, "UpperTorso", Vector3.new(0.07, 0.9, 0.07), CFrame.new(0.5, -0.15, -0.58), CYAN, Enum.Material.Neon, "Seam")
	accessory(m, "LowerTorso", Vector3.new(2.05, 0.4, 1.08), CFrame.new(0, 0.1, 0.01), navy, Enum.Material.Fabric)
	accessory(m, "LowerTorso", Vector3.new(2.06, 0.2, 1.1), CFrame.new(0, -0.06, 0), black, Enum.Material.Leather)                 -- matte belt
	accessory(m, "LowerTorso", Vector3.new(0.3, 0.2, 0.08), CFrame.new(0, -0.06, -0.57), Color3.fromRGB(205, 208, 220), Enum.Material.Metal) -- silver buckle
	for _, n in ipairs({ "RightUpperArm", "LeftUpperArm" }) do
		accessory(m, n, Vector3.new(1.12, 0.35, 1.12), CFrame.new(0, 0.48, 0), navy, Enum.Material.Fabric)                          -- angled shoulder
		accessory(m, n, Vector3.new(1.16, 0.07, 1.16), CFrame.new(0, 0.3, 0), CYAN, Enum.Material.Neon, "Seam")
	end
	for _, n in ipairs({ "RightLowerArm", "LeftLowerArm" }) do
		accessory(m, n, Vector3.new(1.06, 0.07, 1.06), CFrame.new(0, 0.3, 0), CYAN, Enum.Material.Neon, "Seam")                     -- forearm piping
		accessory(m, n, Vector3.new(1.06, 0.07, 1.06), CFrame.new(0, -0.3, 0), CYAN, Enum.Material.Neon, "Seam")
	end
	local g = accessory(m, "RightLowerArm", Vector3.new(1.14, 0.65, 1.14), CFrame.new(0, -0.02, 0), char, Enum.Material.Metal, "Bracer")   -- slim right forearm guard
	if g then g.Name = "KaelGuardR" end
	accessory(m, "RightLowerArm", Vector3.new(1.18, 0.06, 1.18), CFrame.new(0, 0.25, 0), CYAN, Enum.Material.Neon, "Seam")
	for _, n in ipairs({ "RightHand", "LeftHand" }) do
		accessory(m, n, Vector3.new(1.02, 0.34, 1.02), CFrame.new(0, 0.12, 0), black, Enum.Material.Leather)                         -- fingerless glove
	end
	for _, n in ipairs({ "RightUpperLeg", "LeftUpperLeg" }) do accessory(m, n, Vector3.new(1.04, 1.1, 1.04), CFrame.new(0, 0, 0), Color3.fromRGB(28, 30, 40), Enum.Material.Fabric) end
	for _, n in ipairs({ "RightLowerLeg", "LeftLowerLeg" }) do
		accessory(m, n, Vector3.new(0.92, 0.95, 0.92), CFrame.new(0, 0.02, 0), Color3.fromRGB(28, 30, 40), Enum.Material.Fabric)      -- tapered
		accessory(m, n, Vector3.new(1.1, 0.38, 1.1), CFrame.new(0, -0.45, 0), char, Enum.Material.Leather)                           -- boot cuff
	end
	for _, n in ipairs({ "RightFoot", "LeftFoot" }) do accessory(m, n, Vector3.new(1.1, 0.7, 1.25), CFrame.new(0, 0.1, 0), char, Enum.Material.Leather) end
	-- short scarf: collar wrap + two tails (third segment appears in power forms)
	accessory(m, "UpperTorso", Vector3.new(1.7, 0.42, 1.25), CFrame.new(0, 0.9, 0.04), Color3.fromRGB(34, 44, 86), Enum.Material.Fabric)
	local tailC = Color3.fromRGB(34, 44, 86)
	for k, x in ipairs({ -0.32, 0.32 }) do
		local last = cloth(m, "UpperTorso", "Scarf" .. k, CFrame.new(x, 0.78, 0.62), 3, Vector3.new(0.5, 0.55, 0.16), tailC)
		if last then
			last.Transparency = 1                      -- the long third segment is hidden until Charged Mode
			last:SetAttribute("PowerSegment", true)
			local trim = part({ Size = Vector3.new(0.5, 0.07, 0.17), Color = CYAN, Material = Enum.Material.Neon, Anchored = false, Massless = true }, m)
			trim:SetAttribute("Seam", true)
			weld(trim, m:FindFirstChild("Scarf" .. k .. 2) or last, CFrame.new(0, -0.27, 0))
		end
	end
	addTrail(m, "RightHand", BLUE); addTrail(m, "LeftHand", BLUE)
	return m
end

-- REN (Purple): broader shoulders, lower and heavier, silver-lavender side-swept hair, stern square face,
-- black high-collar coat with a split hem and violet lining, charcoal pants, heavy square boots, reinforced bracers, angular back emblem.
local function buildRen()
	local m = newRig("Purple", { skin = Color3.fromRGB(236, 200, 172), torso = Color3.fromRGB(16, 16, 22),
		arm = Color3.fromRGB(20, 20, 28), leg = Color3.fromRGB(44, 46, 56) })
	m:SetAttribute("Character", "Ren")
	local black, coat, char = Color3.fromRGB(14, 14, 20), Color3.fromRGB(18, 18, 26), Color3.fromRGB(46, 48, 58)
	local hairC = Color3.fromRGB(190, 184, 220)
	-- hair: cap + a long slab swept to one side so the brows stay visible
	accessory(m, "Head", Vector3.new(1.32, 0.5, 1.32), CFrame.new(0, 0.63, 0.02), hairC, nil, "Hair")
	accessory(m, "Head", Vector3.new(1.0, 0.34, 1.0), CFrame.new(0.22, 0.88, -0.05) * CFrame.Angles(0, 0, -0.28), hairC, nil, "Hair")
	accessory(m, "Head", Vector3.new(0.7, 0.3, 0.9), CFrame.new(0.62, 0.74, 0.0) * CFrame.Angles(0, 0, -0.5), hairC, nil, "Hair")
	accessory(m, "Head", Vector3.new(0.5, 0.28, 0.5), CFrame.new(0.85, 0.52, -0.05) * CFrame.Angles(0, 0, -0.9), hairC, nil, "Hair")
	accessory(m, "Head", Vector3.new(0.9, 0.18, 0.4), CFrame.new(0.2, 0.52, -0.45) * CFrame.Angles(-0.2, 0, -0.18), hairC, nil, "Hair")   -- fringe above the brows
	accessory(m, "Head", Vector3.new(0.35, 0.6, 0.5), CFrame.new(-0.58, 0.3, 0.2), hairC, nil, "Hair")
	face(m, { eye = { 0.3, 0.15 }, pupil = { 0.16, 0.14 }, brow = { 0.42, 0.1, 12, 0.28 }, mouth = { 0.32, 0, -0.3 }, irisColor = Color3.fromRGB(88, 70, 120), browColor = Color3.fromRGB(26, 22, 32) })
	-- high-collar coat
	accessory(m, "UpperTorso", Vector3.new(2.38, 1.5, 1.16), CFrame.new(0, -0.04, 0.01), coat, Enum.Material.Fabric)
	accessory(m, "UpperTorso", Vector3.new(2.2, 0.8, 1.32), CFrame.new(0, 0.86, 0.02), black, Enum.Material.Fabric)                -- high collar
	accessory(m, "UpperTorso", Vector3.new(0.12, 0.7, 1.34), CFrame.new(0, 0.86, 0), VIOLET, Enum.Material.Neon, "Seam", { Transparency = 1 })
	accessory(m, "UpperTorso", Vector3.new(0.08, 1.35, 0.08), CFrame.new(0, -0.05, -0.6), Color3.fromRGB(60, 60, 78), Enum.Material.Metal)
	accessory(m, "LowerTorso", Vector3.new(2.2, 0.42, 1.12), CFrame.new(0, 0.1, 0.01), coat, Enum.Material.Fabric)
	accessory(m, "LowerTorso", Vector3.new(2.22, 0.2, 1.14), CFrame.new(0, -0.06, 0), black, Enum.Material.Leather)
	-- angular emblem on the back: two nested chevron bars
	for i, w in ipairs({ 1.0, 0.62 }) do
		accessory(m, "UpperTorso", Vector3.new(w, 0.12, 0.05), CFrame.new(-w * 0.2, 0.25 - i * 0.32, 0.6) * CFrame.Angles(0, 0, 0.5), VIOLET, Enum.Material.Neon, "Emblem", { Transparency = 0.45 })
		accessory(m, "UpperTorso", Vector3.new(w, 0.12, 0.05), CFrame.new(w * 0.2, 0.25 - i * 0.32, 0.6) * CFrame.Angles(0, 0, -0.5), VIOLET, Enum.Material.Neon, "Emblem", { Transparency = 0.45 })
	end
	for _, n in ipairs({ "RightUpperArm", "LeftUpperArm" }) do
		accessory(m, n, Vector3.new(1.34, 0.45, 1.34), CFrame.new(0, 0.45, 0), black, Enum.Material.Fabric)                         -- broad shoulder
		accessory(m, n, Vector3.new(1.18, 0.9, 1.18), CFrame.new(0, -0.1, 0), coat, Enum.Material.Fabric)
	end
	-- reinforced bracers: width comes from the cinematic contact data so the clash geometry matches
	local gw = Data.contacts[1].guardRadius * 2
	for _, n in ipairs({ "RightLowerArm", "LeftLowerArm" }) do
		local la = m:FindFirstChild(n)
		local g = accessory(m, n, Vector3.new(gw, la.Size.Y * 0.85, gw), CFrame.new(0, 0, 0), Color3.fromRGB(24, 24, 32), Enum.Material.Metal, "Bracer")
		g.Name = (n == "LeftLowerArm") and "GuardL" or "GuardR"
		for _, y in ipairs({ 0.3, -0.3 }) do
			accessory(m, n, Vector3.new(gw + 0.04, 0.08, gw + 0.04), CFrame.new(0, la.Size.Y * y, 0), VIOLET, Enum.Material.Neon, "Seam", { Transparency = 1 })
		end
		accessory(m, n, Vector3.new(gw + 0.2, 0.5, gw + 0.2), CFrame.new(0, 0, 0), VIOLET, Enum.Material.Neon, "Accent", { Transparency = 1 })   -- translucent layer for Eclipse Form
	end
	for _, n in ipairs({ "RightHand", "LeftHand" }) do accessory(m, n, Vector3.new(1.04, 0.4, 1.04), CFrame.new(0, 0.1, 0), black, Enum.Material.Leather) end
	for _, n in ipairs({ "RightUpperLeg", "LeftUpperLeg" }) do accessory(m, n, Vector3.new(1.16, 1.12, 1.16), CFrame.new(0, 0, 0), char, Enum.Material.Fabric) end
	for _, n in ipairs({ "RightLowerLeg", "LeftLowerLeg" }) do accessory(m, n, Vector3.new(1.1, 1.0, 1.1), CFrame.new(0, 0.02, 0), char, Enum.Material.Fabric) end
	for _, n in ipairs({ "RightFoot", "LeftFoot" }) do accessory(m, n, Vector3.new(1.2, 0.8, 1.38), CFrame.new(0, 0.12, 0), black, Enum.Material.Leather) end   -- heavy square boots
	-- split hem: two flaps at the back, violet lining shows when they swing
	for k, x in ipairs({ -0.52, 0.52 }) do
		cloth(m, "LowerTorso", "Hem" .. k, CFrame.new(x, -0.1, 0.56), 2, Vector3.new(0.95, 0.75, 0.14), coat, VIOLET)
	end
	-- two long hair tails from the back of the head: cloth chains that swing with the body
	for k, x in ipairs({ -0.3, 0.3 }) do
		cloth(m, "Head", "HT" .. k, CFrame.new(x, 0.15, 0.6), 3, Vector3.new(0.42, 1.0, 0.14), hairC)
	end
	for _, c in ipairs(m:GetChildren()) do
		if c:IsA("BasePart") and c.Name:sub(1, 2) == "HT" then c:SetAttribute("Hair", true) end
	end
	addTrail(m, "RightHand", VIOLET); addTrail(m, "LeftHand", VIOLET)
	addTrail(m, "RightLowerArm", VIOLET); addTrail(m, "LeftLowerArm", VIOLET)
	return m
end

local kael = buildKael()
local ren = buildRen()
kael:PivotTo(CFrame.new(-Config.arena.spawn, 3, 0) * CFrame.Angles(0, math.rad(-90), 0))
ren:PivotTo(CFrame.new(Config.arena.spawn, 3, 0) * CFrame.Angles(0, math.rad(90), 0))
for _, m in ipairs({ kael, ren }) do
	m.HumanoidRootPart.Anchored = true     -- the clients position it each frame
end

stage:SetAttribute("Mode", "Cinematic")
stage:SetAttribute("Ready", true)
print("[BG] arena and fighters built (Blue = Kael, Purple = Ren).")
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
put(SP, "LocalScript", "BGDirector", [====[
-- BGDirector (LocalScript, StarterPlayer > StarterPlayerScripts): the CINEMATIC REPLAY of Kael vs Ren.
-- It only runs while the stage attribute Mode == "Cinematic" (BGClient owns Mode == "Play").
-- Plays the keyframes from ShowcaseData on the two fighters, drives the camera, markers, VFX and checks.
-- Controls:  R replay   V VFX on/off   B slow motion   Space pause   , . step (paused)
--            C contact inspector (freeze at the clash, cycle side / top camera, prints the measured gap)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local Engine = require(ReplicatedStorage:WaitForChild("BGEngine"))
local Data = require(ReplicatedStorage:WaitForChild("BGCinematicData"))
local Cloth = require(ReplicatedStorage:WaitForChild("BGCloth"))
local Style = require(ReplicatedStorage:WaitForChild("BGStyle"))

local stage = Workspace:WaitForChild("Showcase")
while not stage:GetAttribute("Ready") do task.wait(0.1) end
local fighters = { Blue = stage:WaitForChild("Blue"), Purple = stage:WaitForChild("Purple") }
for _, m in pairs(fighters) do
	m:WaitForChild("HumanoidRootPart"); m:WaitForChild("RightFoot"); m:WaitForChild("UpperTorso"); m:WaitForChild("LowerTorso")
end

---------------------------------------------------------------- rig + bake
-- Joints are found by the part they move (Part1), so it works whatever the Motor6D is named.
local PART1 = { Root = "LowerTorso", Waist = "UpperTorso", Neck = "Head",
	RightShoulder = "RightUpperArm", RightElbow = "RightLowerArm", RightWrist = "RightHand",
	LeftShoulder = "LeftUpperArm", LeftElbow = "LeftLowerArm", LeftWrist = "LeftHand",
	RightHip = "RightUpperLeg", RightKnee = "RightLowerLeg", RightAnkle = "RightFoot",
	LeftHip = "LeftUpperLeg", LeftKnee = "LeftLowerLeg", LeftAnkle = "LeftFoot" }
local function findJoint(model, n)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") and d.Part1 and d.Part1.Name == PART1[n] and d.Part0 and not d:GetAttribute("Chain") then
			return d
		end
	end
end
local function readRig(model)
	local defs = {}
	for _, n in ipairs(Engine.JOINTS) do
		local m = findJoint(model, n)
		local waited = 0
		while not m and waited < 10 do task.wait(0.1); waited = waited + 0.1; m = findJoint(model, n) end
		if not m then
			local names = {}
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("Motor6D") then table.insert(names, d.Name .. "(" .. d.Parent.Name .. ")") end
			end
			warn("BGDirector: joint for " .. n .. " not found on " .. model.Name .. ". Motor6Ds present: " .. table.concat(names, ", "))
			error("missing joint " .. n)
		end
		defs[n] = { c0 = m.C0, c1 = m.C1, motor = m }
	end
	return defs, { footY = model.RightFoot.Size.Y, footZ = model.RightFoot.Size.Z }
end
local rigDefs, rigSizes = {}, nil
for name, model in pairs(fighters) do
	rigDefs[name], rigSizes = readRig(model)
end
local R = Engine.newRig(rigDefs.Blue, rigSizes)
local tracks, info = Engine.bake(R, Data)
print(string.format("[SHOWCASE] rig: leg %.2f arm %.2f reach %.2f | Blue anchor x=%.2f z=%.2f", R.legLen, R.armLen, R.armReach,
	tracks.Blue.anchor.x, tracks.Blue.anchor.z))

local motors = {}
for name, model in pairs(fighters) do
	motors[name] = {}
	for _, n in ipairs(Engine.JOINTS) do motors[name][n] = rigDefs[name][n].motor end
end
local clothB, clothP = Cloth.new(fighters.Blue), Cloth.new(fighters.Purple)

---------------------------------------------------------------- state
local state = { t = 0, playing = true, speed = 1, vfx = false, pass = 1, inspect = 0, hold = 0, marker = "start", lastT = 0 }
local PASSES_OFF_FIRST = true
local results = { footErr = 0, footErrT = 0, minFootY = 1e9, passDone = false }
local startSnapshot = nil

---------------------------------------------------------------- HUD
local gui = Instance.new("ScreenGui")
gui.Name = "ShowcaseHUD"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
local hud = Instance.new("TextLabel")
hud.BackgroundColor3 = Color3.fromRGB(10, 10, 18); hud.BackgroundTransparency = 0.35
hud.Position = UDim2.new(0, 12, 1, -118); hud.Size = UDim2.new(0, 560, 0, 106)
hud.TextXAlignment = Enum.TextXAlignment.Left; hud.TextYAlignment = Enum.TextYAlignment.Top
hud.Font = Enum.Font.Code; hud.TextSize = 15; hud.TextColor3 = Color3.fromRGB(235, 235, 255)
hud.RichText = false
hud.Parent = gui

local function hudText()
	local mode = state.inspect > 0 and ("INSPECT " .. (state.inspect == 1 and "A side" or "B top")) or (state.playing and "PLAY" or "PAUSED")
	hud.Text = string.format(" %s | pass %d | VFX %s | speed %.2fx | t=%.2f / %.1f\n marker: %s\n %s\n R replay  V vfx  B slow-mo  Space pause  , . step  C contact check",
		mode, state.pass, state.vfx and "ON" or "OFF", state.speed, state.t, Data.duration, state.marker, results.summary or "checks run at the end of pass 1")
end

---------------------------------------------------------------- pose application
local function applyPose(t)
	local snapshot = {}
	for name, model in pairs(fighters) do
		local P = Engine.eval(R, tracks[name], t)
		local out = Engine.solve(R, P)
		model.HumanoidRootPart.CFrame = out.hrp
		for jn, rt in pairs(out.rot) do motors[name][jn].Transform = rt end
		snapshot[name] = { P = P, out = out }
	end
	return snapshot
end

---------------------------------------------------------------- VFX
local function burst(pos, color, size, axis)
	local anchor = Instance.new("Part")
	anchor.Anchored = true; anchor.CanCollide = false; anchor.Transparency = 1; anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = pos; anchor.Parent = Workspace
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(color); pe.LightEmission = 1; pe.Rate = 0
	pe.Lifetime = NumberRange.new(0.12, 0.26)
	pe.Speed = NumberRange.new(8 * size, 18 * size)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Size = NumberSequence.new(0.55 * size, 0)
	pe.Transparency = NumberSequence.new(0, 1)
	pe.Parent = anchor
	pe:Emit(math.floor(22 * size))
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder; ring.Anchored = true; ring.CanCollide = false; ring.CastShadow = false
	ring.Material = Enum.Material.Neon; ring.Color = color; ring.Transparency = 0.1
	ring.Size = Vector3.new(0.12, 0.5, 0.5)
	ring.CFrame = CFrame.lookAt(pos, pos + axis) * CFrame.Angles(0, math.rad(90), 0)
	ring.Parent = Workspace
	TweenService:Create(ring, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.12, 3.0 * size, 3.0 * size), Transparency = 1 }):Play()
	Debris:AddItem(anchor, 0.5); Debris:AddItem(ring, 0.3)
end

local function updateTrails()
	for _, w in ipairs(Data.vfx.trails) do
		local p = fighters[w.fighter]:FindFirstChild(w.part)
		local tr = p and p:FindFirstChild("ShowcaseTrail")
		if tr then tr.Enabled = state.vfx and state.t >= w.from and state.t <= w.to end
	end
end

local firedThisPass = {}
local function fireMarkers(prevT, t)
	for _, mk in ipairs(Data.markers) do
		if mk.t > prevT and mk.t <= t then
			state.marker = mk.name
			if state.vfx then
				for bi, b in ipairs(Data.vfx.bursts) do
					if b.marker == mk.name then
						local c = info[b.contact]
						burst(c.C, b.color, b.size, c.n or Vector3.new(1, 0, 0))
						Style.impact(c.C, b.color, b.size >= 1 and 1.5 or 0.7)
					end
				end
			end
		end
	end
end

---------------------------------------------------------------- camera
local cam = Workspace.CurrentCamera
local camCF, camFov = nil, 36
local function resolveShot(shot)
	local pos, look
	if shot.rel then
		local base = info[1].C
		pos, look = base + shot.off, base
	else
		pos, look = shot.pos, shot.look
	end
	return CFrame.lookAt(pos, look) * CFrame.Angles(0, 0, math.rad(shot.roll or 0)), shot.fov
end
local function cameraTarget(t)
	if state.inspect == 1 then return resolveShot(Data.verifyCameras.A) end
	if state.inspect == 2 then return resolveShot(Data.verifyCameras.B) end
	local shot = Data.cameras[1]
	for _, c in ipairs(Data.cameras) do if c.t <= t then shot = c end end
	return resolveShot(shot)
end

---------------------------------------------------------------- measurements (read the real parts, not the solver)
local function actualGap(snap)
	local blue, purple = fighters.Blue, fighters.Purple
	local c = Data.contacts[1]
	local aSide = c.hand == "R" and "Right" or "Left"
	local dSide = c.arm == "R" and "Right" or "Left"
	local hand = blue[aSide .. "Hand"].Position
	local ua, la = purple[dSide .. "UpperArm"], purple[dSide .. "LowerArm"]
	local E = (ua.CFrame * motors.Purple[dSide .. "Elbow"].C0).Position
	local W = (la.CFrame * motors.Purple[dSide .. "Wrist"].C0).Position
	local dist, nearest = Engine.segmentDistance(hand, E, W)
	return dist - c.guardRadius - c.fist, hand, nearest, c
end

local function reactionCheck()
	-- both fighters must be moving differently on the contact frame: compare poses just before and after
	local d0, d1 = 0.04, 0.04
	local result = {}
	for name in pairs(fighters) do
		local a = Engine.eval(R, tracks[name], Data.contacts[1].t - d0)
		local b = Engine.eval(R, tracks[name], Data.contacts[1].t)
		local c = Engine.eval(R, tracks[name], Data.contacts[1].t + d1)
		local v1 = math.abs(b.rx - a.rx) + math.abs(b.lean - a.lean) / 20 + math.abs(b.twist - a.twist) / 20
		local v2 = math.abs(c.rx - b.rx) + math.abs(c.lean - b.lean) / 20 + math.abs(c.twist - b.twist) / 20
		result[name] = string.format("%s before %.3f -> after %.3f", name, v1, v2)
	end
	return result
end

local function inspectContact()
	-- freeze at the clash and measure from both verification cameras
	state.playing = false; state.t = Data.contacts[1].t; state.inspect = 1; state.vfx = false
	applyPose(state.t)
	RunService.RenderStepped:Wait(); RunService.RenderStepped:Wait()
	local gap, hand, nearest, c = actualGap()
	print(string.format("[SHOWCASE CHECK] contact gap (fist surface to forearm surface) = %.3f studs (0 = touching, negative = overlap)", gap))
	for _, which in ipairs({ "A", "B" }) do
		state.inspect = (which == "A") and 1 or 2
		cam.CameraType = Enum.CameraType.Scriptable
		local cf, fov = cameraTarget(state.t)
		cam.CFrame = cf; cam.FieldOfView = fov; camCF = cf; camFov = fov
		RunService.RenderStepped:Wait(); RunService.RenderStepped:Wait()
		local surface = nearest + (hand - nearest).Unit * c.guardRadius
		local pHand = cam:WorldToViewportPoint(hand)
		local pSurf = cam:WorldToViewportPoint(surface)
		local pEdge = cam:WorldToViewportPoint(hand + cam.CFrame.RightVector * c.fist)
		local px = Vector2.new(pHand.X - pSurf.X, pHand.Y - pSurf.Y).Magnitude
		local rpx = Vector2.new(pHand.X - pEdge.X, pHand.Y - pEdge.Y).Magnitude
		print(string.format("[SHOWCASE CHECK] camera %s: hand centre to forearm surface = %.1f px, fist radius = %.1f px -> %s",
			which, px, rpx, math.abs(px - rpx) <= math.max(4, rpx * 0.25) and "fist meets forearm" or "CHECK: visible gap/overlap"))
	end
	for line, text in pairs(reactionCheck()) do print("[SHOWCASE CHECK] reaction on contact frame, " .. text) end
	state.inspect = 1
end

---------------------------------------------------------------- per-frame loop
local function passStartSnapshot(snap)
	startSnapshot = {}
	for name, s in pairs(snap) do
		startSnapshot[name] = { hrp = s.out.hrp, hands = { s.P.hands.R.t, s.P.hands.L.t }, feet = { s.P.feet.R.g, s.P.feet.L.g } }
	end
end

local function endOfPassChecks(snap)
	local errPos, errHand = 0, 0
	if startSnapshot then
		for name, s in pairs(snap) do
			local st = startSnapshot[name]
			errPos = math.max(errPos, (s.out.hrp.Position - st.hrp.Position).Magnitude)
			errHand = math.max(errHand, (s.P.hands.R.t - st.hands[1]).Magnitude, (s.P.hands.L.t - st.hands[2]).Magnitude)
		end
	end
	results.summary = string.format("checks: clash gap %.3f | counter miss %.3f | foot slide max %.3f (t=%.2f) | lowest foot %.3f | return-to-guard %.3f / %.3f",
		results.contactGap or 0, results.counterMiss or 0, results.footErr, results.footErrT, results.minFootY, errPos, errHand)
	print("[SHOWCASE CHECK] " .. results.summary)
	print("[SHOWCASE CHECK] foot error = distance between each planted foot's toe and its locked plant point (0 = no sliding)")
end

local toeHistory = { Blue = { R = {}, L = {} }, Purple = { R = {}, L = {} } }
local function measureFeet(snap, t)
	for name, sn in pairs(snap) do
		local model = fighters[name]
		for _, side in ipairs({ "R", "L" }) do
			local foot = model[(side == "R" and "Right" or "Left") .. "Foot"]
			local g = sn.P.feet[side].g
			local toe = foot.CFrame:PointToWorldSpace(Vector3.new(0, -R.footY / 2, -R.footZ / 2))
			local heel = foot.CFrame:PointToWorldSpace(Vector3.new(0, -R.footY / 2, R.footZ / 2))
			results.minFootY = math.min(results.minFootY, toe.Y, heel.Y)
			local hist = toeHistory[name][side]
			if g.Y < 0.001 then
				local yaw = math.rad(sn.P.feet[side].yaw)
				local fwd = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
				table.insert(hist, 1, g + fwd * (R.footZ / 2))
				if #hist > 3 then table.remove(hist) end
				-- the parts lag the pose by a frame or two; planted points are constant, so take the closest of the last 3
				local best = math.huge
				for _, ex in ipairs(hist) do best = math.min(best, (toe - ex).Magnitude) end
				if #hist >= 3 and best > results.footErr then results.footErr = best; results.footErrT = t end
			else
				table.clear(hist)
			end
		end
	end
end

local lastPassTime = os.clock()
local pendingMeasure = nil
local function cinematicOn() return stage:GetAttribute("Mode") == "Cinematic" end
RunService:BindToRenderStep("ShowcasePose", Enum.RenderPriority.Camera.Value - 1, function(dt)
	hud.Visible = cinematicOn()
	if not cinematicOn() then return end
	local dtSim = 0
	if state.playing and state.inspect == 0 then
		if state.hold > 0 then
			state.hold = state.hold - dt
		else
			dtSim = math.min(dt, 1 / 20) * state.speed    -- clamp so a hitch can't skip the animation
			local prev = state.t
			state.t = state.t + dtSim
			if state.t >= Data.duration then
				state.t = Data.duration
			end
			fireMarkers(prev, state.t)
		end
	end
	-- the parts only show a pose one frame after it is applied, so measure the previous frame's pose against them
	if pendingMeasure then measureFeet(pendingMeasure.snap, pendingMeasure.t); pendingMeasure = nil end
	Style.setEnabled(state.vfx)
	local snap = applyPose(state.t)
	if state.t == 0 and not startSnapshot then passStartSnapshot(snap) end
	clothB:update(snap.Blue.out.cf.UpperTorso, dtSim)
	clothP:update(snap.Purple.out.cf.LowerTorso, dtSim)
	updateTrails()
	if state.playing and state.inspect == 0 and state.pass == 1 then pendingMeasure = { snap = snap, t = state.t } end
	if state.t >= Data.duration and state.hold <= 0 and state.playing and state.inspect == 0 then
		if state.pass == 1 and not results.passDone then
			results.passDone = true
			endOfPassChecks(snap)
		end
		-- next pass: pass 1 is VFX off, every later pass VFX on
		if state.pass == 1 then state.vfx = true end
		state.pass = state.pass + 1
		state.t = 0; state.hold = 0.8; state.marker = "start"
		clothB:reset(); clothP:reset()
	end
	hudText()
end)

RunService:BindToRenderStep("ShowcaseCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if not cinematicOn() then return end
	cam = Workspace.CurrentCamera
	if not cam then return end
	cam.CameraType = Enum.CameraType.Scriptable
	local cf, fov = cameraTarget(state.t)
	if not camCF then camCF, camFov = cf, fov end
	local a = 1 - math.exp(-dt * 9)
	camCF = camCF:Lerp(cf, a)
	camFov = camFov + (fov - camFov) * a
	cam.CFrame = camCF
	cam.FieldOfView = camFov
end)

---------------------------------------------------------------- controls
local function restart()
	state.t = 0; state.hold = 0.3; state.inspect = 0; state.playing = true; state.marker = "start"
	clothB:reset(); clothP:reset()
end
UserInputService.InputBegan:Connect(function(input, gp)
	if gp or not cinematicOn() then return end
	local k = input.KeyCode
	if k == Enum.KeyCode.R then
		restart()
	elseif k == Enum.KeyCode.V then
		state.vfx = not state.vfx
	elseif k == Enum.KeyCode.B then
		state.speed = (state.speed == 1) and 0.25 or 1
	elseif k == Enum.KeyCode.Space then
		state.playing = not state.playing
		if state.inspect > 0 then state.inspect = 0; state.playing = true end
	elseif k == Enum.KeyCode.Comma and not state.playing then
		state.t = math.max(0, state.t - 1 / 30)
	elseif k == Enum.KeyCode.Period and not state.playing then
		state.t = math.min(Data.duration, state.t + 1 / 30)
	elseif k == Enum.KeyCode.C then
		if state.inspect == 0 then
			task.spawn(inspectContact)
		elseif state.inspect == 1 then
			state.inspect = 2
		else
			state.inspect = 0; state.playing = true
		end
	end
end)

task.spawn(function()
	task.wait(0.6)
	local keep = state.playing
	state.playing = false
	state.t = Data.contacts[1].t
	RunService.RenderStepped:Wait(); RunService.RenderStepped:Wait(); RunService.RenderStepped:Wait()
	local gap = actualGap()
	results.contactGap = gap
	print(string.format("[SHOWCASE CHECK] clash: fist-to-forearm gap = %.3f studs (0 = touching, negative = overlap)", gap))
	state.t = Data.contacts[2].t
	RunService.RenderStepped:Wait(); RunService.RenderStepped:Wait(); RunService.RenderStepped:Wait()
	local c2 = Data.contacts[2]
	local hand2 = fighters[c2.attacker][(c2.hand == "R" and "Right" or "Left") .. "Hand"].Position
	results.counterMiss = (hand2 - info[2].Hc).Magnitude
	print(string.format("[SHOWCASE CHECK] counter: fist-to-target miss = %.3f studs", results.counterMiss))
	state.t = 0; state.hold = 0.4; state.playing = keep
end)

print("[SHOWCASE] Director running. Pass 1 plays with VFX OFF, pass 2 with VFX ON. Keys: R V B Space , . C")
stage:GetAttributeChangedSignal("Mode"):Connect(function()
	if cinematicOn() then restart(); state.pass = 1; state.vfx = false end
end)

-- buttons from the BGClient panel (they set stage attribute CinCmd = "<command>:<time>")
stage:GetAttributeChangedSignal("CinCmd"):Connect(function()
	if not cinematicOn() then return end
	local cmd = tostring(stage:GetAttribute("CinCmd")):match("^(%a+)")
	if cmd == "replay" then restart()
	elseif cmd == "slow" then state.speed = (state.speed == 1) and 0.25 or 1
	elseif cmd == "vfx" then state.vfx = not state.vfx
	elseif cmd == "inspect" then
		if state.inspect == 0 then task.spawn(inspectContact)
		elseif state.inspect == 1 then state.inspect = 2
		else state.inspect = 0; state.playing = true end
	end
end)
]====])
print("[BG] installed. Press Test > Play. It opens in the cinematic replay; press Tab or the Playable button to fight.")
