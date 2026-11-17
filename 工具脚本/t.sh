#!/bin/bash
# usage: t.sh <args...>   runs godot headless in project
cd /workspace/newproj/proj/game
G=/workspace/tools/godot4
exec timeout ${TMO:-600} $G --headless --path . "$@"
