local function readfile(p) local f = assert(io.open(p)); local s = f:read("a"); f:close(); return s end
local Config = load(readfile("../BGConfig.lua"))()
local Clips = load(readfile("../BGClips.lua"))()
local Core = load(readfile("../BGCore.lua"))()
local w = Core.new(Config, Clips, { rng = function() return 0.3 end })
w.f.Blue.x, w.f.Purple.x = -1.5, 1.5
for i = 1, 4 do
	print("press", i, string.format("t=%.2f", w.t), w.f.Blue.act and w.f.Blue.act.clip, w.f.Blue.state)
	w:input("Blue", "m1")
	for _ = 1, 12 do w:update(1/60) end
end
for _ = 1, 60 do w:update(1/60) end
for _, e in ipairs(w.events) do if e.type == "hit" or e.type == "act" then print(string.format("%.2f", e.t), e.type, e.hit or e.clip) end end
print(w.f.Purple.state, w.f.Purple.hp, w.f.Blue.x, w.f.Purple.x)
