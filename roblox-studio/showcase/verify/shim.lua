-- Minimal Vector3 / CFrame / Color3 shim for testing the pose engine outside Roblox.
local V = {}
V.__index = function(t, k)
	if k == "Magnitude" then return math.sqrt(t.X*t.X + t.Y*t.Y + t.Z*t.Z) end
	if k == "Unit" then local m = math.sqrt(t.X*t.X + t.Y*t.Y + t.Z*t.Z); return setmetatable({X=t.X/m,Y=t.Y/m,Z=t.Z/m}, V) end
	return V[k]
end
local function v3(x,y,z) return setmetatable({X=x,Y=y,Z=z}, V) end
Vector3 = { new = function(x,y,z) return v3(x or 0, y or 0, z or 0) end }
V.__add = function(a,b) return v3(a.X+b.X, a.Y+b.Y, a.Z+b.Z) end
V.__sub = function(a,b) return v3(a.X-b.X, a.Y-b.Y, a.Z-b.Z) end
V.__unm = function(a) return v3(-a.X,-a.Y,-a.Z) end
V.__mul = function(a,b)
	if type(a) == "number" then return v3(a*b.X, a*b.Y, a*b.Z) end
	if type(b) == "number" then return v3(a.X*b, a.Y*b, a.Z*b) end
	return v3(a.X*b.X, a.Y*b.Y, a.Z*b.Z)
end
V.__div = function(a,b) return v3(a.X/b, a.Y/b, a.Z/b) end
function V.Dot(a,b) return a.X*b.X + a.Y*b.Y + a.Z*b.Z end
function V.Cross(a,b) return v3(a.Y*b.Z - a.Z*b.Y, a.Z*b.X - a.X*b.Z, a.X*b.Y - a.Y*b.X) end
function V.Lerp(a,b,t) return a + (b-a)*t end

local C = {}
C.__index = function(t,k)
	if k == "Position" then return t.p end
	if k == "X" then return t.p.X elseif k == "Y" then return t.p.Y elseif k == "Z" then return t.p.Z end
	return C[k]
end
local function mk(p, r) return setmetatable({p=p, r=r}, C) end
local I3 = {{1,0,0},{0,1,0},{0,0,1}}
local function mm(a,b)
	local r = {{0,0,0},{0,0,0},{0,0,0}}
	for i=1,3 do for j=1,3 do for k=1,3 do r[i][j] = r[i][j] + a[i][k]*b[k][j] end end end
	return r
end
local function mv(m,v) return v3(m[1][1]*v.X+m[1][2]*v.Y+m[1][3]*v.Z, m[2][1]*v.X+m[2][2]*v.Y+m[2][3]*v.Z, m[3][1]*v.X+m[3][2]*v.Y+m[3][3]*v.Z) end
local function tr(m) return {{m[1][1],m[2][1],m[3][1]},{m[1][2],m[2][2],m[3][2]},{m[1][3],m[2][3],m[3][3]}} end
CFrame = {}
function CFrame.new(a,b,c)
	if a == nil then return mk(v3(0,0,0), I3) end
	if type(a) == "table" then return mk(a, I3) end
	return mk(v3(a,b,c), I3)
end
function CFrame.Angles(x,y,z)
	local cx,sx,cy,sy,cz,sz = math.cos(x),math.sin(x),math.cos(y),math.sin(y),math.cos(z),math.sin(z)
	local Rx = {{1,0,0},{0,cx,-sx},{0,sx,cx}}
	local Ry = {{cy,0,sy},{0,1,0},{-sy,0,cy}}
	local Rz = {{cz,-sz,0},{sz,cz,0},{0,0,1}}
	return mk(v3(0,0,0), mm(mm(Rx,Ry),Rz))
end
function CFrame.fromMatrix(p, x, y, z)
	return mk(p, {{x.X,y.X,z.X},{x.Y,y.Y,z.Y},{x.Z,y.Z,z.Z}})
end
C.__mul = function(a,b)
	if getmetatable(b) == C then return mk(mv(a.r, b.p) + a.p, mm(a.r, b.r)) end
	return mv(a.r, b) + a.p
end
C.__sub = function(a,b) return mk(a.p - b, a.r) end
C.__add = function(a,b) return mk(a.p + b, a.r) end
function C.Inverse(a) local rt = tr(a.r); return mk(-mv(rt, a.p), rt) end
function C.PointToWorldSpace(a,v) return mv(a.r, v) + a.p end
function C.VectorToWorldSpace(a,v) return mv(a.r, v) end
function C.PointToObjectSpace(a,v) return mv(tr(a.r), v - a.p) end
Color3 = { fromRGB = function(r,g,b) return {r=r,g=g,b=b} end }
