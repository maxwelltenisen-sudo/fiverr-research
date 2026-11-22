-- BGConfig (ModuleScript, ReplicatedStorage): every tunable number. Times in seconds, distances in studs.
-- Nothing in BGCore or the clips hard-codes a damage, range, cooldown, threshold or timer: change them here.
local C = {}

C.arena = { radius = 15, minGap = 2.1, spawn = 4.2 }
C.hpMax = 100
C.koRefill = 1.6                 -- seconds after reaching 0 HP before the practice fighter refills

C.meter = {
	max = 100,
	form1 = 50,                  -- Charged Mode / Rift Mode threshold
	final = 100,                 -- Thunder Ascension / Eclipse Form threshold
	drain = 4,                   -- meter per second drained toward 50 while in the first form
	form1Surge = 25,             -- activating the first form lifts the meter to at least form1 + this, so it does not end instantly
	finalDuration = 12,          -- seconds the final form lasts
}

C.guard = {
	arc = 110,                   -- degrees in front of the defender that a block covers
	blockMult = 0.15,            -- damage kept when blocked
	timedWindow = 0.25,          -- seconds after pressing guard that count as a timed block (Ren only)
	riposteWindow = 1.0,         -- seconds Ren has to press the counter after a timed block
	timedStagger = { Base = 0.55, Form1 = 0.95, Final = 0.95 },   -- stagger put on the attacker
	blockPush = 0.6,
}

C.slip = { counterWindow = 1.1 } -- seconds Kael can press the counter after a clean dodge
C.openDamageMult = 1.25          -- damage multiplier while "open" (after a missed Arc Breaker / Storm Pierce)
C.eclipseCounterMult = 1.6       -- stored Eclipse Guard energy multiplies the next Void Counter
C.combo = { reset = 0.8, buffer = 0.45 }   -- a press this long before the chain point still counts (forgiving spam)

-- meter gains
C.gain = { block = 3, timedBlock = 12, dodge = 10, counterLanded = 6 }

C.char = {
	Kael = { walk = 10.0, backWalk = 7.0, guardWalk = 3.6, turn = 900 },
	Ren  = { walk = 8.2, backWalk = 5.8, guardWalk = 3.0, turn = 720 },
}

-- Cooldowns (seconds) for each skill id.
C.cd = {
	Kael = { flash = 4.0, arc = 7.0, sky = 9.0, slip = 5.0, ult = 0 },
	Ren  = { anchor = 8.0, pulse = 9.0, ult = 0 },
}
C.flash = { charges = 1, chargesForm = 2 }   -- Flash Step charges in base / Charged Mode

-- Hits. range = centre-to-centre distance, arc = total cone in degrees (360 = all around).
-- stagger1 overrides stagger while the attacker is in a power form. mg = meter gained when it lands.
C.hits = {
	kael_jab    = { dmg = 4,  range = 3.5, arc = 100, stagger = 0.28, mg = 4 },
	kael_cross  = { dmg = 5,  range = 3.6, arc = 100, stagger = 0.30, mg = 4 },
	kael_hook   = { dmg = 6,  range = 3.5, arc = 110, stagger = 0.34, mg = 5 },
	kael_palm   = { dmg = 8,  range = 3.7, arc = 100, stagger = 0.60, push = 7.0, mg = 7 },   -- final hit pushes
	kael_arc    = { dmg = 12, range = 5.4, arc = 90,  stagger = 0.90, stagger1 = 1.25, mg = 10 },
	kael_sky    = { dmg = 7,  range = 3.7, arc = 100, launch = true, airTime = 1.0, airH = 3.6, mg = 8 },
	kael_skyfollow = { dmg = 10, mg = 8, stagger = 0.8 },
	kael_counter = { dmg = 9, range = 4.0, arc = 120, stagger = 0.7, mg = 8 },
	kael_pierce = { dmg = 15, range = 6.5, arc = 80,  stagger = 1.0, push = 3.5, mg = 12 },
	kael_thunder_launch = { dmg = 8, range = 5.5, arc = 130, launch = true, airTime = 1.5, airH = 5.0, unblockable = true, mg = 0 },
	kael_thunder_slam = { dmg = 30, range = 5.5, arc = 360, stagger = 1.3, area = true, unblockable = true, mg = 0 },

	ren_jab     = { dmg = 4,  range = 3.4, arc = 100, stagger = 0.28, mg = 4 },
	ren_elbow   = { dmg = 5,  range = 3.2, arc = 110, stagger = 0.30, mg = 4 },
	ren_backfist = { dmg = 6, range = 3.6, arc = 120, stagger = 0.34, mg = 5 },
	ren_palm    = { dmg = 11, range = 3.6, arc = 100, stagger = 0.75, push = 6.0, mg = 8 },
	ren_pulse   = { dmg = 6,  range = 5.5, range1 = 6.8, arc = 360, push = 6.0, stagger = 0.5, area = true, mg = 8 },
	ren_counter = { dmg = 12, range = 6.5, arc = 180, stagger = 1.0, push = 3.0, mg = 8 },
	ren_horizon_blast = { dmg = 28, range = 12, arc = 360, push = 7.0, stagger = 1.3, area = true, unblockable = true, mg = 0 },
}
C.horizon = { radius = 12, pullSpeed = 6 }    -- Event Horizon field radius and inward pull (studs per second)

-- Power forms make the fighter hit harder, move faster and swing faster (tempo scales the action clock).
C.form = {
	Form1 = { dmg = 1.15, tempo = 1.15, speed = 1.12 },
	Final = { dmg = 1.4,  tempo = 1.3,  speed = 1.25 },
}
-- Hit-stop: both fighters freeze for a few frames on a landed hit (this is most of what makes a punch feel heavy).
C.hitstop = { light = 0.05, big = 0.095, block = 0.03 }

C.transformInvuln = 1.0
C.knocked = 0.55                  -- getting-up time after a launch lands

-- Practice dummy behaviour.
C.ai = { interval = 2.6, approachRange = 3.6 }

return C
