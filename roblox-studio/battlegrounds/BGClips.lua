-- BGClips (ModuleScript, ReplicatedStorage): EDITABLE ANIMATION SOURCE for Kael and Ren.
-- Each clip = keyframes (same format as ShowcaseData: keys inherit the previous key, only list what changes)
-- plus gameplay metadata the server reads: dur, loop, chain, markers, move, lift, win, openOnMiss.
--   Pose axes (the fighter faces +X, so f = forward, s = + to the fighter's right, y = height above chest centre):
--   rh/lh hands {f,s,y}; rf/lf feet {f,s,lift}; rp/lp elbow pole; dx/dz body shift; pyaw/twist/lean/crouch/roll/headYaw/headPitch.
--   Angles are degrees, + yaw/pyaw/twist turns LEFT. ease: linear|inout|in2|in3|out2|out3.
-- Markers: { t, name, op = "hit" | "follow" | "slam" | "field" | "pull" | "formset" | "leap", hit = <BGConfig.hits id>, hand = <part> }.
--   Any marker without an op is a pure cue for the client (sparks, rings, afterimage, trail windows ...).
-- move = { from, to, dist, dir = "fwd"|"input"|"side"|"back" } travels the fighter while the clip plays.
-- win  = { kind = "dodge" | "invuln" | "armor", from, to } windows measured from the clip start.
local Clips = {}

local function H(f, s, y) return { f = f, s = s, y = y } end
local function F(f, s, lift) return { f = f, s = s, lift = lift or 0 } end

---------------------------------------------------------------------------------------------- bases
local KBASE = {
	dx = 0, dz = 0, yaw = 0, pyaw = -22, twist = -8, lean = 6, roll = 0, crouch = 0.35,
	headYaw = 0, headPitch = 3, rfYaw = -38, lfYaw = -8, rfPitch = 0, lfPitch = 0,
	rf = F(-0.55, 0.55), lf = F(0.75, -0.35),
	rh = H(0.85, 0.5, 0.8), lh = H(1.15, -0.5, 0.85),
	rp = H(0.2, 0.9, -0.6), lp = H(0.2, -0.9, -0.6),
}
local RBASE = {
	dx = 0, dz = 0, yaw = 0, pyaw = -18, twist = -6, lean = 3, roll = 0, crouch = 0.5,
	headYaw = 0, headPitch = 2, rfYaw = -30, lfYaw = -6, rfPitch = 0, lfPitch = 0,
	rf = F(-0.5, 0.6), lf = F(0.55, -0.4),
	rh = H(0.78, 0.35, 0.95), lh = H(0.95, -0.4, 1.0),               -- elbows tucked, hands near the centreline
	rp = H(0.0, 0.55, -0.85), lp = H(0.0, -0.55, -0.85),
}
Clips.bases = { Kael = KBASE, Ren = RBASE }

---------------------------------------------------------------------------------------------- helpers
local function clip(dur, keys, meta)
	meta = meta or {}
	meta.dur, meta.keys = dur, keys
	meta.markers = meta.markers or {}
	return meta
end
local function hit(t, id, hand, name) return { t = t, name = name or ("contact_" .. id), op = "hit", hit = id, hand = hand } end

-- shared reaction clips, scaled per fighter weight (k = 1 light, 0.7 heavy)
local function reactions(base, k)
	local r = {}
	r.hit = clip(0.5, {
		{ t = 0 },
		{ t = 0.07, ease = "out2", lean = base.lean - 14 * k, headPitch = -12, dx = -0.25 * k, lh = H(0.75, -0.5, 0.55), rh = H(0.6, 0.5, 0.55), crouch = base.crouch - 0.05 },
		{ t = 0.26, ease = "inout", lean = base.lean - 8 * k, dx = -0.15 * k, headPitch = -6 },
		{ t = 0.5, ease = "inout", lean = base.lean - 3, dx = -0.05, headPitch = 0, lh = base.lh, rh = base.rh },
	}, { clamp = true })
	r.knock = clip(0.7, {
		{ t = 0 },
		{ t = 0.1, ease = "out2", lean = base.lean - 24 * k, headPitch = -18, dx = -0.5 * k, crouch = base.crouch - 0.12,
			rh = H(0.2, 1.15, 0.2), lh = H(0.2, -1.15, 0.2), rp = H(0.0, 0.9, -0.2), lp = H(0.0, -0.9, -0.2), rf = F(-0.8, 0.6, 0.25) },
		{ t = 0.4, ease = "inout", lean = base.lean - 14 * k, dx = -0.35 * k, rf = F(-0.8, 0.6, 0) },
		{ t = 0.7, ease = "inout", lean = base.lean - 8, rh = H(0.6, 0.6, 0.5), lh = H(0.7, -0.6, 0.5), rp = base.rp, lp = base.lp },
	}, { clamp = true })
	r.air = clip(0.6, {
		{ t = 0 },
		{ t = 0.12, ease = "out2", lean = -16, crouch = 0.0, headPitch = -14, roll = 6,
			rh = H(0.0, 1.25, 1.2), lh = H(0.0, -1.25, 1.2), rp = H(0.0, 0.9, 0.2), lp = H(0.0, -0.9, 0.2),
			rf = F(-0.4, 0.6, 0.55), lf = F(0.3, -0.4, 0.35) },
		{ t = 0.6, ease = "inout", lean = -30, headPitch = -22, roll = 10, rf = F(-0.6, 0.6, 0.7), lf = F(0.5, -0.4, 0.5) },
	}, { clamp = true })
	r.getup = clip(0.6, {
		{ t = 0, lean = 28, crouch = 0.9, headPitch = 10, lh = H(0.6, -0.6, -0.2), rh = H(0.6, 0.6, -0.2) },
		{ t = 0.35, ease = "out2", lean = 14, crouch = 0.65, headPitch = 4 },
		{ t = 0.6, ease = "inout", lean = base.lean, crouch = base.crouch, headPitch = base.headPitch, lh = base.lh, rh = base.rh },
	})
	r.open = clip(0.5, {
		{ t = 0 },
		{ t = 0.12, ease = "out2", lean = base.lean + 12, crouch = base.crouch - 0.12, lh = H(0.7, -0.6, 0.2), rh = H(0.7, 0.6, 0.2), headPitch = 8 },
		{ t = 0.5, ease = "inout", lean = base.lean + 8, crouch = base.crouch - 0.08 },
	}, { clamp = true })
	r.guard_hit = clip(0.26, {
		{ t = 0 },
		{ t = 0.05, ease = "out2", dx = -0.22 * k, lean = base.lean - 4, headPitch = -3 },
		{ t = 0.26, ease = "inout", dx = 0, lean = base.lean, headPitch = base.headPitch },
	})
	return r
end

local function walk(stride, bob)
	local s = stride
	local keys = {
		{ t = 0,    ease = "linear", lf = F(s, -0.35, 0),    rf = F(-s, 0.55, 0) },
		{ t = 0.15, ease = "linear", lf = F(0, -0.35, 0),    rf = F(0, 0.55, 0.38) },
		{ t = 0.30, ease = "linear", lf = F(-s, -0.35, 0),   rf = F(s, 0.55, 0) },
		{ t = 0.45, ease = "linear", lf = F(0, -0.35, 0.38), rf = F(0, 0.55, 0) },
		{ t = 0.60, ease = "linear", lf = F(s, -0.35, 0),    rf = F(-s, 0.55, 0) },
	}
	return keys
end

---------------------------------------------------------------------------------------------- KAEL
local K = {}
K.idle = clip(2.4, {
	{ t = 0 },
	{ t = 1.2, ease = "inout", crouch = 0.40, lean = 7, dx = 0.05, lh = H(1.15, -0.5, 0.9), headPitch = 2 },
	{ t = 2.4, ease = "inout", crouch = 0.35, lean = 6, dx = 0, lh = H(1.15, -0.5, 0.85), headPitch = 3 },
}, { loop = true })
K.walk = clip(0.6, walk(1.05), { loop = true, walkStride = 2.1 })
K.guard = clip(0.2, {
	{ t = 0 },
	{ t = 0.12, ease = "out2", crouch = 0.45, lean = 4, lh = H(1.0, -0.3, 1.1), rh = H(0.8, 0.3, 1.05), rp = H(0.0, 0.6, -0.8), lp = H(0.0, -0.6, -0.8) },
	{ t = 0.2, ease = "linear" },
}, { clamp = true })

K.m1_1 = clip(0.42, {
	{ t = 0 },
	{ t = 0.06, ease = "out2", lh = H(1.05, -0.45, 0.9), lean = 8 },
	{ t = 0.15, ease = "in2", lh = H(2.0, -0.35, 0.95), twist = -2, lean = 9 },
	{ t = 0.3, ease = "out2", lh = H(1.15, -0.5, 0.85), twist = -8, lean = 6 },
	{ t = 0.42, ease = "inout" },
}, { chain = 0.27, move = { { from = 0.04, to = 0.16, dist = 1.5, dir = "fwd" } },
	markers = { hit(0.15, "kael_jab", "LeftHand", "contact_jab") } })
K.m1_2 = clip(0.5, {
	{ t = 0 },
	{ t = 0.1, ease = "out2", pyaw = -34, twist = -20, crouch = 0.45, rh = H(0.5, 0.75, 0.6) },
	{ t = 0.2, ease = "in2", pyaw = 12, twist = 14, lean = 14, rh = H(2.0, 0.6, 0.9), rfPitch = 25, rfYaw = -16 },
	{ t = 0.35, ease = "out2", pyaw = -18, twist = -8, lean = 8, rh = H(0.9, 0.5, 0.85), rfPitch = 0, rfYaw = -38 },
	{ t = 0.5, ease = "inout", pyaw = -22, lean = 6, rh = H(0.85, 0.5, 0.8) },
}, { chain = 0.3, move = { { from = 0.06, to = 0.2, dist = 1.4, dir = "fwd" } },
	markers = { hit(0.2, "kael_cross", "RightHand", "contact_cross") } })
K.m1_3 = clip(0.58, {
	{ t = 0 },
	{ t = 0.12, ease = "out2", crouch = 0.62, lean = 12, pyaw = -30, twist = -22, lh = H(0.95, -1.2, 0.05), lp = H(0.0, -1.0, -0.2) },
	{ t = 0.22, ease = "in2", crouch = 0.58, lean = 18, pyaw = 6, twist = 10, lh = H(1.55, 0.3, -0.35), lp = H(0.3, -0.7, -0.6) },
	{ t = 0.38, ease = "out2", crouch = 0.42, lean = 9, pyaw = -22, twist = -8, lh = H(1.15, -0.5, 0.85), lp = H(0.2, -0.9, -0.6) },
	{ t = 0.58, ease = "inout", crouch = 0.35, lean = 6 },
}, { chain = 0.34, move = { { from = 0.08, to = 0.22, dist = 1.2, dir = "fwd" } },
	markers = { hit(0.22, "kael_hook", "LeftHand", "contact_hook") } })
K.m1_4 = clip(0.78, {
	{ t = 0 },
	{ t = 0.13, ease = "out2", crouch = 0.68, lean = 10, pyaw = -34, twist = -22, rh = H(0.9, 0.6, -0.5) },
	{ t = 0.26, ease = "in2", crouch = 0.22, lean = 4, pyaw = 10, twist = 12, rh = H(1.9, 0.45, 1.15), rfPitch = 30, rfYaw = -18 },
	{ t = 0.5, ease = "out2", crouch = 0.38, lean = 8, rh = H(1.2, 0.5, 0.9), rfPitch = 8 },
	{ t = 0.78, ease = "inout", pyaw = -22, twist = -8, lean = 6, crouch = 0.35, rh = H(0.85, 0.5, 0.8), rfPitch = 0, rfYaw = -38 },
}, { move = { { from = 0.1, to = 0.28, dist = 1.9, dir = "fwd" } },
	trail = { { from = 0.2, to = 0.4, hand = "RightHand" } },
	markers = { hit(0.26, "kael_palm", "RightHand", "contact_palm") } })

K.flash = clip(0.42, {
	{ t = 0 },
	{ t = 0.06, ease = "out2", crouch = 0.58, lean = 16, headPitch = 8 },
	{ t = 0.16, ease = "linear", crouch = 0.62, lean = 22, lf = F(1.5, -0.35, 0.25), rf = F(-1.2, 0.55, 0.25) },
	{ t = 0.3, ease = "out2", crouch = 0.5, lean = 10, lf = F(0.9, -0.35, 0), rf = F(-0.6, 0.55, 0) },
	{ t = 0.42, ease = "inout" },
}, { move = { { from = 0.06, to = 0.2, dist = 10.0, dir = "input" } },
	markers = { { t = 0.06, name = "afterimage" } } })
K.flash_back = clip(0.42, {
	{ t = 0 },
	{ t = 0.06, ease = "out2", crouch = 0.55, lean = -6 },
	{ t = 0.16, ease = "linear", crouch = 0.6, lean = -12, lf = F(0.2, -0.35, 0.25), rf = F(-1.5, 0.55, 0.25) },
	{ t = 0.3, ease = "out2", crouch = 0.5, lean = 2, lf = F(0.7, -0.35, 0), rf = F(-0.6, 0.55, 0) },
	{ t = 0.42, ease = "inout" },
}, { move = { { from = 0.06, to = 0.2, dist = 7.0, dir = "input" } },
	markers = { { t = 0.06, name = "afterimage" } } })

K.arc = clip(1.0, {
	{ t = 0 },
	{ t = 0.2, ease = "inout", crouch = 0.6, lean = 4, pyaw = -48, twist = -32, rfYaw = -50, rh = H(0.2, 0.9, 0.3), lh = H(1.0, -0.5, 1.0) },
	{ t = 0.45, ease = "linear", crouch = 0.68, pyaw = -52, twist = -36 },
	{ t = 0.62, ease = "in3", crouch = 0.45, lean = 22, pyaw = 20, twist = 22, rfYaw = -8, rfPitch = 35,
		rh = H(2.1, 0.6, 0.85), dx = 0.4, lf = F(1.25, -0.35, 0), rf = F(-0.85, 0.55, 0) },
	{ t = 0.8, ease = "out2", crouch = 0.5, lean = 16, dx = 0.35, rh = H(1.6, 0.5, 0.85), lf = F(1.2, -0.35, 0), rf = F(-0.7, 0.55, 0) },
	{ t = 1.0, ease = "inout", dx = 0, crouch = 0.35, lean = 6, pyaw = -22, twist = -8, rfYaw = -38, rfPitch = 0, rh = H(0.85, 0.5, 0.8),
		lf = F(0.75, -0.35, 0), rf = F(-0.55, 0.55, 0) },
}, { move = { { from = 0.45, to = 0.65, dist = 4.4, dir = "fwd" } }, openOnMiss = 0.6,
	trail = { { from = 0.5, to = 0.8, hand = "RightHand" } },
	markers = { { t = 0.2, name = "windup_charge" }, hit(0.62, "kael_arc", "RightHand", "contact_arc") } })

K.storm = clip(0.95, {
	{ t = 0 },
	{ t = 0.18, ease = "inout", crouch = 0.66, lean = 10, pyaw = -50, twist = -34, rfYaw = -52, rh = H(0.3, 0.7, 0.0), lh = H(1.0, -0.5, 1.0) },
	{ t = 0.4, ease = "linear", crouch = 0.72, pyaw = -54 },
	{ t = 0.54, ease = "in3", crouch = 0.5, lean = 24, pyaw = 18, twist = 25, rfYaw = -8, rfPitch = 35,
		rh = H(2.25, 0.3, 0.8), dx = 0.45, lf = F(1.25, -0.35, 0), rf = F(-0.9, 0.55, 0) },
	{ t = 0.75, ease = "out2", crouch = 0.5, lean = 18, dx = 0.4, rh = H(1.8, 0.3, 0.8), lf = F(1.2, -0.35, 0), rf = F(-0.7, 0.55, 0) },
	{ t = 0.95, ease = "inout", dx = 0, crouch = 0.35, lean = 6, pyaw = -22, twist = -8, rfYaw = -38, rfPitch = 0, rh = H(0.85, 0.5, 0.8),
		lf = F(0.75, -0.35, 0), rf = F(-0.55, 0.55, 0) },
}, { move = { { from = 0.4, to = 0.56, dist = 14.0, dir = "fwd" } }, openOnMiss = 0.7,
	trail = { { from = 0.4, to = 0.8, hand = "RightHand" } },
	markers = { { t = 0.18, name = "windup_charge" }, hit(0.54, "kael_pierce", "RightHand", "contact_pierce") } })

K.sky = clip(0.85, {
	{ t = 0 },
	{ t = 0.12, ease = "out2", crouch = 0.75, lean = 6, pyaw = -30, twist = -18, rh = H(0.7, 0.6, -0.7), lh = H(1.0, -0.5, 0.95) },
	{ t = 0.28, ease = "in2", crouch = 0.15, lean = -4, pyaw = 12, twist = 14, rh = H(1.4, 0.5, 1.6), rfPitch = 30, rfYaw = -18, headPitch = -6 },
	{ t = 0.5, ease = "out2", crouch = 0.3, lean = 2, rh = H(1.1, 0.5, 1.3), headPitch = 0 },
	{ t = 0.85, ease = "inout", crouch = 0.35, lean = 6, pyaw = -22, twist = -8, rh = H(0.85, 0.5, 0.8), rfPitch = 0, rfYaw = -38 },
}, { move = { { from = 0.1, to = 0.3, dist = 1.2, dir = "fwd" } },
	trail = { { from = 0.2, to = 0.45, hand = "RightHand" } },
	markers = { hit(0.28, "kael_sky", "RightHand", "contact_sky") } })
K.sky_follow = clip(0.95, {
	{ t = 0 },
	{ t = 0.14, ease = "out2", crouch = 0.3, lean = -4, rh = H(0.2, 0.4, 1.6), lh = H(0.2, -0.4, 1.6), rp = H(0.0, 0.9, 0.3), lp = H(0.0, -0.9, 0.3),
		lf = F(0.9, -0.35, 0.8), rf = F(-0.1, 0.55, 0.9) },
	{ t = 0.34, ease = "linear", lean = -6 },
	{ t = 0.46, ease = "in3", crouch = 0.2, lean = 22, rh = H(1.4, 0.3, -0.5), lh = H(1.4, -0.3, -0.5), rp = H(0.3, 0.8, -0.2), lp = H(0.3, -0.8, -0.2) },
	{ t = 0.58, ease = "out2", crouch = 0.62, lean = 14, lf = F(1.1, -0.35, 0), rf = F(-0.3, 0.55, 0) },
	{ t = 0.95, ease = "inout", crouch = 0.35, lean = 6, rh = H(0.85, 0.5, 0.8), lh = H(1.15, -0.5, 0.85), rp = H(0.2, 0.9, -0.6), lp = H(0.2, -0.9, -0.6),
		lf = F(0.75, -0.35, 0), rf = F(-0.55, 0.55, 0) },
}, { lift = { { from = 0.08, to = 0.5, h = 2.0 } },
	trail = { { from = 0.36, to = 0.56, hand = "RightHand" } },
	markers = { { t = 0.46, name = "contact_skyfollow", op = "follow", hit = "kael_skyfollow", hand = "RightHand" } } })

K.slip = clip(0.6, {
	{ t = 0 },
	{ t = 0.08, ease = "out2", lean = -10, crouch = 0.55, pyaw = -40, twist = -14, headYaw = 8, dz = 0.2, lh = H(0.9, -0.5, 1.0), rh = H(0.7, 0.5, 0.95) },
	{ t = 0.22, ease = "inout", lean = -14, crouch = 0.6, roll = 8, dz = 0.35 },
	{ t = 0.4, ease = "inout", lean = 4, crouch = 0.45, roll = 0, dz = 0.1, headYaw = 0 },
	{ t = 0.6, ease = "inout", lean = 6, crouch = 0.35, pyaw = -22, twist = -8, dz = 0, lh = H(1.15, -0.5, 0.85), rh = H(0.85, 0.5, 0.8) },
}, { move = { { from = 0.04, to = 0.24, dist = 2.4, dir = "side" } }, win = { { kind = "dodge", from = 0.03, to = 0.34 } },
	markers = { { t = 0.06, name = "slip_whoosh" } } })
K.counter = clip(0.6, {
	{ t = 0 , pyaw = -34, twist = -14, crouch = 0.5, lean = -4, rh = H(0.6, 0.8, 0.8), lh = H(1.0, -0.6, 0.9) },
	{ t = 0.08, ease = "out2", pyaw = -46, twist = -26, lean = 2 },
	{ t = 0.18, ease = "in2", pyaw = 14, twist = 18, lean = 16, crouch = 0.42, rh = H(2.0, 0.6, 0.9), rfPitch = 28, rfYaw = -16 },
	{ t = 0.34, ease = "out2", lean = 10, rh = H(1.2, 0.5, 0.85), rfPitch = 6 },
	{ t = 0.6, ease = "inout", pyaw = -22, twist = -8, lean = 6, crouch = 0.35, rh = H(0.85, 0.5, 0.8), rfPitch = 0, rfYaw = -38 },
}, { move = { { from = 0.08, to = 0.2, dist = 1.0, dir = "fwd" } },
	trail = { { from = 0.12, to = 0.3, hand = "RightHand" } },
	markers = { hit(0.18, "kael_counter", "RightHand", "contact_counter") } })

K.form1_on = clip(1.0, {
	{ t = 0 },
	{ t = 0.2, ease = "inout", crouch = 0.62, lean = 5, rh = H(0.5, 0.2, 0.2), lh = H(0.5, -0.2, 0.2), rp = H(0.0, 0.6, -0.9), lp = H(0.0, -0.6, -0.9), headPitch = 8 },
	{ t = 0.45, ease = "out3", crouch = 0.25, lean = -2, rh = H(0.9, 1.3, 0.5), lh = H(0.9, -1.3, 0.5), rp = H(0.0, 1.0, -0.4), lp = H(0.0, -1.0, -0.4), headPitch = -4 },
	{ t = 0.75, ease = "inout", crouch = 0.4, lean = 5, headPitch = 2 },
	{ t = 1.0, ease = "inout", crouch = 0.35, lean = 6, rh = H(0.85, 0.5, 0.8), lh = H(1.15, -0.5, 0.85), rp = H(0.2, 0.9, -0.6), lp = H(0.2, -0.9, -0.6), headPitch = 3 },
}, { win = { { kind = "invuln", from = 0, to = 1.0 } },
	markers = { { t = 0.2, name = "pulse_gather" }, { t = 0.45, name = "pulse_chest", op = "formset", form = "Form1" }, { t = 0.6, name = "pulse_arms" } } })
K.final_on = clip(1.6, {
	{ t = 0 },
	{ t = 0.3, ease = "inout", crouch = 0.72, lean = 6, rh = H(0.5, 0.2, 0.0), lh = H(0.5, -0.2, 0.0), rp = H(0.0, 0.6, -0.9), lp = H(0.0, -0.6, -0.9) },
	{ t = 0.65, ease = "out3", crouch = 0.1, lean = -8, headPitch = -14, rh = H(0.5, 1.45, 0.9), lh = H(0.5, -1.45, 0.9), rp = H(0.0, 1.0, -0.2), lp = H(0.0, -1.0, -0.2), rf = F(-0.7, 0.8, 0), lf = F(0.7, -0.8, 0) },
	{ t = 1.0, ease = "inout", crouch = 0.2, lean = -3, headPitch = -6 },
	{ t = 1.6, ease = "inout", crouch = 0.35, lean = 6, headPitch = 3, rh = H(0.85, 0.5, 0.8), lh = H(1.15, -0.5, 0.85), rp = H(0.2, 0.9, -0.6), lp = H(0.2, -0.9, -0.6),
		rf = F(-0.55, 0.55, 0), lf = F(0.75, -0.35, 0) },
}, { win = { { kind = "invuln", from = 0, to = 1.6 } },
	markers = { { t = 0.3, name = "pulse_gather" }, { t = 0.65, name = "pulse_chest", op = "formset", form = "Final" }, { t = 0.95, name = "pulse_arms" } } })

K.thunder = clip(2.4, {
	{ t = 0 },
	{ t = 0.4, ease = "inout", crouch = 0.75, lean = 10, pyaw = -34, twist = -20, rh = H(0.6, 0.6, -0.4), lh = H(0.9, -0.5, 0.6) },
	{ t = 0.55, ease = "in2", crouch = 0.2, lean = -2, pyaw = 10, twist = 14, rh = H(1.5, 0.5, 1.65), lh = H(0.9, -0.6, 0.9), rfPitch = 30 },
	{ t = 0.75, ease = "out2", crouch = 0.3, lean = -6, rh = H(0.3, 0.5, 1.7), lh = H(0.3, -0.5, 1.7), rp = H(0.0, 0.9, 0.3), lp = H(0.0, -0.9, 0.3),
		lf = F(0.9, -0.35, 0.8), rf = F(-0.1, 0.55, 0.9), pyaw = -22, twist = -8 },
	{ t = 1.1, ease = "linear", lean = -8 },
	{ t = 1.28, ease = "in3", crouch = 0.2, lean = 26, rh = H(1.4, 0.3, -0.6), lh = H(1.4, -0.3, -0.6), rp = H(0.3, 0.8, -0.2), lp = H(0.3, -0.8, -0.2) },
	{ t = 1.45, ease = "out2", crouch = 0.8, lean = 18, lf = F(1.2, -0.35, 0), rf = F(-0.4, 0.55, 0) },
	{ t = 2.4, ease = "inout", crouch = 0.35, lean = 6, rh = H(0.85, 0.5, 0.8), lh = H(1.15, -0.5, 0.85), rp = H(0.2, 0.9, -0.6), lp = H(0.2, -0.9, -0.6),
		lf = F(0.75, -0.35, 0), rf = F(-0.55, 0.55, 0), pyaw = -22, twist = -8, rfPitch = 0 },
}, { move = { { from = 0.4, to = 0.56, dist = 7.0, dir = "fwd" } }, lift = { { from = 0.6, to = 1.3, h = 4.2 } },
	win = { { kind = "armor", from = 0.3, to = 1.6 } }, ult = true,
	trail = { { from = 0.45, to = 0.75, hand = "RightHand" }, { from = 1.1, to = 1.4, hand = "RightHand" } },
	markers = { { t = 0.3, name = "windup_charge" }, hit(0.55, "kael_thunder_launch", "RightHand", "contact_thunder_launch"),
		{ t = 0.6, name = "leap", op = "leap" },
		{ t = 1.28, name = "contact_thunder_slam", op = "slam", hit = "kael_thunder_slam", hand = "RightHand" } } })
do
	local r = reactions(KBASE, 1)
	for n, c in pairs(r) do K[n] = c end
end

---------------------------------------------------------------------------------------------- REN
local R = {}
R.idle = clip(3.2, {
	{ t = 0 },
	{ t = 1.6, ease = "inout", lean = 4.5, crouch = 0.53, headPitch = 1.5, rh = H(0.78, 0.35, 0.99) },
	{ t = 3.2, ease = "inout", lean = 3, crouch = 0.5, headPitch = 2, rh = H(0.78, 0.35, 0.95) },
}, { loop = true })
R.walk = clip(0.6, walk(0.85), { loop = true, walkStride = 1.7 })
R.guard = clip(0.22, {
	{ t = 0 },
	{ t = 0.13, ease = "out2", crouch = 0.6, lean = 2, lh = H(0.9, -0.2, 1.35), rh = H(0.75, 0.25, 1.2), lp = H(0.0, -0.3, -1.0), rp = H(0.0, 0.3, -1.0) },
	{ t = 0.22, ease = "linear" },
}, { clamp = true })
R.timed_block = clip(0.45, {
	{ t = 0, crouch = 0.6, lean = 2, lh = H(0.9, -0.2, 1.35), rh = H(0.75, 0.25, 1.2), lp = H(0.0, -0.3, -1.0), rp = H(0.0, 0.3, -1.0) },
	{ t = 0.06, ease = "out3", dx = -0.1, lh = H(1.35, 0.1, 1.3), rh = H(1.1, 0.35, 1.25), headPitch = 0 },
	{ t = 0.3, ease = "inout", dx = 0, lh = H(0.9, -0.2, 1.35), rh = H(0.75, 0.25, 1.2) },
	{ t = 0.45, ease = "linear" },
}, { markers = { { t = 0.05, name = "timed_ripple" } } })

R.m1_1 = clip(0.5, {
	{ t = 0 },
	{ t = 0.08, ease = "out2", lh = H(1.0, -0.35, 0.95), lean = 5 },
	{ t = 0.17, ease = "in2", lh = H(1.9, -0.25, 0.95), lean = 6, twist = -4 },
	{ t = 0.32, ease = "out2", lh = H(0.95, -0.4, 1.0), lean = 3, twist = -6 },
	{ t = 0.5, ease = "inout" },
}, { chain = 0.3, move = { { from = 0.05, to = 0.18, dist = 1.2, dir = "fwd" } },
	markers = { hit(0.17, "ren_jab", "LeftHand", "contact_jab") } })
R.m1_2 = clip(0.52, {
	{ t = 0 },
	{ t = 0.1, ease = "out2", pyaw = -30, twist = -16, crouch = 0.56, rh = H(0.5, 0.5, 0.8) },
	{ t = 0.19, ease = "in2", pyaw = 16, twist = 20, lean = 10, rh = H(1.35, 0.45, 1.0), rp = H(0.5, 0.9, -0.2) },
	{ t = 0.34, ease = "out2", pyaw = -18, twist = -6, lean = 3, rh = H(0.8, 0.35, 0.95), rp = H(0.0, 0.55, -0.85) },
	{ t = 0.52, ease = "inout", crouch = 0.5 },
}, { chain = 0.32, move = { { from = 0.06, to = 0.2, dist = 1.1, dir = "fwd" } },
	markers = { hit(0.19, "ren_elbow", "RightHand", "contact_elbow") } })
R.m1_3 = clip(0.66, {
	{ t = 0 },
	{ t = 0.14, ease = "out2", pyaw = -34, twist = -22, crouch = 0.58, rh = H(0.3, 1.0, 1.0), rp = H(0.0, 0.9, -0.5) },
	{ t = 0.29, ease = "in2", pyaw = 40, twist = 30, lean = 8, crouch = 0.5, rh = H(1.6, -0.35, 1.05), rp = H(0.3, 0.8, -0.4), headYaw = 6 },
	{ t = 0.46, ease = "out2", pyaw = -4, twist = 0, lean = 4, rh = H(1.0, 0.2, 1.0) },
	{ t = 0.66, ease = "inout", pyaw = -18, twist = -6, lean = 3, rh = H(0.78, 0.35, 0.95), headYaw = 0, rp = H(0.0, 0.55, -0.85) },
}, { chain = 0.4, move = { { from = 0.1, to = 0.3, dist = 1.3, dir = "fwd" } },
	trail = { { from = 0.2, to = 0.4, hand = "RightHand" } },
	markers = { hit(0.29, "ren_backfist", "RightHand", "contact_backfist") } })
R.m1_4 = clip(1.2, {
	{ t = 0 },
	{ t = 0.35, ease = "inout", crouch = 0.78, lean = 2, pyaw = -40, twist = -28, rh = H(0.3, 0.7, 0.4), lh = H(0.9, -0.5, 1.0) },
	{ t = 0.55, ease = "linear", crouch = 0.84, pyaw = -44 },
	{ t = 0.65, ease = "in3", crouch = 0.52, lean = 16, pyaw = 22, twist = 24, rh = H(2.0, 0.45, 1.0), lf = F(1.3, -0.4, 0), rfPitch = 25 },
	{ t = 0.85, ease = "out2", crouch = 0.62, lean = 12, rh = H(1.7, 0.4, 1.0) },
	{ t = 1.2, ease = "inout", crouch = 0.5, lean = 3, pyaw = -18, twist = -6, rh = H(0.78, 0.35, 0.95), lf = F(0.55, -0.4, 0), rfPitch = 0 },
}, { move = { { from = 0.45, to = 0.67, dist = 2.2, dir = "fwd" } }, anticipation = { 0.2, 0.6 },
	trail = { { from = 0.58, to = 0.85, hand = "RightHand" } },
	markers = { { t = 0.3, name = "anticipation_set" }, hit(0.65, "ren_palm", "RightHand", "contact_palm") } })

R.anchor = clip(2.3, {
	{ t = 0 },
	{ t = 0.22, ease = "out2", crouch = 0.92, lean = 0, pyaw = 0, twist = 0, rfYaw = 0, lfYaw = 0, headPitch = 4,
		lf = F(0.8, -0.65, 0), rf = F(-0.8, 0.85, 0), rh = H(0.8, 0.8, 0.5), lh = H(0.9, -0.8, 0.5), rp = H(0.0, 0.9, -0.5), lp = H(0.0, -0.9, -0.5) },
	{ t = 1.75, ease = "linear", crouch = 0.95 },
	{ t = 1.9, ease = "out3", crouch = 0.55, lean = 14, rh = H(1.75, 0.45, 0.95), lh = H(1.75, -0.45, 0.95), rp = H(0.3, 0.8, -0.3), lp = H(0.3, -0.8, -0.3) },
	{ t = 2.3, ease = "inout", crouch = 0.5, lean = 3, pyaw = -18, twist = -6, rfYaw = -30, lfYaw = -6, headPitch = 2,
		lf = F(0.55, -0.4, 0), rf = F(-0.5, 0.6, 0), rh = H(0.78, 0.35, 0.95), lh = H(0.95, -0.4, 1.0), rp = H(0.0, 0.55, -0.85), lp = H(0.0, -0.55, -0.85) },
}, { win = { { kind = "armor", from = 0.2, to = 1.75 } }, noMove = true,
	markers = { { t = 0.22, name = "anchor_plant" }, { t = 1.9, name = "anchor_release" } } })
R.pulse = clip(1.05, {
	{ t = 0 },
	{ t = 0.28, ease = "out2", crouch = 0.4, lean = -2, rh = H(0.5, 0.6, 1.55), rp = H(0.0, 0.8, -0.3) },
	{ t = 0.5, ease = "in3", crouch = 0.88, lean = 22, rh = H(1.4, 0.3, -0.9), lh = H(0.9, -0.5, 0.5), rp = H(0.3, 0.7, -0.3) },
	{ t = 0.7, ease = "linear", crouch = 0.9 },
	{ t = 1.05, ease = "inout", crouch = 0.5, lean = 3, rh = H(0.78, 0.35, 0.95), lh = H(0.95, -0.4, 1.0), rp = H(0.0, 0.55, -0.85) },
}, { trail = { { from = 0.36, to = 0.56, hand = "RightHand" } },
	markers = { { t = 0.28, name = "pulse_raise" }, { t = 0.5, name = "contact_pulse", op = "hit", hit = "ren_pulse", hand = "RightHand", fx = "ring_ground" } } })
R.void_counter = clip(0.85, {
	{ t = 0, crouch = 0.6, lean = 2, lh = H(0.9, -0.2, 1.35), rh = H(0.75, 0.25, 1.2), lp = H(0.0, -0.3, -1.0), rp = H(0.0, 0.3, -0.9) },
	{ t = 0.1, ease = "out2", pyaw = -30, twist = -20, lh = H(1.0, -0.95, 1.1), crouch = 0.55, rh = H(0.5, 0.6, 0.9) },
	{ t = 0.24, ease = "in2", pyaw = 20, twist = 24, lean = 14, crouch = 0.5, rh = H(1.95, 0.3, 1.0), lh = H(0.8, -0.4, 1.0) },
	{ t = 0.4, ease = "out2", lean = 8, rh = H(1.3, 0.35, 1.0) },
	{ t = 0.85, ease = "inout", pyaw = -18, twist = -6, lean = 3, crouch = 0.5, rh = H(0.78, 0.35, 0.95), lh = H(0.95, -0.4, 1.0) },
}, { move = { { from = 0.12, to = 0.26, dist = 1.2, dir = "fwd" } },
	trail = { { from = 0.1, to = 0.32, hand = "LeftHand" }, { from = 0.18, to = 0.38, hand = "RightHand" } },
	markers = { { t = 0.1, name = "redirect_arc" }, hit(0.24, "ren_counter", "RightHand", "contact_counter") } })

R.rift_on = clip(1.1, {
	{ t = 0 },
	{ t = 0.22, ease = "inout", crouch = 0.88, pyaw = 0, twist = 0, lean = 0, rh = H(0.6, -0.2, 0.9), lh = H(0.6, 0.2, 0.9), rp = H(0.0, 0.5, -0.8), lp = H(0.0, -0.5, -0.8) },
	{ t = 0.5, ease = "out3", crouch = 0.92, rh = H(0.7, 1.1, 0.4), lh = H(0.7, -1.1, 0.4), rp = H(0.0, 1.0, -0.4), lp = H(0.0, -1.0, -0.4) },
	{ t = 0.8, ease = "inout", crouch = 0.7 },
	{ t = 1.1, ease = "inout", crouch = 0.5, lean = 3, pyaw = -18, twist = -6, rh = H(0.78, 0.35, 0.95), lh = H(0.95, -0.4, 1.0), rp = H(0.0, 0.55, -0.85), lp = H(0.0, -0.55, -0.85) },
}, { win = { { kind = "invuln", from = 0, to = 1.1 } }, noMove = true,
	markers = { { t = 0.22, name = "pulse_gather" }, { t = 0.5, name = "pulse_forearms", op = "formset", form = "Form1" } } })
R.eclipse_on = clip(1.7, {
	{ t = 0 },
	{ t = 0.4, ease = "inout", crouch = 0.95, pyaw = 0, twist = 0, lean = 0, rh = H(0.5, 0.5, 0.2), lh = H(0.5, -0.5, 0.2), rp = H(0.0, 0.6, -0.9), lp = H(0.0, -0.6, -0.9) },
	{ t = 0.85, ease = "out3", crouch = 0.4, lean = -4, headPitch = -10, rh = H(0.5, 1.25, 1.4), lh = H(0.5, -1.25, 1.4), rp = H(0.0, 1.0, 0.0), lp = H(0.0, -1.0, 0.0) },
	{ t = 1.1, ease = "inout", crouch = 0.55, headPitch = -4 },
	{ t = 1.7, ease = "inout", crouch = 0.5, lean = 3, pyaw = -18, twist = -6, headPitch = 2, rh = H(0.78, 0.35, 0.95), lh = H(0.95, -0.4, 1.0), rp = H(0.0, 0.55, -0.85), lp = H(0.0, -0.55, -0.85) },
}, { win = { { kind = "invuln", from = 0, to = 1.7 } }, noMove = true,
	markers = { { t = 0.4, name = "pulse_gather" }, { t = 0.85, name = "pulse_forearms", op = "formset", form = "Final" }, { t = 1.1, name = "pulse_orbit" } } })

R.horizon = clip(3.4, {
	{ t = 0 },
	{ t = 0.5, ease = "out2", crouch = 0.45, lean = -2, rh = H(0.5, 1.25, 1.5), lh = H(0.5, -1.25, 1.5), rp = H(0.0, 1.0, 0.0), lp = H(0.0, -1.0, 0.0) },
	{ t = 1.7, ease = "linear", crouch = 0.4, lean = -3 },
	{ t = 1.85, ease = "in3", crouch = 0.92, lean = 22, rh = H(1.2, 0.4, -0.9), lh = H(1.2, -0.4, -0.9), rp = H(0.3, 0.7, -0.3), lp = H(0.3, -0.7, -0.3) },
	{ t = 2.2, ease = "linear", crouch = 0.95 },
	{ t = 3.4, ease = "inout", crouch = 0.5, lean = 3, pyaw = -18, twist = -6, rh = H(0.78, 0.35, 0.95), lh = H(0.95, -0.4, 1.0), rp = H(0.0, 0.55, -0.85), lp = H(0.0, -0.55, -0.85) },
}, { noMove = true, ult = true, win = { { kind = "armor", from = 0.2, to = 2.2 } },
	markers = {
		{ t = 0.3, name = "field_open", op = "field", dur = 1.5 },
		{ t = 0.6, name = "pull1", op = "pull" }, { t = 0.8, name = "pull2", op = "pull" }, { t = 1.0, name = "pull3", op = "pull" },
		{ t = 1.2, name = "pull4", op = "pull" }, { t = 1.4, name = "pull5", op = "pull" }, { t = 1.6, name = "pull6", op = "pull" },
		{ t = 1.85, name = "contact_horizon_blast", op = "hit", hit = "ren_horizon_blast", hand = "RightHand", fx = "ring_ground" },
	} })
do
	local r = reactions(RBASE, 0.7)
	for n, c in pairs(r) do R[n] = c end
end

Clips.Kael, Clips.Ren = K, R

-- SPEED: the keyframes above are authored at "1.0"; the game plays them faster (k < 1 shortens every non-looping clip:
-- keys, markers, move / lift / window times). Change DEFAULT_SPEED to taste, or call Clips.setSpeed(1) for the authored timing.
Clips.DEFAULT_SPEED = 0.78
local function deep(t)
	if type(t) ~= "table" then return t end
	local r = {}
	for k, v in pairs(t) do r[k] = deep(v) end
	return r
end
local ORIG = { Kael = deep(K), Ren = deep(R) }
local function scaleClip(c, k)
	c.dur = c.dur * k
	for _, key in ipairs(c.keys) do key.t = key.t * k end
	for _, mk in ipairs(c.markers) do mk.t = mk.t * k end
	if c.chain then c.chain = c.chain * k end
	for _, list in ipairs({ c.move or {}, c.lift or {}, c.win or {}, c.trail or {} }) do
		for _, x in ipairs(list) do x.from, x.to = x.from * k, x.to * k end
	end
	if c.anticipation then c.anticipation = { c.anticipation[1] * k, c.anticipation[2] * k } end
end
function Clips.setSpeed(k)
	for char, set in pairs(ORIG) do
		for name, c in pairs(set) do
			local n = deep(c)
			if not n.loop and k ~= 1 then scaleClip(n, k) end
			Clips[char][name] = n
		end
	end
	Clips.speed = k
end
Clips.setSpeed(Clips.DEFAULT_SPEED)

-- Engine data for one fighter (what BGEngine.bake wants): every clip becomes a named track.
function Clips.engineData(char)
	local fighters = {}
	for name, c in pairs(Clips[char]) do
		fighters[name] = { baseYaw = -90, anchor = { x = 0, z = 0 }, base = Clips.bases[char], keys = c.keys }
	end
	return { fighters = fighters, contacts = {} }
end

return Clips
