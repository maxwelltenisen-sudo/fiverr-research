-- LocalScript: put in StarterPlayer > StarterPlayerScripts.
-- Moves the camera to each shot sent by StoryBuilder and shows optional captions.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local cam = workspace.CurrentCamera
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

remote.OnClientEvent:Connect(function(data)
	cam.CameraType = Enum.CameraType.Scriptable
	TweenService:Create(cam, TweenInfo.new(data.tween, Enum.EasingStyle.Sine), { CFrame = data.cframe }):Play()
	label.Text = data.caption or ""
end)
