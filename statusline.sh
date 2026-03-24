#!/usr/bin/env bash
# Claude Code status line — Pac-Man style (dynamic BFS version)
# Maze 30×7 with multiple corridors & intersections.
# BFS from center determines eat order — dots vanish outward naturally.

input=$(cat)

# ── colours ──────────────────────────────────────────────────────────────────
B='\033[34m'; Y='\033[1;33m'; R='\033[1;31m'; P='\033[1;35m'
W='\033[0;37m'; DIM='\033[2m'; NC='\033[0m'

# ── extract fields ───────────────────────────────────────────────────────────
ctx_pct=$(echo "$input"    | jq -r '.context_window.used_percentage // "0"')
five_pct=$(echo "$input"   | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
week_pct=$(echo "$input"   | jq -r '.rate_limits.seven_day.used_percentage // empty')
week_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

ctx_int=$(printf "%.0f" "$ctx_pct" 2>/dev/null || echo 0)
five_int=$(printf "%.0f" "${five_pct:-0}" 2>/dev/null || echo 0)
week_int=$(printf "%.0f" "${week_pct:-0}" 2>/dev/null || echo 0)

# ── helpers ──────────────────────────────────────────────────────────────────
fmt_reset() {
  local ts="$1"; [ -z "$ts" ] && return
  local now; now=$(date +%s); local diff=$(( ts - now ))
  if (( diff <= 0 )); then printf "now"; return; fi
  local d=$(( diff / 86400 )) h=$(( (diff % 86400) / 3600 )) m=$(( (diff % 3600) / 60 ))
  if (( d > 0 )); then printf "%dd%dh" "$d" "$h"
  elif (( h > 0 )); then printf "%dh%dm" "$h" "$m"
  else printf "%dm" "$m"; fi
}

colour_pct() {
  local pct="$1"
  if   (( pct >= 80 )); then printf "${R}%d%%${NC}" "$pct"
  elif (( pct >= 50 )); then printf "${Y}%d%%${NC}" "$pct"
  else printf "${W}%d%%${NC}" "$pct"; fi
}

# ── maze (30 wide × 7 tall) ─────────────────────────────────────────────────
# 3 horizontal corridors connected by 5 vertical passages (cols 1,7,14,21,28)
# 0=wall, 1=dot
M0="000000000000000000000000000000"
M1="011111111111111111111111111110"
M2="010000010000001000000100000010"
M3="011111111111111111111111111110"
M4="010000010000001000000100000010"
M5="011111111111111111111111111110"
M6="000000000000000000000000000000"

# ── pre-build flat maze array ────────────────────────────────────────────────
declare -a MZ
for (( r=0; r<=6; r++ )); do
  eval "row=\$M${r}"
  for (( c=0; c<30; c++ )); do
    MZ[$(( r * 30 + c ))]=${row:$c:1}
  done
done

# ── BFS from center of middle corridor ───────────────────────────────────────
# Expands outward: first along row 3, then through passages to rows 1 & 5
declare -a BR BC SEEN QR QC
head=0; tail=0; bi=0

# Start: center of row 3
sr=3; sc=14
QR[0]=$sr; QC[0]=$sc; tail=1
SEEN[$(( sr * 30 + sc ))]=1

while (( head < tail )); do
  cr=${QR[$head]}; cc=${QC[$head]}; ((head++))
  BR[$bi]=$cr; BC[$bi]=$cc; ((bi++))

  # Neighbors: left, right, up, down (horizontal first for corridor-like spread)
  for dc in -1 1; do
    nc=$(( cc + dc ))
    if (( nc >= 0 && nc < 30 )); then
      idx=$(( cr * 30 + nc ))
      if [[ "${MZ[$idx]}" == "1" ]] && [[ -z "${SEEN[$idx]}" ]]; then
        SEEN[$idx]=1; QR[$tail]=$cr; QC[$tail]=$nc; ((tail++))
      fi
    fi
  done
  for dr in -1 1; do
    nr=$(( cr + dr ))
    if (( nr >= 0 && nr <= 6 )); then
      idx=$(( nr * 30 + cc ))
      if [[ "${MZ[$idx]}" == "1" ]] && [[ -z "${SEEN[$idx]}" ]]; then
        SEEN[$idx]=1; QR[$tail]=$nr; QC[$tail]=$cc; ((tail++))
      fi
    fi
  done
done
total=$bi

# ── pac-man position ─────────────────────────────────────────────────────────
eaten=$(( ctx_int * total / 100 ))
(( eaten >= total )) && eaten=$(( total - 1 ))
(( eaten < 0 )) && eaten=0
pac_r=${BR[$eaten]}; pac_c=${BC[$eaten]}

# ── ghost positions (in uneaten area, from opposite ends) ────────────────────
remaining=$(( total - eaten - 1 ))
g1r=-1; g1c=-1; g2r=-1; g2c=-1

if [ -n "$five_pct" ] && (( remaining > 0 )); then
  # Ghost1 (red): close to pac-man in BFS order. High % = closer.
  offset=$(( remaining * (100 - five_int) / 100 ))
  (( offset < 1 )) && offset=1
  g1=$(( eaten + offset ))
  (( g1 >= total )) && g1=$(( total - 1 ))
  g1r=${BR[$g1]}; g1c=${BC[$g1]}
fi

if [ -n "$week_pct" ] && (( remaining > 0 )); then
  # Ghost2 (purple): from far end of BFS. High % = closer.
  offset=$(( remaining * (100 - week_int) / 100 ))
  (( offset < 1 )) && offset=1
  g2=$(( total - offset ))
  (( g2 <= eaten )) && g2=$(( eaten + 2 ))
  (( g2 >= total )) && g2=$(( total - 1 ))
  g2r=${BR[$g2]}; g2c=${BC[$g2]}
  # Avoid overlap
  if (( g1r >= 0 && g2r == g1r && g2c == g1c )); then
    (( g2 < total - 1 )) && { ((g2++)); g2r=${BR[$g2]}; g2c=${BC[$g2]}; }
  fi
fi

# ── build display grid ──────────────────────────────────────────────────────
declare -a G
for (( i=0; i<210; i++ )); do G[$i]=${MZ[$i]}; done

# Mark eaten dots
for (( i=0; i<eaten; i++ )); do
  G[$(( BR[i] * 30 + BC[i] ))]=2
done

# Place characters
G[$(( pac_r * 30 + pac_c ))]=3
if (( g1r >= 0 )); then
  idx=$(( g1r * 30 + g1c ))
  (( idx != pac_r * 30 + pac_c )) && G[$idx]=4
fi
if (( g2r >= 0 )); then
  idx=$(( g2r * 30 + g2c ))
  (( idx != pac_r * 30 + pac_c )) && G[$idx]=5
fi

# ── render maze rows ────────────────────────────────────────────────────────
declare -a MR
for (( r=0; r<=6; r++ )); do
  line=""
  for (( c=0; c<30; c++ )); do
    case "${G[$(( r * 30 + c ))]}" in
      0) line+="${B}█${NC}" ;;
      1) line+="${W}·${NC}" ;;
      2) line+=" " ;;
      3) line+="${Y}ᗧ${NC}" ;;
      4) line+="${R}ᗝ${NC}" ;;
      5) line+="${P}ᗝ${NC}" ;;
    esac
  done
  MR[$r]="$line"
done

# ── format left-side stats ───────────────────────────────────────────────────
five_rs=$(fmt_reset "$five_reset"); week_rs=$(fmt_reset "$week_reset")
pad() { local n=$(( 27 - $1 )); printf "%*s" "$n" ""; }

ctx_c=$(colour_pct "$ctx_int"); ctx_vl=$(( 4 + ${#ctx_int} + 1 ))

if [ -n "$five_pct" ]; then
  five_c=$(colour_pct "$five_int")
  if [ -n "$five_rs" ]; then
    l5="$(printf "${R}ᗝ${NC} ${DIM}5h${NC} %s ${DIM}⟳%s${NC}" "$five_c" "$five_rs")"
    l5v=$(( 5 + ${#five_int} + 1 + 2 + ${#five_rs} ))
  else
    l5="$(printf "${R}ᗝ${NC} ${DIM}5h${NC} %s" "$five_c")"; l5v=$(( 5 + ${#five_int} + 1 ))
  fi
else l5=""; l5v=0; fi

if [ -n "$week_pct" ]; then
  week_c=$(colour_pct "$week_int")
  if [ -n "$week_rs" ]; then
    l6="$(printf "${P}ᗝ${NC} ${DIM}7d${NC} %s ${DIM}⟳%s${NC}" "$week_c" "$week_rs")"
    l6v=$(( 5 + ${#week_int} + 1 + 2 + ${#week_rs} ))
  else
    l6="$(printf "${P}ᗝ${NC} ${DIM}7d${NC} %s" "$week_c")"; l6v=$(( 5 + ${#week_int} + 1 ))
  fi
else l6=""; l6v=0; fi

# ── output ───────────────────────────────────────────────────────────────────
printf "${B}█▀▀${NC} ${B}█${NC}   ${B}▄▀▄${NC} ${B}█ █${NC} ${B}█▀▄${NC} ${B}█▀▀${NC}    ${MR[0]}\n"
printf "${B}█${NC}   ${B}█${NC}   ${B}█▀█${NC} ${B}█ █${NC} ${B}█ █${NC} ${B}█▀${NC}     ${MR[1]}\n"
printf "${B}▀▀▀${NC} ${B}▀▀▀${NC} ${B}▀ ▀${NC} ${B}▀▀▀${NC} ${B}▀▀${NC}  ${B}▀▀▀${NC}    ${MR[2]}\n"
printf "${DIM}ctx${NC} %s$(pad $ctx_vl)${MR[3]}\n" "$ctx_c"
printf "%s$(pad $l5v)${MR[4]}\n" "$l5"
printf "%s$(pad $l6v)${MR[5]}\n" "$l6"
printf "${DIM}                           ${NC}${MR[6]}\n"
