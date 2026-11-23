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
			local palm = P.hands[c.dhand].t
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
