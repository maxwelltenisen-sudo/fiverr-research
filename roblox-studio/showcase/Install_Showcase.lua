-- ONE-PASTE INSTALLER for the Roblox combat showcase.
-- Paste this whole file into the Command Bar (View > Command Bar) in Roblox Studio and press Enter.
-- It creates 4 scripts in the right places and disables (does not delete) your older story scripts.
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
		if (c:IsA("Script") or c:IsA("LocalScript")) and not c.Name:find("Showcase") then
			c.Enabled = false
			print("disabled (re-enable in Properties if you want it back): " .. c:GetFullName())
		end
	end
end
put(RS, "ModuleScript", "ShowcaseEngine", [====[
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
put(RS, "ModuleScript", "ShowcaseData", [====[
-- ShowcaseData (ModuleScript, ReplicatedStorage): THE EDITABLE ANIMATION SOURCE.
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
		guardRadius = 0.53, fist = 0.3, reach = 0.52 },
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
put(SSS, "Script", "ShowcaseBuilder", [====[
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
	-- Current Roblox rigs ship AnimationConstraints (no Motor6Ds). The Director drives Motor6D.Transform,
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
]====])
put(SP, "LocalScript", "ShowcaseDirector", [====[
-- ShowcaseDirector (LocalScript, StarterPlayer > StarterPlayerScripts)
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

local Engine = require(ReplicatedStorage:WaitForChild("ShowcaseEngine"))
local Data = require(ReplicatedStorage:WaitForChild("ShowcaseData"))

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
		if d:IsA("Motor6D") and d.Part1 and d.Part1.Name == PART1[n] and d.Part0 and not d.Name:find("Scarf") then
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
			warn("ShowcaseDirector: joint for " .. n .. " not found on " .. model.Name .. ". Motor6Ds present: " .. table.concat(names, ", "))
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
local scarfJoints = {}
for i = 1, 3 do
	local m = fighters.Blue:FindFirstChild("ScarfJoint" .. i, true)
	if m then scarfJoints[i] = m end
end

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

---------------------------------------------------------------- scarf lag (Blue): trails the torso turn, settles in recovery
local scarfState = { yaw = { 0, 0, 0 }, pitch = { 0, 0, 0 }, prevPos = nil, prevYaw = 0 }
local function wrapAngle(a)
	while a > math.pi do a = a - 2 * math.pi end
	while a < -math.pi do a = a + 2 * math.pi end
	return a
end
local function updateScarf(out, dtSim)
	if #scarfJoints == 0 then return end
	local ut = out.cf.UpperTorso
	local fwd = ut:VectorToWorldSpace(Vector3.new(0, 0, -1))
	local yaw = math.atan2(-fwd.X, -fwd.Z)
	local pos = ut.Position
	if not scarfState.prevPos then scarfState.prevPos = pos; scarfState.prevYaw = yaw; for i = 1, 3 do scarfState.yaw[i] = yaw end end
	local vf = 0
	if dtSim > 1e-4 then vf = (pos - scarfState.prevPos):Dot(Vector3.new(fwd.X, 0, fwd.Z)) / dtSim end
	scarfState.prevPos = pos
	local rates = { 14, 9, 6 }
	for i = 1, #scarfJoints do
		if dtSim > 0 then
			local k = 1 - math.exp(-dtSim * rates[i])
			scarfState.yaw[i] = scarfState.yaw[i] + wrapAngle(yaw - scarfState.yaw[i]) * k
			local wantPitch = math.clamp(-vf * 3.2, -38, 38)
			scarfState.pitch[i] = scarfState.pitch[i] + (wantPitch - scarfState.pitch[i]) * k
		end
		local roll = math.clamp(math.deg(wrapAngle(yaw - scarfState.yaw[i])) * 0.9, -40, 40)
		scarfJoints[i].Transform = CFrame.Angles(math.rad(-7 + scarfState.pitch[i] * (0.6 + 0.2 * i) * 0.5), 0, math.rad(roll))
	end
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
RunService:BindToRenderStep("ShowcasePose", Enum.RenderPriority.Camera.Value - 1, function(dt)
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
	local snap = applyPose(state.t)
	if state.t == 0 and not startSnapshot then passStartSnapshot(snap) end
	updateScarf(snap.Blue.out, dtSim)
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
		scarfState.prevPos = nil
	end
	hudText()
end)

RunService:BindToRenderStep("ShowcaseCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
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
	scarfState.prevPos = nil
end
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
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
]====])
print("[SHOWCASE] installed. Press Test > Play. Pass 1 plays with VFX OFF, pass 2 with VFX ON.")
