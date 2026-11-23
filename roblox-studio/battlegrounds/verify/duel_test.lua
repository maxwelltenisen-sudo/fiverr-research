local function readfile(p) local f = assert(io.open(p)); local s = f:read("a"); f:close(); return s end
dofile("shim.lua")
local Engine = load(readfile("../BGEngine.lua"))()
local D = load(readfile("../BGDuel.lua"))()
local R = Engine.newRig(dofile("rig.lua"), { footY = 0.3, footZ = 1.0 })
local tracks, info = Engine.bake(R, D.engineData())
print(string.format("duel: %d frames @ %d fps = %.1f s total (duel %.1f s + epilogue %.1f s); keys: Gojo %d, Toji %d", D.frames, D.fps, D.frames / D.fps, D.duelFrames / D.fps, (D.frames - D.duelFrames) / D.fps, #tracks.Blue.keys, #tracks.Purple.keys))
local function at(frame, who) local P = Engine.eval(R, tracks[who], frame / 30) return P, Engine.solve(R, P) end
-- contacts
local c1 = info[1]
local P, O = at(906, "Purple")
local _, Og = at(906, "Blue")
local head = Og.cf.Head.Position
print(string.format("INFINITY STOP f906: fist centre to Gojo's head centre = %.2f; target %.2f (gap %.2f + fist %.2f); Toji hand miss %.3f", (O.piv.RightWrist - head).Magnitude, 0.8, 0.5, 0.3, O.miss.RightHand))
local P2, O2 = at(2716, "Purple")
local _, Og2 = at(2716, "Blue")
print(string.format("SPEAR f2716: Toji hand miss %.3f; hand to Gojo upper torso = %.2f", O2.miss.RightHand, (P2.hands.R.t - Og2.cf.UpperTorso.Position).Magnitude))
-- per chapter: reach misses, penetration, floor
for _, ch in ipairs(D.chapters) do
	local maxMiss, missAt, minToe, toeAt, pen, rotMax, rotAt = 0, "", 9, "", 0, 0, ""
	local prev = {}
	for fr = ch.f0, ch.f1 - 1, 1 do
		local O = {}
		for _, who in ipairs({ "Blue", "Purple" }) do
			local P, Ow = at(fr, who)
			O[who] = Ow
			for j, m in pairs(Ow.miss) do if m > maxMiss then maxMiss, missAt = m, who .. " " .. j .. " f" .. fr end end
			local gy = P.gy or 0
			for _, side in ipairs({ "Right", "Left" }) do
				local ty = Ow.toe[side].Y - gy
				if ty < minToe then minToe, toeAt = ty, who .. " f" .. fr end
			end
			if prev[who] then
				for j, rt in pairs(Ow.rot) do
					local m = prev[who].rot[j]:Inverse() * rt
					local c = math.max(-1, math.min(1, (m.r[1][1] + m.r[2][2] + m.r[3][3] - 1) / 2))
					local a = math.deg(math.acos(c))
					if a > rotMax then rotMax, rotAt = a, who .. " " .. j .. " f" .. fr end
				end
			end
			prev[who] = Ow
		end
		if ch.id < 9 and not (fr >= 906 and fr <= 1000) then
			for _, who in ipairs({ "Blue", "Purple" }) do
				local other = who == "Blue" and "Purple" or "Blue"
				local a, b = O[other].cf.LowerTorso.Position, O[other].cf.Head.Position
				for _, j in ipairs({ "RightElbow", "LeftElbow", "RightWrist", "LeftWrist" }) do
					if Engine.segmentDistance(O[who].piv[j], a, b) < 0.55 and not (fr >= 2714 and fr <= 2724) then pen = pen + 1 end
				end
			end
		end
	end
	print(string.format("ch%d %-28s reach miss %.2f (%s) | lowest toe above ground %.3f (%s) | limb-in-body frames %d | max joint step %.0f deg (%s)", ch.id, ch.name:sub(1, 28), maxMiss, missAt, minToe, toeAt, pen, rotMax, rotAt))
end
