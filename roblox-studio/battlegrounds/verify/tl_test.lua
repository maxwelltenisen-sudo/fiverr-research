local function readfile(p) local f = assert(io.open(p)); local s = f:read("a"); f:close(); return s end
dofile("shim.lua")
local Engine = load(readfile("../BGEngine.lua"))()
local T = load(readfile("../BGTimeline.lua"))()
local R = Engine.newRig(dofile("rig.lua"), { footY = 0.3, footZ = 1.0 })
local tracks, info = Engine.bake(R, T.engineData())
print(string.format("Kael anchor x=%.2f z=%.2f | Ren anchor x=%.2f", tracks.Blue.anchor.x, tracks.Blue.anchor.z, tracks.Purple.anchor.x))
local function at(frame, who)
	local P = Engine.eval(R, tracks[who], frame / 30)
	return P, Engine.solve(R, P)
end
local function body(frame, who) local P = at(frame, who) return P.rx, P.rz end
for _, fr in ipairs({ 0, 6, 14, 22, 34, 44, 56, 70, 91, 104, 118, 128, 142, 150, 179 }) do
	local bx = body(fr, "Blue"); local rx = body(fr, "Purple")
	print(string.format("f%3d Kael x=%6.2f  Ren x=%6.2f  gap=%5.2f", fr, bx, rx, rx - bx))
end
-- stopped fist
local c2, c3, c1 = info[2], info[3], info[1]
local Pk, Ok = at(34, "Blue")
print(string.format("STOP: hover plane x=%.2f palm x=%.2f; fist centre x=%.2f -> strip between fist surface and palm = %.2f (hand miss %.3f)",
	c2.plane.X, c2.C.X, c2.Hc.X, c2.C.X - (c2.Hc.X + 0.3), Ok.miss.RightHand))
local P3, O3 = at(44, "Blue")
print(string.format("BRACER f44: hand centre x=%.2f plane x=%.2f (offset %.2f); hand miss %.3f", c3.Hc.X, c2.plane.X, c2.plane.X - c3.Hc.X, O3.miss.RightHand))
local P1, O1 = at(56, "Blue")
local _, Op = at(56, "Purple")
local E, W = Op.piv.LeftElbow, Op.piv.LeftWrist
local d = Engine.segmentDistance(O1.piv.RightWrist + (P1.hands.R.t - O1.piv.RightWrist), E, W)
print(string.format("CLASH f56: fist-to-forearm gap = %.3f (hand miss %.3f); Kael body x=%.2f", d - 0.52 - 0.3, O1.miss.RightHand, P1.rx))
-- reach / flips / floor over the whole timeline
local worst, prev = {}, {}
local minFoot, maxMiss, missAt, minFootAt = 9, 0, 0, ""
for who, _ in pairs({ Blue = 1, Purple = 1 }) do
	local pr
	for fr = 0, 179, 0.5 do
		local P, O = at(fr, who)
		for j, m in pairs(O.miss) do if m > maxMiss then maxMiss, missAt = m, who .. " " .. j .. " f" .. fr end end
		local ty = math.min(O.toe.Right.Y, O.toe.Left.Y); if ty < minFoot then minFoot, minFootAt = ty, who .. " f" .. fr end
		if pr then
			for j, rt in pairs(O.rot) do
				local m = pr.rot[j]:Inverse() * rt
				local c = math.max(-1, math.min(1, (m.r[1][1] + m.r[2][2] + m.r[3][3] - 1) / 2))
				local a = math.deg(math.acos(c))
				if not worst[who] or a > worst[who][1] then worst[who] = { a, j, fr } end
			end
		end
		pr = O
	end
end
print(string.format("max IK reach miss over the timeline: %.3f (%s) | lowest toe y %.3f (%s)", maxMiss, missAt, minFoot, minFootAt))
for who, w in pairs(worst) do print(string.format("%s biggest joint step per half-frame: %.1f deg %s @f%.1f", who, w[1], w[2], w[3])) end
-- Ren: head direction at the end (should face -X but look toward +X? print forward vector)
local _, Oh = at(179, "Purple")
local fwd = Oh.cf.Head:VectorToWorldSpace(Vector3.new(0, 0, -1))
print(string.format("Ren head forward at f179 = (%.2f, %.2f, %.2f)", fwd.X, fwd.Y, fwd.Z))

-- limbs passing through bodies: elbows / wrists vs the other fighter's torso axis and their own
local function seg(O) return O.piv.Waist or (O.cf.LowerTorso.Position), O.cf.Head.Position end
local bad = {}
for fr = 0, 179, 1 do
	local P = {}
	for _, who in ipairs({ "Blue", "Purple" }) do
		local _, O = at(fr, who)
		P[who] = O
	end
	for _, who in ipairs({ "Blue", "Purple" }) do
		local other = who == "Blue" and "Purple" or "Blue"
		local a, b = P[other].cf.LowerTorso.Position, P[other].cf.Head.Position
		for _, j in ipairs({ "RightElbow", "LeftElbow", "RightWrist", "LeftWrist" }) do
			local d = Engine.segmentDistance(P[who].piv[j], a, b)
			local limit = 0.62
			local contactFrames = (fr >= 55 and fr <= 58)
			if d < limit and not contactFrames then bad[#bad + 1] = string.format("%s %s inside %s torso (%.2f) f%d", who, j, other, d, fr) end
		end
		-- own torso
		local la, lb = P[who].cf.LowerTorso.Position, P[who].cf.Head.Position
		for _, j in ipairs({ "RightWrist", "LeftWrist" }) do
			local d = Engine.segmentDistance(P[who].piv[j], la, lb)
			if d < 0.45 then bad[#bad + 1] = string.format("%s %s inside own torso (%.2f) f%d", who, j, d, fr) end
		end
	end
end
print("limb/body penetration warnings: " .. #bad)
for i = 1, math.min(#bad, 14) do print("   " .. bad[i]) end
