#!/bin/zsh
# One training round, start to verdict. Nothing replaces your checkpoint until
# you copy the candidate over it (see README, "Promote").
#   CATALOG=catalogs/example.json pipeline/run.sh
#   REAL=my_sentences.txt MINUTES=100 pipeline/run.sh
#   LABELS=labels.jsonl CATALOG=mine.json pipeline/run.sh   # labels you already have (Tars app, MCP): no generation step
set -uo pipefail
cd "$(dirname "$0")/.."
export PYTHONUNBUFFERED=1
# zsh: unquoted ${X} is one word (paths with spaces stay whole); ${=X} splits the flag lists.
# Apple GPUs: cap MPS memory so a long run can't swamp the machine.
export PYTORCH_MPS_HIGH_WATERMARK_RATIO=${MPS_HIGH:-0.6} PYTORCH_MPS_LOW_WATERMARK_RATIO=${MPS_LOW:-0.5}
PY=${PYTHON:-python}
CATALOG=${CATALOG:-catalogs/example.json}
st() { "$PY" pipeline/status.py stage "$@"; }
RUNS=${TARS_RUNS:-runs}   # the Tars app points this outside its (read-only) bundle
mkdir -p "$RUNS"
LOG=${RUN_LOG:-$RUNS/run_$(date +%Y%m%d-%H%M%S).log}
fail() { st failed "$1"; echo "FAILED: $1"; exit 1; }
trap 'st stopped "Stopped"; exit 130' INT TERM
{
  st starting
  if [ -z "${LABELS:-}" ]; then
    st generating "Claude writes hard, multi-step commands (no tools)"
    $PY pipeline/generate.py --catalog "$CATALOG" --workers ${WORKERS:-6} ${REAL:+--real} ${REAL:-} || fail "generation"
  fi
  st building "Split, route and skill questions"
  $PY pipeline/build.py --catalog "$CATALOG" ${LABELS:+--labels} ${LABELS:-} ${REPLAY:+--replay} ${REPLAY:-} ${=BUILD_FLAGS:-} || fail "dataset build"
  st evaluating "Baseline on the test sets"
  $PY pipeline/evaluate.py baseline || fail "baseline"
  st training "Full fine-tune"
  nice -n 5 $PY pipeline/train.py --minutes ${MINUTES:-100} --batch-size ${BATCH:-8} --grad-accum ${ACCUM:-4} ${=TRAIN_FLAGS:-} || fail "training"
  st evaluating "Base vs candidate on sentences it never saw"
  $PY pipeline/evaluate.py compare || fail "evaluation"
  st done "Finished: read the verdict"
} 2>&1 | tee "$LOG"
