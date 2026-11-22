-- BGCore (ModuleScript, ReplicatedStorage): authoritative combat rules, no Roblox instances.
-- The server script owns one Core, feeds it player input and reads back snapshots + events.
-- Everything here (hits, blocks, dodges, meter, forms, ultimates, cooldowns) is decided on the server only.
local Core = {}
Core.__index = Core

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end   -- Luau has atan2, Lua 5.4 only has two-argument atan
local function clamp(x, a, b) return math.max(a, math.min(b, x)) end
local function hyp(x, z) return math.sqrt(x * x + z * z) end
local function wrap(a) while a > math.pi do a = a - 2 * math.pi end while a < -math.pi do a = a + 2 * math.pi end return a end

local ULT = { Kael = "thunder", Ren = "horizon" }
local FORM1 = { Kael = "form1_on", Ren = "rift_on" }
local FINAL = { Kael = "final_on", Ren = "eclipse_on" }

---------------------------------------------------------------------------------------------- setup
local function newFighter(id, char, x, z, ang)
	return {
		id = id, char = char, x = x, z = z, ang = ang, y = 0, hp = 0, meter = 0, form = "Base",
		state = "idle", act = nil, guardHeld = false, guardStart = -9, inF = 0, inS = 0, moving = false, moveBack = false,
		cd = {}, charges = 1, flashNext = nil, comboIdx = 0, comboLast = -9, bufM1 = -9,
		staggerUntil = 0, staggerClip = "hit", knockedUntil = 0, openUntil = 0, air = nil,
		counterUntil = -1, riposteUntil = -1, riposteTarget = nil, stored = false, followUntil = -1, followFrom = -1,
		finalUntil = 0, ultUsed = false, push = nil, react = nil, lift = 0,
		clip = "idle", clipT0 = 0, clipSpeed = 1, seq = 0, koAt = nil,
	}
end

function Core.new(cfg, clips, opts)
	opts = opts or {}
	local w = setmetatable({ cfg = cfg, clips = clips, t = 0, freeze = 0, events = {}, rng = opts.rng or math.random }, Core)
	w.f = {
		Blue = newFighter("Blue", "Kael", -cfg.arena.spawn, 0, 0),
		Purple = newFighter("Purple", "Ren", cfg.arena.spawn, 0, math.pi),
	}
	w.ai = {}
	w:reset()
	return w
end

function Core:reset()
	local cfg = self.cfg
	for id, f in pairs(self.f) do
		local keepChar = f.char
		local nf = newFighter(id, keepChar, id == "Blue" and -cfg.arena.spawn or cfg.arena.spawn, 0, id == "Blue" and 0 or math.pi)
		nf.hp = cfg.hpMax
		nf.clipT0 = self.t
		self.f[id] = nf
	end
	for _, ai in pairs(self.ai) do ai.queue = {}; ai.nextAt = self.t + 1.5 end
	self.freeze = 0
	self:emit("reset", {})
end

function Core:emit(kind, t)
	t.type, t.t = kind, self.t
	self.events[#self.events + 1] = t
end
function Core:drain()
	local e = self.events
	self.events = {}
	return e
end
function Core:other(f) return self.f[f.id == "Blue" and "Purple" or "Blue"] end
function Core:meta(f, name) return self.clips[f.char][name] end

---------------------------------------------------------------------------------------------- helpers
local function fwdVec(f) return math.cos(f.ang), math.sin(f.ang) end
local function rightVec(f) return -math.sin(f.ang), math.cos(f.ang) end

function Core:tempo(f)
	local fm = self.cfg.form[f.form]
	return fm and fm.tempo or 1
end

function Core:setClip(f, name, speed)
	f.clip, f.clipT0, f.clipSpeed, f.seq = name, self.t, speed or 1, f.seq + 1
end

function Core:win(f, kind)
	local a = f.act
	if not a then return false end
	local w = a.meta.win
	if not w then return false end
	for _, x in ipairs(w) do
		if x.kind == kind and a.t >= x.from and a.t <= x.to then return true end
	end
	return false
end

function Core:canAct(f)
	return f.act == nil and (f.state == "idle" or f.state == "block") and f.hp > 0
end

function Core:clampPos(f)
	local r = self.cfg.arena.radius
	local d = hyp(f.x, f.z)
	if d > r then f.x, f.z = f.x * r / d, f.z * r / d end
end

-- move without stepping through the other fighter (unless airborne) and stay in the arena
function Core:moveBy(f, dx, dz)
	local o = self:other(f)
	local nx, nz = f.x + dx, f.z + dz
	if f.lift < 0.3 and o.y < 0.3 and o.lift < 0.3 then
		local gap = self.cfg.arena.minGap
		local ox, oz = nx - o.x, nz - o.z
		local d = hyp(ox, oz)
		if d < gap then
			if d < 1e-4 then ox, oz, d = -math.cos(f.ang), -math.sin(f.ang), 1 end
			nx, nz = o.x + ox / d * gap, o.z + oz / d * gap
		end
	end
	f.x, f.z = nx, nz
	self:clampPos(f)
end

function Core:faceOpponent(f, dt, rate)
	local o = self:other(f)
	local want = atan2(o.z - f.z, o.x - f.x)
	local diff = wrap(want - f.ang)
	if rate then
		local step = math.rad(rate) * dt
		f.ang = wrap(f.ang + clamp(diff, -step, step))
	else
		f.ang = want
	end
end

function Core:addMeter(f, n)
	if n <= 0 then return end
	if f.form == "Final" then f.meter = self.cfg.meter.max; return end
	f.meter = math.min(self.cfg.meter.max, f.meter + n)
	self:emit("meter", { f = f.id, v = f.meter })
end

function Core:cooldownReady(f, key) return (f.cd[key] or 0) <= self.t end
function Core:startCd(f, key) f.cd[key] = self.t + (self.cfg.cd[f.char][key] or 0) end

function Core:maxCharges(f) return f.form == "Base" and self.cfg.flash.charges or self.cfg.flash.chargesForm end

---------------------------------------------------------------------------------------------- actions
function Core:startAct(f, name, extra)
	local m = self:meta(f, name)
	assert(m, "no clip " .. tostring(name) .. " for " .. f.char)
	f.state = "act"
	f.guardHeld = f.guardHeld   -- keep the held key; guard resumes after the action
	f.react = nil
	self:faceOpponent(f, 0)
	local a = { clip = name, t = 0, meta = m, fired = {}, landed = false, blocked = false }
	if extra then for k, v in pairs(extra) do a[k] = v end end
	-- movement direction for input-directed dashes
	local fx, fz = fwdVec(f)
	local rx, rz = rightVec(f)
	local vx, vz = fx * f.inF + rx * f.inS, fz * f.inF + rz * f.inS
	if hyp(vx, vz) < 0.2 then vx, vz = fx, fz end
	local l = hyp(vx, vz)
	a.dirx, a.dirz = vx / l, vz / l
	a.sideSign = (f.inS < -0.3) and -1 or 1
	f.act = a
	self:setClip(f, name, self:tempo(f))
	self:emit("act", { f = f.id, clip = name })
	return a
end

function Core:endForm(f, why)
	if f.form == "Base" then return end
	if f.form == "Final" then f.meter = 0 else f.meter = math.min(f.meter, self.cfg.meter.form1) end   -- the first form ends AT 50%; the final form resets to 0
	f.form = "Base"
	f.ultUsed = false
	f.stored = false
	f.charges = math.min(f.charges, 1)
	f.flashNext = nil
	self:emit("form", { f = f.id, form = "Base", why = why })
end

function Core:cancelAct(f, interrupted)
	local a = f.act
	if not a then return end
	f.act = nil
	f.lift = 0
	if a.meta.ult and interrupted then self:endForm(f, "interrupted") end
end

function Core:endAct(f)
	local a = f.act
	f.act = nil
	f.lift = 0
	f.state = "idle"
	if a.clip:sub(1, 3) == "m1_" then f.comboLast = self.t end
	if a.clip == "m1_4" then f.comboIdx = 0 end
	if a.meta.openOnMiss and not a.landed and not a.blocked then
		f.openUntil = self.t + a.meta.openOnMiss
		f.state = "open"
		self:emit("open", { f = f.id })
	end
	if a.meta.ult then self:endForm(f, "ultimate") end
	if f.state == "idle" and f.guardHeld then f.state, f.guardStart = "block", self.t end
end

---------------------------------------------------------------------------------------------- hit resolution
function Core:damage(f, n, src)
	if n <= 0 then return end
	f.hp = math.max(0, f.hp - n)
	if f.hp <= 0 and not f.koAt then
		f.koAt = self.t
		self:emit("ko", { f = f.id })
	end
end

function Core:applyPush(f, dirx, dirz, dist, dur)
	if dist <= 0 then return end
	f.push = { vx = dirx * dist / (dur or 0.25), vz = dirz * dist / (dur or 0.25), left = dur or 0.25 }
end

-- returns "hit" | "block" | "timed" | "dodged" | "armor" | "miss"
function Core:resolveHit(att, hid, a, opts)
	opts = opts or {}
	local cfg = self.cfg
	local h = cfg.hits[hid]
	local tgt = self:other(att)
	local dx, dz = tgt.x - att.x, tgt.z - att.z
	local dist = hyp(dx, dz)
	local range = h.range
	if h.range1 and att.form ~= "Base" then range = h.range1 end
	if opts.range then range = opts.range end
	if dist > range then return "miss" end
	local ux, uz = 1, 0
	if dist > 1e-4 then ux, uz = dx / dist, dz / dist end
	if (h.arc or 360) < 360 then
		local fx, fz = fwdVec(att)
		if ux * fx + uz * fz < math.cos(math.rad(h.arc / 2)) then return "miss" end
	end
	if tgt.state == "air" and not opts.airOK then return "miss" end
	if self:win(tgt, "invuln") then return "miss" end
	if tgt.hp <= 0 then return "miss" end
	local pos = { x = tgt.x, z = tgt.z }

	-- Static Slip dodge
	if self:win(tgt, "dodge") and not h.area then
		tgt.counterUntil = self.t + cfg.slip.counterWindow
		self:addMeter(tgt, cfg.gain.dodge)
		self:emit("dodge", { f = tgt.id, by = att.id, hit = hid, x = pos.x, z = pos.z })
		return "dodged"
	end

	local dmg = h.dmg
	-- block
	if tgt.state == "block" and not h.unblockable then
		local tx, tz = fwdVec(tgt)
		if -ux * tx + -uz * tz >= math.cos(math.rad(cfg.guard.arc / 2)) then
			local timed = tgt.char == "Ren" and (self.t - tgt.guardStart) <= cfg.guard.timedWindow
			self:damage(tgt, dmg * cfg.guard.blockMult, att)
			self.freeze = math.max(self.freeze, cfg.hitstop.block)
			a.blocked = true
			self:applyPush(tgt, ux, uz, cfg.guard.blockPush, 0.15)
			if timed then
				self:addMeter(tgt, cfg.gain.timedBlock)
				tgt.riposteUntil = self.t + cfg.guard.riposteWindow
				tgt.riposteTarget = att.id
				if tgt.form == "Final" then tgt.stored = true end
				local st = cfg.guard.timedStagger[tgt.form] or 0.55
				self:cancelAct(att, false)
				att.state, att.staggerUntil, att.staggerClip = "stagger", self.t + st, "hit"
				self:setClip(att, "hit")
				tgt.react = { clip = "timed_block", untilT = self.t + 0.45 }
				self:setClip(tgt, "timed_block")
				self:emit("timed", { f = tgt.id, by = att.id, hit = hid, x = pos.x, z = pos.z, stored = tgt.stored })
				return "timed"
			end
			self:addMeter(tgt, cfg.gain.block)
			tgt.react = { clip = "guard_hit", untilT = self.t + 0.26 }
			self:setClip(tgt, "guard_hit")
			self:emit("block", { f = tgt.id, by = att.id, hit = hid, x = pos.x, z = pos.z })
			return "block"
		end
	end

	local fm = cfg.form[att.form]
	if fm then dmg = dmg * fm.dmg end
	if tgt.state == "open" then dmg = dmg * cfg.openDamageMult end
	if opts.dmgMult then dmg = dmg * opts.dmgMult end
	self:damage(tgt, dmg, att)
	self.freeze = math.max(self.freeze, ((h.push or 0) > 0 or dmg >= 10) and cfg.hitstop.big or cfg.hitstop.light)
	a.landed = true
	self:addMeter(att, h.mg or 0)

	-- armour (Anchor Step, ultimate wind-ups): damage lands, no stagger or push
	if self:win(tgt, "armor") then
		self:emit("hit", { f = tgt.id, by = att.id, hit = hid, armor = true, dmg = dmg, x = pos.x, z = pos.z })
		return "armor"
	end

	if tgt.act then self:cancelAct(tgt, true) end
	tgt.react = nil
	tgt.guardHeld = tgt.guardHeld
	if h.launch then
		tgt.air = { t0 = self.t, dur = h.airTime or 1.0, h = h.airH or 3.5 }
		tgt.state, tgt.y = "air", 0
		self:setClip(tgt, "air")
		if hid == "kael_sky" then
			att.followFrom = self.t + 0.15
			att.followUntil = self.t + tgt.air.dur - 0.05
		end
	else
		local st = h.stagger or 0.3
		if h.stagger1 and att.form ~= "Base" then st = h.stagger1 end
		if opts.staggerMult then st = st * opts.staggerMult end
		local push = (opts.push or h.push or 0)
		tgt.state = "stagger"
		tgt.staggerUntil = math.max(tgt.staggerUntil, self.t + st)
		tgt.staggerClip = (push > 0 or st >= 0.8) and "knock" or "hit"
		self:setClip(tgt, tgt.staggerClip)
		self:applyPush(tgt, ux, uz, push, 0.25)
	end
	self:emit("hit", { f = tgt.id, by = att.id, hit = hid, dmg = dmg, x = pos.x, z = pos.z, launch = h.launch, final = (h.push or 0) > 0 })
	return "hit"
end

---------------------------------------------------------------------------------------------- markers
function Core:marker(f, a, mk)
	local o = self:other(f)
	self:emit("marker", { f = f.id, clip = a.clip, name = mk.name, hand = mk.hand, fx = mk.fx, op = mk.op, x = f.x, z = f.z, ang = f.ang })
	if mk.op == "hit" then
		local opts
		if a.clip == "void_counter" and a.stored then opts = { dmgMult = self.cfg.eclipseCounterMult, push = (self.cfg.hits.ren_counter.push or 0) * 1.5 } end
		local res = self:resolveHit(f, mk.hit, a, opts)
		if a.clip == "void_counter" and a.stored and res == "hit" then f.stored = false end
		if a.clip == "counter" and res == "hit" then self:addMeter(f, self.cfg.gain.counterLanded) end
		self:emit("result", { f = f.id, hit = mk.hit, result = res })
	elseif mk.op == "follow" then
		if o.state == "air" then
			local res = self:resolveHit(f, mk.hit, a, { airOK = true, range = 7 })
			if res == "hit" or res == "armor" then
				-- bring the opponent back down with a compact impact
				o.air = nil
				o.y = 0
				o.state, o.staggerUntil, o.staggerClip = "stagger", self.t + (self.cfg.hits.kael_skyfollow.stagger or 0.8), "knock"
				self:setClip(o, "knock")
				self:emit("slam", { f = o.id, x = o.x, z = o.z, small = true })
			end
			self:emit("result", { f = f.id, hit = mk.hit, result = res })
		else
			self:emit("result", { f = f.id, hit = mk.hit, result = "miss" })
		end
	elseif mk.op == "slam" then
		local res = self:resolveHit(f, mk.hit, a, { airOK = true })
		if o.state == "air" then
			o.air = nil
			o.y = 0
			o.state, o.staggerUntil, o.staggerClip = "stagger", self.t + (self.cfg.hits[mk.hit].stagger or 1.0), "knock"
			self:setClip(o, "knock")
		end
		self:emit("slam", { f = o.id, x = f.x, z = f.z, big = true })
		self:emit("result", { f = f.id, hit = mk.hit, result = res })
	elseif mk.op == "field" then
		a.field = { x = f.x, z = f.z }
		self:emit("field", { f = f.id, x = f.x, z = f.z, radius = self.cfg.horizon.radius, dur = mk.dur or 1.5 })
	elseif mk.op == "pull" then
		local fl = a.field
		if fl and o.state ~= "air" and not self:win(o, "invuln") then
			local dx, dz = fl.x - o.x, fl.z - o.z
			local d = hyp(dx, dz)
			if d <= self.cfg.horizon.radius and d > 1e-3 then
				local step = math.min(self.cfg.horizon.pullSpeed * 0.2, math.max(0, d - self.cfg.arena.minGap))
				self:applyPush(o, dx / d, dz / d, step, 0.19)
				self:emit("pull", { f = o.id })
			end
		end
	elseif mk.op == "formset" then
		f.form = mk.form
		if mk.form == "Final" then
			f.meter = self.cfg.meter.max
			f.finalUntil = self.t + self.cfg.meter.finalDuration
			f.ultUsed = false
		else
			f.meter = math.max(f.meter, self.cfg.meter.form1 + self.cfg.meter.form1Surge)
		end
		f.charges = self:maxCharges(f)
		self:emit("form", { f = f.id, form = mk.form })
	end
end

---------------------------------------------------------------------------------------------- input
function Core:input(id, kind, a, b)
	local f = self.f[id]
	if not f then return false end
	local cfg = self.cfg
	if kind == "move" then
		f.inF, f.inS = clamp(tonumber(a) or 0, -1, 1), clamp(tonumber(b) or 0, -1, 1)
		return true
	elseif kind == "guard" then
		f.guardHeld = a and true or false
		if f.guardHeld and self:canAct(f) and f.state ~= "block" then
			f.state, f.guardStart = "block", self.t
		elseif not f.guardHeld and f.state == "block" then
			f.state = "idle"
		end
		return true
	end
	if f.hp <= 0 then return false end
	if kind == "m1" then
		local act = f.act
		if act and act.clip:sub(1, 3) == "m1_" and act.meta.chain then f.bufM1 = self.t; return true end
		if not self:canAct(f) then return false end
		local idx = 1
		if f.comboIdx > 0 and f.comboIdx < 4 and self.t - f.comboLast < cfg.combo.reset then idx = f.comboIdx + 1 end
		f.comboIdx = idx
		self:startAct(f, "m1_" .. idx)
		return true
	elseif kind == "skill" then
		return self:skill(f, a)
	elseif kind == "counter" then
		if f.char == "Kael" then
			local ok = f.counterUntil > self.t and (self:canAct(f) or (f.act and f.act.clip == "slip" and f.act.t >= 0.12))
			if not ok then return false end
			f.counterUntil = -1
			self:cancelAct(f, false)
			self:startAct(f, "counter")
			return true
		else
			if not (f.riposteUntil > self.t and (self:canAct(f) or (f.act and f.act.clip == "timed_block"))) then return false end
			f.riposteUntil = -1
			self:cancelAct(f, false)
			self:startAct(f, "void_counter", { stored = f.stored })
			return true
		end
	elseif kind == "ult" then
		if f.form ~= "Final" or f.ultUsed or not self:canAct(f) then return false end
		f.ultUsed = true
		self:startAct(f, ULT[f.char])
		return true
	elseif kind == "form1" then
		if f.form ~= "Base" or f.meter < cfg.meter.form1 or not self:canAct(f) then return false end
		self:startAct(f, FORM1[f.char])
		return true
	elseif kind == "final" then
		if f.form == "Final" or f.meter < cfg.meter.final or not self:canAct(f) then return false end
		self:startAct(f, FINAL[f.char])
		return true
	end
	return false
end

function Core:skill(f, id)
	if f.char == "Kael" then
		if id == 1 then
			if not self:canAct(f) or f.charges < 1 then return false end
			f.charges = f.charges - 1
			if not f.flashNext then f.flashNext = self.t + self.cfg.cd.Kael.flash end
			self:startAct(f, f.inF < -0.3 and math.abs(f.inS) < 0.6 and "flash_back" or "flash")
			return true
		elseif id == 2 then
			if not self:canAct(f) or not self:cooldownReady(f, "arc") then return false end
			self:startCd(f, "arc")
			self:startAct(f, f.form == "Final" and "storm" or "arc")
			return true
		elseif id == 3 then
			local o = self:other(f)
			local cancelOk = f.act and f.act.clip == "sky" and f.act.t >= 0.3
			if o.state == "air" and self.t >= f.followFrom and self.t <= f.followUntil and (self:canAct(f) or cancelOk) then
				f.followUntil = -1
				self:cancelAct(f, false)
				self:startAct(f, "sky_follow")
				return true
			end
			if not self:canAct(f) or not self:cooldownReady(f, "sky") then return false end
			self:startCd(f, "sky")
			self:startAct(f, "sky")
			return true
		elseif id == 4 then
			if not self:canAct(f) or not self:cooldownReady(f, "slip") then return false end
			self:startCd(f, "slip")
			self:startAct(f, "slip")
			return true
		end
	else
		if id == 1 then
			if not self:canAct(f) or not self:cooldownReady(f, "anchor") then return false end
			self:startCd(f, "anchor")
			self:startAct(f, "anchor")
			return true
		elseif id == 2 then
			if not self:canAct(f) or not self:cooldownReady(f, "pulse") then return false end
			self:startCd(f, "pulse")
			self:startAct(f, "pulse")
			return true
		end
	end
	return false
end

-- Studio-only preview: jump straight to a form (the server script refuses this outside Studio).
function Core:forceForm(id, form)
	local f = self.f[id]
	local cfg = self.cfg
	self:cancelAct(f, false)
	f.state, f.air, f.y, f.staggerUntil, f.openUntil, f.push, f.react = "idle", nil, 0, 0, 0, nil, nil
	if form == "Base" then
		f.form = "Base"; f.meter = 0; f.ultUsed = false; f.stored = false; f.charges = 1
		self:setClip(f, "idle")
		self:emit("form", { f = f.id, form = "Base", why = "preview" })
	elseif form == "Form1" then
		if f.form == "Final" then f.form = "Base" end
		f.meter = 75
		self:startAct(f, FORM1[f.char])
	elseif form == "Final" then
		f.meter = cfg.meter.max
		self:startAct(f, FINAL[f.char])
	end
end

function Core:setAI(id, mode)
	if mode == nil or mode == "Off" then self.ai[id] = nil; return end
	self.ai[id] = { mode = mode, queue = {}, nextAt = self.t + 1.0 }
end

---------------------------------------------------------------------------------------------- update
function Core:updateAI(f, dt)
	local ai = self.ai[f.id]
	if not ai then return end
	local o = self:other(f)
	local dist = hyp(o.x - f.x, o.z - f.z)
	if ai.mode == "Guard" then
		if not f.guardHeld then self:input(f.id, "guard", true) end
		self:input(f.id, "move", 0, 0)
		return
	end
	if f.guardHeld then self:input(f.id, "guard", false) end
	if ai.mode == "Idle" then self:input(f.id, "move", 0, 0); return end
	-- Attack: approach, then throw a short sequence so dodges and timed blocks can be tested
	if not self:canAct(f) then return end
	if dist > self.cfg.ai.approachRange + 0.6 then self:input(f.id, "move", 1, 0) else self:input(f.id, "move", 0, 0) end
	if #ai.queue > 0 and self.t >= ai.queue[1].at then
		local q = table.remove(ai.queue, 1)
		if q.kind == "m1" then self:input(f.id, "m1") else self:input(f.id, "skill", q.id) end
	elseif #ai.queue == 0 and self.t >= ai.nextAt and dist <= self.cfg.ai.approachRange + 0.8 then
		local r = self.rng()
		if r < 0.5 then
			for i = 0, 3 do ai.queue[#ai.queue + 1] = { at = self.t + i * 0.3, kind = "m1" } end
		else
			ai.queue[1] = { at = self.t, kind = "skill", id = 2 }
		end
		ai.nextAt = self.t + self.cfg.ai.interval * (0.8 + 0.4 * self.rng())
	end
end

function Core:updateFighter(f, dt)
	local cfg = self.cfg
	local o = self:other(f)

	-- meter, forms, charges
	if f.form == "Form1" then
		f.meter = f.meter - cfg.meter.drain * dt
		if f.meter <= cfg.meter.form1 then f.meter = cfg.meter.form1; self:endForm(f, "drained") end
	elseif f.form == "Final" and self.t >= f.finalUntil and not (f.act and f.act.meta.ult) then
		self:endForm(f, "timeout")
	end
	if f.flashNext and self.t >= f.flashNext then
		f.charges = math.min(self:maxCharges(f), f.charges + 1)
		f.flashNext = f.charges < self:maxCharges(f) and (self.t + cfg.cd.Kael.flash) or nil
	end

	-- KO refill
	if f.koAt and self.t - f.koAt >= cfg.koRefill then f.hp, f.koAt = cfg.hpMax, nil; self:emit("refill", { f = f.id }) end

	-- timed reactions
	if f.react and self.t >= f.react.untilT then f.react = nil end

	-- pushes
	if f.push then
		local step = math.min(dt, f.push.left)
		self:moveBy(f, f.push.vx * step, f.push.vz * step)
		f.push.left = f.push.left - step
		if f.push.left <= 1e-6 then f.push = nil end
	end

	-- airborne
	if f.air then
		local u = (self.t - f.air.t0) / f.air.dur
		if u >= 1 then
			f.air, f.y = nil, 0
			f.state, f.knockedUntil = "knocked", self.t + cfg.knocked
			self:setClip(f, "getup")
			self:emit("land", { f = f.id, x = f.x, z = f.z })
		else
			f.y = f.air.h * 4 * u * (1 - u)
		end
	end

	-- states that end on a timer
	if f.state == "stagger" and self.t >= f.staggerUntil then f.state = "idle" end
	if f.state == "knocked" and self.t >= f.knockedUntil then f.state = "idle" end
	if f.state == "open" and self.t >= f.openUntil then f.state = "idle" end
	if f.state == "idle" and f.guardHeld and f.hp > 0 then f.state, f.guardStart = "block", self.t end

	-- action
	local a = f.act
	if a then
		local prev = a.t
		a.t = a.t + dt * self:tempo(f)
		local m = a.meta
		if m.move and not m.noMove then
			for _, mv in ipairs(m.move) do
				local ov = clamp(a.t, mv.from, mv.to) - clamp(prev, mv.from, mv.to)
				if ov > 0 then
					local d = mv.dist * ov / (mv.to - mv.from)
					local fx, fz = fwdVec(f)
					local rx, rz = rightVec(f)
					local dx, dz = fx, fz
					if mv.dir == "input" then dx, dz = a.dirx, a.dirz
					elseif mv.dir == "side" then dx, dz = rx * a.sideSign, rz * a.sideSign
					elseif mv.dir == "back" then dx, dz = -fx, -fz end
					self:moveBy(f, dx * d, dz * d)
				end
			end
		end
		f.lift = 0
		if m.lift then
			for _, lf in ipairs(m.lift) do
				if a.t >= lf.from and a.t <= lf.to then
					f.lift = math.max(f.lift, lf.h * math.sin(math.pi * (a.t - lf.from) / (lf.to - lf.from)))
				end
			end
		end
		for _, mk in ipairs(m.markers) do
			if not a.fired[mk] and mk.t <= a.t then
				a.fired[mk] = true
				self:marker(f, a, mk)
				if f.act ~= a then return end     -- the marker interrupted us
			end
		end
		-- combo chain
		if m.chain and a.t >= m.chain and self.t - f.bufM1 <= cfg.combo.buffer and a.clip ~= "m1_4" then
			local n = tonumber(a.clip:sub(4)) + 1
			f.bufM1 = -9
			f.comboIdx = n
			self:startAct(f, "m1_" .. n)
			return
		end
		if a.t >= m.dur then self:endAct(f) end
	elseif f.state == "idle" or f.state == "block" then
		-- walking
		local fx, fz = fwdVec(f)
		local rx, rz = rightVec(f)
		local vx, vz = fx * f.inF + rx * f.inS, fz * f.inF + rz * f.inS
		local l = hyp(vx, vz)
		f.moving, f.moveBack = false, false
		if l > 0.05 then
			if l > 1 then vx, vz, l = vx / l, vz / l, 1 end
			local ch = cfg.char[f.char]
			local fmv = cfg.form[f.form]
			local base = (f.state == "block") and ch.guardWalk or ((f.inF < -0.3 and math.abs(f.inS) < 0.6) and ch.backWalk or ch.walk)
			local sp = base * (fmv and fmv.speed or 1)
			self:moveBy(f, vx / l * sp * l * dt, vz / l * sp * l * dt)
			f.moving, f.moveBack = true, f.inF < -0.3 and math.abs(f.inS) < 0.6
			f.moveSpeed = sp * l
		end
	end

	-- facing
	if f.act == nil and f.state ~= "air" and f.state ~= "knocked" then self:faceOpponent(f, dt, cfg.char[f.char].turn) end

	-- displayed clip
	local want
	if f.act then want = nil
	elseif f.state == "stagger" then want = nil
	elseif f.state == "air" or f.state == "knocked" then want = nil
	elseif f.state == "open" then want = "open"
	elseif f.react and f.state == "block" then want = f.react.clip
	elseif f.state == "block" then want = "guard"
	elseif f.moving then want = "walk"
	else want = "idle" end
	if want and want ~= f.clip then self:setClip(f, want) end
	if want == "walk" then
		local stride = self:meta(f, "walk").walkStride
		f.clipSpeed = clamp((f.moveSpeed or 0) / (stride / 0.3), 0.4, 1.8)
	end
end

function Core:update(dt)
	self.t = self.t + dt
	if self.freeze > 0 then            -- hit-stop: clips, actions and timers hold still for a few frames
		self.freeze = self.freeze - dt
		for _, f in pairs(self.f) do
			f.clipT0 = f.clipT0 + dt
			f.staggerUntil = f.staggerUntil + dt
			f.openUntil = f.openUntil + dt
			f.knockedUntil = f.knockedUntil + dt
			if f.air then f.air.t0 = f.air.t0 + dt end
			if f.push then f.push.left = f.push.left + 0 end
		end
		return
	end
	for _, id in ipairs({ "Blue", "Purple" }) do self:updateAI(self.f[id], dt) end
	for _, id in ipairs({ "Blue", "Purple" }) do self:updateFighter(self.f[id], dt) end
	-- overlap separation (grounded fighters only)
	local a, b = self.f.Blue, self.f.Purple
	if a.lift < 0.3 and b.lift < 0.3 and a.y < 0.3 and b.y < 0.3 then
		local dx, dz = b.x - a.x, b.z - a.z
		local d = hyp(dx, dz)
		local gap = self.cfg.arena.minGap
		if d < gap and d > 1e-4 then
			local push = (gap - d) / 2
			a.x, a.z = a.x - dx / d * push, a.z - dz / d * push
			b.x, b.z = b.x + dx / d * push, b.z + dz / d * push
		end
	end
end

---------------------------------------------------------------------------------------------- snapshot for clients / UI
function Core:snapshot()
	local out = {}
	for id, f in pairs(self.f) do
		local cd = {}
		for k, v in pairs(f.cd) do cd[k] = math.max(0, v - self.t) end
		cd.flashCharges = f.charges
		cd.flashNext = f.flashNext and math.max(0, f.flashNext - self.t) or 0
		out[id] = {
			char = f.char, x = f.x, z = f.z, ang = f.ang, y = f.y + f.lift,
			clip = f.clip, clipT = (self.t - f.clipT0) * f.clipSpeed, clipSpeed = f.clipSpeed, seq = f.seq,
			back = f.moveBack and f.clip == "walk", hp = f.hp, meter = f.meter, form = f.form, state = f.state,
			cd = cd, finalLeft = f.form == "Final" and math.max(0, f.finalUntil - self.t) or 0, ultReady = f.form == "Final" and not f.ultUsed,
			counterLeft = math.max(f.counterUntil - self.t, f.riposteUntil - self.t, 0), stored = f.stored,
			followLeft = math.max(0, f.followUntil - self.t),
		}
	end
	return out
end

return Core
