local function readfile(p) local f = assert(io.open(p)); local s = f:read("a"); f:close(); return s end
dofile("shim.lua")
local ROOT = "../"
local Engine = load(readfile(ROOT.."ShowcaseEngine.lua"))()
local Data = load(readfile(ROOT.."ShowcaseData.lua"))()
local R = Engine.newRig(dofile("rig.lua"), { footY = 0.3, footZ = 1.0 })
local tracks = Engine.bake(R, Data)
local function ang(a, b)
	local m = a:Inverse() * b
	local tr = m.r[1][1] + m.r[2][2] + m.r[3][3]
	local c = math.max(-1, math.min(1, (tr - 1) / 2))
	return math.deg(math.acos(c))
end
local dt = 1/60
for _, nm in ipairs({"Blue","Purple"}) do
	local prev, worst = nil, {}
	local maxRoot, rootT = 0, 0
	local t = 0
	while t <= Data.duration do
		local out = Engine.solve(R, Engine.eval(R, tracks[nm], t))
		if prev then
			for j, rt in pairs(out.rot) do
				local a = ang(prev.rot[j], rt)
				if not worst[j] or a > worst[j][1] then worst[j] = {a, t} end
			end
			local d = (out.hrp.Position - prev.hrp.Position).Magnitude
			if d > maxRoot then maxRoot, rootT = d, t end
		end
		prev = out
		t = t + dt
	end
	local names = {}
	for j in pairs(worst) do names[#names+1] = j end
	table.sort(names, function(a,b) return worst[a][1] > worst[b][1] end)
	io.write(nm, " biggest per-frame joint rotation (deg/frame @60fps): ")
	for i = 1, 5 do io.write(string.format("%s %.1f@%.2fs  ", names[i], worst[names[i]][1], worst[names[i]][2])) end
	print(string.format("\n   max root move per frame %.3f studs at t=%.2f", maxRoot, rootT))
end
