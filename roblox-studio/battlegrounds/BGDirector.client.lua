-- BGDirector (LocalScript, StarterPlayer > StarterPlayerScripts): the CINEMATIC REPLAY of Kael vs Ren.
-- It only runs while the stage attribute Mode == "Cinematic" (BGClient owns Mode == "Play").
-- Plays the keyframes from ShowcaseData on the two fighters, drives the camera, markers, VFX and checks.
-- Controls:  R replay   V VFX on/off   B slow motion   Space pause   , . step (paused)
--            C contact inspector (freeze at the clash, cycle side / top camera, prints the measured gap)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local Engine = require(ReplicatedStorage:WaitForChild("BGEngine"))
local Data = require(ReplicatedStorage:WaitForChild("BGCinematicData"))
local Cloth = require(ReplicatedStorage:WaitForChild("BGCloth"))
local Style = require(ReplicatedStorage:WaitForChild("BGStyle"))

local stage = Workspace:WaitForChild("Showcase")
while not stage:GetAttribute("Ready") do task.wait(0.1) end
local fighters = { Blue = stage:WaitForChild("Blue"), Purple = stage:WaitForChild("Purple") }
for _, m in pairs(fighters) do
	m:WaitForChild("HumanoidRootPart"); m:WaitForChild("RightFoot"); m:WaitForChild("UpperTorso"); m:WaitForChild("LowerTorso")
end

---------------------------------------------------------------- rig + bake
-- Joints are found by the part they move (Part1), so it works whatever the Motor6D is named.
local PART1 = { Root = "LowerTorso", Waist = "UpperTorso", Neck = "Head",
	RightShoulder = "RightUpperArm", RightElbow = "RightLowerArm", RightWrist = "RightHand",
	LeftShoulder = "LeftUpperArm", LeftElbow = "LeftLowerArm", LeftWrist = "LeftHand",
	RightHip = "RightUpperLeg", RightKnee = "RightLowerLeg", RightAnkle = "RightFoot",
	LeftHip = "LeftUpperLeg", LeftKnee = "LeftLowerLeg", LeftAnkle = "LeftFoot" }
local function findJoint(model, n)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") and d.Part1 and d.Part1.Name == PART1[n] and d.Part0 and not d:GetAttribute("Chain") then
			return d
		end
	end
end
local function readRig(model)
	local defs = {}
	for _, n in ipairs(Engine.JOINTS) do
		local m = findJoint(model, n)
		local waited = 0
		while not m and waited < 10 do task.wait(0.1); waited = waited + 0.1; m = findJoint(model, n) end
		if not m then
			local names = {}
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("Motor6D") then table.insert(names, d.Name .. "(" .. d.Parent.Name .. ")") end
			end
			warn("BGDirector: joint for " .. n .. " not found on " .. model.Name .. ". Motor6Ds present: " .. table.concat(names, ", "))
			error("missing joint " .. n)
		end
		defs[n] = { c0 = m.C0, c1 = m.C1, motor = m }
	end
	return defs, { footY = model.RightFoot.Size.Y, footZ = model.RightFoot.Size.Z }
end
local rigDefs, rigSizes = {}, nil
for name, model in pairs(fighters) do
	rigDefs[name], rigSizes = readRig(model)
end
local R = Engine.newRig(rigDefs.Blue, rigSizes)
local tracks, info = Engine.bake(R, Data)
print(string.format("[SHOWCASE] rig: leg %.2f arm %.2f reach %.2f | Blue anchor x=%.2f z=%.2f", R.legLen, R.armLen, R.armReach,
	tracks.Blue.anchor.x, tracks.Blue.anchor.z))

local motors = {}
for name, model in pairs(fighters) do
	motors[name] = {}
	for _, n in ipairs(Engine.JOINTS) do motors[name][n] = rigDefs[name][n].motor end
end
local clothB, clothP = Cloth.new(fighters.Blue), Cloth.new(fighters.Purple)

---------------------------------------------------------------- state
local state = { t = 0, playing = true, speed = 1, vfx = false, pass = 1, inspect = 0, hold = 0, marker = "start", lastT = 0 }
local PASSES_OFF_FIRST = true
local results = { footErr = 0, footErrT = 0, minFootY = 1e9, passDone = false }
local startSnapshot = nil

---------------------------------------------------------------- HUD
local gui = Instance.new("ScreenGui")
gui.Name = "ShowcaseHUD"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
local hud = Instance.new("TextLabel")
hud.BackgroundColor3 = Color3.fromRGB(10, 10, 18); hud.BackgroundTransparency = 0.35
hud.Position = UDim2.new(0, 12, 1, -118); hud.Size = UDim2.new(0, 560, 0, 106)
hud.TextXAlignment = Enum.TextXAlignment.Left; hud.TextYAlignment = Enum.TextYAlignment.Top
hud.Font = Enum.Font.Code; hud.TextSize = 15; hud.TextColor3 = Color3.fromRGB(235, 235, 255)
hud.RichText = false
hud.Parent = gui

local function hudText()
	local mode = state.inspect > 0 and ("INSPECT " .. (state.inspect == 1 and "A side" or "B top")) or (state.playing and "PLAY" or "PAUSED")
	hud.Text = string.format(" %s | pass %d | VFX %s | speed %.2fx | t=%.2f / %.1f\n marker: %s\n %s\n R replay  V vfx  B slow-mo  Space pause  , . step  C contact check",
		mode, state.pass, state.vfx and "ON" or "OFF", state.speed, state.t, Data.duration, state.marker, results.summary or "checks run at the end of pass 1")
end

---------------------------------------------------------------- pose application
local function applyPose(t)
	local snapshot = {}
	for name, model in pairs(fighters) do
		local P = Engine.eval(R, tracks[name], t)
		local out = Engine.solve(R, P)
		model.HumanoidRootPart.CFrame = out.hrp
		for jn, rt in pairs(out.rot) do motors[name][jn].Transform = rt end
		snapshot[name] = { P = P, out = out }
	end
	return snapshot
end

---------------------------------------------------------------- VFX
local function burst(pos, color, size, axis)
	local anchor = Instance.new("Part")
	anchor.Anchored = true; anchor.CanCollide = false; anchor.Transparency = 1; anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = pos; anchor.Parent = Workspace
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(color); pe.LightEmission = 1; pe.Rate = 0
	pe.Lifetime = NumberRange.new(0.12, 0.26)
	pe.Speed = NumberRange.new(8 * size, 18 * size)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Size = NumberSequence.new(0.55 * size, 0)
	pe.Transparency = NumberSequence.new(0, 1)
	pe.Parent = anchor
	pe:Emit(math.floor(22 * size))
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder; ring.Anchored = true; ring.CanCollide = false; ring.CastShadow = false
	ring.Material = Enum.Material.Neon; ring.Color = color; ring.Transparency = 0.1
	ring.Size = Vector3.new(0.12, 0.5, 0.5)
	ring.CFrame = CFrame.lookAt(pos, pos + axis) * CFrame.Angles(0, math.rad(90), 0)
	ring.Parent = Workspace
	TweenService:Create(ring, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.12, 3.0 * size, 3.0 * size), Transparency = 1 }):Play()
	Debris:AddItem(anchor, 0.5); Debris:AddItem(ring, 0.3)
end

local function updateTrails()
	for _, w in ipairs(Data.vfx.trails) do
		local p = fighters[w.fighter]:FindFirstChild(w.part)
		local tr = p and p:FindFirstChild("ShowcaseTrail")
		if tr then tr.Enabled = state.vfx and state.t >= w.from and state.t <= w.to end
	end
end

local firedThisPass = {}
local function fireMarkers(prevT, t)
	for _, mk in ipairs(Data.markers) do
		if mk.t > prevT and mk.t <= t then
			state.marker = mk.name
			if state.vfx then
				for bi, b in ipairs(Data.vfx.bursts) do
					if b.marker == mk.name then
						local c = info[b.contact]
						burst(c.C, b.color, b.size, c.n or Vector3.new(1, 0, 0))
						Style.impact(c.C, b.color, b.size >= 1 and 1.5 or 0.7)
					end
				end
			end
		end
	end
end

---------------------------------------------------------------- camera
local cam = Workspace.CurrentCamera
local camCF, camFov = nil, 36
local function resolveShot(shot)
	local pos, look
	if shot.rel then
		local base = info[1].C
		pos, look = base + shot.off, base
	else
		pos, look = shot.pos, shot.look
	end
	return CFrame.lookAt(pos, look) * CFrame.Angles(0, 0, math.rad(shot.roll or 0)), shot.fov
end
local function cameraTarget(t)
	if state.inspect == 1 then return resolveShot(Data.verifyCameras.A) end
	if state.inspect == 2 then return resolveShot(Data.verifyCameras.B) end
	local shot = Data.cameras[1]
	for _, c in ipairs(Data.cameras) do if c.t <= t then shot = c end end
	return resolveShot(shot)
end

---------------------------------------------------------------- measurements (read the real parts, not the solver)
local function actualGap(snap)
	local blue, purple = fighters.Blue, fighters.Purple
	local c = Data.contacts[1]
	local aSide = c.hand == "R" and "Right" or "Left"
	local dSide = c.arm == "R" and "Right" or "Left"
	local hand = blue[aSide .. "Hand"].Position
	local ua, la = purple[dSide .. "UpperArm"], purple[dSide .. "LowerArm"]
	local E = (ua.CFrame * motors.Purple[dSide .. "Elbow"].C0).Position
	local W = (la.CFrame * motors.Purple[dSide .. "Wrist"].C0).Position
	local dist, nearest = Engine.segmentDistance(hand, E, W)
	return dist - c.guardRadius - c.fist, hand, nearest, c
end

local function reactionCheck()
	-- both fighters must be moving differently on the contact frame: compare poses just before and after
	local d0, d1 = 0.04, 0.04
	local result = {}
	for name in pairs(fighters) do
		local a = Engine.eval(R, tracks[name], Data.contacts[1].t - d0)
		local b = Engine.eval(R, tracks[name], Data.contacts[1].t)
		local c = Engine.eval(R, tracks[name], Data.contacts[1].t + d1)
		local v1 = math.abs(b.rx - a.rx) + math.abs(b.lean - a.lean) / 20 + math.abs(b.twist - a.twist) / 20
		local v2 = math.abs(c.rx - b.rx) + math.abs(c.lean - b.lean) / 20 + math.abs(c.twist - b.twist) / 20
		result[name] = string.format("%s before %.3f -> after %.3f", name, v1, v2)
	end
	return result
end

local function inspectContact()
	-- freeze at the clash and measure from both verification cameras
	state.playing = false; state.t = Data.contacts[1].t; state.inspect = 1; state.vfx = false
	applyPose(state.t)
	RunService.RenderStepped:Wait(); RunService.RenderStepped:Wait()
	local gap, hand, nearest, c = actualGap()
	print(string.format("[SHOWCASE CHECK] contact gap (fist surface to forearm surface) = %.3f studs (0 = touching, negative = overlap)", gap))
	for _, which in ipairs({ "A", "B" }) do
		state.inspect = (which == "A") and 1 or 2
		cam.CameraType = Enum.CameraType.Scriptable
		local cf, fov = cameraTarget(state.t)
		cam.CFrame = cf; cam.FieldOfView = fov; camCF = cf; camFov = fov
		RunService.RenderStepped:Wait(); RunService.RenderStepped:Wait()
		local surface = nearest + (hand - nearest).Unit * c.guardRadius
		local pHand = cam:WorldToViewportPoint(hand)
		local pSurf = cam:WorldToViewportPoint(surface)
		local pEdge = cam:WorldToViewportPoint(hand + cam.CFrame.RightVector * c.fist)
		local px = Vector2.new(pHand.X - pSurf.X, pHand.Y - pSurf.Y).Magnitude
		local rpx = Vector2.new(pHand.X - pEdge.X, pHand.Y - pEdge.Y).Magnitude
		print(string.format("[SHOWCASE CHECK] camera %s: hand centre to forearm surface = %.1f px, fist radius = %.1f px -> %s",
			which, px, rpx, math.abs(px - rpx) <= math.max(4, rpx * 0.25) and "fist meets forearm" or "CHECK: visible gap/overlap"))
	end
	for line, text in pairs(reactionCheck()) do print("[SHOWCASE CHECK] reaction on contact frame, " .. text) end
	state.inspect = 1
end

---------------------------------------------------------------- per-frame loop
local function passStartSnapshot(snap)
	startSnapshot = {}
	for name, s in pairs(snap) do
		startSnapshot[name] = { hrp = s.out.hrp, hands = { s.P.hands.R.t, s.P.hands.L.t }, feet = { s.P.feet.R.g, s.P.feet.L.g } }
	end
end

local function endOfPassChecks(snap)
	local errPos, errHand = 0, 0
	if startSnapshot then
		for name, s in pairs(snap) do
			local st = startSnapshot[name]
			errPos = math.max(errPos, (s.out.hrp.Position - st.hrp.Position).Magnitude)
			errHand = math.max(errHand, (s.P.hands.R.t - st.hands[1]).Magnitude, (s.P.hands.L.t - st.hands[2]).Magnitude)
		end
	end
	results.summary = string.format("checks: clash gap %.3f | counter miss %.3f | foot slide max %.3f (t=%.2f) | lowest foot %.3f | return-to-guard %.3f / %.3f",
		results.contactGap or 0, results.counterMiss or 0, results.footErr, results.footErrT, results.minFootY, errPos, errHand)
	print("[SHOWCASE CHECK] " .. results.summary)
	print("[SHOWCASE CHECK] foot error = distance between each planted foot's toe and its locked plant point (0 = no sliding)")
end

local toeHistory = { Blue = { R = {}, L = {} }, Purple = { R = {}, L = {} } }
local function measureFeet(snap, t)
	for name, sn in pairs(snap) do
		local model = fighters[name]
		for _, side in ipairs({ "R", "L" }) do
			local foot = model[(side == "R" and "Right" or "Left") .. "Foot"]
			local g = sn.P.feet[side].g
			local toe = foot.CFrame:PointToWorldSpace(Vector3.new(0, -R.footY / 2, -R.footZ / 2))
			local heel = foot.CFrame:PointToWorldSpace(Vector3.new(0, -R.footY / 2, R.footZ / 2))
			results.minFootY = math.min(results.minFootY, toe.Y, heel.Y)
			local hist = toeHistory[name][side]
			if g.Y < 0.001 then
				local yaw = math.rad(sn.P.feet[side].yaw)
				local fwd = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
				table.insert(hist, 1, g + fwd * (R.footZ / 2))
				if #hist > 3 then table.remove(hist) end
				-- the parts lag the pose by a frame or two; planted points are constant, so take the closest of the last 3
				local best = math.huge
				for _, ex in ipairs(hist) do best = math.min(best, (toe - ex).Magnitude) end
				if #hist >= 3 and best > results.footErr then results.footErr = best; results.footErrT = t end
			else
				table.clear(hist)
			end
		end
	end
end

local lastPassTime = os.clock()
local pendingMeasure = nil
local function cinematicOn() return stage:GetAttribute("Mode") == "Cinematic" end
RunService:BindToRenderStep("ShowcasePose", Enum.RenderPriority.Camera.Value - 1, function(dt)
	hud.Visible = cinematicOn()
	if not cinematicOn() then return end
	local dtSim = 0
	if state.playing and state.inspect == 0 then
		if state.hold > 0 then
			state.hold = state.hold - dt
		else
			dtSim = math.min(dt, 1 / 20) * state.speed    -- clamp so a hitch can't skip the animation
			local prev = state.t
			state.t = state.t + dtSim
			if state.t >= Data.duration then
				state.t = Data.duration
			end
			fireMarkers(prev, state.t)
		end
	end
	-- the parts only show a pose one frame after it is applied, so measure the previous frame's pose against them
	if pendingMeasure then measureFeet(pendingMeasure.snap, pendingMeasure.t); pendingMeasure = nil end
	Style.setEnabled(state.vfx)
	local snap = applyPose(state.t)
	if state.t == 0 and not startSnapshot then passStartSnapshot(snap) end
	clothB:update(snap.Blue.out.cf.UpperTorso, dtSim)
	clothP:update(snap.Purple.out.cf.LowerTorso, dtSim)
	updateTrails()
	if state.playing and state.inspect == 0 and state.pass == 1 then pendingMeasure = { snap = snap, t = state.t } end
	if state.t >= Data.duration and state.hold <= 0 and state.playing and state.inspect == 0 then
		if state.pass == 1 and not results.passDone then
			results.passDone = true
			endOfPassChecks(snap)
		end
		-- next pass: pass 1 is VFX off, every later pass VFX on
		if state.pass == 1 then state.vfx = true end
		state.pass = state.pass + 1
		state.t = 0; state.hold = 0.8; state.marker = "start"
		clothB:reset(); clothP:reset()
	end
	hudText()
end)

RunService:BindToRenderStep("ShowcaseCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if not cinematicOn() then return end
	cam = Workspace.CurrentCamera
	if not cam then return end
	cam.CameraType = Enum.CameraType.Scriptable
	local cf, fov = cameraTarget(state.t)
	if not camCF then camCF, camFov = cf, fov end
	local a = 1 - math.exp(-dt * 9)
	camCF = camCF:Lerp(cf, a)
	camFov = camFov + (fov - camFov) * a
	cam.CFrame = camCF
	cam.FieldOfView = camFov
end)

---------------------------------------------------------------- controls
local function restart()
	state.t = 0; state.hold = 0.3; state.inspect = 0; state.playing = true; state.marker = "start"
	clothB:reset(); clothP:reset()
end
UserInputService.InputBegan:Connect(function(input, gp)
	if gp or not cinematicOn() then return end
	local k = input.KeyCode
	if k == Enum.KeyCode.R then
		restart()
	elseif k == Enum.KeyCode.V then
		state.vfx = not state.vfx
	elseif k == Enum.KeyCode.B then
		state.speed = (state.speed == 1) and 0.25 or 1
	elseif k == Enum.KeyCode.Space then
		state.playing = not state.playing
		if state.inspect > 0 then state.inspect = 0; state.playing = true end
	elseif k == Enum.KeyCode.Comma and not state.playing then
		state.t = math.max(0, state.t - 1 / 30)
	elseif k == Enum.KeyCode.Period and not state.playing then
		state.t = math.min(Data.duration, state.t + 1 / 30)
	elseif k == Enum.KeyCode.C then
		if state.inspect == 0 then
			task.spawn(inspectContact)
		elseif state.inspect == 1 then
			state.inspect = 2
		else
			state.inspect = 0; state.playing = true
		end
	end
end)

task.spawn(function()
	task.wait(0.6)
	local keep = state.playing
	state.playing = false
	state.t = Data.contacts[1].t
	RunService.RenderStepped:Wait(); RunService.RenderStepped:Wait(); RunService.RenderStepped:Wait()
	local gap = actualGap()
	results.contactGap = gap
	print(string.format("[SHOWCASE CHECK] clash: fist-to-forearm gap = %.3f studs (0 = touching, negative = overlap)", gap))
	state.t = Data.contacts[2].t
	RunService.RenderStepped:Wait(); RunService.RenderStepped:Wait(); RunService.RenderStepped:Wait()
	local c2 = Data.contacts[2]
	local hand2 = fighters[c2.attacker][(c2.hand == "R" and "Right" or "Left") .. "Hand"].Position
	results.counterMiss = (hand2 - info[2].Hc).Magnitude
	print(string.format("[SHOWCASE CHECK] counter: fist-to-target miss = %.3f studs", results.counterMiss))
	state.t = 0; state.hold = 0.4; state.playing = keep
end)

print("[SHOWCASE] Director running. Pass 1 plays with VFX OFF, pass 2 with VFX ON. Keys: R V B Space , . C")
stage:GetAttributeChangedSignal("Mode"):Connect(function()
	if cinematicOn() then restart(); state.pass = 1; state.vfx = false end
end)

-- buttons from the BGClient panel (they set stage attribute CinCmd = "<command>:<time>")
stage:GetAttributeChangedSignal("CinCmd"):Connect(function()
	if not cinematicOn() then return end
	local cmd = tostring(stage:GetAttribute("CinCmd")):match("^(%a+)")
	if cmd == "replay" then restart()
	elseif cmd == "slow" then state.speed = (state.speed == 1) and 0.25 or 1
	elseif cmd == "vfx" then state.vfx = not state.vfx
	elseif cmd == "inspect" then
		if state.inspect == 0 then task.spawn(inspectContact)
		elseif state.inspect == 1 then state.inspect = 2
		else state.inspect = 0; state.playing = true end
	end
end)
