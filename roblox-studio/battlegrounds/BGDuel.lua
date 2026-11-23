-- BGDuel (ModuleScript, ReplicatedStorage): THE FOUR-MINUTE TIMELINE. Teen Gojo ("Blue" rig) vs Toji ("Purple" rig), original choreography.
-- 30 fps. Frames 0-7199 are the duel (4:00); 7200-7799 is the optional epilogue. Everything that has a time lives here:
-- fighter keys, camera shots, effects, costume states, sound cues, slow motion. Poses are macros; footwork is generated automatically.
-- Every state (glasses, spear, chain, tiles, lighting) is a pure function of the frame, so any chapter starts correctly when selected.
--   Axes: +X is screen-right. Gojo faces -X (toward the gate), Toji faces +X. Heights: gy = ground height under the fighter.
local D = {}
D.fps, D.duelFrames, D.frames = 30, 7200, 7800
D.duration = D.frames / D.fps

local function sec(m, s) return math.floor((m * 60 + s) * D.fps) end
D.chapters = {
	{ id = 1, name = "Who moved first?",      f0 = sec(0, 0),   f1 = sec(0, 20),  q = "Who moved first?" },
	{ id = 2, name = "Infinity",              f0 = sec(0, 20),  f1 = sec(0, 50),  q = "Can he be touched at all?" },
	{ id = 3, name = "Blue",                  f0 = sec(0, 50),  f1 = sec(1, 20),  q = "Can he beat the pull?" },
	{ id = 4, name = "Toji takes control",    f0 = sec(1, 20),  f1 = sec(1, 55),  q = "What is the one thing Infinity cannot stop?" },
	{ id = 5, name = "Awakening",             f0 = sec(1, 55),  f1 = sec(2, 20),  q = "Is it over?" },
	{ id = 6, name = "Red",                   f0 = sec(2, 20),  f1 = sec(2, 55),  q = "Can he be hit now?" },
	{ id = 7, name = "Toji's full arsenal",   f0 = sec(2, 55),  f1 = sec(3, 35),  q = "Can speed and steel win?" },
	{ id = 8, name = "Hollow Purple",         f0 = sec(3, 35),  f1 = sec(4, 0),   q = "What happens when both forces meet?" },
	{ id = 9, name = "Years later - Unlimited Void (epilogue)", f0 = sec(4, 0), f1 = sec(4, 20), q = "What does the strongest see?", epilogue = true },
}
function D.chapterAt(frame) local c = D.chapters[1] for _, ch in ipairs(D.chapters) do if frame >= ch.f0 then c = ch end end return c end

---------------------------------------------------------------------------------------------- arena landmarks
D.arena = {
	gate = { x = -20 }, pillar = { x = -4 },
	stair = { x0 = 10, x1 = 15.5, topY = 3.2 },      -- 4 steps from x0 to x1
	walkway = { x0 = 15.5, x1 = 34, y = 3.2 },
	step = { x = 12.2, y = 1.6 },                    -- the broken step the glasses end on
}
local function groundAt(x)           -- ground height for placing fighters
	local s = D.arena.stair
	if x >= D.arena.walkway.x0 then return s.topY end
	if x >= s.x0 then return s.topY * (x - s.x0) / (s.x1 - s.x0) end
	return 0
end
D.groundAt = groundAt

---------------------------------------------------------------------------------------------- poses (field tables; keys inherit)
local function H(f, s, y) return { f = f, s = s, y = y } end
local function F(f, s, lift) return { f = f, s = s, lift = lift or 0 } end
local function merge(a, b) local r = {} for k, v in pairs(a) do r[k] = v end if b then for k, v in pairs(b) do r[k] = v end end return r end

-- Gojo: tall, slender, hands in pockets, weight easy
local G = {}
G.base = { dx = 0, dz = 0, yaw = 0, pyaw = -6, twist = 0, lean = 0, roll = 0, crouch = 0.0, headYaw = 0, headPitch = 0, gy = 0,
	rfYaw = -8, lfYaw = -4, rfPitch = 0, lfPitch = 0, rf = F(-0.2, 0.5), lf = F(0.2, -0.45),
	rh = H(0.1, 0.72, -1.0), lh = H(0.1, -0.72, -1.0), rp = H(0.0, 0.5, -0.9), lp = H(0.0, -0.5, -0.9) }
G.stand = {}
G.shift = { roll = 2, lean = 1.5, pyaw = -2 }
G.tilt = { roll = -3, headPitch = -3, lean = -1 }                   -- amused head tilt
G.watch = { lean = -2, pyaw = -10 }
G.point = { pyaw = -22, twist = -10, lean = 2, rh = H(1.7, 0.2, 0.55), rp = H(0.3, 0.3, 0.2) }                    -- Blue: arm out, finger at a point
G.pointHold = { pyaw = -22, twist = -10, lean = 4, rh = H(1.75, 0.2, 0.6) }
G.dodgeA = { lean = -12, roll = 6, pyaw = -30, headYaw = 6, rh = H(0.1, 0.7, -0.9) }                                 -- minimal lean away
G.dodgeB = { lean = 8, roll = -6, pyaw = 10, headYaw = -8 }
G.hit = { lean = -22, crouch = 0.2, headPitch = -16, rh = H(0.3, 1.0, 0.0), lh = H(0.3, -1.0, 0.0), rp = H(0.0, 0.9, 0.0), lp = H(0.0, -0.9, 0.0) }
G.down = { crouch = 1.45, lean = -16, pyaw = -14, headPitch = 12, lh = H(0.95, -0.55, -1.7), rh = H(0.4, 0.7, -1.2), rf = F(-0.3, 0.7), lf = F(0.7, -0.5) }  -- seated against the floor, left hand flat on a tile
G.breathe1 = { lean = -14, crouch = 1.42 }
G.breathe2 = { lean = -17, crouch = 1.48 }
G.rise1 = { crouch = 1.2, lean = 6, headPitch = 6, lh = H(0.9, -0.55, -1.4), rh = H(0.5, 0.7, -1.0) }
G.rise2 = { crouch = 0.4, lean = 4, headPitch = 0, lh = H(0.1, -0.72, -1.0), rh = H(0.1, 0.72, -1.0) }
G.red = { pyaw = -30, twist = -14, lean = -4, rh = H(1.6, 0.15, 0.7), rp = H(0.3, 0.4, 0.1) }                         -- palm out
G.purple = { pyaw = -14, twist = -6, lean = 2, rh = H(1.45, 0.35, 0.65), lh = H(1.45, -0.35, 0.65), rp = H(0.2, 0.5, 0.0), lp = H(0.2, -0.5, 0.0) }
G.crossArms = { rh = H(1.0, 0.1, 0.5), lh = H(1.0, -0.1, 0.5) }
G.sidestep = { roll = 8, lean = -4 }
G.run = { lean = 14, crouch = 0.4, rh = H(0.3, 0.8, -0.8), lh = H(0.3, -0.8, -0.8) }

-- Toji: broad, loose, shoulders slack until the instant he moves
local J = {}
J.base = { dx = 0, dz = 0, yaw = 0, pyaw = -12, twist = -4, lean = 3, roll = 0, crouch = 0.3, headYaw = 0, headPitch = 3, gy = 0,
	rfYaw = -20, lfYaw = -8, rfPitch = 0, lfPitch = 0, rf = F(-0.5, 0.6), lf = F(0.5, -0.45),
	rh = H(0.15, 0.82, -1.0), lh = H(0.15, -0.82, -1.0), rp = H(0.0, 0.6, -0.9), lp = H(0.0, -0.6, -0.9) }
J.loose = {}
J.settle = { roll = -2, lean = 2, headPitch = 5 }
J.coil = { crouch = 0.8, lean = 22, pyaw = -26, twist = -18, headPitch = 6, rh = H(0.2, 0.8, -0.2), lh = H(0.6, -0.7, 0.1) }    -- anticipation: weight drops, shoulders finally engage
J.dash = { crouch = 0.65, lean = 30, pyaw = -6, twist = 6, headPitch = 4, rh = H(-0.1, 0.8, -0.3), lh = H(0.4, -0.7, -0.2) }
J.land = { crouch = 1.0, lean = 16, pyaw = -12, rh = H(0.5, 0.8, -0.4), lh = H(0.6, -0.8, -0.4) }
J.strike = { crouch = 0.6, lean = 20, pyaw = 16, twist = 18, rh = H(2.0, 0.4, 1.1), rp = H(0.3, 0.7, 0.0), lh = H(0.4, -0.8, 0.2) }
J.strikeLoad = { crouch = 0.75, lean = 12, pyaw = -34, twist = -22, rh = H(0.3, 0.9, 0.3), lh = H(0.9, -0.5, 0.5) }
J.watchHand = { lean = 6, headPitch = 12, rh = H(0.9, 0.3, 0.5), rp = H(0.2, 0.5, 0.0) }      -- studies his own hand
J.crouchLow = { crouch = 1.1, lean = 18, rh = H(0.7, 0.8, -0.5), lh = H(0.7, -0.8, -0.5) }
J.air = { crouch = -0.4, lean = 24, rh = H(0.8, 0.7, 0.3), lh = H(0.8, -0.7, 0.3) }
J.airSpear = { crouch = -0.3, lean = 20, pyaw = 12, twist = 14, rh = H(1.5, 0.4, 0.5), lh = H(0.6, -0.8, 0.2) }
J.spearHold = { crouch = 0.5, lean = 10, pyaw = -10, rh = H(1.0, 0.6, 0.1), rp = H(0.2, 0.7, -0.2), lh = H(0.5, -0.8, -0.3) }
J.spearThrust = { crouch = 0.55, lean = 24, pyaw = 18, twist = 22, rh = H(2.1, 0.3, 0.7), lh = H(0.3, -0.8, 0.0) }
J.sweep = { crouch = 0.5, lean = 14, pyaw = 30, twist = 30, rh = H(1.4, 1.1, 0.4), lh = H(0.5, -0.9, 0.1) }
J.sweepBack = { crouch = 0.55, lean = 8, pyaw = -40, twist = -30, rh = H(0.5, 1.0, 0.4) }
J.pull = { crouch = 0.6, lean = -8, pyaw = -30, twist = -20, rh = H(0.6, 0.7, 0.4), lh = H(0.5, -0.7, 0.4) }     -- hauling the chain
J.flick = { rh = H(0.9, 0.5, 0.2), headPitch = 4 }
J.stagger = { lean = -24, crouch = 0.5, headPitch = -14, rh = H(0.4, 1.0, 0.3), lh = H(0.4, -1.0, 0.3) }
J.turnBack = { headYaw = 70, twist = 20, pyaw = 10 }                                          -- hears a footstep behind him
J.guard = { crouch = 0.8, lean = 6, rh = H(1.0, 0.5, 0.7), lh = H(1.0, -0.5, 0.7) }
J.p = { stand = {}, }

---------------------------------------------------------------------------------------------- sequence builder + compiler
-- seq:add(frame, poseNames, {x, z, yaw, gy, ease, <any pose field overrides>})   poseNames = one table or a list merged in order
local Seq = {}
Seq.__index = Seq
local function newSeq(base, baseYaw, x0, z0) return setmetatable({ base = base, baseYaw = baseYaw, keys = {}, x0 = x0, z0 = z0 }, Seq) end
function Seq:add(f, poses, o)
	o = o or {}
	local fields = {}
	if poses then
		if poses.rh or poses.crouch or poses.lean or poses.pyaw or poses.lh or poses.roll or poses.headYaw or poses.headPitch or poses.twist or poses.gy or next(poses) == nil then poses = { poses } end
		for _, p in ipairs(poses) do fields = merge(fields, p) end
	end
	local k = { f = f, fields = fields, x = o.x, z = o.z, yaw = o.yaw, gy = o.gy, ease = o.ease, move = o.move }
	for a, b in pairs(o) do if not ({ x = 1, z = 1, yaw = 1, gy = 1, ease = 1, move = 1 })[a] then k.fields[a] = b end end
	table.insert(self.keys, k)
	return self
end

local function lastPos(seq, i)
	for j = i - 1, 1, -1 do
		local k = seq.keys[j]
		if k.rx then return k end
	end
end

-- numeric-aware linear blend of two pose-field tables (hands/feet are small tables of numbers)
local function lerpFields(a, b, u)
	local r = {}
	for k, v in pairs(b) do
		local av = a[k]
		if type(v) == "number" then r[k] = (type(av) == "number") and (av + (v - av) * u) or v
		elseif type(v) == "table" then
			local t = {}
			for kk, vv in pairs(v) do
				local avv = type(av) == "table" and av[kk] or nil
				t[kk] = (type(vv) == "number" and type(avv) == "number") and (avv + (vv - avv) * u) or vv
			end
			r[k] = t
		else r[k] = v end
	end
	return r
end

-- Resolve absolute positions, add intermediate footsteps on every long move, generate feet (walk steps, dash trails, plants), emit Engine data.
function Seq:compile()
	table.sort(self.keys, function(a, b) return a.f < b.f end)
	local px, pz, pyaw, pgy, pf = self.x0, self.z0, 0, 0, 0
	local cur = merge(self.base, {})                  -- cumulative pose fields (what the Engine will have inherited so far)
	local flip, prevMoving = false, false
	local out = {}
	local function emit(f, rx, rz, ryaw, rgy, fields, ease, feet)
		local ek = { t = f / D.fps, ease = ease, dx = rx - self.x0, dz = rz - self.z0, yaw = ryaw, gy = rgy }
		for a, b in pairs(fields) do ek[a] = b end
		if feet then ek.lf, ek.rf = feet[1], feet[2] end
		out[#out + 1] = ek
	end
	for i, k in ipairs(self.keys) do
		local rx, rz = k.x or px, k.z or pz
		local ryaw = k.yaw or pyaw
		local rgy = k.gy or groundAt(rx)
		local nxt = merge(cur, k.fields)
		if i == 1 then
			emit(k.f, rx, rz, ryaw, rgy, nxt, k.ease, { nxt.lf or self.base.lf, nxt.rf or self.base.rf })
		else
			local dxw, dzw = rx - px, rz - pz
			local dist = math.sqrt(dxw * dxw + dzw * dzw)
			local df = k.f - pf
			local dt = math.max(df / D.fps, 1e-3)
			local speed = dist / dt
			local explicitFeet = k.fields.lf ~= nil or k.fields.rf ~= nil
			local y = math.rad(self.baseYaw + ryaw)
			local fx, fz = -math.sin(y), -math.cos(y)
			local rx_, rz_ = math.cos(y), -math.sin(y)
			local mf, ms = 0, 0
			if dist > 1e-3 then mf, ms = (dxw * fx + dzw * fz) / dist, (dxw * rx_ + dzw * rz_) / dist end
			if explicitFeet or dist < 0.35 then
				local feet
				if not explicitFeet and prevMoving then feet = { F(0.35, -0.45, 0), F(-0.35, 0.55, 0) }; prevMoving = false end
				emit(k.f, rx, rz, ryaw, rgy, k.fields, k.ease, feet)
			elseif speed >= 7 then
				emit(k.f, rx, rz, ryaw, rgy, k.fields, k.ease, { F(0.4 + 0.8 * mf, -0.4 + 0.8 * ms, 0.6), F(-0.5 - 0.8 * mf, 0.5 - 0.8 * ms, 0.7) })
				prevMoving = true
			else
				-- walk: one footstep per ~0.9 studs, sub-keys along the path
				local n = math.max(1, math.ceil(dist / 0.9))
				for j = 1, n do
					local u = j / n
					local last = (j == n)
					local sx, sz, sy = px + dxw * u, pz + dzw * u, pyaw + (ryaw - pyaw) * u
					local sg = last and rgy or (k.gy and (pgy + (rgy - pgy) * u) or groundAt(sx))
					flip = not flip
					local s = flip and 1 or -1
					local feet = { F(0.45 + s * mf * 0.75, -0.42 + s * ms * 0.75, flip and 0 or 0.22), F(-0.45 - s * mf * 0.75, 0.55 - s * ms * 0.75, flip and 0.22 or 0) }
					local f = pf + df * u
					local fields = last and k.fields or lerpFields(cur, nxt, u)
					if last and speed < 7 then feet = nil end
					emit(f, sx, sz, sy, sg, fields, last and k.ease or "linear", feet)
				end
				-- plant on arrival
				out[#out].lf, out[#out].rf = F(0.35, -0.45, 0), F(-0.35, 0.55, 0)
				prevMoving = false
			end
		end
		cur = nxt
		px, pz, pyaw, pgy, pf = rx, rz, ryaw, rgy, k.f
	end
	return { baseYaw = self.baseYaw, anchor = { x = self.x0, z = self.z0 }, base = self.base, keys = out }
end

local Gj = newSeq(G.base, 90, 6.0, 0.0)        -- Gojo faces -X
local Tj = newSeq(J.base, -90, -20.0, 0.0)     -- Toji faces +X
D.seq = { Blue = Gj, Purple = Tj }

---------------------------------------------------------------------------------------------- CHAPTER 1: Who moved first? (0-600)
Gj:add(0,   G.stand, { x = 6.0, z = 0.0 })
Gj:add(40,  G.shift)
Gj:add(50,  { G.shift, { headYaw = 0 } })
Gj:add(78,  { G.watch, { headYaw = -26 } }, { ease = "out2" })                -- head follows AFTER the eyes found Toji
Gj:add(150, { G.watch, { headYaw = -26 } })
Gj:add(160, { G.watch, { headYaw = -30, headPitch = 2 } })
Gj:add(236, G.tilt)
Gj:add(300, { G.tilt, { headYaw = -18 } })
Gj:add(420, G.stand, { x = 6.2 })
Gj:add(560, { G.shift, { headYaw = -12 } })
Gj:add(599, { G.stand })
Tj:add(0,   J.loose, { x = -20.0, z = 0.0 })
Tj:add(60,  J.loose, { x = -20.0 })
Tj:add(120, J.settle, { x = -19.8 })
Tj:add(150, J.coil, { x = -19.8, ease = "in2" })                              -- 5 frames anticipation: the shoulders stay loose until here
Tj:add(155, J.dash, { x = -19.2, ease = "in3" })
Tj:add(159, J.land, { x = -4.2, z = 0.4, ease = "linear" })                   -- 4 frames across the courtyard, gate to pillar
Tj:add(166, J.land, { x = -4.0, ease = "out3" })
Tj:add(190, J.settle, { x = -3.6, ease = "inout" })
Tj:add(236, J.loose, { x = -3.4 })
Tj:add(300, { J.loose, { headPitch = 6 } })
Tj:add(330, J.loose, { x = -3.2 })
Tj:add(420, J.loose, { x = -1.4, z = 0.2 })                                   -- walks toward him
Tj:add(500, J.settle, { x = 0.6, z = 0.3 })
Tj:add(599, J.loose, { x = 1.2, z = 0.3 })

---------------------------------------------------------------------------------------------- CHAPTER 2: Infinity (600-1500)
-- attempt 1: a flicked pebble slows beside Gojo's cheek (pebble path in D.fx)
Tj:add(600, J.flick, { x = 1.2 })
Tj:add(612, { J.flick, { rh = H(1.5, 0.5, 0.9) } }, { ease = "in2" })
Tj:add(622, J.loose, { x = 1.2 })
Gj:add(612, G.stand)
Gj:add(655, { G.watch, { headYaw = -8, headPitch = 4 } })
Gj:add(700, G.tilt)
-- attempt 2: an ordinary strike decelerates a visible gap short of Gojo's face (slow motion 905-960)
Tj:add(760, J.settle, { x = 1.4 })
Tj:add(840, J.loose, { x = 2.6, z = 0.3 })
Tj:add(895, J.strikeLoad, { x = 3.2, ease = "in2" })
Tj:add(900, J.strikeLoad, { x = 3.2 })
Tj:add(906, J.strike, { x = 3.5, ease = "in3" })                              -- contact baked: hover short of the face
Tj:add(960, J.strike, { x = 3.5, ease = "linear" })
Tj:add(985, J.settle, { x = 3.0, ease = "out2" })
Gj:add(840, G.stand)
Gj:add(900, { G.watch, { headPitch = 2 } })
Gj:add(906, { G.dodgeA, { rh = H(0.1, 0.72, -1.0) } }, { ease = "out2" })     -- he barely moves: a tiny lean while Infinity does the work
Gj:add(960, { G.dodgeA })
Gj:add(1000, G.tilt)
-- attempt 3: Toji changes direction midway and watches when Gojo turns
Tj:add(1040, J.coil, { x = 3.0, ease = "in2" })
Tj:add(1046, J.dash, { x = 3.0, ease = "in2" })
Tj:add(1050, J.dash, { x = 5.2, z = 1.8, ease = "linear" })                   -- feints to the near side
Tj:add(1055, J.strikeLoad, { x = 5.6, z = 1.8 })
Tj:add(1058, J.dash, { x = 7.8, z = -2.4, yaw = 20, ease = "linear" })        -- cuts back across behind Gojo's head
Tj:add(1066, J.strike, { x = 8.4, z = -2.4, yaw = 20 })
Tj:add(1100, J.watchHand, { x = 7.6, z = -2.0, yaw = 20 })
Tj:add(1180, J.watchHand, { x = 6.4, z = -0.8, yaw = 10 })
Tj:add(1260, J.settle, { x = 5.0, z = -0.4, yaw = 0 })
Tj:add(1380, J.settle, { x = 2.4, z = 0.2 })
Tj:add(1499, J.loose, { x = 1.0, z = 0.2 })
Gj:add(1040, { G.watch, { headYaw = -22 } })
Gj:add(1058, { G.watch, { headYaw = 10 } }, { ease = "linear" })              -- Gojo turns to follow; Toji's head tracks that turn
Gj:add(1090, { G.tilt, { headYaw = 18 } })
Gj:add(1200, { G.stand, { headYaw = 8 } })
Gj:add(1400, G.stand)
Gj:add(1499, G.shift)

---------------------------------------------------------------------------------------------- CHAPTER 3: Blue (1500-2400)
Gj:add(1500, G.stand)
Gj:add(1530, G.pointHold, { ease = "out2" })
Gj:add(1620, G.pointHold)
Gj:add(1690, { G.pointHold, { lean = -6 } })
Gj:add(1780, G.stand, { ease = "inout" })
Gj:add(1900, { G.watch, { headYaw = 40 } }, { yaw = 0 })
Gj:add(2000, { G.watch, { headYaw = 55 } })
Gj:add(2100, G.shift, { x = 6.2 })
Gj:add(2160, { G.watch, { headYaw = 60 } })
Gj:add(2250, G.stand, { x = 9.2 })                                            -- follows up toward the stair, then the walkway
Gj:add(2340, G.stand, { x = 16.6 })
Gj:add(2399, G.stand, { x = 18.0 })
-- Toji: trousers pull sideways (cloth wind), footing gives, he rides the slab up and over, lands on the stair, then the walkway
Tj:add(1530, J.loose, { x = 1.0, z = 0.2 })
Tj:add(1590, { J.crouchLow, { roll = 8 } }, { x = 0.6, z = 0.4 })              -- being pulled: footing gives
Tj:add(1640, J.crouchLow, { x = -1.6, z = 0.4, ease = "linear" })              -- dragged toward the point; slab arrives
Tj:add(1690, { J.coil, { crouch = 0.9 } }, { x = -2.2 })                       -- he steps onto the slab
Tj:add(1700, J.dash, { x = -1.0, gy = 0.4, ease = "in2" })
Tj:add(1708, J.air, { x = 3.0, gy = 2.3, ease = "linear" })                    -- rides the tilting slab upward
Tj:add(1722, J.air, { x = 8.0, gy = 4.4, ease = "linear" })                    -- over Gojo
Tj:add(1736, J.airSpear, { x = 11.2, gy = 4.0, ease = "in2" })
Tj:add(1744, J.land, { x = 11.8, gy = 1.9, ease = "out2" })                    -- lands on the stair
Tj:add(1770, J.settle, { x = 12.0 })
Tj:add(1900, J.loose, { x = 13.5 })
Tj:add(2100, J.loose, { x = 15.0 })
Tj:add(2200, J.settle, { x = 19.0 })
Tj:add(2399, J.loose, { x = 24.0 })

---------------------------------------------------------------------------------------------- CHAPTER 4: Toji takes control (2400-3450)
Tj:add(2400, J.loose, { x = 24.0, z = 0.0 })
Tj:add(2480, J.spearHold, { x = 24.0 })                                       -- the curse uncoils and produces the Inverted Spear of Heaven
Tj:add(2560, J.spearHold, { x = 24.0 })
Tj:add(2640, J.spearHold, { x = 24.2, z = 0.3 })
Tj:add(2700, J.coil, { x = 24.2, ease = "in2" })
Tj:add(2705, J.dash, { x = 24.4, ease = "in2" })
Tj:add(2711, J.air, { x = 18.0, z = 1.8, ease = "linear" })                    -- crosses behind the swarm while Gojo watches the empty stair
Tj:add(2716, J.spearThrust, { x = 17.0, z = 1.0, ease = "linear" })           -- contact baked on Gojo's torso
Tj:add(2722, J.spearThrust, { x = 17.0, z = 1.0 })
Tj:add(2760, J.spearHold, { x = 16.4, z = 1.0, ease = "out2" })
Tj:add(2900, J.settle, { x = 17.6, z = 0.8 })
Tj:add(3000, J.loose, { x = 20.0, z = 0.4 })
Tj:add(3100, J.loose, { x = 17.0, z = -0.8 })                                  -- leaves: down the stair, out of frame
Tj:add(3200, J.dash, { x = 13.0, z = -0.6 })
Tj:add(3260, J.dash, { x = 5.0 })
Tj:add(3340, J.dash, { x = -8.0 })
Tj:add(3449, J.loose, { x = -12.0 })
Gj:add(2400, G.stand, { x = 18.0 })
Gj:add(2500, { G.watch, { headYaw = 10 } })
Gj:add(2600, { G.stand, { headYaw = -10 } })
Gj:add(2680, { G.watch, { headYaw = -34 } })                                  -- eyes tracking the swarm
Gj:add(2710, { G.watch, { headYaw = -50, headPitch = 6 } })
Gj:add(2716, G.hit, { x = 18.0, ease = "in3" })                                -- spear contact (Infinity folds inward)
Gj:add(2740, { G.hit, { lean = -26 } }, { x = 18.6, ease = "out2" })
Gj:add(2800, G.down, { x = 19.4, ease = "out2" })
Gj:add(3449, G.down, { x = 19.4 })

---------------------------------------------------------------------------------------------- CHAPTER 5: Awakening (3450-4200)
Gj:add(3450, G.down, { x = 19.4 })
Gj:add(3560, G.breathe1)
Gj:add(3640, G.breathe2)
Gj:add(3720, G.breathe1)
Gj:add(3780, { G.breathe2, { lh = H(0.95, -0.55, -1.75) } })                  -- fingers regain tension: the hand presses the tile
Gj:add(3850, G.rise1, { ease = "inout" })
Gj:add(3930, G.rise2, { ease = "inout" })
Gj:add(3990, G.stand, { x = 19.2 })
Gj:add(4060, G.stand, { x = 17.2 })                                            -- walks to the top of the stair
Gj:add(4130, G.stand, { x = 14.0, z = 0.6 })
Gj:add(4199, G.stand, { x = 11.0, z = 0.6 })
Tj:add(3450, J.loose, { x = -12.0 })
Tj:add(3900, J.settle, { x = -9.0, yaw = 180 })
Tj:add(4040, J.loose, { x = -9.0, yaw = 180 })                                 -- hears a footstep behind him
Tj:add(4060, { J.loose, { headYaw = -40 } }, { yaw = 180 })
Tj:add(4090, { J.turnBack }, { x = -9.0, yaw = 180 })
Tj:add(4150, J.settle, { x = -9.0, yaw = 0, ease = "out2" })
Tj:add(4199, J.loose, { x = -9.0, yaw = 0 })

---------------------------------------------------------------------------------------------- CHAPTER 6: Red (4200-5250)
Gj:add(4200, G.stand, { x = 11.0, z = 0.6 })
Gj:add(4260, G.stand, { x = 6.2, z = 0.0, ease = "inout" })
Gj:add(4330, { G.watch, { headYaw = -34 } })                                    -- already looking at the landing point
Gj:add(4380, G.red, { ease = "out2" })
Gj:add(4460, G.red)
Gj:add(4530, { G.stand, { headYaw = -20 } })
Gj:add(4620, G.dodgeA, { x = 6.0 })
Gj:add(4670, G.sidestep, { x = 5.6, z = -0.4 })
Gj:add(4740, G.dodgeB, { x = 6.0, z = 0.2 })
Gj:add(4800, { G.sidestep, { lean = -2 } }, { x = 5.8, z = -0.3 })
Gj:add(4900, G.dodgeA, { x = 6.2, z = 0.0 })
Gj:add(5000, { G.watch }, { x = 6.0 })
Gj:add(5120, { G.tilt }, { x = 6.0 })
Gj:add(5249, G.stand, { x = 6.0 })
Tj:add(4200, J.loose, { x = -9.0 })
Tj:add(4290, J.settle, { x = -17.0, yaw = 0 })
Tj:add(4330, J.coil, { x = -19.8, ease = "in2" })
Tj:add(4336, J.dash, { x = -19.2, ease = "in3" })
Tj:add(4340, J.dash, { x = -9.0, z = 0.2, ease = "linear" })
Tj:add(4342, { J.strike, { lean = 10 } }, { x = -5.4, z = 0.3, ease = "in2" })      -- the Red core repels him: reversed travel
Tj:add(4350, J.stagger, { x = -9.2, ease = "out2" })
Tj:add(4372, J.stagger, { x = -15.0, ease = "out2" })
Tj:add(4390, J.land, { x = -15.8, ease = "out2" })
Tj:add(4460, J.settle, { x = -15.0 })
Tj:add(4500, J.coil, { x = -14.8, ease = "in2" })
Tj:add(4506, J.dash, { x = -10.0, ease = "in2" })
Tj:add(4510, J.air, { x = -4.0, gy = 1.4, ease = "linear" })                     -- fast exchange: Toji changes height
Tj:add(4514, J.strike, { x = 3.0, gy = 0.0, ease = "in2" })
Tj:add(4522, J.land, { x = 3.4 })
Tj:add(4560, J.dash, { x = 8.5, z = -1.0 })
Tj:add(4565, J.strike, { x = 6.8, z = -1.2, ease = "in2" })
Tj:add(4590, J.crouchLow, { x = 6.0, z = 1.4 })
Tj:add(4640, J.dash, { x = 2.0, z = 1.6 })
Tj:add(4646, { J.strike, { rh = H(1.6, 0.4, 0.9) } }, { x = 4.2, z = 1.0, ease = "in2" })
Tj:add(4700, J.land, { x = 3.2, z = 0.8 })
Tj:add(4780, J.air, { x = 6.8, z = -0.2, gy = 1.8, ease = "in2" })
Tj:add(4786, J.airSpear, { x = 7.4, z = 0.2, gy = 1.9 })
Tj:add(4800, J.land, { x = 4.6, z = 0.4, gy = 0.0 })
Tj:add(4900, J.crouchLow, { x = 4.0, z = -0.2 })
Tj:add(4960, J.dash, { x = 8.4, z = 0.3 })
Tj:add(4966, J.strike, { x = 7.6, z = 0.0, ease = "in2" })
Tj:add(5020, J.settle, { x = 3.4, z = 0.2 })
Tj:add(5249, J.loose, { x = 3.0, z = 0.2 })

---------------------------------------------------------------------------------------------- CHAPTER 7: Toji's full arsenal (5250-6450)
Tj:add(5250, J.loose, { x = 3.0, z = 0.2 })
Tj:add(5340, J.spearHold, { x = 2.6 })                                          -- chain revealed: spear + chain, far end hidden in the curse
Tj:add(5460, J.coil, { x = 2.4, ease = "in2" })
Tj:add(5466, J.sweepBack, { x = 2.4 })
Tj:add(5474, J.sweep, { x = 3.4, ease = "in3" })                                -- exchange 1: a broad sweep that changes the available space
Tj:add(5486, J.sweep, { x = 3.8, ease = "out2" })
Tj:add(5530, J.settle, { x = 3.6 })
Tj:add(5680, J.dash, { x = 8.0 })
Tj:add(5686, J.strike, { x = 6.6, ease = "in2" })
Tj:add(5700, J.land, { x = 5.0 })
Tj:add(5780, J.pull, { x = 5.0 })                                               -- exchange 2: sudden return interrupts the approach
Tj:add(5800, J.pull, { x = 4.0, ease = "in2" })
Tj:add(5812, J.spearHold, { x = 4.0 })
Tj:add(5950, J.coil, { x = 3.8, ease = "in2" })
Tj:add(5956, J.air, { x = 7.0, gy = 2.0, ease = "in2" })                         -- exchange 3: airborne crossing, the chain divides the frame
Tj:add(5966, J.airSpear, { x = 12.0, gy = 2.6, z = -0.3, ease = "linear" })
Tj:add(5976, J.air, { x = 17.0, gy = 3.4, ease = "linear" })
Tj:add(5984, J.land, { x = 18.4, ease = "out2" })
Tj:add(6050, J.settle, { x = 17.0 })
Tj:add(6120, J.dash, { x = 10.0 })
Tj:add(6126, J.strike, { x = 8.0, z = 0.0, ease = "in2" })                       -- he nearly reclaims the advantage
Tj:add(6180, J.crouchLow, { x = 7.0, z = 0.4 })
Tj:add(6300, J.settle, { x = 6.0 })
Tj:add(6449, J.loose, { x = 2.0 })
Gj:add(5250, G.stand, { x = 6.0 })
Gj:add(5340, { G.watch, { headYaw = -28 } })
Gj:add(5474, G.dodgeA, { x = 6.0 })
Gj:add(5486, G.sidestep, { x = 7.8, z = -0.5, ease = "out2" })
Gj:add(5560, { G.watch, { headYaw = -20 } }, { x = 8.0 })
Gj:add(5640, G.stand, { x = 6.4, z = 0.0 })                                       -- steps in: the return interrupts him
Gj:add(5680, G.run, { x = 3.8 })
Gj:add(5800, G.hit, { x = 4.8, ease = "out2" })
Gj:add(5840, G.sidestep, { x = 7.2 })
Gj:add(5950, { G.watch, { headYaw = -16 } }, { x = 7.0 })
Gj:add(5976, G.dodgeA, { x = 9.4, ease = "out2" })
Gj:add(6060, G.sidestep, { x = 11.0 })
Gj:add(6130, G.dodgeB, { x = 11.6, z = 0.4 })
Gj:add(6220, G.sidestep, { x = 12.4 })
Gj:add(6449, { G.watch, { headYaw = -20 } }, { x = 12.4 })

---------------------------------------------------------------------------------------------- CHAPTER 8: Hollow Purple (6450-7200)
Gj:add(6450, { G.watch }, { x = 12.4, z = 0.0 })
Gj:add(6530, G.pointHold, { x = 12.4 })                                           -- Blue
Gj:add(6600, G.red, { x = 12.4 })                                                 -- Red
Gj:add(6700, G.purple, { x = 12.4, ease = "inout" })                              -- brings the two together
Gj:add(6870, G.purple, { x = 12.4 })
Gj:add(6900, { G.purple, { lean = -4 } }, { ease = "in3" })                       -- release
Gj:add(6960, { G.purple, { lean = -8 } })
Gj:add(7050, G.stand, { x = 12.4 })
Gj:add(7160, { G.tilt, { headPitch = 6 } })
Gj:add(7199, { G.tilt, { headPitch = 6 } })
Tj:add(6450, J.loose, { x = 2.0 })
Tj:add(6600, J.settle, { x = 2.4 })
Tj:add(6700, { J.guard }, { x = 2.4 })
Tj:add(6790, { J.guard, { headPitch = 0 } }, { x = 2.4 })                         -- recognises an unfamiliar technique
Tj:add(6860, J.dash, { x = 3.4 })
Tj:add(6900, { J.guard, { lean = 16 } }, { x = 3.4 })
Tj:add(6960, J.stagger, { x = 2.0, ease = "out2" })
Tj:add(7100, J.settle, { x = 1.4 })
Tj:add(7199, J.loose, { x = 1.4 })

---------------------------------------------------------------------------------------------- EPILOGUE (7200-7799): adult Gojo, blindfold, Unlimited Void
Gj:add(7200, G.stand, { x = 6.0, z = 0.0, gy = 0, yaw = 0 })
Gj:add(7400, { G.stand, { headPitch = -4 } })
Gj:add(7500, { G.watch })
Gj:add(7799, { G.stand })
Tj:add(7200, J.loose, { x = -60.0, z = -60.0 })                                    -- Toji is not in the epilogue (parked far away)
Tj:add(7799, J.loose, { x = -60.0, z = -60.0 })

---------------------------------------------------------------------------------------------- contacts (solved by BGEngine.bake)
D.contacts = {
	{ id = "fist-stop", kind = "hover", f = 906, attacker = "Purple", hand = "R", defender = "Blue", dpart = "head", dy = 0.0, gap = 0.5, fist = 0.3 },
	{ id = "spear-fold", kind = "chest", f = 2716, attacker = "Purple", hand = "R", defender = "Blue", surface = 0.5, up = 0.1 },
}

---------------------------------------------------------------------------------------------- eyes (Gojo's eyes find Toji before his head turns)
D.eyes = {
	Blue = { { f = 0, x = 0, y = 0 }, { f = 50, x = 0, y = 0 }, { f = 58, x = -0.075, y = 0 }, { f = 300, x = -0.075, y = 0 }, { f = 1058, x = 0.07, y = 0 },
		{ f = 1400, x = -0.05, y = 0 }, { f = 2680, x = -0.075, y = 0.02 }, { f = 3800, x = 0, y = 0 }, { f = 3880, x = 0.0, y = 0 },
		{ f = 4330, x = -0.075, y = 0 }, { f = 7000, x = 0, y = 0 }, { f = 7199, x = 0, y = -0.03 } },
	Purple = { { f = 0, x = 0, y = 0 }, { f = 4040, x = 0, y = 0 }, { f = 4052, x = 0.06, y = 0 }, { f = 4150, x = 0, y = 0 } },
}

---------------------------------------------------------------------------------------------- camera
-- pos/look = {x, y, z} or { rel = "Blue"|"Purple", o = {x, y, z} } (relative to that fighter's head). cut = true jumps on that frame; otherwise it blends from the previous key.
local function cam(f, pos, look, fov, extra)
	local c = { f = f, pos = pos, look = look, fov = fov }
	if extra then for k, v in pairs(extra) do c[k] = v end end
	return c
end
local function rel(who, x, y, z) return { rel = who, o = { x, y, z } } end
local WIDE_A = { { -4.0, 3.6, 17.5 }, { -4.0, 2.6, 0 }, 44 }                -- the opening wide: gate, pillar and Gojo, repeated in chapter 6
D.camera = {
	-- 1: glasses close-up, wide, Toji's landing, Gojo's eyes, Toji's scar
	cam(0,    rel("Blue", -0.1, 0.05, -1.6), rel("Blue", 0, 0.05, 0), 18, { cut = true, name = "1 glasses CU" }),
	cam(59,   rel("Blue", -0.1, 0.05, -1.6), rel("Blue", 0, 0.05, 0), 18),
	cam(60,   WIDE_A[1], WIDE_A[2], WIDE_A[3], { cut = true, name = "1 wide: gate, pillar, stair" }),
	cam(235,  WIDE_A[1], WIDE_A[2], WIDE_A[3]),
	cam(236,  rel("Blue", -0.4, 0.15, -2.4), rel("Blue", 0, 0.05, 0), 22, { cut = true, name = "1 Gojo CU: eyes first" }),
	cam(268,  rel("Blue", -0.4, 0.15, -2.4), rel("Blue", 0, 0.05, 0), 22),
	cam(269,  rel("Purple", 0.9, 0.1, 2.1), rel("Purple", 0, 0.0, 0), 20, { cut = true, name = "1 Toji CU: scar" }),
	cam(300,  rel("Purple", 0.9, 0.1, 2.1), rel("Purple", 0, 0.0, 0), 20),
	cam(301,  { -1.0, 3.2, 12.0 }, { 1.2, 2.8, 0 }, 40, { cut = true, name = "1 two-shot" }),
	cam(599,  { -0.6, 3.2, 11.4 }, { 1.6, 2.8, 0 }, 40),
	-- 2: pebble, fist stop (slow motion), feint
	cam(600,  { 4.0, 3.6, 7.0 }, { 5.6, 3.6, 0 }, 28, { cut = true, name = "2 pebble by the cheek" }),
	cam(700,  { 4.4, 3.6, 6.4 }, { 5.8, 3.6, 0 }, 26),
	cam(701,  { 2.0, 3.2, 11.0 }, { 4.2, 2.8, 0 }, 40, { cut = true, name = "2 two-shot" }),
	cam(900,  { 2.0, 3.2, 11.0 }, { 4.2, 2.8, 0 }, 40),
	cam(901,  { 4.2, 3.6, 5.6 }, { 5.0, 3.7, 0 }, 24, { cut = true, name = "2 the gap (slow)" }),
	cam(985,  { 4.4, 3.6, 5.2 }, { 5.0, 3.7, 0 }, 24),
	cam(986,  { 3.0, 3.2, 12.0 }, { 5.0, 2.8, 0 }, 40, { cut = true, name = "2 feint wide" }),
	cam(1260, { 3.4, 3.2, 12.0 }, { 5.0, 2.8, 0 }, 40),
	cam(1261, rel("Purple", 0.6, 0.15, 2.0), rel("Purple", 0, 0, 0), 22, { cut = true, name = "2 Toji studies" }),
	cam(1360, rel("Purple", 0.6, 0.15, 2.0), rel("Purple", 0, 0, 0), 22),
	cam(1361, { 3.0, 3.2, 12.0 }, { 3.8, 2.8, 0 }, 42, { cut = true }),
	-- 3: Blue: one continuous full-body shot of the maneuver, then the stair
	cam(1500, { 0.5, 3.4, 15.5 }, { 2.0, 2.6, 0 }, 46, { cut = true, name = "3 Gojo picks the point" }),
	cam(1680, { 0.5, 3.4, 15.5 }, { 2.0, 2.6, 0 }, 46),
	cam(1681, { 3.0, 4.2, 20.0 }, { 5.0, 3.0, 0 }, 52, { cut = true, name = "3 full-body maneuver (continuous)" }),
	cam(1790, { 4.0, 4.2, 20.0 }, { 7.0, 3.0, 0 }, 52),
	cam(1791, { 11.0, 4.0, 17.0 }, { 13.0, 3.0, 0 }, 46, { cut = true, name = "3 stair" }),
	cam(2399, { 16.0, 5.5, 18.0 }, { 20.0, 4.0, 0 }, 46),
	-- 4: walkway, swarm, Gojo's POV, wide reveal, the fold, Gojo down
	cam(2400, { 20.0, 5.4, 15.0 }, { 21.5, 4.4, 0 }, 44, { cut = true, name = "4 walkway: the curse uncoils" }),
	cam(2599, { 21.0, 5.4, 14.0 }, { 22.5, 4.4, 0 }, 42),
	cam(2600, { 17.0, 5.6, 13.0 }, { 18.0, 4.4, 0 }, 40, { cut = true, name = "4 the swarm" }),
	cam(2670, { 17.0, 5.6, 13.0 }, { 18.0, 4.4, 0 }, 40),
	cam(2671, rel("Blue", 0.0, 0.0, 0.5), { 13.0, 2.0, 0 }, 55, { cut = true, name = "4 Gojo POV: the empty stair" }),
	cam(2705, rel("Blue", 0.0, 0.0, 0.5), { 13.0, 2.0, 0 }, 55),
	cam(2706, { 19.0, 6.0, 15.0 }, { 18.0, 4.4, 0 }, 44, { cut = true, name = "4 wide: where he actually went" }),
	cam(2722, { 18.2, 5.6, 9.0 }, { 18.0, 4.6, 0 }, 28),
	cam(2760, { 19.0, 5.4, 12.0 }, { 19.0, 4.2, 0 }, 40, { name = "4 Gojo down" }),
	cam(3100, { 19.0, 5.2, 12.0 }, { 19.0, 4.0, 0 }, 40),
	cam(3101, { 14.0, 5.0, 16.0 }, { 14.0, 3.0, 0 }, 46, { cut = true, name = "4 Toji leaves frame" }),
	cam(3449, { 4.0, 4.0, 18.0 }, { 4.0, 2.0, 0 }, 46),
	-- 5: awakening (quiet): hand on tile, eyes, footstep, discovery
	cam(3450, rel("Blue", 0.4, -2.6, -1.6), rel("Blue", 0.8, -3.0, 0), 20, { cut = true, name = "5 hand on the tile" }),
	cam(3790, rel("Blue", 0.4, -2.6, -1.6), rel("Blue", 0.8, -3.0, 0), 18),
	cam(3791, rel("Blue", -0.2, 0.1, -2.2), rel("Blue", 0, 0.0, 0), 20, { cut = true, name = "5 eyes, no glasses" }),
	cam(3890, rel("Blue", -0.2, 0.1, -2.0), rel("Blue", 0, 0.0, 0), 18),
	cam(3891, { -5.0, 3.0, 11.0 }, { -9.0, 2.6, 0 }, 40, { cut = true, name = "5 Toji hears a footstep" }),
	cam(4090, { -5.0, 3.0, 11.0 }, { -9.0, 2.6, 0 }, 40),
	cam(4091, { -2.0, 3.4, 14.0 }, { 4.0, 3.0, 0 }, 46, { cut = true, name = "5 discovered: standing" }),
	cam(4199, { -1.0, 3.4, 14.0 }, { 5.0, 3.0, 0 }, 44),
	-- 6: Red: the opening angle again
	cam(4200, WIDE_A[1], WIDE_A[2], WIDE_A[3], { cut = true, name = "6 opening angle repeated" }),
	cam(4520, WIDE_A[1], WIDE_A[2], WIDE_A[3]),
	cam(4521, { -3.0, 4.0, 17.0 }, { 0.5, 2.8, 0 }, 46, { cut = true, name = "6 fast exchange wide" }),
	cam(5249, { 0.0, 4.0, 16.5 }, { 3.5, 2.8, 0 }, 46),
	-- 7: arsenal
	cam(5250, { 2.0, 3.6, 14.0 }, { 4.0, 2.8, 0 }, 44, { cut = true, name = "7 chain revealed" }),
	cam(5470, { 2.0, 3.6, 14.0 }, { 4.0, 2.8, 0 }, 44),
	cam(5471, { 3.0, 4.2, 18.0 }, { 4.6, 2.8, 0 }, 48, { cut = true, name = "7 the sweep" }),
	cam(5679, { 3.0, 4.2, 18.0 }, { 4.6, 2.8, 0 }, 48),
	cam(5680, { 5.0, 3.6, 13.0 }, { 5.2, 2.8, 0 }, 42, { cut = true, name = "7 the return" }),
	cam(5949, { 5.0, 3.6, 13.0 }, { 5.2, 2.8, 0 }, 42),
	cam(5950, { 10.0, 4.4, 20.0 }, { 11.0, 3.2, 0 }, 52, { cut = true, name = "7 airborne crossing (chain divides frame)" }),
	cam(6120, { 10.5, 4.4, 20.0 }, { 11.0, 3.2, 0 }, 52),
	cam(6121, { 7.0, 3.8, 14.0 }, { 8.0, 2.8, 0 }, 44, { cut = true, name = "7 nearly his" }),
	cam(6449, { 5.0, 3.8, 14.0 }, { 7.0, 2.8, 0 }, 44),
	-- 8: purple
	cam(6450, { 8.0, 3.4, 13.0 }, { 8.0, 2.8, 0 }, 42, { cut = true, name = "8 Gojo gathers" }),
	cam(6780, { 8.0, 3.4, 13.0 }, { 8.0, 2.8, 0 }, 42),
	cam(6781, rel("Purple", 0.5, 0.1, 2.0), rel("Purple", 0, 0, 0), 22, { cut = true, name = "8 Toji recognises it" }),
	cam(6860, rel("Purple", 0.5, 0.1, 2.0), rel("Purple", 0, 0, 0), 20),
	cam(6861, { -1.0, 4.4, 24.0 }, { 3.0, 2.8, 0 }, 56, { cut = true, name = "8 wide release: both + the pillar" }),
	cam(7010, { -1.0, 4.4, 24.0 }, { 3.0, 2.8, 0 }, 56),
	cam(7011, { 4.0, 3.2, 16.0 }, { 2.0, 1.2, 0 }, 40, { cut = true, name = "8 the cleared path" }),
	cam(7120, { 6.0, 2.6, 12.0 }, { 11.0, 1.8, 0 }, 40),
	cam(7121, rel("Blue", -0.2, 0.1, -2.4), rel("Blue", 0, 0.0, 0), 20, { cut = true, name = "8 Gojo's expression" }),
	cam(7199, rel("Blue", -0.2, 0.1, -2.4), rel("Blue", 0, 0.0, 0), 18),
	-- epilogue
	cam(7200, { 6.0, 3.4, 14.0 }, { 6.0, 3.0, 0 }, 42, { cut = true, name = "9 Years later" }),
	cam(7400, { 6.0, 3.4, 11.0 }, { 6.0, 3.0, 0 }, 38),
	cam(7401, rel("Blue", -0.2, 0.1, -2.2), rel("Blue", 0, 0, 0), 20, { cut = true, name = "9 one eye revealed" }),
	cam(7520, rel("Blue", -0.2, 0.1, -2.0), rel("Blue", 0, 0, 0), 18),
	cam(7521, { 6.0, 3.6, 16.0 }, { 6.0, 3.0, 0 }, 50, { cut = true, name = "9 the field" }),
	cam(7690, { 6.0, 3.6, 13.0 }, { 6.0, 3.0, 0 }, 46),
	cam(7691, rel("Blue", -0.2, 0.1, -2.2), rel("Blue", 0, 0, 0), 20, { cut = true, name = "9 same eye framing as the awakening" }),
	cam(7799, rel("Blue", -0.2, 0.1, -2.0), rel("Blue", 0, 0, 0), 18),
}
D.shake = { { f = 159, amp = 0.35, frames = 5 }, { f = 1744, amp = 0.3, frames = 5 }, { f = 2722, amp = 0.35, frames = 5 }, { f = 4342, amp = 0.4, frames = 6 }, { f = 6900, amp = 0.6, frames = 8 } }
D.slowmo = { { f0 = 906, f1 = 960, scale = 0.25 }, { f0 = 6860, f1 = 6900, scale = 0.3 } }      -- the first Infinity stop, and the beat before Purple

---------------------------------------------------------------------------------------------- state as functions of frame
function D.glassesState(f)       -- "face" | "flying" | "step" | "settling" | "settled" | "none"
	if f >= 7200 then return "none" end
	if f < 2716 then return "face" end
	if f < 2790 then return "flying" end
	if f < 7040 then return "step" end
	if f < 7125 then return "settling" end
	return "settled"
end
function D.spearVisible(f) return (f >= 2490 and f < 3460) or (f >= 4330 and f < 7200) end
function D.chainVisible(f) return f >= 5340 and f < 6449 end
function D.curseUncoiled(f) return f >= 2450 and f < 3460 or f >= 5300 and f < 6449 end

---------------------------------------------------------------------------------------------- effects (frames only; the player draws them)
D.fx = {
	reflection = { f0 = 30, f1 = 50 },
	pebble = { f0 = 612, f1 = 700, startOff = { -3.6, 0.2, 0.1 }, stopGap = 0.35 },
	infinityStops = { { id = "fist-stop", f0 = 906, f1 = 1020 } },
	blue = { f0 = 1500, f1 = 1740, point = { -5.0, 2.2, 0.0 }, tilt0 = 1560, slab0 = 1600, slab1 = 1700 },
	flyHeads = { f0 = 2600, f1 = 2760, count = 26 },
	fold = { f = 2716, dur = 24 },
	rct = { f0 = 3540, f1 = 3900 },
	red = { f0 = 4342, f1 = 4372, point = { -5.2, 2.0, 0.3 } },
	chain = { f0 = 5340, f1 = 6449 },
	purple = { blue0 = 6530, red0 = 6600, merge = 6820, release = 6900, beam1 = 7010, laneZ = 0.0 },
	void = { f0 = 7440, f1 = 7799 },
}
D.sound = {  -- cues (ids in D.soundIds; blank = silence). music is a separate envelope
	{ f = 30, cue = "glass_shadow" }, { f = 158, cue = "burst" }, { f = 625, cue = "pebble_stop" }, { f = 909, cue = "infinity_stop" },
	{ f = 1560, cue = "blue" }, { f = 1745, cue = "land" }, { f = 2716, cue = "spear_fold" }, { f = 4045, cue = "footstep" },
	{ f = 4342, cue = "red" }, { f = 5474, cue = "chain" }, { f = 6900, cue = "purple" }, { f = 7125, cue = "glasses" }, { f = 7440, cue = "void" },
}
D.soundIds = {
	burst = "rbxasset://sounds/swordlunge.wav", land = "rbxasset://sounds/impact_water.mp3", spear_fold = "rbxasset://sounds/impact_explosion_03.mp3",
	blue = "rbxasset://sounds/bass.mp3", red = "rbxasset://sounds/swordslash.wav", chain = "rbxasset://sounds/swordslash.wav", purple = "rbxasset://sounds/impact_explosion_03.mp3",
	footstep = "rbxasset://sounds/snap.mp3", infinity_stop = "rbxasset://sounds/electronicpingshort.wav", pebble_stop = "rbxasset://sounds/electronicpingshort.wav",
	glasses = "rbxasset://sounds/snap.mp3", void = "rbxasset://sounds/bass.mp3", glass_shadow = "",
}
D.music = {  -- master volume envelope (frame, volume): music drops for the awakening, falls silent for Purple's aftermath
	{ 0, 0.5 }, { 3420, 0.5 }, { 3450, 0 }, { 4090, 0 }, { 4200, 0.5 }, { 6850, 0.5 }, { 6860, 0 }, { 7120, 0 }, { 7200, 0.4 }, { 7799, 0.4 },
}

---------------------------------------------------------------------------------------------- engine data
local function copy(t) local r = {} for k, v in pairs(t) do r[k] = v end return r end
function D.engineData()
	local out = { fighters = {}, contacts = {} }
	for name, s in pairs(D.seq) do out.fighters[name] = s:compile() end
	for i, c in ipairs(D.contacts) do
		local nc = copy(c)
		nc.t, nc.f = c.f / D.fps, nil
		out.contacts[i] = nc
	end
	return out
end
function D.playRate(frame)       -- slow-motion scale at this frame (1 = normal)
	for _, s in ipairs(D.slowmo) do if frame >= s.f0 and frame < s.f1 then return s.scale end end
	return 1
end
return D
