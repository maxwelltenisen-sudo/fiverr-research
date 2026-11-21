local function readfile(p) local f = assert(io.open(p)); local s = f:read("a"); f:close(); return s end
dofile("shim.lua")
local ROOT = "../"
local Engine = load(readfile(ROOT.."ShowcaseEngine.lua"))()
local Data = load(readfile(ROOT.."ShowcaseData.lua"))()
local R = Engine.newRig(dofile("rig.lua"), { footY = 0.3, footZ = 1.0 })
local tracks = Engine.bake(R, Data)
for _, nm in ipairs({"Blue","Purple"}) do
	local worst = { Right = {9, 0}, Left = {9, 0} }
	local t = 0
	while t <= Data.duration do
		local P = Engine.eval(R, tracks[nm], t)
		local out = Engine.solve(R, P)
		for _, side in ipairs({"Right","Left"}) do
			local k = side:sub(1,1)
			local d = (P.hands[k].t - out.piv[side.."Shoulder"]).Magnitude
			if d < worst[side][1] then worst[side] = {d, t} end
		end
		t = t + 0.02
	end
	print(nm, string.format("min shoulder->hand: Right %.2f at %.2fs | Left %.2f at %.2fs", worst.Right[1], worst.Right[2], worst.Left[1], worst.Left[2]))
end
-- per-key listing of the distances
for _, nm in ipairs({"Blue","Purple"}) do
	for _, k in ipairs(tracks[nm].keys) do
		local P = Engine.eval(R, tracks[nm], k.t)
		local out = Engine.solve(R, P)
		local dR = (P.hands.R.t - out.piv.RightShoulder).Magnitude
		local dL = (P.hands.L.t - out.piv.LeftShoulder).Magnitude
		if dR < 1.0 or dL < 1.0 then print(string.format("  %s t=%.2f %-26s R=%.2f L=%.2f", nm, k.t, k.name, dR, dL)) end
	end
end
