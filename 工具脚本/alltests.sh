#!/bin/bash
# 全套自测：check-only + ybtest + engtest + modetest×2 + uitest + regtest + stress
cd /workspace/newproj/proj/game
G=/workspace/tools/godot4
OUT=/tmp/alltests; mkdir -p $OUT; rm -f $OUT/*
fail=0
for f in scripts/*.gd data/*.gd; do
  r=$(timeout 60 $G --headless --path . --check-only --script $f 2>&1 | grep -v "^Godot Engine" | grep -v "^$")
  if [ -n "$r" ]; then echo "CHECK FAIL $f: $r"; fail=1; else echo "check ok $f"; fi
done
run() { name=$1; shift; timeout ${TMO:-600} $G --headless --path . -- "$@" > $OUT/$name.log 2>&1; echo "$name exit=$?"; }
run yb --ybtest; tail -1 /tmp/ask_ybtest.txt; echo
run eng --engtest; cat /tmp/ask_eng_result.txt; echo
run ddz --modetest=doudizhu; cat /tmp/ask_mode_result.txt; echo
run duel --modetest=duel; cat /tmp/ask_mode_result.txt; echo
run ui --uitest; cat /tmp/ask_uitest.txt; echo
run reg --regtest; tail -1 /tmp/ask_regtest.txt; grep FAIL /tmp/ask_regtest.txt; echo
run stress --stress=${STRESS_N:-600},all,${STRESS_SEED:-5000}; tail -1 /tmp/ask_stress.txt; echo; grep FAIL /tmp/ask_stress.txt | head
if [ -n "$UIPLAY" ]; then run uiplay --uiplay=$UIPLAY; cat /tmp/ask_uiplay.txt; echo; fi
echo "=== script errors ==="
grep -h -E "SCRIPT ERROR|^ERROR|USER ERROR" -A2 $OUT/*.log | head -40
grep -h -c -E "SCRIPT ERROR|^ERROR|USER ERROR" $OUT/*.log | awk "{s+=\$1} END{print \"error_lines=\" s}"
