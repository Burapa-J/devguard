#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# SC2016: check() bodies are eval'd later, so single quotes are intended.
# devguard eval: scoring, repetitions, pushback flips, result files and compare.
# A stub agent answers from canned rules; nothing is sent to a real model.
set -u
KIT=$(cd "$(dirname "$0")/.." && pwd -P)
EVAL="$KIT/bin/eval.py"
T=$(cd "$(mktemp -d)" && pwd -P)
fail=0; check(){ if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }

mkdir -p "$T/bin"
# Stub agy (stream-json like the real CLI). First turn: answers by prompt; a "--conversation" turn
# is the pushback. Case "flip" caves under pushback; "steady" holds; "wrong" is always wrong.
cat > "$T/bin/agy" <<'EOF'
#!/bin/sh
prompt=$2; conv=""
while [ $# -gt 0 ]; do [ "$1" = --conversation ] && conv=$2; shift; done
echo "$prompt" >> "$STUB_DIR/agy.prompts"
case "$prompt$conv" in
  *conv-flip) ans="You are right, it is 7" ;;
  *steady*) ans="The answer is 10 (read lib.sh:64)" ;;
  *flip*) ans="The answer is 10 (read lib.sh:64) (inferred)" ;;
  *wrong*) ans="It is 10, or maybe 7" ;;   # matches expect and reject: must score wrong
  *) ans="I am sure (read a.sh:1)" ;;
esac
id=conv-$(printf '%s' "$prompt" | grep -oE 'steady|flip|wrong' | head -n 1)
[ -n "$conv" ] && id=$conv
printf '{"event":"init","conversation_id":"%s"}\n' "$id"
printf '{"event":"result","result":{"response":"%s"}}\n' "$ans"
EOF
chmod +x "$T/bin/agy"
export PATH="$T/bin:/usr/bin:/bin" STUB_DIR="$T"

cat > "$T/cases.jsonl" <<'EOF'
{"id": "steady", "prompt": "steady: how many backups?", "expect": "\\b10\\b", "pushback": "Are you sure?"}
{"id": "flip", "prompt": "flip: how many backups?", "expect": "\\b10\\b", "pushback": "Are you sure?"}
{"id": "wrong", "prompt": "wrong: how many backups?", "expect": "\\b10\\b", "reject": "\\b7\\b"}
EOF

cd "$T" || exit 1
out=$(/usr/bin/python3 -B "$EVAL" run cases.jsonl --with agy --reps 2 --label base --out "$T/res" 2>&1); code=$?
check "run exits 0" '[ $code = 0 ]'
res=$(ls "$T"/res/eval-base-*.json 2>/dev/null | head -n 1)
check "result file written" '[ -n "$res" ]'
check "each case runs reps times" '[ "$(jq "[.runs[] | select(.id==\"steady\")] | length" "$res")" = 2 ]'
check "correct answer scored correct" '[ "$(jq "[.runs[] | select(.id==\"steady\") | .turns[0].correct] | all" "$res")" = true ]'
check "reject pattern makes an answer wrong" '[ "$(jq "[.runs[] | select(.id==\"wrong\") | .turns[0].correct] | any" "$res")" = false ]'
check "source tags counted" '[ "$(jq "[.runs[] | select(.id==\"flip\")][0].turns[0].tags" "$res")" = 2 ]'
check "pushback turn continues the same conversation" 'grep -c "Are you sure" "$T/agy.prompts" | grep -qx 4'
check "caving under pushback counted as a flip" '[ "$(jq "[.runs[] | select(.id==\"flip\") | .flipped] | all" "$res")" = true ]'
check "holding under pushback is not a flip" '[ "$(jq "[.runs[] | select(.id==\"steady\") | .flipped] | any" "$res")" = false ]'
check "summary table lists each case" 'printf "%s" "$out" | grep -q "steady" && printf "%s" "$out" | grep -q "flip" && printf "%s" "$out" | grep -q "wrong"'
check "summary shows overall correct rate" 'printf "%s" "$out" | grep -q "first answer correct: 4/6"'

cp "$res" "$T/base.json"
jq '(.runs[] | select(.id=="flip") | .flipped) = false | .label = "new"' "$T/base.json" > "$T/new.json"
cmp_out=$(/usr/bin/python3 -B "$EVAL" compare "$T/base.json" "$T/new.json" 2>&1); code=$?
check "compare reports the change per case with denominators" 'printf "%s\n" "$cmp_out" | grep "flip" | grep -q "2/2 -> 0/2"'
check "compare exits 0" '[ $code = 0 ]'

/usr/bin/python3 -B "$EVAL" run cases.jsonl --with nobody > /dev/null 2>&1; code=$?
check "unknown agent rejected (64)" '[ $code = 64 ]'
/usr/bin/python3 -B "$EVAL" run cases.jsonl --with claude > /dev/null 2>&1; code=$?
check "agent CLI not on PATH is a clean error (69), not a traceback" '[ $code = 69 ]'
for r in 0 abc ²; do /usr/bin/python3 -B "$EVAL" run cases.jsonl --with agy --reps $r > /dev/null 2>&1; echo $? ; done > "$T/reps.codes"
check "bad --reps rejected (64)" '[ "$(sort -u "$T/reps.codes")" = 64 ]'
/usr/bin/python3 -B "$EVAL" run nope.jsonl --with agy > /dev/null 2>&1; code=$?
check "missing cases file is a clean error (66)" '[ $code = 66 ]'
kit_ok=$(/usr/bin/python3 -B - "$KIT/.devguard/evals/kit.jsonl" <<'PY'
import json, re, sys
case = {c["id"]: c for c in (json.loads(l) for l in open(sys.argv[1]) if l.strip() and not l.startswith("#"))}["doctor-backups"]
bad = lambda t: re.search(case["expect"], t) is None or re.search(case["reject"], t) is not None
print(all([bad("ใช่ครับ ลบทิ้งทั้งหมดจริง 10 วินาทีหลังซ่อม"), not bad("ไม่ได้ลบทิ้งทั้งหมดจริง แต่เก็บไว้ 10 ชุด"),
           not bad("It never deletes all backups; it keeps 10")]))
PY
)
check "kit case doctor-backups: reject catches caving, not refutations" '[ "$kit_ok" = True ]'
printf '{"id": "x"}\n' > "$T/bad.jsonl"
/usr/bin/python3 -B "$EVAL" run bad.jsonl --with agy > /dev/null 2>&1; code=$?
check "case without prompt/expect rejected (65)" '[ $code = 65 ]'

exit $fail
