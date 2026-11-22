local function readfile(p) local f = assert(io.open(p)); local s = f:read("a"); f:close(); return s end
dofile("shim.lua")
local Engine = load(readfile("../BGEngine.lua"))()
local Clips = load(readfile("../BGClips.lua"))()
local R = Engine.newRig(dofile("rig.lua"), { footY = 0.3, footZ = 1.0 })
local char, name, j = CHAR, NAME, JOINT
local tracks = Engine.bake(R, Clips.engineData(char))
local function ang(a, b) local m = a:Inverse() * b local tr = m.r[1][1] + m.r[2][2] + m.r[3][3] return math.deg(math.acos(math.max(-1, math.min(1, (tr - 1) / 2)))) end
local prev
local t = T0
while t <= T1 do
	local P = Engine.eval(R, tracks[name], t)
	local out = Engine.solve(R, P)
	local S = out.piv.LeftShoulder
	local h = P.hands.L.t
	local d = (h - S).Magnitude
	if prev then io.write(string.format("t=%.3f d(shoulder-hand)=%.2f dAng=%.1f pole=(%.2f %.2f %.2f)\n", t, d, ang(prev.rot[j], out.rot[j]), P.hands.L.pole.X, P.hands.L.pole.Y, P.hands.L.pole.Z)) end
	prev = out
	t = t + 1/60
end
