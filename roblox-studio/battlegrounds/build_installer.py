# Regenerates Install_Battlegrounds.lua (one paste into Studio's Command Bar) from the source files in this folder.
#   python3 build_installer.py
import os
here = os.path.dirname(os.path.abspath(__file__))
FILES = [  # (parent, class, name, file)
    ("RS", "ModuleScript", "BGEngine", "BGEngine.lua"),
    ("RS", "ModuleScript", "BGConfig", "BGConfig.lua"),
    ("RS", "ModuleScript", "BGClips", "BGClips.lua"),
    ("RS", "ModuleScript", "BGCore", "BGCore.lua"),
    ("RS", "ModuleScript", "BGCloth", "BGCloth.lua"),
    ("RS", "ModuleScript", "BGRig", "BGRig.lua"),
    ("RS", "ModuleScript", "BGCinematicData", "BGCinematicData.lua"),
    ("SSS", "Script", "BGBuilder", "BGBuilder.server.lua"),
    ("SSS", "Script", "BGServer", "BGServer.server.lua"),
    ("SP", "LocalScript", "BGClient", "BGClient.client.lua"),
    ("SP", "LocalScript", "BGDirector", "BGDirector.client.lua"),
]
head = '''-- ONE-PASTE INSTALLER: Kael vs Ren battlegrounds showcase.
-- Paste this whole file into Roblox Studio's Command Bar (View > Command Bar) or the Output window's command line, press Enter.
-- Creates 7 ModuleScripts (ReplicatedStorage), 2 Scripts (ServerScriptService), 2 LocalScripts (StarterPlayerScripts).
-- Your older story / showcase scripts are DISABLED, not deleted (re-enable them in Properties if you want them back).
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local SP = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")
local function put(parent, class, name, src)
	local old = parent:FindFirstChild(name)
	if old then old:Destroy() end
	local o = Instance.new(class)
	o.Name = name
	o.Source = src
	o.Parent = parent
	print("created " .. o:GetFullName())
end
for _, container in ipairs({ SSS, SP }) do
	for _, c in ipairs(container:GetChildren()) do
		if (c:IsA("Script") or c:IsA("LocalScript")) and c.Name:sub(1, 2) ~= "BG" and c.Name:sub(1, 3) ~= "Rbx" then
			c.Enabled = false
			print("disabled (re-enable in Properties if you want it back): " .. c:GetFullName())
		end
	end
end
'''
out = [head]
for parent, cls, name, f in FILES:
    src = open(os.path.join(here, f)).read()
    assert "]====]" not in src, f
    out.append('put(%s, "%s", "%s", [====[\n%s]====])\n' % (parent, cls, name, src))
out.append('print("[BG] installed. Press Test > Play. It opens in the cinematic replay; press Tab or the Playable button to fight.")\n')
open(os.path.join(here, "Install_Battlegrounds.lua"), "w").write("".join(out))
print("wrote Install_Battlegrounds.lua", sum(len(x) for x in out), "bytes")
