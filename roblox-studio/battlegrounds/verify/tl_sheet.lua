-- dumps side-view skeleton points for key frames as JSON-ish lines: frame who joint x y
local function readfile(p) local f = assert(io.open(p)); local s = f:read("a"); f:close(); return s end
dofile("shim.lua")
local Engine = load(readfile("../BGEngine.lua"))()
local T = load(readfile("../BGTimeline.lua"))()
local R = Engine.newRig(dofile("rig.lua"), { footY = 0.3, footZ = 1.0 })
local tracks = Engine.bake(R, T.engineData())
local out = {}
for _, fr in ipairs({ 0, 6, 12, 22, 34, 44, 49, 56, 61, 84, 93, 102, 118, 133, 140, 150, 179 }) do
	for _, who in ipairs({ "Blue", "Purple" }) do
		local P = Engine.eval(R, tracks[who], fr / 30)
		local O = Engine.solve(R, P)
		local pts = {}
		for _, j in ipairs({ "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow", "LeftWrist", "RightHip", "RightKnee", "RightAnkle", "LeftHip", "LeftKnee", "LeftAnkle" }) do
			local p = O.piv[j]; pts[#pts + 1] = string.format("%s:%.3f,%.3f,%.3f", j, p.X, p.Y, p.Z)
		end
		local h = O.cf.Head.Position
		pts[#pts + 1] = string.format("Head:%.3f,%.3f,%.3f", h.X, h.Y, h.Z)
		local lt = O.cf.LowerTorso.Position
		pts[#pts + 1] = string.format("Pelvis:%.3f,%.3f,%.3f", lt.X, lt.Y, lt.Z)
		out[#out + 1] = fr .. " " .. who .. " " .. table.concat(pts, " ")
	end
end
return table.concat(out, "\n")
