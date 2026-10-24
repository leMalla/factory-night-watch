"""Run GUI/presence logic checks with Lua 5.4 or its shared library."""
import ctypes
import ctypes.util
import os
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
os.environ['FNW_MOD_ROOT'] = str(ROOT / 'mod')
test = ROOT / 'tests' / 'gui.lua'
executable = shutil.which('lua5.4')
if executable:
    raise SystemExit(subprocess.call([executable, str(test)]))
library = ctypes.util.find_library('lua5.4')
if not library:
    raise SystemExit('Install Lua 5.4 (lua5.4 executable or shared library) to run tests.')
lua = ctypes.CDLL(library)
lua.luaL_newstate.restype = ctypes.c_void_p
lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
lua.luaL_loadfilex.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
lua.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_longlong, ctypes.c_void_p]
lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
lua.lua_tolstring.restype = ctypes.c_char_p
lua.lua_close.argtypes = [ctypes.c_void_p]
state = lua.luaL_newstate()
if not state:
    raise SystemExit('Cannot create Lua state')
try:
    lua.luaL_openlibs(state)
    code = lua.luaL_loadfilex(state, str(test).encode(), None) or lua.lua_pcallk(state, 0, 0, 0, 0, None)
    if code:
        print(lua.lua_tolstring(state, -1, None).decode())
        raise SystemExit(1)
finally:
    lua.lua_close(state)
