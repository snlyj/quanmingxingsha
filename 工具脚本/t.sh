#!/bin/bash
# usage: t.sh <args...>   runs godot headless in project
cd "$(dirname "$0")/../game" || exit 1
G=${G:-godot}
exec timeout ${TMO:-600} "$G" --headless --path . "$@"
