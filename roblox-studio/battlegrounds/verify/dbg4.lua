local function readfile(p) local f = assert(io.open(p)); local s = f:read("a"); f:close(); return s end
dofile("shim.lua")
local Engine = load(readfile("../BGEngine.lua"))()
local D = load(readfile("../BGDuel.lua"))()
local R = Engine.newRig(dofile("rig.lua"), { footY = 0.3, footZ = 1.0 })
local tracks = Engine.bake(R, D.engineData())
local out = {}
for fr = 600, 6450 do
	if (fr >= 1000 and fr < 1500) or (fr >= 5250 and fr < 6450) then
		local O = {}
		for _, w in ipairs({ "Blue", "Purple" }) do O[w] = Engine.solve(R, Engine.eval(R, tracks[w], fr / 30)) end
		for _, who in ipairs({ "Blue", "Purple" }) do
			local other = who == "Blue" and "Purple" or "Blue"
			for _, j in ipairs({ "RightElbow", "LeftElbow", "RightWrist", "LeftWrist" }) do
				if Engine.segmentDistance(O[who].piv[j], O[other].cf.LowerTorso.Position, O[other].cf.Head.Position) < 0.55 then out[#out + 1] = who .. " " .. j .. " f" .. fr end
			end
		end
	end
end
print(table.concat(out, "; "))
