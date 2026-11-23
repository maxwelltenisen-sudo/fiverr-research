-- BGTimeline (ModuleScript, ReplicatedStorage): THE ONE SHARED TIMELINE for the 6-second cinematic.
-- 30 fps, frames 0-179. Fighter poses, camera cuts, debris, field, power effects, camera shake and sound cues all read from here.
-- To move a beat, change its frame number in this file only: nothing else holds timing.
--
--   T.beats      named sections (HUD / checks use them)
--   T.fighters   keyframes per rig (Blue = Kael, Purple = Ren), same pose format as BGClips but keyed by frame `f`
--   T.contacts   places where two bodies must meet (solved by BGEngine.bake)
--   T.camera     shots: {f, pos, look, fov, roll, cut = true} (cut = jump on that frame, otherwise it blends from the previous key)
--   T.fx         timed effect events; T.sound = cue list; T.eyes = Ren's eye-look keys
-- Axes: world +X is screen-right (camera sits on the +Z side). Kael faces +X, Ren faces -X. Hands/feet: f forward, s to the fighter's right, y height.
local T = {}
T.fps, T.frames = 30, 180
T.duration = T.frames / T.fps          -- 6.0 s, played by elapsed time
function T.t(frame) return frame / T.fps end

T.beats = {
	{ f = 0,   name = "open" },
	{ f = 15,  name = "impossible stop" },
	{ f = 38,  name = "reversal" },
	{ f = 70,  name = "Ren takes control" },
	{ f = 107, name = "all out" },
	{ f = 150, name = "payoff" },
}

local function H(f, s, y) return { f = f, s = s, y = y } end
local function F(f, s, lift) return { f = f, s = s, lift = lift or 0 } end

---------------------------------------------------------------------------------------------- fighters
local KB = {   -- Kael: confident sideways stance, relaxed shoulders, loose hands
	dx = 0, dz = 0, yaw = 0, pyaw = -34, twist = -10, lean = 4, roll = 0, crouch = 0.2, headYaw = 0, headPitch = 0,
	rfYaw = -50, lfYaw = -14, rfPitch = 0, lfPitch = 0, rf = F(-0.7, 0.55), lf = F(0.55, -0.4),
	rh = H(0.25, 0.55, -0.55), lh = H(0.4, -0.5, -0.5), rp = H(0.0, 0.6, -0.9), lp = H(0.0, -0.6, -0.9),
}
local RB = {   -- Ren: upright, one hand loose at his side
	dx = 0, dz = 0, yaw = 0, pyaw = -8, twist = -3, lean = 0, roll = 0, crouch = 0.05, headYaw = 0, headPitch = 0,
	rfYaw = -12, lfYaw = -6, rfPitch = 0, lfPitch = 0, rf = F(-0.15, 0.55), lf = F(0.15, -0.45),
	rh = H(0.05, 0.7, -0.95), lh = H(0.15, -0.65, -0.95), rp = H(0.0, 0.5, -0.9), lp = H(0.0, -0.5, -0.9),
}
T.bases = { Blue = KB, Purple = RB }

T.fighters = {
	Blue = {
		baseYaw = -90, anchor = { x = -12, z = 0 },        -- anchor is re-solved so the follow-up lands on Ren's forearm
		base = KB,
		keys = {
			{ f = 0 },
			-- 0-14 Pursuit: hips drop, launch by frame 6 (feet are listed on every moving key so they travel with the body)
			{ f = 3,  ease = "out2", crouch = 0.9, lean = 14, pyaw = -18, twist = -12, headPitch = 6, rh = H(0.1, 0.7, -0.3), lh = H(0.9, -0.4, 0.2) },
			{ f = 6,  ease = "in2", dx = 0.5, crouch = 0.8, lean = 24, pyaw = -6, twist = 4, lf = F(1.1, -0.35, 0.15), rf = F(-1.3, 0.55, 0.35), rh = H(-0.1, 0.7, -0.3), lh = H(0.7, -0.4, 0.1) },
			{ f = 10, ease = "linear", dx = 2.6, crouch = 0.45, lean = 28, lf = F(0.2, -0.35, 0.7), rf = F(-1.5, 0.55, 0.8) },
			{ f = 14, ease = "linear", dx = 5.8, lf = F(0.2, -0.35, 0.7), rf = F(-1.5, 0.55, 0.8) },
			-- 15-37 the burst, then the fist slows and hangs
			{ f = 18, ease = "linear", dx = 9.0, crouch = 0.5, lean = 26, lf = F(0.3, -0.35, 0.7), rf = F(-1.5, 0.55, 0.8), rh = H(0.6, 0.7, 0.2) },
			{ f = 22, ease = "out2", dx = 11.0, crouch = 0.55, lean = 22, pyaw = 10, twist = 14, lf = F(1.4, -0.35, 0.25), rf = F(-1.2, 0.55, 0.5), rh = H(1.5, 0.65, 0.45) },
			{ f = 27, ease = "out3", dx = 11.9, lf = F(1.3, -0.35, 0), rf = F(-0.75, 0.55, 0), rh = H(1.95, 0.6, 0.5) },
			{ f = 31, ease = "out2", dx = 12.1, rh = H(2.05, 0.6, 0.5), lh = H(0.9, -0.75, 0.3) },
			{ f = 34, ease = "linear", dx = 12.15, rh = H(2.05, 0.6, 0.5) },        -- hand baked from the hover contact
			-- 38-69 the reversal
			{ f = 38, ease = "in2", crouch = 1.25, lean = 34, pyaw = -6, twist = 2, rh = H(1.6, 0.6, 1.1) },
			{ f = 42, ease = "out2", crouch = 1.35, lean = 38, rh = H(1.5, 0.6, 0.9) },
			{ f = 44, ease = "linear", crouch = 1.3, lean = 36, rh = H(1.6, 0.6, 0.3) },       -- baked: bracer touches the field
			{ f = 46, ease = "in3", dx = 12.35, crouch = 0.75, lean = 30, lf = F(1.5, -0.35, 0), rf = F(-1.0, 0.55, 0.2) },
			{ f = 48, ease = "linear", dx = 12.55, crouch = 0.4, lean = 28, lf = F(1.1, -0.35, 0.5), rf = F(-1.3, 0.55, 0.7), rh = H(0.7, 0.6, 0.3) },
			{ f = 51, ease = "out2", dx = 12.7, crouch = -0.2, lean = 24, lf = F(0.7, -0.35, 1.0), rf = F(-1.0, 0.55, 1.1), rh = H(1.0, 0.55, 0.7) },
			{ f = 54, ease = "in2", dx = 12.78, crouch = -0.3, lean = 20, lf = F(0.8, -0.35, 1.1), rf = F(-0.6, 0.55, 1.2), rh = H(1.6, 0.55, 1.0) },
			{ f = 56, ease = "in3", dx = 12.8, crouch = 0.0, lean = 18, pyaw = 14, twist = 18, lf = F(1.1, -0.35, 0.8), rf = F(-0.4, 0.55, 0.9), rh = H(2.0, 0.6, 0.9) },   -- CONTACT: hand baked
			{ f = 57, ease = "linear" },                                                -- contact pose held two frames (56-57)
			{ f = 60, ease = "out2", dx = 12.5, crouch = 1.2, lean = 22, lf = F(1.2, -0.35, 0), rf = F(-0.7, 0.55, 0), rh = H(1.2, 0.6, 0.6) },   -- hard landing
			{ f = 66, ease = "inout", dx = 12.3, crouch = 0.8, lean = 10, pyaw = -18, twist = -6, rh = H(0.5, 0.55, 0.0), lh = H(0.5, -0.5, 0.0) },
			-- 70-106 Ren takes control: the pull from behind, then the push
			{ f = 70, ease = "inout", dx = 12.2, crouch = 0.6, lean = 14 },
			{ f = 80, ease = "inout", dx = 12.2, crouch = 0.7, lean = 18, rf = F(-1.5, 0.55, 0), rh = H(0.6, 0.7, 0.2), lh = H(0.7, -0.7, 0.2) },
			{ f = 88, ease = "inout", dx = 12.2, crouch = 0.75, lean = 20, rf = F(-1.75, 0.55, 0) },
			{ f = 91, ease = "in2", dx = 12.2, crouch = 0.4, lean = -26, headPitch = -18, rh = H(0.2, 1.1, 0.5), lh = H(0.2, -1.1, 0.5), lf = F(0.9, -0.35, 0.1), rf = F(-1.3, 0.55, 0.2) },
			{ f = 95, ease = "linear", dx = 9.6, crouch = 0.1, lean = -30, lf = F(1.3, -0.35, 0.25), rf = F(-0.6, 0.55, 0.3) },
			{ f = 100, ease = "out2", dx = 5.4, crouch = 0.9, lean = -22, lf = F(1.9, -0.35, 0), rf = F(0.7, 0.55, 0), headPitch = -8, lh = H(0.9, -0.95, 0.4), rh = H(0.9, 0.95, 0.4) },
			{ f = 104, ease = "out2", dx = 3.8, crouch = 1.0, lean = 8, headPitch = 4, lf = F(1.3, -0.35, 0), rf = F(0.0, 0.55, 0), lh = H(0.9, -0.9, 0.2), rh = H(0.9, 0.9, 0.2) },
			-- 107-149 all out: he plants a foot and bursts across the firing lane
			{ f = 107, ease = "inout", dx = 3.7, crouch = 1.0, lean = 18, rh = H(0.6, 0.5, 0.0), lh = H(0.7, -0.5, 0.0) },
			{ f = 118, ease = "inout", dx = 3.8, crouch = 0.95, lean = 22, pyaw = -24, twist = -14, lf = F(1.2, -0.35, 0), rf = F(-1.2, 0.55, 0), rh = H(0.2, 0.7, -0.2) },
			{ f = 126, ease = "inout", dx = 3.9, crouch = 1.0, lean = 28, pyaw = -28 },
			{ f = 128, ease = "in3", dx = 4.5, dz = 0.4, crouch = 0.7, lean = 30, lf = F(1.0, -0.35, 0.2), rf = F(-1.4, 0.55, 0.5) },
			{ f = 132, ease = "linear", dx = 10.7, dz = 2.0, crouch = 0.45, lean = 30, lf = F(0.2, -0.35, 0.8), rf = F(-1.6, 0.55, 0.9), rh = H(-0.1, 0.7, -0.2) },
			{ f = 137, ease = "linear", dx = 17.2, dz = 2.4, lean = 28, lf = F(0.2, -0.35, 0.8), rf = F(-1.6, 0.55, 0.9) },
			{ f = 142, ease = "out2", dx = 20.7, dz = 2.4, crouch = 0.8, lean = 24, lf = F(1.3, -0.35, 0.05), rf = F(-0.5, 0.55, 0.05) },
			-- 150-179 payoff: one knee, head down
			{ f = 150, ease = "out2", dx = 21.6, crouch = 1.35, lean = 26, headPitch = 22, pyaw = -10, twist = -4, lf = F(1.4, -0.35, 0), rf = F(-0.7, 0.55, 0), rh = H(0.7, 0.5, -1.2), lh = H(0.5, -0.5, -0.8) },
			{ f = 179, ease = "inout", dx = 21.7, crouch = 1.38, lean = 24, headPitch = 24 },
		},
	},
	Purple = {
		baseYaw = 90, anchor = { x = 4.6, z = 0 },
		base = RB,
		keys = {
			{ f = 0 },
			{ f = 8,  ease = "inout", lh = H(0.9, -0.3, -0.2), headPitch = 0 },
			{ f = 15, ease = "out2", lh = H(1.45, -0.15, 0.5), headPitch = 4 },            -- open palm rises to meet the incoming strike
			{ f = 24, ease = "linear", headPitch = 7 },                                    -- looks at the fist
			{ f = 34, ease = "linear", lh = H(1.45, -0.15, 0.5), headPitch = 7 },
			{ f = 40, ease = "inout", headPitch = -5, headYaw = 0 },                       -- lifts his eyes toward Kael
			{ f = 46, ease = "out2", lean = -6, dx = 0.1, lh = H(1.25, -0.2, 0.55) },     -- the field folds; he rocks back
			{ f = 52, ease = "inout", lean = 0, pyaw = -16, twist = -10, lh = H(0.95, -0.4, 1.0), lp = H(0.0, -0.4, -0.9) },
			{ f = 56, ease = "in2", pyaw = -22, twist = -18, lh = H(0.95, -0.4, 1.25), lp = H(0.0, -0.4, -0.9), rh = H(0.3, 0.7, -0.4) },   -- CONTACT: forearm raised, coat twists
			{ f = 57, ease = "linear" },
			{ f = 61, ease = "out2", dx = 1.1, pyaw = -34, twist = -26, lean = -8, rf = F(0.2, 0.55, 0), lf = F(0.9, -0.45, 0) },    -- boot skids half a tile
			{ f = 67, ease = "out2", dx = 2.0, pyaw = -12, twist = -6, lean = 0, rf = F(0.4, 0.55, 0), lf = F(0.8, -0.45, 0), lh = H(1.2, -0.2, 0.7), rh = H(0.1, 0.7, -0.9) },
			-- 70-106: pull (left hand draws in), then push (right hand thrusts out)
			{ f = 72, ease = "out2", dx = 2.0, lh = H(1.5, -0.15, 0.6), headPitch = 0 },
			{ f = 82, ease = "inout", lh = H(0.4, -0.3, 0.35), twist = -2 },
			{ f = 87, ease = "inout", lh = H(0.2, -0.5, -0.4), rh = H(0.4, 0.6, 0.5), twist = -16, pyaw = -20 },
			{ f = 91, ease = "in3", pyaw = 14, twist = 12, rh = H(1.9, 0.3, 0.75), rp = H(0.4, 0.8, 0.0), lf = F(0.35, -0.5, 0), rf = F(-0.3, 0.6, 0), rfYaw = -4, lfYaw = 0 },
			{ f = 100, ease = "linear", rh = H(1.9, 0.3, 0.75) },
			{ f = 107, ease = "inout", lf = F(0.15, -0.45), rf = F(-0.15, 0.55), rfYaw = -12, lfYaw = -6, pyaw = -8, twist = -3, rh = H(0.1, 0.7, -0.9), lh = H(0.15, -0.65, -0.95), rp = H(0.0, 0.5, -0.9) },
			-- 107-149: nearly motionless; the two points are brought together in front of him
			{ f = 112, ease = "inout", lh = H(1.0, -0.95, 0.6), rh = H(1.0, 0.95, 0.6), lp = H(0.0, -0.6, -0.5), rp = H(0.0, 0.6, -0.5) },
			{ f = 121, ease = "inout", lh = H(1.5, -0.3, 0.7), rh = H(1.5, 0.3, 0.7) },
			{ f = 128, ease = "in3", lean = -3, lh = H(1.75, -0.12, 0.72), rh = H(1.75, 0.12, 0.72) },
			{ f = 149, ease = "linear" },
			{ f = 156, ease = "inout", lean = 0, lh = H(0.5, -0.5, -0.5), rh = H(0.3, 0.6, -0.8) },
			{ f = 164, ease = "inout", lf = F(0.15, -0.45), rf = F(-0.15, 0.55) },
			{ f = 172, ease = "inout", headYaw = 60, twist = 14, pyaw = 4 },
			{ f = 179, ease = "inout", headYaw = 100, twist = 30, pyaw = 14 },
		},
	},
}

-- Ren's eye-look keys (x, y in head units); eyes move before the head does
T.eyes = {
	{ f = 0, x = 0, y = 0 }, { f = 22, x = 0, y = -0.05 }, { f = 36, x = 0, y = 0.05 }, { f = 107, x = 0, y = 0 },
	{ f = 154, x = 0.07, y = 0 }, { f = 160, x = 0.07, y = 0 }, { f = 176, x = 0, y = 0 },
}

---------------------------------------------------------------------------------------------- contacts
T.contacts = {
	-- Kael's follow-up lands on Ren's raised left forearm
	{ id = "followup", kind = "guard", f = 56, attacker = "Blue", hand = "R", defender = "Purple", arm = "L", guardRadius = 0.52, fist = 0.3, reach = 0.55 },
	-- the impossible stop: fist ends `gap` studs short of Ren's palm
	{ id = "stop", kind = "hover", f = 34, attacker = "Blue", hand = "R", defender = "Purple", dhand = "L", gap = 0.55, fist = 0.3 },
	-- the bracer is pressed into the field plane
	{ id = "bracer", kind = "point", f = 44, attacker = "Blue", hand = "R", ref = 2, dx = -0.1, dy = -0.75, dz = 0 },
}

---------------------------------------------------------------------------------------------- camera
-- Left-to-right is preserved: every shot is on the +Z side looking toward -Z. Cuts jump on their frame; other keys blend.
T.camera = {
	{ f = 0,   name = "A wide 3/4",   pos = { -4.5, 3.4, 13.5 }, look = { -3.5, 3.0, 0 },  fov = 44 },
	{ f = 14,  name = "A hold",       pos = { -4.5, 3.4, 13.5 }, look = { -3.5, 3.0, 0 },  fov = 44 },
	{ f = 15,  name = "B stop",       pos = { 2.2, 3.4, 8.2 },  look = { 2.4, 3.3, 0 },   fov = 28, cut = true },
	{ f = 37,  name = "B push-in",    pos = { 2.4, 3.4, 7.0 },  look = { 2.5, 3.3, 0 },   fov = 28 },
	{ f = 38,  name = "B2",           pos = { 2.3, 3.0, 6.8 },  look = { 2.5, 3.0, 0 },   fov = 28, cut = true },
	{ f = 45,  name = "C tight",      pos = { 3.0, 2.9, 5.0 },  look = { 3.1, 2.9, 0 },   fov = 26, cut = true },
	{ f = 57,  name = "C contact",    pos = { 3.4, 3.0, 5.0 },  look = { 3.5, 3.1, 0 },   fov = 26 },
	{ f = 58,  name = "C settle",     pos = { 3.8, 3.0, 6.8 },  look = { 4.0, 3.0, 0 },   fov = 30 },
	{ f = 70,  name = "D wide low",   pos = { -0.5, 2.2, 14.0 }, look = { -0.5, 2.4, 0 },  fov = 50, cut = true },
	{ f = 106, name = "D hold",       pos = { -0.5, 2.2, 14.0 }, look = { -0.5, 2.4, 0 },  fov = 50 },
	{ f = 107, name = "E wide side",  pos = { 0.8, 3.2, 16.0 }, look = { 0.8, 2.9, 0 },   fov = 48, cut = true },
	{ f = 149, name = "E drift",      pos = { 1.2, 3.2, 15.4 }, look = { 1.2, 2.9, 0 },   fov = 47 },
	{ f = 150, name = "F final",      pos = { 5.8, 2.8, 13.0 }, look = { 6.0, 2.4, 0 },   fov = 44, cut = true },
	{ f = 179, name = "F hold",       pos = { 6.0, 2.8, 12.6 }, look = { 6.2, 2.4, 0 },   fov = 44 },
}
T.shake = { { f = 128, amp = 0.55, frames = 7 } }      -- one brief impulse, only on the strongest discharge

---------------------------------------------------------------------------------------------- effects
-- Every effect reads these frames; positions that depend on the bodies come from the solved rig at runtime.
T.fx = {
	dust      = { { f = 6, who = "Blue", kind = "launch" }, { f = 60, who = "Blue", kind = "land" }, { f = 128, who = "Blue", kind = "launch" }, { f = 142, who = "Blue", kind = "land" } },
	grit      = { from = 15, release = 38, count = 14, stopped = 2 },        -- suspended at the boundary; two stop exactly at the fist's plane
	field     = { show = 14, ripple = 18, fold = 44, gone = 52 },            -- boundary disc, contact ripple folds inward at 44-50
	afterimage = { { f = 46, who = "Blue" } },                               -- the single cyan silhouette left at Overdrive takeoff
	tiles     = {                                                            -- loose tiles hop where Kael lands / is thrown / where the beam carves
		{ f = 60, kind = "hop", x = "Blue", radius = 6, h = 0.9 },
		{ f = 91, kind = "hop", x = "Blue", radius = 5, h = 0.5 },
		{ f = 100, kind = "skid", x = "Blue", radius = 4, h = 0.25 },
		{ f = 129, kind = "carve", z = -0.5, x0 = 5.0, x1 = -22.0, speed = 70 },
		{ f = 142, kind = "hop", x = "Blue", radius = 5, h = 0.6 },
		{ f = 156, kind = "drop" },                                          -- one loose tile falls between them
	},
	stones    = { count = 16, pullFrom = 70, pullTo = 88, push = 91, settle = 106 },   -- roll toward the blue point, then are thrown back
	bluePoint = { f = 70, hold = 104, form = 112, merge = 121 },
	redPulse  = { f = 91, dur = 5 },
	core      = { form = 121, fire = 128, collapse = 149 },                  -- blue + red merge into violet at 121; discharge down the lane at 128
	beam      = { f = 128, hold = 138, gone = 149, z = -0.5, len = 26 },
	windKael  = { { from = 70, to = 90, wind = 9 } },                        -- scarf pulled taut toward the blue point
}

T.sound = {
	{ f = 5,   cue = "launch" }, { f = 36, cue = "hush" }, { f = 46, cue = "field_break" }, { f = 56, cue = "block_hit" },
	{ f = 70, cue = "pull" }, { f = 91, cue = "push" }, { f = 112, cue = "duck_start" }, { f = 124, cue = "duck_end" },
	{ f = 121, cue = "core" }, { f = 128, cue = "discharge" }, { f = 142, cue = "land" }, { f = 156, cue = "tile_drop" },
}
-- built-in client sounds; replace with your own rbxassetid:// ids (uploaded under your account) to taste
T.soundIds = {
	launch = "rbxasset://sounds/swordlunge.wav", hush = "", field_break = "rbxasset://sounds/impact_water.mp3", block_hit = "rbxasset://sounds/impact_explosion_03.mp3",
	pull = "rbxasset://sounds/bass.mp3", push = "rbxasset://sounds/swordslash.wav", core = "rbxasset://sounds/electronicpingshort.wav",
	discharge = "rbxasset://sounds/impact_explosion_03.mp3", land = "rbxasset://sounds/impact_water.mp3", tile_drop = "rbxasset://sounds/snap.mp3",
}

---------------------------------------------------------------------------------------------- helpers
local function copy(t) local r = {} for k, v in pairs(t) do r[k] = v end return r end
-- Engine data: frames become seconds
function T.engineData()
	local out = { fighters = {}, contacts = {} }
	for name, fd in pairs(T.fighters) do
		local keys = {}
		for i, k in ipairs(fd.keys) do
			local nk = copy(k)
			nk.t, nk.f = k.f / T.fps, nil
			keys[i] = nk
		end
		out.fighters[name] = { baseYaw = fd.baseYaw, anchor = { x = fd.anchor.x, z = fd.anchor.z }, base = fd.base, keys = keys }
	end
	for i, c in ipairs(T.contacts) do
		local nc = copy(c)
		nc.t, nc.f = c.f / T.fps, nil
		out.contacts[i] = nc
	end
	return out
end

function T.shotAt(frame)
	local cur
	for _, k in ipairs(T.camera) do if k.f <= frame then cur = k end end
	return cur
end

return T
