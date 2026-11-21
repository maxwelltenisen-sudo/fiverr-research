-- LocalScript: put in StarterPlayer > StarterPlayerScripts.
print("Camera LocalScript started")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local remote = ReplicatedStorage:WaitForChild("StoryEvent")

local gui = Instance.new("ScreenGui")
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local label = Instance.new("TextLabel")
label.AnchorPoint = Vector2.new(0.5, 0.5)
label.Position = UDim2.fromScale(0.5, 0.5)
label.Size = UDim2.fromScale(0.8, 0.15)
label.BackgroundTransparency = 1
label.TextScaled = true
label.Font = Enum.Font.GothamBlack
label.TextColor3 = Color3.new(1, 1, 1)
label.TextStrokeTransparency = 0
label.Text = ""
label.Parent = gui

local target = nil          -- CFrame we are moving the camera to
local targetFov = 70
local shakePower, shakeEnd = 0, 0
local gotFirst = false

-- runs every frame so nothing else can take the camera back
RunService:BindToRenderStep("StoryCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local cam = workspace.CurrentCamera
	if not cam or not target then return end
	cam.CameraType = Enum.CameraType.Scriptable
	local a = math.clamp(dt * 6, 0, 1)
	local cf = cam.CFrame:Lerp(target, a)
	if os.clock() < shakeEnd and shakePower > 0 then
		local s = shakePower * 0.15
		cf = cf * CFrame.new((math.random() - 0.5) * s, (math.random() - 0.5) * s, 0)
	end
	cam.CFrame = cf
	cam.FieldOfView = cam.FieldOfView + (targetFov - cam.FieldOfView) * a
end)

remote.OnClientEvent:Connect(function(data)
	if not gotFirst then
		gotFirst = true
		print("Camera script: first shot received")
	end
	if data.shake and data.shake > 0 then
		shakePower, shakeEnd = data.shake, os.clock() + (data.time or 0.4)
	end
	if data.shakeOnly then return end
	target = data.cframe
	targetFov = data.fov or 70
	label.Text = data.caption or ""
end)

-- DEBUG: prints what this client can see, 8 seconds after start.
task.delay(8, function()
	local g = workspace:FindFirstChild("Gojo")
	print("DEBUG StreamingEnabled:", workspace.StreamingEnabled)
	print("DEBUG found on client -> Ground:", workspace:FindFirstChild("Ground") ~= nil,
		"Gojo:", g ~= nil, "Toji:", workspace:FindFirstChild("Toji") ~= nil)
	local cam = workspace.CurrentCamera
	print("DEBUG camera:", cam.CameraType, cam.CFrame.Position)
	if g then
		local total, visible = 0, 0
		for _, d in ipairs(g:GetDescendants()) do
			if d:IsA("BasePart") then
				total = total + 1
				if d.Transparency < 1 then visible = visible + 1 end
			end
		end
		local r = g:FindFirstChild("HumanoidRootPart")
		print("DEBUG Gojo parts:", total, "visible:", visible, "position:", r and r.Position)
	end
end)
