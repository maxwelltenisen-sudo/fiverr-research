-- BGCloth (ModuleScript, ReplicatedStorage): lets hanging cloth (scarf tails, coat hem) follow the body with a slight delay.
-- BGBuilder makes the chains: Motor6Ds with attributes Chain (name) and Depth (1 = nearest the body).
local Cloth = {}
Cloth.__index = Cloth

local RATES = { 14, 9, 6.5, 5 }      -- deeper segments react slower => visible lag

local function wrapAngle(a)
	while a > math.pi do a = a - 2 * math.pi end
	while a < -math.pi do a = a + 2 * math.pi end
	return a
end

function Cloth.new(model)
	local self = setmetatable({ chains = {}, prevPos = nil }, Cloth)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") and d:GetAttribute("Chain") then
			local name = d:GetAttribute("Chain")
			local c = self.chains[name]
			if not c then
				c = { joints = {}, yaw = {}, pitch = {}, phase = math.random() * 6 }
				self.chains[name] = c
			end
			c.joints[d:GetAttribute("Depth")] = d
		end
	end
	return self
end

function Cloth:reset() self.prevPos = nil end

-- utCF = world CFrame of the UpperTorso (or LowerTorso for hems); dt = simulated seconds this frame (0 when paused)
function Cloth:update(utCF, dt)
	local fwd = utCF:VectorToWorldSpace(Vector3.new(0, 0, -1))
	local yaw = math.atan2(-fwd.X, -fwd.Z)
	local pos = utCF.Position
	if not self.prevPos then
		self.prevPos = pos
		for _, c in pairs(self.chains) do for i = 1, #c.joints do c.yaw[i], c.pitch[i] = yaw, 0 end end
	end
	local vf, vl = 0, 0
	if dt > 1e-4 then
		local v = (pos - self.prevPos) / dt
		vf = v:Dot(Vector3.new(fwd.X, 0, fwd.Z))
		vl = v:Dot(Vector3.new(-fwd.Z, 0, fwd.X))
	end
	self.prevPos = pos
	local now = os.clock()
	for _, c in pairs(self.chains) do
		for i = 1, #c.joints do
			local j = c.joints[i]
			if dt > 0 then
				local k = 1 - math.exp(-dt * (RATES[i] or 4))
				c.yaw[i] = (c.yaw[i] or yaw) + wrapAngle(yaw - (c.yaw[i] or yaw)) * k
				local want = math.clamp(-vf * 3.0, -40, 40)
				c.pitch[i] = (c.pitch[i] or 0) + (want - (c.pitch[i] or 0)) * k
			end
			local roll = math.clamp(math.deg(wrapAngle(yaw - (c.yaw[i] or yaw))) * 0.9 + vl * -1.5, -42, 42)
			local sway = math.sin(now * 1.6 + c.phase + i * 0.7) * 1.5
			j.Transform = CFrame.Angles(math.rad(-6 + (c.pitch[i] or 0) * (0.6 + 0.2 * i) * 0.5 + sway), 0, math.rad(roll))
		end
	end
end

return Cloth
