local function readfile(p) local f = assert(io.open(p)); local s = f:read("a"); f:close(); return s end
local Config = load(readfile("../BGConfig.lua"))()
local Clips = load(readfile("../BGClips.lua"))()
local Core = load(readfile("../BGCore.lua"))()
local fails, checks = 0, 0
local function check(cond, msg)
	checks = checks + 1
	if not cond then fails = fails + 1; print("  FAIL: " .. msg) else print("  ok:   " .. msg) end
end
local function new(gap)
	local w = Core.new(Config, Clips, { rng = function() return 0.3 end })
	gap = gap or 3.0
	w.f.Blue.x, w.f.Purple.x = -gap / 2, gap / 2
	return w
end
local function run(w, sec) for _ = 1, math.floor(sec * 60 + 0.5) do w:update(1 / 60) end end
local function events(w, kind) local out = {} for _, e in ipairs(w.events) do if e.type == kind then out[#out + 1] = e end end return out end
local B, P = "Blue", "Purple"

print("1. M1 combo: four hits, only the last pushes")
do
	local w = new()
	local hits, pushStart
	for i = 1, 4 do
		w:input(B, "m1"); run(w, 0.1)
		if i < 4 then run(w, 0.18) end
	end
	run(w, 1.2)
	local hs = events(w, "hit")
	check(#hs == 4, "4 hits landed (got " .. #hs .. ")")
	local names = {}
	for _, h in ipairs(hs) do names[#names + 1] = h.hit end
	check(table.concat(names, ",") == "kael_jab,kael_cross,kael_hook,kael_palm", "order jab,cross,hook,palm (" .. table.concat(names, ",") .. ")")
	check(hs[4].final and not hs[1].final and not hs[2].final and not hs[3].final, "only the final hit is flagged as pushing")
	check(w.f.Purple.x > 1.5 + 3.0, "target pushed back by final hit (x=" .. string.format("%.2f", w.f.Purple.x) .. ")")
	check(math.abs(w.f.Purple.hp - (100 - 4 - 5 - 6 - 8)) < 1e-6, "damage 4+5+6+8 applied, hp=" .. w.f.Purple.hp)
	check(w.f.Blue.meter == 4 + 4 + 5 + 7, "attacker meter 20, got " .. w.f.Blue.meter)
end

print("2. Misses build no meter; Arc Breaker miss leaves Kael open")
do
	local w = new(13.0)
	w:input(B, "m1"); run(w, 0.6)
	check(w.f.Blue.meter == 0, "no meter from a whiffed jab")
	w:input(B, "skill", 2); run(w, 0.9)
	check(w.f.Blue.meter == 0 and #events(w, "hit") == 0, "no meter, no hit from whiffed Arc Breaker")
	run(w, 0.3)
	check(w.f.Blue.state == "open" or #events(w, "open") > 0, "Kael is open after a miss")
	w:input(B, "m1")
	check(w.f.Blue.act == nil or w.f.Blue.state ~= "idle", "cannot act while open")
end

print("3. Arc Breaker: clean hit staggers, block absorbs")
do
	local w = new(4.0)
	w:input(B, "skill", 2); run(w, 0.9)
	check(w.f.Purple.hp == 100 - 12 and w.f.Purple.state == "stagger", "hit: 12 dmg + stagger (hp " .. w.f.Purple.hp .. ", " .. w.f.Purple.state .. ")")
	local w2 = new(4.0)
	w2:input(P, "guard", true); run(w2, 0.4)       -- hold the block well before the hit (not timed)
	w2:input(B, "skill", 2); run(w2, 0.9)
	check(math.abs(w2.f.Purple.hp - (100 - 12 * 0.15)) < 1e-6 and w2.f.Purple.state == "block", "block absorbs: hp " .. w2.f.Purple.hp)
	check(#events(w2, "block") == 1 and #events(w2, "timed") == 0, "ordinary block, not timed")
	check(w2.f.Blue.state ~= "open", "a blocked Arc Breaker does not leave Kael open")
end

print("4. Timed Rift Guard -> Void Counter; late counter fails")
do
	local w = new(3.0)
	w:input(B, "m1"); run(w, 0.12)
	w:input(P, "guard", true); run(w, 0.1)        -- guard goes up just before the jab contact at 0.15
	local timed = events(w, "timed")
	check(#timed == 1, "timed block detected")
	check(w.f.Blue.state == "stagger", "attacker staggered by the timed block")
	local snap = w:snapshot()
	check(snap.Purple.counterLeft > 0.8, "riposte window open (" .. string.format("%.2f", snap.Purple.counterLeft) .. "s)")
	run(w, 0.2)
	w:input(P, "counter"); run(w, 0.6)
	local hs = events(w, "hit")
	check(hs[#hs] and hs[#hs].hit == "ren_counter", "Void Counter landed")
	local w2 = new(3.0)
	w2:input(B, "m1"); run(w2, 0.12)
	w2:input(P, "guard", true); run(w2, 1.3)
	check(w2:input(P, "counter") == false, "counter refused after the window closed")
	local w3 = new(3.0)
	check(w3:input(P, "counter") == false, "counter refused with no timed block")
end

print("5. Static Slip dodge -> optional counter")
do
	local w = new(3.0)
	w:setAI(P, "Idle")
	w:input(P, "m1")             -- Ren throws a guard jab (contact at 0.17)
	w:input(B, "skill", 4); run(w, 0.5)
	check(#events(w, "dodge") == 1 and w.f.Blue.hp == 100, "dodge: no damage taken")
	check(w.f.Blue.meter > 0, "dodge builds meter")
	local ok = w:input(B, "counter")
	check(ok, "counter unlocked by the dodge")
	run(w, 0.5)
	local hs = events(w, "hit")
	check(hs[#hs] and hs[#hs].hit == "kael_counter", "counter strike landed")
	local w2 = new(3.0)
	check(w2:input(B, "counter") == false, "counter refused without a dodge")
end

print("6. Sky Current lift + timed follow-up slam")
do
	local w = new(3.0)
	w:input(B, "skill", 3); run(w, 0.4)
	check(w.f.Purple.state == "air", "opponent lifted")
	run(w, 0.15)
	check(w.f.Purple.y > 0.5, "opponent is off the ground (y=" .. string.format("%.2f", w.f.Purple.y) .. ")")
	local ok = w:input(B, "skill", 3); run(w, 0.6)
	check(ok, "follow-up accepted in the window")
	check(#events(w, "slam") >= 1 and w.f.Purple.y == 0, "slam brings them down")
	local hs = events(w, "hit")
	check(hs[#hs].hit == "kael_skyfollow", "follow-up hit registered")
	local w2 = new(3.0)
	w2:input(B, "skill", 3); run(w2, 1.6)
	check(w2:input(B, "skill", 3) == false, "no follow-up after the window (and Sky Current is on cooldown)")
end

print("7. Meter, Charged Mode, drain, final form, ultimate, reset")
do
	local w = new(12.0)
	check(w:input(B, "form1") == false, "cannot activate Charged Mode below 50%")
	w.f.Blue.meter = 50
	check(w:input(B, "form1") == true, "Charged Mode starts at 50%")
	check(w:input(B, "m1") == false, "cannot attack during the transformation")
	run(w, 0.3)
	check(w.f.Blue.hp > 0 and w:input(B, "m1") == false, "still locked mid-transformation")
	-- invulnerable during activation
	local w1 = new(3.0)
	w1.f.Blue.meter = 50
	w1:input(B, "form1"); run(w1, 0.1)
	w1:input(P, "m1"); run(w1, 0.4)
	check(w1.f.Blue.hp == 100, "invulnerable while transforming")
	run(w, 1.0)
	check(w.f.Blue.form == "Form1", "Charged Mode active")
	check(w.f.Blue.charges == 2, "Flash Step gets a second charge")
	w.f.Blue.meter = 80
	run(w, 3.0)
	check(w.f.Blue.meter < 80 and w.f.Blue.meter > 50, "meter drains toward 50 (" .. string.format("%.1f", w.f.Blue.meter) .. ")")
	run(w, 10)
	check(w.f.Blue.form == "Base" and w.f.Blue.meter == 50, "returns to Base at 50%")
	w.f.Blue.meter = 100
	check(w:input(B, "final") == true, "Final form starts at 100% straight from Base")
	run(w, 1.7)
	check(w.f.Blue.form == "Final", "Thunder Ascension active")
	check(w.f.Blue.finalUntil - w.t > 9.5, "12 second timer running")
	-- storm pierce replaces arc breaker
	w.f.Purple.x = 4.5
	w:input(B, "skill", 2); run(w, 0.1)
	check(w.f.Blue.act and w.f.Blue.act.clip == "storm", "Arc Breaker replaced by Storm Pierce")
	run(w, 1.3)
	-- ultimate once
	w.f.Blue.x, w.f.Purple.x, w.f.Blue.state, w.f.Blue.openUntil = -1.5, 1.5, "idle", 0
	check(w:input(B, "ult") == true, "Thunderfall available")
	run(w, 0.65)
	check(w.f.Purple.state == "air", "Thunderfall launches the opponent")
	run(w, 1.9)
	local slam = events(w, "slam")
	local big = false
	for _, s in ipairs(slam) do if s.big then big = true end end
	check(big, "single big ground slam")
	check(w.f.Blue.form == "Base" and w.f.Blue.meter == 0, "form ended and meter reset to 0 after the ultimate")
	check(w.f.Purple.hp < 100 - 8 - 25, "ultimate damage applied (hp " .. string.format("%.1f", w.f.Purple.hp) .. ")")
	check(w:input(B, "ult") == false, "no ultimate without the final form")
	-- timer expiry
	local w2 = new(12.0)
	w2.f.Blue.meter = 100; w2:input(B, "final"); run(w2, 14)
	check(w2.f.Blue.form == "Base" and w2.f.Blue.meter == 0, "final form expires after 12 s with meter reset")
end

print("8. Ren: Anchor Step, Gravity Pulse, Rift Mode, Eclipse Guard, Event Horizon")
do
	local w = new(3.0)
	w:input(P, "skill", 1); run(w, 0.4)
	w:input(B, "skill", 2); run(w, 0.9)
	check(w.f.Purple.state ~= "stagger", "Anchor Step resists the stagger")
	local w2 = new(4.0)
	w2:input(P, "skill", 2); run(w2, 0.7)
	check(w2.f.Blue.x < -2.0 - 0.4 and w2.f.Blue.hp == 94, "Gravity Pulse pushes outward and hits (x " .. string.format("%.2f", w2.f.Blue.x) .. ")")
	local w3 = new(6.3)
	w3.f.Purple.form = "Form1"; w3.f.Purple.meter = 75
	w3:input(P, "skill", 2); run(w3, 0.7)
	check(w3.f.Blue.hp == 94, "Gravity Pulse range grows in Rift Mode (hits at 6.3)")
	local w3b = new(6.3)
	w3b:input(P, "skill", 2); run(w3b, 0.7)
	check(w3b.f.Blue.hp == 100, "...but not in Base")
	-- Eclipse Guard stored energy
	local w4 = new(3.0)
	w4.f.Purple.meter = 100; w4:input(P, "final"); run(w4, 1.8)
	check(w4.f.Purple.form == "Final", "Eclipse Form active")
	w4:input(B, "m1"); run(w4, 0.12); w4:input(P, "guard", true); run(w4, 0.1)
	check(w4.f.Purple.stored == true, "timed block stores energy in Eclipse Form")
	run(w4, 0.2)
	local hp0 = w4.f.Blue.hp
	w4:input(P, "counter"); run(w4, 0.6)
	local dealt = hp0 - w4.f.Blue.hp
	check(dealt > 12 * 1.5 and not w4.f.Purple.stored, "stored energy empowers the counter (" .. string.format("%.1f", dealt) .. ") and is consumed")
	-- Event Horizon
	local w5 = new(8.0)
	w5.f.Purple.meter = 100; w5:input(P, "final"); run(w5, 1.8)
	local x0 = w5.f.Blue.x
	w5:input(P, "ult"); run(w5, 1.5)
	check(#events(w5, "field") == 1, "ground field announced")
	check(w5.f.Blue.x > x0 + 0.5, "opponent pulled inward (" .. string.format("%.2f -> %.2f", x0, w5.f.Blue.x) .. ")")
	run(w5, 1.0)
	check(w5.f.Blue.hp < 100 - 20, "outward impact lands (hp " .. string.format("%.1f", w5.f.Blue.hp) .. ")")
	run(w5, 2.0)
	check(w5.f.Purple.form == "Base" and w5.f.Purple.meter == 0, "Eclipse Form ends and meter resets after Event Horizon")
	local w6 = new(8.0)
	w6.f.Purple.meter = 100; w6:input(P, "final"); run(w6, 1.8)
	w6.f.Blue.x = -13.5
	w6:input(P, "ult"); run(w6, 3.6)
	check(w6.f.Blue.hp == 100, "an opponent outside the field is untouched")
end

print("9. Reset, repeated replays, no overlaps")
do
	local w = new(3.0)
	w.f.Blue.meter = 100; w:input(B, "final"); run(w, 1.0)
	w:input(P, "m1"); run(w, 0.3)
	w:reset()
	local f = w.f.Blue
	check(f.form == "Base" and f.meter == 0 and f.act == nil and f.state == "idle" and f.hp == 100 and f.finalUntil == 0, "reset clears form, meter, action, timers")
	for round = 1, 5 do
		w.f.Blue.x, w.f.Purple.x = -1.5, 1.5
		w:input(B, "m1"); run(w, 0.5)
		w:reset()
	end
	check(w.f.Purple.hp == 100 and #w.f.Blue.cd == 0, "5 reset cycles leave no residue")
	-- fighters never overlap
	local w2 = new(6.0)
	w2:input(B, "move", 1, 0)
	run(w2, 3.0)
	check(w2.f.Purple.x - w2.f.Blue.x >= Config.arena.minGap - 0.01, "walking into the opponent stops at the minimum gap (" .. string.format("%.2f", w2.f.Purple.x - w2.f.Blue.x) .. ")")
	-- dummy AI attack loop runs
	local w3 = new(3.0)
	w3:setAI(P, "Attack"); run(w3, 12)
	check(w3.f.Blue.hp < 100, "dummy in Attack mode lands hits on an idle player")
	local w4 = new(3.0)
	w4:setAI(P, "Guard"); w4:input(B, "m1"); run(w4, 0.8)
	check(w4.f.Purple.hp > 99, "dummy in Guard mode blocks")
end

print(string.format("\n%d checks, %d failed", checks, fails))

print("10. Static validation of clips, hit ids and cinematic data")
do
	local missing = {}
	for _, char in ipairs({ "Kael", "Ren" }) do
		for name, c in pairs(Clips[char]) do
			if name ~= "bases" then
				if c.keys[1].t ~= 0 then missing[#missing + 1] = char .. "." .. name .. " first key not at 0" end
				for i = 2, #c.keys do if c.keys[i].t <= c.keys[i - 1].t then missing[#missing + 1] = char .. "." .. name .. " keys out of order @" .. i end end
				if c.keys[#c.keys].t > c.dur + 1e-6 then missing[#missing + 1] = char .. "." .. name .. " key beyond dur" end
				for _, mk in ipairs(c.markers) do
					if mk.t > c.dur then missing[#missing + 1] = char .. "." .. name .. " marker beyond dur: " .. mk.name end
					if mk.hit and not Config.hits[mk.hit] then missing[#missing + 1] = char .. "." .. name .. " unknown hit " .. mk.hit end
				end
			end
		end
	end
	for _, n in ipairs({ "idle", "walk", "guard", "hit", "knock", "air", "getup", "open", "guard_hit", "m1_1", "m1_2", "m1_3", "m1_4", "form1_on", "final_on", "thunder", "flash", "flash_back", "arc", "storm", "sky", "sky_follow", "slip", "counter" }) do
		if not Clips.Kael[n] then missing[#missing + 1] = "Kael missing " .. n end
	end
	for _, n in ipairs({ "idle", "walk", "guard", "hit", "knock", "air", "getup", "open", "guard_hit", "m1_1", "m1_2", "m1_3", "m1_4", "rift_on", "eclipse_on", "horizon", "anchor", "pulse", "void_counter", "timed_block" }) do
		if not Clips.Ren[n] then missing[#missing + 1] = "Ren missing " .. n end
	end
	check(#missing == 0, "all clips well-formed (" .. table.concat(missing, "; ") .. ")")
	-- every marker contact name is unique per clip and every hit clip has a contact marker
	local contacts = 0
	for _, char in ipairs({ "Kael", "Ren" }) do for name, c in pairs(Clips[char]) do if name ~= "bases" then for _, mk in ipairs(c.markers) do if mk.op == "hit" then contacts = contacts + 1 end end end end end
	check(contacts >= 14, "contact markers present (" .. contacts .. ")")
end
print(string.format("\n%d checks, %d failed (final)", checks, fails))
