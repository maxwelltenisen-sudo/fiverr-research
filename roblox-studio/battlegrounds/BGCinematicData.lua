-- BGCinematicData (ModuleScript, ReplicatedStorage): THE EDITABLE ANIMATION SOURCE.
-- Times are seconds. Keys inherit everything from the previous key; list only what changes.
-- Axes: stage X runs Blue -> Purple. Angles in degrees. yaw/pyaw/twist: + = turn left (counter-clockwise from above).
-- Hands rh/lh = {f=forward, s=side (+ = fighter's right), y=height above chest centre}.
-- Feet rf/lf  = {f, s, lift}. A foot only moves when its key lists rf/lf; otherwise it stays planted.
-- Poles rp/lp = direction the elbow points (same axes). ease: linear | inout | in2 | in3 | out2 | out3.
local D = {}

D.duration = 10.4

D.fighters = {
	Blue = {
		baseYaw = -90, anchor = { x = -1.5, z = -0.2 },       -- anchor is re-solved at the clash
		base = {
			dx = -1.9, dz = 0, yaw = 0, pyaw = -22, twist = -8, lean = 6, roll = 0, crouch = 0.35,
			headYaw = 0, headPitch = 3,
			rfYaw = -38, lfYaw = -8, rfPitch = 0, lfPitch = 0,
			rf = { f = -0.55, s = 0.55, lift = 0 }, lf = { f = 0.75, s = -0.35, lift = 0 },
			rh = { f = 0.85, s = 0.5, y = 0.8 }, lh = { f = 1.15, s = -0.5, y = 0.85 },
			rp = { f = 0.2, s = 0.9, y = -0.6 }, lp = { f = 0.2, s = -0.9, y = -0.6 },
		},
		keys = {
			{ t = 0.0,  name = "guard" },
			{ t = 0.55, name = "guard_shift_a", dx = -1.83, crouch = 0.42, lean = 7, lh = { f = 1.15, s = -0.5, y = 0.92 } },
			{ t = 1.1,  name = "guard_shift_b", dx = -1.96, crouch = 0.3, lean = 5, lh = { f = 1.15, s = -0.5, y = 0.8 } },
			{ t = 1.5,  name = "stepIn_lead_lift", dx = -1.55, lean = 10, crouch = 0.4,
				lf = { f = 0.9, s = -0.35, lift = 0.4 } },
			{ t = 1.8,  name = "stepIn_lead_plant", dx = -1.2, lf = { f = 1.3, s = -0.35, lift = 0 } },
			{ t = 2.05, name = "stepIn_rear_lift_jab_load", dx = -0.9, lh = { f = 0.9, s = -0.5, y = 0.85 },
				rf = { f = -0.2, s = 0.55, lift = 0.35 } },
			{ t = 2.3,  name = "jab", ease = "in2", dx = -0.5, twist = -2, rf = { f = -0.5, s = 0.55, lift = 0 },
				lh = { f = 2.0, s = -0.35, y = 0.95 } },
			{ t = 2.6,  name = "jab_retract", ease = "out2", twist = -8, lh = { f = 1.15, s = -0.5, y = 0.85 } },
			{ t = 2.9,  name = "rear_load", pyaw = -42, twist = -26, crouch = 0.55, lean = 8, dx = -0.62,
				rfYaw = -46, rh = { f = 0.5, s = 0.75, y = 0.45 } },
			{ t = 3.5,  name = "rear_drive", ease = "in2", pyaw = -6, twist = 4, crouch = 0.42, lean = 14, dx = -0.22,
				rfYaw = -16, rfPitch = 22, rh = { f = 1.2, s = 0.6, y = 0.8 } },
			{ t = 4.0,  name = "CONTACT", ease = "in3", pyaw = 14, twist = 18, lean = 18, dx = 0, rfYaw = -4, rfPitch = 34,
				headPitch = 6, lh = { f = 1.0, s = -0.7, y = 0.8 }, rh = { f = 2.0, s = 0.6, y = 0.9 } },    -- rh is baked from the defender's forearm
			{ t = 4.12, name = "contact_absorb", ease = "out2", lean = 15, dx = -0.07, twist = 15, headPitch = 8,
				lh = { f = 1.0, s = -0.7, y = 0.8 }, rh = { f = 1.9, s = 0.6, y = 0.9 } },
			{ t = 4.6,  name = "clash_hold_end", ease = "linear" },
			{ t = 4.95, name = "pull_back", ease = "out2", pyaw = -10, twist = 0, lean = 10, dx = -0.16, rfYaw = -20, rfPitch = 10,
				headPitch = 3, rh = { f = 0.85, s = 0.55, y = 0.85 } },
			{ t = 5.15, name = "HIT_REACT", ease = "in2", pyaw = 8, twist = -16, lean = 1, dx = -0.12, headPitch = -14, headYaw = 12,
				crouch = 0.3, lh = { f = 0.8, s = -0.7, y = 0.6 }, rh = { f = 0.7, s = 0.7, y = 0.6 } },
			{ t = 5.55, name = "recoil", ease = "out2", pyaw = -4, twist = -10, lean = -3, dx = -0.9, crouch = 0.25,
				headPitch = -8, headYaw = 4, lh = { f = 0.95, s = -0.6, y = 0.75 }, rh = { f = 0.85, s = 0.55, y = 0.8 } },
			{ t = 5.8,  name = "recover_step_lift", dx = -1.0, rf = { f = -0.35, s = 0.55, lift = 0.35 }, rfPitch = 0, rfYaw = -30 },
			{ t = 6.1,  name = "recover_step_plant", dx = -1.1, lean = 6, pyaw = -18, twist = -8,
				rf = { f = -0.65, s = 0.55, lift = 0 }, rfYaw = -38, headPitch = 3, headYaw = 0 },
			{ t = 6.4,  name = "return_lead_lift", dx = -1.55, lf = { f = 0.55, s = -0.35, lift = 0.3 } },
			{ t = 6.7,  name = "return_lead_plant", dx = -1.9, pyaw = -22, crouch = 0.35, lf = { f = 0.75, s = -0.35, lift = 0 } },
			{ t = 7.0,  name = "return_rear_lift", rf = { f = -0.2, s = 0.55, lift = 0.3 } },
			{ t = 7.3,  name = "return_guard", rf = { f = -0.55, s = 0.55, lift = 0 },
				rh = { f = 0.85, s = 0.5, y = 0.8 }, lh = { f = 1.15, s = -0.5, y = 0.85 } },
			{ t = 8.6,  name = "guard_shift_c", dx = -1.94, crouch = 0.4, lean = 7 },
			{ t = 10.4, name = "guard_end", dx = -1.9, crouch = 0.35, lean = 6 },
		},
	},
	Purple = {
		baseYaw = 90, anchor = { x = 1.3, z = 0.0 },
		base = {
			dx = 0, dz = 0, yaw = 0, pyaw = -18, twist = -6, lean = 3, roll = 0, crouch = 0.5,
			headYaw = 0, headPitch = 2,
			rfYaw = -30, lfYaw = -6, rfPitch = 0, lfPitch = 0,
			rf = { f = -0.5, s = 0.6, lift = 0 }, lf = { f = 0.55, s = -0.4, lift = 0 },
			rh = { f = 0.85, s = 0.5, y = 0.95 }, lh = { f = 1.0, s = -0.55, y = 1.0 },
			rp = { f = 0.2, s = 0.9, y = -0.6 }, lp = { f = 0.2, s = -0.9, y = -0.6 },
		},
		keys = {
			{ t = 0.0,  name = "guard" },
			{ t = 0.55, name = "guard_shift_a", dx = 0.05, crouch = 0.56, lean = 4 },
			{ t = 1.1,  name = "guard_shift_b", dx = -0.04, crouch = 0.46, lean = 3 },
			{ t = 1.8,  name = "tighten", crouch = 0.54, lean = 4, headYaw = 0 },
			{ t = 2.3,  name = "jab_slip", ease = "out2", dx = 0.12, lean = 1, headYaw = -8, headPitch = 4, crouch = 0.58 },
			{ t = 2.8,  name = "jab_reset", ease = "inout", dx = 0, lean = 3, headYaw = 0, headPitch = 2, crouch = 0.5 },
			{ t = 3.5,  name = "block_set", pyaw = -24, twist = -10, crouch = 0.58, lean = 4,
				lh = { f = 0.75, s = -0.75, y = 0.8 }, lp = { f = 0.7, s = -0.3, y = -0.7 } },
			{ t = 4.0,  name = "CONTACT", ease = "out2", dx = 0.04, twist = -12 },
			{ t = 4.12, name = "block_absorb", ease = "out2", dx = 0.2, twist = -22, pyaw = -30, lean = 1, headYaw = 6, crouch = 0.62 },
			{ t = 4.6,  name = "clash_hold_end", ease = "linear" },
			{ t = 4.85, name = "counter_load", ease = "inout", pyaw = -38, twist = -20, dx = 0.1,
				rfYaw = -42, rh = { f = 0.6, s = 0.7, y = 0.75 }, lh = { f = 0.95, s = -0.7, y = 0.9 } },
			{ t = 5.15, name = "COUNTER_HIT", ease = "in2", pyaw = 32, twist = 24, lean = 17, dx = -0.7, crouch = 0.46,
				rfYaw = -8, rfPitch = 12, headYaw = 0, headPitch = 4,
				rh = { f = 1.8, s = 0.4, y = 0.8 }, lh = { f = 0.9, s = -0.8, y = 0.8 } },
			{ t = 5.4,  name = "counter_follow", ease = "out2", dx = -0.55, lean = 14, rh = { f = 2.75, s = 0.2, y = 0.5 } },
			{ t = 6.0,  name = "counter_recover", ease = "inout", pyaw = -18, twist = -6, lean = 3, dx = 0, crouch = 0.5,
				rfYaw = -30, rfPitch = 0, rh = { f = 0.85, s = 0.5, y = 0.95 }, lh = { f = 1.0, s = -0.55, y = 1.0 } },
			{ t = 8.6,  name = "guard_shift_c", dx = 0.04, crouch = 0.55, lean = 4 },
			{ t = 10.4, name = "guard_end", dx = 0, crouch = 0.5, lean = 3 },
		},
	},
}

-- Contacts. "guard": the attacker's fist meets the defender's raised forearm (attacker anchor is solved).
-- "chest": the attacker's fist lands on the defender's upper torso front.
D.contacts = {
	{ id = "clash", kind = "guard", t = 4.0, attacker = "Blue", hand = "R", defender = "Purple", arm = "L",
		guardRadius = 0.62, fist = 0.3, reach = 0.52 },
	{ id = "counter", kind = "chest", t = 5.15, attacker = "Purple", hand = "R", defender = "Blue",
		surface = 0.45, up = 0.35 },
}

-- Animation markers (named events the Director fires; also the VFX cues).
D.markers = {
	{ t = 0.0,  name = "start" },
	{ t = 1.5,  name = "step_in" },
	{ t = 2.3,  name = "jab_peak" },
	{ t = 3.5,  name = "rear_drive_start" },
	{ t = 4.0,  name = "contact" },
	{ t = 4.6,  name = "clash_release" },
	{ t = 5.15, name = "counter_contact" },
	{ t = 6.1,  name = "recover_step" },
	{ t = 7.3,  name = "back_in_guard" },
}

-- VFX windows and bursts (all skipped when VFX is off).
D.vfx = {
	trails = {
		{ fighter = "Blue", part = "LeftHand",  from = 2.05, to = 2.65 },
		{ fighter = "Blue", part = "RightHand", from = 3.3,  to = 4.15 },
	},
	bursts = {
		{ marker = "contact",         contact = 1, color = Color3.fromRGB(175, 90, 255), size = 1.0 },
		{ marker = "counter_contact", contact = 2, color = Color3.fromRGB(175, 90, 255), size = 0.55 },
	},
}

-- Cameras. rel = "contact1" places the camera relative to the clash point.
D.cameras = {
	{ t = 0.0,  pos = Vector3.new(-0.4, 3.6, 12.5), look = Vector3.new(-0.4, 3.0, 0),  fov = 36 },
	{ t = 1.5,  pos = Vector3.new(-3.4, 3.0, 8.5),  look = Vector3.new(-1.9, 3.0, 0),  fov = 38 },
	{ t = 2.6,  pos = Vector3.new(-5.4, 2.4, 5.6),  look = Vector3.new(-1.8, 3.4, 0),  fov = 40, roll = -3 },
	{ t = 3.5,  pos = Vector3.new(-1.0, 3.4, 8.0),  look = Vector3.new(-0.8, 3.4, 0),  fov = 34 },
	{ t = 3.95, rel = "contact1", off = Vector3.new(0.2, 0.1, 6.0), fov = 24 },            -- angle A: side
	{ t = 4.3,  rel = "contact1", off = Vector3.new(0.6, 5.6, 2.6), fov = 30 },            -- angle B: high
	{ t = 4.6,  pos = Vector3.new(-0.2, 2.6, 8.0),  look = Vector3.new(-0.2, 3.4, 0),  fov = 36, roll = 2 },
	{ t = 5.5,  pos = Vector3.new(-3.0, 3.2, 7.5),  look = Vector3.new(-2.3, 3.2, 0),  fov = 36 },
	{ t = 7.0,  pos = Vector3.new(-0.4, 3.6, 12.5), look = Vector3.new(-0.4, 3.0, 0),  fov = 36 },
}

-- Verification cameras for the contact inspector (key C).
D.verifyCameras = {
	A = { rel = "contact1", off = Vector3.new(0, 0, 5.5), fov = 20 },     -- side: checks X and height alignment
	B = { rel = "contact1", off = Vector3.new(0, 5.5, 0.01), fov = 20 },  -- top-down: checks X and Z alignment
}

D.colors = {
	blue = Color3.fromRGB(60, 150, 255),
	violet = Color3.fromRGB(175, 90, 255),
}

return D
