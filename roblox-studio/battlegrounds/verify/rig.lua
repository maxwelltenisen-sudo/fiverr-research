-- Mock R15-like rig (offset shoulder pivots on purpose, to exercise the general solver).
local function cf(x,y,z) return CFrame.new(x,y,z) end
local d = {
	Root = { c0 = cf(0,0,0), c1 = cf(0,0.2,0) },
	Waist = { c0 = cf(0,0.2,0), c1 = cf(0,-0.8,0) },
	Neck = { c0 = cf(0,0.8,0), c1 = cf(0,-0.5,0) },
	RightShoulder = { c0 = cf(1.0,0.55,0), c1 = cf(-0.5,0.5,0) },
	LeftShoulder = { c0 = cf(-1.0,0.55,0), c1 = cf(0.5,0.5,0) },
	RightElbow = { c0 = cf(0,-0.45,0), c1 = cf(0,0.5,0) },
	LeftElbow = { c0 = cf(0,-0.45,0), c1 = cf(0,0.5,0) },
	RightWrist = { c0 = cf(0,-0.5,0), c1 = cf(0,0.15,0) },
	LeftWrist = { c0 = cf(0,-0.5,0), c1 = cf(0,0.15,0) },
	RightHip = { c0 = cf(0.5,-0.2,0), c1 = cf(0,0.5,0) },
	LeftHip = { c0 = cf(-0.5,-0.2,0), c1 = cf(0,0.5,0) },
	RightKnee = { c0 = cf(0,-0.5,0), c1 = cf(0,0.5,0) },
	LeftKnee = { c0 = cf(0,-0.5,0), c1 = cf(0,0.5,0) },
	RightAnkle = { c0 = cf(0,-0.5,0), c1 = cf(0,0.1,0) },
	LeftAnkle = { c0 = cf(0,-0.5,0), c1 = cf(0,0.1,0) },
}
return d
