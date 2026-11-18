#!/usr/bin/env bash
# 用法：bash 工具脚本/alltests.sh
# 环境变量：G=Godot 路径，STRESS_N=局数，STRESS_SEED=起始种子，UIPLAY=模拟点击局数，TMO=单项超时秒数。
set -euo pipefail

cd "$(dirname "$0")/../game"
godot=${G:-godot}
stress_n=${STRESS_N:-600}
ui_n=${UIPLAY:-}
for count in "$stress_n" "${ui_n:-1}"; do
  if [[ ! $count =~ ^[1-9][0-9]*$ ]]; then
    echo "STRESS_N 和 UIPLAY 应为正整数" >&2
    exit 2
  fi
done

out=$(mktemp -d "${TMPDIR:-/tmp}/qmxs-tests.XXXXXXXX")
export XDG_DATA_HOME="$out/user-data"
export QMX_TEST_DIR="$out"
export GODOT_SILENCE_ROOT_WARNING=1
echo "测试日志目录 $out"

if ! timeout 300 "$godot" --headless --path . --import > "$out/import.log" 2>&1; then
  cat "$out/import.log" >&2
  exit 1
fi
failed=0
for script in scripts/*.gd data/*.gd; do
  log="$out/check-${script//\//-}.log"
  if timeout 60 "$godot" --headless --path . --check-only --script "$script" > "$log" 2>&1; then
    echo "check ok $script"
  else
    echo "CHECK FAIL $script" >&2
    cat "$log" >&2
    failed=1
  fi
done
if (( failed )); then
  exit 1
fi

run() {
  local name=$1 report=$2 pattern=$3 expected=$4 status=0 found=0
  shift 4
  QMX_TEST_DIR="$out/$name" timeout "${TMO:-600}" "$godot" --headless --path . -- "$@" > "$out/$name.log" 2>&1 || status=$?
  report="$out/$name/$report"
  if [[ -f $report ]]; then
    found=$(grep -Ec "$pattern" "$report" || true)
    grep -E '^(FAIL|.*TEST_DONE|STRESS_DONE|UIPLAY_DONE|game)' "$report" || true
  fi
  echo "$name exit=$status"
  if (( status != 0 || found != expected )); then
    echo "FAIL $name：完成或通过标记 $found/$expected，详情 $out/$name.log" >&2
    failed=1
  fi
}

run yb ask_ybtest.txt '^YBTEST_DONE fails=0$' 1 --ybtest
run eng ask_eng_result.txt '^game[1-3] over=true winner=.+' 3 --engtest
run ddz ask_mode_result.txt '^game[1-3] over=true winner=.+' 3 --modetest=doudizhu
run duel ask_mode_result.txt '^game[1-3] over=true winner=.+' 3 --modetest=duel
run ui ask_uitest.txt '^game_over=true ' 1 --uitest
run reg ask_regtest.txt '^REGTEST_DONE tests=[1-9][0-9]* fails=0$' 1 --regtest
run stress ask_stress.txt "^STRESS_DONE games=$stress_n fails=0 " 1 "--stress=$stress_n,all,${STRESS_SEED:-5000}" --logdump
if [[ -n $ui_n ]]; then
  run uiplay ask_uiplay.txt "^UIPLAY_DONE games=$ui_n fails=0 " 1 "--uiplay=$ui_n"
fi

errors=$(grep -hE '^(SCRIPT ERROR|ERROR:|USER ERROR)' "$out"/*.log || true)
if [[ -n $errors ]]; then
  echo "$errors" >&2
  echo "error_lines=$(wc -l <<< "$errors")"
  failed=1
else
  echo "error_lines=0"
fi
exit "$failed"
