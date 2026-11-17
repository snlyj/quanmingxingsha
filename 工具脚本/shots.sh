#!/bin/bash
# 用法：shots.sh <WxH> <tag> [targets...]
cd /workspace/newproj/proj/game
R=$1; TAG=$2; shift 2
for t in "$@"; do
  rm -f /tmp/ask_shot_$t.png
  timeout 200 xvfb-run -a -s "-screen 0 ${R}x24" /workspace/tools/godot4 --path . --rendering-driver opengl3 --resolution $R -- --shot=$t $SHOT_EXTRA > /tmp/shots/log_${TAG}_$t.txt 2>&1
  if [ -f /tmp/ask_shot_$t.png ]; then mv /tmp/ask_shot_$t.png /tmp/shots/${TAG}_$t.png; echo "ok $TAG $t"; else echo "MISSING $TAG $t"; fi
  grep -E "SCRIPT ERROR" -A2 /tmp/shots/log_${TAG}_$t.txt | head -5
done
