local function readfile(p) local f = assert(io.open(p)); local s = f:read("a"); f:close(); return s end
dofile("shim.lua")
local ROOT = "../"
local Engine = load(readfile(ROOT.."ShowcaseEngine.lua"))()
local Data = load(readfile(ROOT.."ShowcaseData.lua"))()
local defs = dofile("rig.lua")
local R = Engine.newRig(defs, { footY = 0.3, footZ = 1.0 })
print(string.format("rig: legLen=%.2f armLen=%.2f armReach=%.2f hipStand=%.2f chestStand=%.2f", R.legLen, R.armLen, R.armReach, R.hipStand, R.chestStand))
local tracks, info = Engine.bake(R, Data)
local Bt, Pt = tracks.Blue, tracks.Purple
print(string.format("solved Blue anchor x=%.3f z=%.3f ; Purple anchor x=%.3f z=%.3f", Bt.anchor.x, Bt.anchor.z, Pt.anchor.x, Pt.anchor.z))
local c1 = info[1]
print(string.format("clash point C=(%.2f,%.2f,%.2f) fist target Hc=(%.2f,%.2f,%.2f)", c1.C.X,c1.C.Y,c1.C.Z,c1.Hc.X,c1.Hc.Y,c1.Hc.Z))

local function at(t)
	local pb = Engine.eval(R, Bt, t); local pp = Engine.eval(R, Pt, t)
	return pb, pp, Engine.solve(R, pb), Engine.solve(R, pp)
end

-- contact check at t=4.0
local pb, pp, ob, op = at(4.0)
local hand = ob.cf.RightHand.Position
local E, W = op.piv.LeftElbow, op.piv.LeftWrist
local dist = Engine.segmentDistance(hand, E, W)
print(string.format("CLASH: blue hand centre (%.3f,%.3f,%.3f) to purple forearm axis = %.3f ; gap = %.3f (radius .53 + fist .3 = 0.83) ; hand-target miss=%.3f", hand.X,hand.Y,hand.Z, dist, dist-0.53-0.3, ob.miss.RightHand))
local body = (ob.cf.UpperTorso.Position - op.cf.UpperTorso.Position).Magnitude
print(string.format("torso centre distance at clash = %.2f", body))
-- counter contact
local pb2, pp2, ob2, op2 = at(5.15)
local ch = info[2].Hc
local h2 = op2.cf.RightHand.Position
print(string.format("COUNTER: purple hand to blue chest target = %.3f ; hand miss %.3f ; blue UT dist=%.2f", (h2-ch).Magnitude, op2.miss.RightHand, (ob2.cf.UpperTorso.Position-op2.cf.UpperTorso.Position).Magnitude))

-- sweep for reach misses and self clearance
local worst = {}
local minSep, minSepT = 99, 0
local minHandSelf = 99
local function note(key, val, t) if not worst[key] or val > worst[key][1] then worst[key] = {val, t} end end
local t = 0
while t <= Data.duration + 1e-6 do
	local pb, pp, ob, op = at(t)
	for _, side in ipairs({"Right","Left"}) do
		note("Blue "..side.."Hand", ob.miss[side.."Hand"], t); note("Purple "..side.."Hand", op.miss[side.."Hand"], t)
		note("Blue "..side.."Foot", ob.miss[side.."Foot"], t); note("Purple "..side.."Foot", op.miss[side.."Foot"], t)
	end
	local sep = (ob.cf.UpperTorso.Position - op.cf.UpperTorso.Position).Magnitude
	if sep < minSep then minSep, minSepT = sep, t end
	for _, o in ipairs({ob, op}) do
		for _, s in ipairs({"RightHand","LeftHand"}) do
			local dh = (o.cf[s].Position - o.cf.Head.Position).Magnitude
			if dh < minHandSelf then minHandSelf = dh end
		end
	end
	t = t + 0.02
end
local names = {}
for k in pairs(worst) do names[#names+1] = k end
table.sort(names)
for _, k in ipairs(names) do if worst[k][1] > 0.01 then print(string.format("REACH miss %-20s max %.3f at t=%.2f", k, worst[k][1], worst[k][2])) end end
print(string.format("min torso separation %.2f at t=%.2f ; min hand-to-own-head distance %.2f", minSep, minSepT, minHandSelf))

-- return-to-guard
local function snap(tr, t)
	local P = Engine.eval(R, tr, t)
	return P
end
for _, nm in ipairs({"Blue","Purple"}) do
	local a, b = snap(tracks[nm], 0), snap(tracks[nm], Data.duration)
	local e = math.abs(a.rx-b.rx)+math.abs(a.rz-b.rz)+math.abs(a.crouch-b.crouch)+math.abs(a.lean-b.lean)+math.abs(a.pyaw-b.pyaw)+math.abs(a.twist-b.twist)
	local fe = (a.feet.R.g-b.feet.R.g).Magnitude + (a.feet.L.g-b.feet.L.g).Magnitude + (a.hands.R.t-b.hands.R.t).Magnitude + (a.hands.L.t-b.hands.L.t).Magnitude
	print(string.format("RETURN %s: body param err %.4f ; feet+hands world err %.4f", nm, e, fe))
end

-- dump skeleton frames for plotting
local out = {}
local function sk(o)
	local p = function(v) return string.format("[%.3f,%.3f,%.3f]", v.X, v.Y, v.Z) end
	local parts = {
		"\"hips\":"..p(o.cf.LowerTorso.Position), "\"chest\":"..p(o.cf.UpperTorso.Position), "\"head\":"..p(o.cf.Head.Position),
		"\"rs\":"..p(o.piv.RightShoulder), "\"re\":"..p(o.piv.RightElbow), "\"rw\":"..p(o.piv.RightWrist), "\"rh\":"..p(o.cf.RightHand.Position),
		"\"ls\":"..p(o.piv.LeftShoulder), "\"le\":"..p(o.piv.LeftElbow), "\"lw\":"..p(o.piv.LeftWrist), "\"lh\":"..p(o.cf.LeftHand.Position),
		"\"rhip\":"..p(o.piv.RightHip), "\"rk\":"..p(o.piv.RightKnee), "\"ra\":"..p(o.piv.RightAnkle), "\"rt\":"..p(o.toe.Right),
		"\"lhip\":"..p(o.piv.LeftHip), "\"lk\":"..p(o.piv.LeftKnee), "\"la\":"..p(o.piv.LeftAnkle), "\"lt\":"..p(o.toe.Left),
	}
	return "{"..table.concat(parts, ",").."}"
end
local times = {0,0.55,1.5,1.8,2.05,2.3,2.9,3.5,4.0,4.12,4.95,5.15,5.55,6.1,6.7,7.3,10.4}
local lines = {}
for _, tt in ipairs(times) do
	local _, _, ob, op = at(tt)
	lines[#lines+1] = string.format("{\"t\":%.2f,\"blue\":%s,\"purple\":%s}", tt, sk(ob), sk(op))
end
local f = io.open("frames.json","w"); f:write("["..table.concat(lines,",").."]"); f:close()
-- where do hands come close to the own head?
local tt = 0
local worstH = {99}
while tt <= Data.duration do
	local pb, pp, ob, op = at(tt)
	for nm, o in pairs({Blue=ob, Purple=op}) do
		for _, s in ipairs({"RightHand","LeftHand"}) do
			local dh = (o.cf[s].Position - o.cf.Head.Position).Magnitude
			if dh < worstH[1] then worstH = {dh, tt, nm, s} end
		end
	end
	tt = tt + 0.02
end
print(string.format("closest hand-to-head: %.2f  at t=%.2f  %s %s", worstH[1], worstH[2], worstH[3], worstH[4]))
for i, k in ipairs(Pt.keys) do if k.name == "COUNTER_HIT" or k.name == "counter_follow" then print(k.name, string.format("rh f=%.2f s=%.2f y=%.2f", k.rh.f, k.rh.s, k.rh.y)) end end
