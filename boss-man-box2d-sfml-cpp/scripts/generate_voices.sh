#!/usr/bin/env bash
#
# Digitizes spoken voice clips for the C++ game using a macOS `say` voice, so the
# port can play them without any runtime TTS. Re-run any time you change the
# voice or the wording — the clips are regenerated in place.
#
#   ./scripts/generate_voices.sh                 # default voice (Rocko)
#   VOICE="Daniel" ./scripts/generate_voices.sh  # different voice
#   RATE=160 ./scripts/generate_voices.sh        # words-per-minute (default: natural)
#
# Output: assets/voice/<key>.wav  (16-bit mono PCM — SFML-friendly)
#
set -euo pipefail
cd "$(dirname "$0")/.."   # repo root

VOICE="${VOICE:-Rocko (English (US))}"
RATE="${RATE:-}"                       # empty = the voice's natural speed (no slowdown)
OUTDIR="${OUTDIR:-assets/voice}"
mkdir -p "$OUTDIR"

# ---- wording (edit freely, then re-run) ----------------------------------
# Item display names. The codes (P/F/C/M) must match the C++ key builder in
# Game::collectTPSReport — change names here, not the codes. (A case function,
# not an associative array, so this runs on the stock macOS bash 3.2.)
# These match the in-game HUD exactly: "The TPS report is missing Printer, Fax."
item_name() {
  case "$1" in
    P) printf 'Printer' ;;
    F) printf 'Fax' ;;
    C) printf 'Cover Sheet' ;;
    M) printf 'Book Binder' ;;
  esac
}
TPS_PREFIX="The TPS report is missing"   # leading phrase
TPS_SUFFIX="."                            # trailing punctuation

# Joins item codes into a comma-separated list, e.g. "Printer, Fax, Cover Sheet"
# (no "and", no Oxford-style "the") — matches Strings.Message.tpsMissingItems.
natural_list() {
  local it=("$@") out="" i
  for ((i=0; i<$#; i++)); do
    if (( i > 0 )); then out+=", "; fi
    out+="$(item_name "${it[i]}")"
  done
  printf '%s' "$out"
}

render() {  # render <key> <text>
  local key="$1" text="$2"
  local aiff="$OUTDIR/$key.aiff" wav="$OUTDIR/$key.wav"
  if [[ -n "$RATE" ]]; then say -v "$VOICE" -r "$RATE" -o "$aiff" "$text"
  else                       say -v "$VOICE" -o "$aiff" "$text"; fi
  afconvert -f WAVE -d LEI16 "$aiff" "$wav"
  rm -f "$aiff"
  printf '  %-22s "%s"\n' "$key.wav" "$text"
}

echo "Voice: $VOICE  |  Rate: ${RATE:-natural}  |  Out: $OUTDIR"
echo "TPS report — every missing-item combination:"

# Required items in canonical order; bit b -> CODES[b].
CODES=(P F C M)
for ((mask=1; mask<=15; mask++)); do      # all 15 non-empty subsets
  subset=()
  for ((b=0; b<4; b++)); do (( mask & (1<<b) )) && subset+=("${CODES[b]}"); done
  key="tps_missing_$(IFS=; printf '%s' "${subset[*]}")"   # e.g. tps_missing_PC
  text="$TPS_PREFIX $(natural_list "${subset[@]}")$TPS_SUFFIX"
  render "$key" "$text"
done

# ---- random spoken pools (boss picks one clip at random in-game) ----------
# <prefix>_1.wav, <prefix>_2.wav, ... — the C++ SoundManager::playVoiceRandom
# probes how many exist, so add/remove lines freely and just re-run. Lines are
# verbatim from Strings.Speech in the SpriteKit build.
render_pool() {  # render_pool <prefix> <line>...
  local prefix="$1"; shift
  local i=1
  for line in "$@"; do render "${prefix}_${i}" "$line"; i=$((i + 1)); done
}

echo "Boss capture lines:"
render_pool capture "Aw, geez." "Hey now." "Whoaaa." "Ouch."

echo "Caught-by-boss lines:"
render_pool caught "TPS reports." "Cover sheet please." "Saturday's the day." \
  "Memo, anyone?" "Did you see my shiny red stapler?"

echo "Fish / treat lines:"
render_pool fish "Terrific." "Fantastic." "Swell." "Niiice."

echo "TPS-report-delivered lines:"
render_pool tps_done "Atta boy." "Well done." "Excellent." "Solid work."

echo "Game-over lines:"
render_pool gameover "Please clear out your desk." "Security, escort him." \
  "If you would work Saturday, that'd be great." "Did you see my shiny red stapler?" \
  "Please add a cover sheet for your TPS Report."

echo "Level-start lines:"
render_pool levelstart "Hi there." "What's happening?" "New floor." "Welcome back."

echo "Done."
