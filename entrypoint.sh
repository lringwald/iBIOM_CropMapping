#!/usr/bin/env bash
# =============================================================================
# entrypoint.sh — iBIOM Pasture-Livestock & CropMapping WKUBE Routine
# =============================================================================
set -euo pipefail
umask 0000

# --- resolve APP_DIR regardless of `sh -c entrypoint.sh` invocation ----------
if [ -z "${APP_DIR:-}" ]; then
  _d="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo .)"
  if   [ -f "$_d/main_pasture.R" ]; then APP_DIR="$_d"
  elif [ -f /app/main_pasture.R ]; then APP_DIR=/app
  else APP_DIR="$(pwd)"; fi
fi
cd "$APP_DIR" 2>/dev/null || { echo "ERROR: APP_DIR '$APP_DIR' is not a directory" >&2; exit 1; }
if [ ! -f main_pasture.R ]; then
  echo "ERROR: main_pasture.R not found in '$PWD'. Set APP_DIR to repo root." >&2
  exit 1
fi

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  echo "iBIOM Pasture, Livestock & CropMapping WKUBE Routine"
  echo "Tasks: trial | pasture | cropland | all | check"
  echo "Configure via environment variables or config.json (see docs/routine_config.schema.json)"
  exit 0
fi

if [ "${1:-}" = "--version" ]; then
  cat .build_id 2>/dev/null || echo "development"
  exit 0
fi

TASKS="trial pasture cropland all check"
is_task() { case " $TASKS " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# --- load generated knob registry --------------------------------------------
[ -f config/knobs.generated.sh ] || { echo "ERROR: config/knobs.generated.sh missing. Run: Rscript tools/gen_config.R" >&2; exit 1; }
. config/knobs.generated.sh

# --- optional JSON config reader for non-env defaults ------------------------
json_knob() {
  local key="$1" cfg=""
  [ -f config.json ] && cfg="config.json" || { [ -f config/config.json ] && cfg="config/config.json" || true; }
  [ -z "$cfg" ] && return 1
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg k "$key" 'if has($k) and .[$k] != null then .[$k] | tostring else empty end' "$cfg" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); v=d.get(sys.argv[2]); print("" if v is None else str(v))' "$cfg" "$key" 2>/dev/null
  else
    return 1
  fi
}

KN=(); KV=(); KS=()
knob() {
  local n="$1" env_var def blank v s jv
  eval "env_var=\${KNOB_ENV_$n:-$n}; def=\${KNOB_DEFAULT_$n-}; blank=\${KNOB_BLANK_$n-}"
  v="${!env_var-}"
  if [ -n "$v" ]; then
    s="environment"
  elif [ -n "${!env_var+x}" ]; then
    v="$blank"; s="blank -> registry"
  else
    jv="$(json_knob "$n" 2>/dev/null || true)"
    if [ -n "$jv" ] && [ "$jv" != "$def" ]; then
      v="$jv"; s="config.json"
    else
      v="$def"; s="default"
    fi
  fi
  printf -v "$n" '%s' "$v"
  KN+=("$n"); KV+=("$v"); KS+=("$s")
}

for n in "${KNOB_REGISTRY[@]}"; do knob "$n"; done

off() { case "$(printf '%s' "${1:-}" | tr 'A-Z' 'a-z')" in ""|0|no|off|false|auto|default) return 0;; *) return 1;; esac; }
for b in USE_EUROSTAT_PRIORS EXPORT_SPATIAL SKIP_EXISTING TRIAL; do
  if off "${!b:-}"; then eval "$b=0"; else eval "$b=1"; fi
done

if ! is_task "$TASK"; then
  echo "ERROR: unknown TASK '$TASK'. Allowed: $TASKS" >&2
  exit 1
fi

# --- normalize TRIAL and YEARS/COUNTRIES scope -------------------------------
if [ "$TASK" = "trial" ] || [ "$TRIAL" = "1" ]; then
  if [ "$COUNTRIES" = "all" ] || [ -z "$COUNTRIES" ]; then
    COUNTRIES="AT,NL,ES"
  fi
  YEARS="2018"
fi
if [ "$(printf '%s' "$YEARS" | tr 'A-Z' 'a-z')" = "all" ]; then
  YEARS="2000,2010,2018"
fi

# --- multi-root storage resolution (WKUBE /mnt/wdrv -> local accli -> local) -
if [ ! -d "/mnt/wdrv" ]; then
  ACCLI_MNT="$HOME/accelerator/mnt/ibiom"
  if [ "$LUM_DIR" = "/mnt/wdrv/iBIOM_Explorer/Land_use_and_management" ]; then
    if [ -d "$ACCLI_MNT/iBIOM_Explorer/Land_use_and_management" ]; then
      LUM_DIR="$ACCLI_MNT/iBIOM_Explorer/Land_use_and_management"
      for i in "${!KN[@]}"; do
        [ "${KN[$i]}" = "LUM_DIR" ] && KV[$i]="$LUM_DIR" && KS[$i]="local accli mount"
      done
    elif [ -d "input/LUM_data" ]; then
      LUM_DIR="input/LUM_data"
      for i in "${!KN[@]}"; do
        [ "${KN[$i]}" = "LUM_DIR" ] && KV[$i]="$LUM_DIR" && KS[$i]="local input fallback"
      done
    fi
  fi
  if [ "$SHARED_INPUT_DIR" = "/mnt/wdrv/Data/preprocessed_data/iBIOM_CropMapping_input" ]; then
    if [ -d "$ACCLI_MNT/Data/preprocessed_data/iBIOM_CropMapping_input" ]; then
      SHARED_INPUT_DIR="$ACCLI_MNT/Data/preprocessed_data/iBIOM_CropMapping_input"
    else
      SHARED_INPUT_DIR="input"
    fi
    for i in "${!KN[@]}"; do
      [ "${KN[$i]}" = "SHARED_INPUT_DIR" ] && KV[$i]="$SHARED_INPUT_DIR" && KS[$i]="local fallback"
    done
  fi
fi

# --- persistent storage redirection under /mnt/wdrv --------------------------
if [ -n "$WORK_DIR" ] && [ -d "/mnt/wdrv" ] && [[ "$WORK_DIR" == /mnt/wdrv/* ]]; then
  mkdir -p "$WORK_DIR/$OUTPUT_DIR"
  if [ -L "$OUTPUT_DIR" ]; then
    _cur_tgt="$(readlink "$OUTPUT_DIR")"
    if [ "$_cur_tgt" != "$WORK_DIR/$OUTPUT_DIR" ]; then
      rm -f "$OUTPUT_DIR"
    fi
  elif [ -d "$OUTPUT_DIR" ]; then
    cp -an "$OUTPUT_DIR/." "$WORK_DIR/$OUTPUT_DIR/" 2>/dev/null || true
    rm -rf "$OUTPUT_DIR"
  fi
  if [ ! -e "$OUTPUT_DIR" ]; then
    ln -s "$WORK_DIR/$OUTPUT_DIR" "$OUTPUT_DIR" || {
      echo "ERROR: cannot create symlink $OUTPUT_DIR -> $WORK_DIR/$OUTPUT_DIR" >&2; exit 1;
    }
  fi
  _probe="$OUTPUT_DIR/.redirect_check.$$"
  if ! : > "$_probe" 2>/dev/null || [ ! -f "$WORK_DIR/$OUTPUT_DIR/.redirect_check.$$" ]; then
    echo "ERROR: $OUTPUT_DIR does not resolve writeably onto $WORK_DIR/$OUTPUT_DIR" >&2
    rm -f "$_probe" 2>/dev/null || true
    exit 1
  fi
  rm -f "$_probe"
  echo ">>> Mounted drive output redirect: $OUTPUT_DIR -> $WORK_DIR/$OUTPUT_DIR"
fi

mkdir -p "$OUTPUT_DIR" "$OUTPUT_DIR/$RESULT_TAG"

# Pin BLAS/OpenMP threads to 1
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1
export LUM_DIR SHARED_INPUT_DIR TASK YEARS COUNTRIES RESULT_TAG

# --- preserve local user_config.R if running outside container ---------------
USER_CFG_BACKUP=""
cleanup_user_config() {
  if [ -n "$USER_CFG_BACKUP" ] && [ -f "$USER_CFG_BACKUP" ]; then
    mv -f "$USER_CFG_BACKUP" user_config.R
  fi
}
trap cleanup_user_config EXIT

if [ "$APP_DIR" != "/app" ] && [ ! -f /.dockerenv ] && [ -f user_config.R ]; then
  USER_CFG_BACKUP=".user_config.R.bak.$$"
  cp -p user_config.R "$USER_CFG_BACKUP"
fi

# Format R vectors cleanly from comma-separated strings
r_char_vec() {
  local raw="$1"
  if [ -z "$raw" ] || [ "$(printf '%s' "$raw" | tr 'A-Z' 'a-z')" = "all" ] || [ "$(printf '%s' "$raw" | tr 'A-Z' 'a-z')" = "null" ]; then
    echo "NULL"
    return
  fi
  local IFS=',' parts=() out=""
  read -ra parts <<< "$raw"
  for p in "${parts[@]}"; do
    p="$(printf '%s' "$p" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -z "$p" ] && continue
    [ -n "$out" ] && out="$out, "
    out="$out\"$p\""
  done
  [ -z "$out" ] && echo "character()" || echo "c($out)"
}

R_YEARS="$(r_char_vec "$YEARS")"
R_COUNTRIES="$(r_char_vec "$COUNTRIES")"
if [ -n "$FORCE_PREP" ]; then
  R_FORCE_PREP="$(r_char_vec "$FORCE_PREP")"
else
  R_FORCE_PREP="character()"
fi
R_EURO="$( [ "$USE_EUROSTAT_PRIORS" = "1" ] && echo TRUE || echo FALSE )"
R_SPATIAL="$( [ "$EXPORT_SPATIAL" = "1" ] && echo TRUE || echo FALSE )"
R_SKIP="$( [ "$SKIP_EXISTING" = "1" ] && echo TRUE || echo FALSE )"
LOCAL_INPUT_DIR="$( [ -d input ] && echo "input" || echo "$SHARED_INPUT_DIR" )"

cat > user_config.R <<EOF
##### AUTO-GENERATED BY entrypoint.sh — DO NOT EDIT BY HAND #####
INPUT_DIR                   <- "$LOCAL_INPUT_DIR"
LUM_DIR                     <- "$LUM_DIR"
SHARED_INPUT_DIR            <- "$SHARED_INPUT_DIR"
GAMS_PATH                   <- "C:/GAMS/49"

RESULT_TAG                  <- "$RESULT_TAG"
RUN_YEARS                   <- $R_YEARS
GLOBIOM_targets             <- FALSE
lum_crop_map                <- c(seq(2001, 2005, 1))
FORCE_PREP                  <- $R_FORCE_PREP
SKIP_EXISTING               <- $R_SKIP

PASTURE_RESULT_TAG          <- "$RESULT_TAG"
PASTURE_RUN_YEARS           <- $R_YEARS
PASTURE_COUNTRIES           <- $R_COUNTRIES
lum_grass_map               <- 15:25
LIVESTOCK_ACCOUNTING_SOURCE <- "$LIVESTOCK_SOURCE"
FAOSTAT_EMISSION_SOURCE     <- "$EMISSION_SOURCE"
USE_EUROSTAT_PRIORS         <- $R_EURO
GWP_VERSION                 <- "$GWP_VERSION"
EXPORT_PASTURE_SPATIAL      <- $R_SPATIAL
EOF

# --- provenance banner -------------------------------------------------------
BUILD_ID="development"
[ -r .build_id ] && BUILD_ID="$(cat .build_id 2>/dev/null || echo development)"
NOW_ID="$(sh tools/build_id.sh . 2>/dev/null || echo unknown)"
GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"

echo "============================================================================="
echo ">>> iBIOM Pasture, Livestock & CropMapping WKUBE Routine"
echo ">>> Build ID:    $BUILD_ID (live disk: $NOW_ID)"
echo ">>> Git Commit:  $GIT_COMMIT"
echo ">>> App Dir:     $PWD"
echo ">>> Task:        $TASK (TRIAL=$TRIAL)"
echo ">>> Years:       $YEARS | Countries: $COUNTRIES"
echo ">>> BLAS threads: OPENBLAS=${OPENBLAS_NUM_THREADS:-unset}"
echo "-----------------------------------------------------------------------------"
for i in "${!KN[@]}"; do
  printf "    %-22s = %-42s [%s]\n" "${KN[$i]}" "${KV[$i]}" "${KS[$i]}"
done
echo "============================================================================="

# Write atomic entrypoint manifest (safe against foreign-GID file ownership on /mnt/wdrv)
EP_MANIFEST="$OUTPUT_DIR/$RESULT_TAG/entrypoint_manifest.json"
TMP_M="${TMPDIR:-/tmp}/ep_manifest.$$.json"
{
  printf '{\n  "started_utc": "%s",\n  "build_id": "%s",\n  "git_commit": "%s",\n  "task": "%s",\n  "knobs": {\n' \
    "$(date -u +%FT%TZ)" "$BUILD_ID" "$GIT_COMMIT" "$TASK"
  for i in "${!KN[@]}"; do
    printf '    "%s": {"value": "%s", "source": "%s"}%s\n' \
      "${KN[$i]}" "${KV[$i]}" "${KS[$i]}" "$([ $i -lt $(( ${#KN[@]} - 1 )) ] && echo ,)"
  done
  printf '  }\n}\n'
} > "$TMP_M" 2>/dev/null || true
rm -f "$EP_MANIFEST" 2>/dev/null || true
if [ -f "$TMP_M" ] && : 2>/dev/null > "$EP_MANIFEST"; then
  cat "$TMP_M" > "$EP_MANIFEST" || true
fi
rm -f "$TMP_M" 2>/dev/null || true

# --- dispatch requested task -------------------------------------------------
case "$TASK" in
  check)
    Rscript codes/pasture/P00_check_env.R
    ;;
  trial|pasture)
    Rscript codes/pasture/P00_check_env.R
    Rscript main_pasture.R
    ;;
  cropland)
    Rscript main.R
    ;;
  all)
    Rscript codes/pasture/P00_check_env.R
    Rscript main_pasture.R
    Rscript main.R
    ;;
esac

echo ">>> TASK=$TASK finished $(date -u +%FT%TZ)"

