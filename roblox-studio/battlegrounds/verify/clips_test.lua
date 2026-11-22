local function readfile(p) local f = assert(io.open(p)); local s = f:read("a"); f:close(); return s end
dofile("shim.lua")
local Engine = load(readfile("../BGEngine.lua"))()
local Clips = load(readfile("../BGClips.lua"))()
local R = Engine.newRig(dofile("rig.lua"), { footY = 0.3, footZ = 1.0 })
local function ang(a, b)
	local m = a:Inverse() * b
	local tr = m.r[1][1] + m.r[2][2] + m.r[3][3]
	return math.deg(math.acos(math.max(-1, math.min(1, (tr - 1) / 2))))
end
local bad = 0
for _, char in ipairs({ "Kael", "Ren" }) do
	local tracks = Engine.bake(R, Clips.engineData(char))
	local names = {}
	for n in pairs(Clips[char]) do if n ~= "bases" then names[#names + 1] = n end end
	table.sort(names)
	for _, n in ipairs(names) do
		local c = Clips[char][n]
		local minD, minDT = 9, 0; local worstJ = ""; local prev, worstRot, worstT, maxMiss, missT, missJ = nil, 0, 0, 0, 0, ""
		local t = 0
		while t <= c.dur + 1e-6 do
			local P0 = Engine.eval(R, tracks[n], t)
			local out = Engine.solve(R, P0)
			for _, sd in ipairs({ "Left", "Right" }) do local dd = (P0.hands[sd:sub(1,1)].t - out.piv[sd .. "Shoulder"]).Magnitude if dd < minD then minD, minDT = dd, t end end
			for j, m in pairs(out.miss) do if m > maxMiss then maxMiss, missT, missJ = m, t, j end end
			if prev then
				for j, rt in pairs(out.rot) do
					local a = ang(prev.rot[j], rt)
					if a > worstRot then worstRot, worstT, worstJ = a, t, j end
				end
			end
			prev = out
			t = t + 1 / 60
		end
		-- loop seam
		local seam = 0
		if c.loop then
			local a = Engine.solve(R, Engine.eval(R, tracks[n], 0))
			local b = Engine.solve(R, Engine.eval(R, tracks[n], c.dur))
			for j, rt in pairs(a.rot) do seam = math.max(seam, ang(rt, b.rot[j])) end
		end
		local flag = (maxMiss > 0.12 or worstRot > 80 or seam > 2) and "  <== CHECK" or ""
		if flag ~= "" then bad = bad + 1 end
		print(string.format("%-5s %-14s dur %.2f  maxReachMiss %.2f (%s t=%.2f)  maxJoint %s %.1f @%.2f  seam %.1f  minHandShoulder %.2f@%.2f%s",
			char, n, c.dur, maxMiss, missJ, missT, worstJ, worstRot, worstT, seam, minD, minDT, flag))
	end
end
print("clips needing attention: " .. bad)
