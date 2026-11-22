-- BGRig (ModuleScript, ReplicatedStorage): reads the joint layout of an R15 rig built by BGBuilder.
-- Joints are found by the part they move (Part1), so it works whatever the Motor6D is named.
local Engine = require(script.Parent:WaitForChild("BGEngine"))
local Rig = {}

local PART1 = { Root = "LowerTorso", Waist = "UpperTorso", Neck = "Head",
	RightShoulder = "RightUpperArm", RightElbow = "RightLowerArm", RightWrist = "RightHand",
	LeftShoulder = "LeftUpperArm", LeftElbow = "LeftLowerArm", LeftWrist = "LeftHand",
	RightHip = "RightUpperLeg", RightKnee = "RightLowerLeg", RightAnkle = "RightFoot",
	LeftHip = "LeftUpperLeg", LeftKnee = "LeftLowerLeg", LeftAnkle = "LeftFoot" }

local function findJoint(model, n)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") and d.Part1 and d.Part1.Name == PART1[n] and d.Part0 and not d:GetAttribute("Chain") then return d end
	end
end

function Rig.waitReady(model)
	model:WaitForChild("HumanoidRootPart"); model:WaitForChild("RightFoot"); model:WaitForChild("UpperTorso"); model:WaitForChild("LowerTorso")
end

-- returns defs (c0/c1/motor per joint), sizes, motors[jointName]
function Rig.read(model)
	local defs, motors = {}, {}
	for _, n in ipairs(Engine.JOINTS) do
		local m = findJoint(model, n)
		local waited = 0
		while not m and waited < 10 do task.wait(0.1); waited += 0.1; m = findJoint(model, n) end
		assert(m, "BGRig: no joint for " .. n .. " on " .. model.Name)
		defs[n] = { c0 = m.C0, c1 = m.C1, motor = m }
		motors[n] = m
	end
	return defs, { footY = model.RightFoot.Size.Y, footZ = model.RightFoot.Size.Z }, motors
end

return Rig
