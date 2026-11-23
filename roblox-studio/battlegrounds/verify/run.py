# Offline pose-solver checks for every clip on a mock R15 rig:  pip install lupa ; python3 run.py
from lupa import LuaRuntime
import os, sys
os.chdir(os.path.dirname(os.path.abspath(__file__)))
for f in sys.argv[1:] or ["clips_test.lua", "core_test.lua", "tl_test.lua"]:
    if os.path.exists(f):
        print("=====", f)
        LuaRuntime().execute(open(f).read())
