# Re-runs the solver checks on a mock R15 rig (no Roblox needed):  pip install lupa ; python3 run.py
from lupa import LuaRuntime
import os
os.chdir(os.path.dirname(os.path.abspath(__file__)))
for f in ("test.lua", "smooth.lua", "scan.lua"):
    print("=====", f)
    LuaRuntime().execute(open(f).read())
