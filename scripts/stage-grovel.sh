#!/usr/bin/env bash
# Load ASDF system (runs grovel) and copy processed grovel Lisp into grovel/<os>-<arch>/.
# Usage: ./scripts/stage-grovel.sh event-backend-libuv
# Looks for event-protocol at ./event-protocol/ or ../event-protocol/
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SYS="${1:?system name}"

uname_s="$(uname -s)"
uname_m="$(uname -m)"
case "$uname_s" in
  Linux) os=linux ;;
  Darwin) os=darwin ;;
  MINGW*|MSYS*|CYGWIN*) os=windows ;;
  *) echo "unsupported OS: $uname_s" >&2; exit 1 ;;
esac
case "$uname_m" in
  x86_64|amd64) arch=amd64 ;;
  aarch64|arm64) arch=arm64 ;;
  *) echo "unsupported arch: $uname_m" >&2; exit 1 ;;
esac

DEST="$ROOT/grovel/${os}-${arch}"
mkdir -p "$DEST"

PROTO=""
for cand in "$ROOT/event-protocol" "$ROOT/../event-protocol"; do
  if [[ -f "$cand/event-protocol.asd" ]]; then
    PROTO="$(cd "$cand" && pwd)"
    break
  fi
done
if [[ -z "$PROTO" ]]; then
  echo "event-protocol.asd not found (expected ./event-protocol or ../event-protocol)" >&2
  exit 1
fi

export HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-}"
if [[ -z "${HOMEBREW_PREFIX}" && -d /opt/homebrew ]]; then
  export HOMEBREW_PREFIX=/opt/homebrew
fi

LISP=(sbcl --non-interactive)
if command -v ros >/dev/null 2>&1; then
  LISP=(ros -e)
fi

LOG="$(mktemp)"
run_lisp() {
  if [[ "${LISP[0]}" == "ros" ]]; then
    ros -e "(asdf:load-asd #p\"${PROTO}/event-protocol.asd\")" \
        -e "(asdf:load-asd #p\"${ROOT}/${SYS}.asd\")" \
        -e "(asdf:load-system \"${SYS}\")" \
        -e '(format t "LOADED~%")' -q
  else
    sbcl --non-interactive \
      --eval "(asdf:load-asd #p\"${PROTO}/event-protocol.asd\")" \
      --eval "(asdf:load-asd #p\"${ROOT}/${SYS}.asd\")" \
      --eval "(asdf:load-system \"${SYS}\")" \
      --eval '(format t "LOADED~%")'
  fi
}

run_lisp >"$LOG" 2>&1 || { tail -80 "$LOG"; exit 1; }

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/common-lisp"
mapfile -d '' -t _grovel_cache < <(find "$CACHE" -path "*${SYS}*/grovel.processed-grovel-file" -print0 2>/dev/null || true)
PROCESSED=""
if ((${#_grovel_cache[@]} > 0)); then
  PROCESSED="$(ls -t "${_grovel_cache[@]}" 2>/dev/null | head -1)"
fi
if [[ -z "$PROCESSED" || ! -f "$PROCESSED" ]]; then
  echo "could not locate grovel.processed-grovel-file; log:" >&2
  tail -40 "$LOG" >&2
  exit 1
fi

cp -f "$PROCESSED" "$DEST/grovel.cffi.lisp"
echo "staged $DEST/grovel.cffi.lisp from $PROCESSED"
