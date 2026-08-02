#!/usr/bin/env bash
# Load ASDF system (runs grovel) and copy processed grovel Lisp into grovel/<os>-<arch>/.
# Usage: ./scripts/stage-grovel.sh event-backend-libuv
# Looks for event-protocol at ./event-protocol/ or ../event-protocol/
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SYS="${1:?system name}"

if [[ -z "${EVENT_PROTOCOL_UV_INCLUDE:-}" && -f "$ROOT/build/event-protocol-uv-include" ]]; then
  export EVENT_PROTOCOL_UV_INCLUDE="$(cat "$ROOT/build/event-protocol-uv-include")"
fi

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
for cand in \
  "$ROOT/event-protocol" \
  "$ROOT/../event-protocol" \
  "$ROOT/.qlot/local-projects/event-protocol"; do
  if [[ -f "$cand/event-protocol.asd" ]]; then
    PROTO="$(cd "$cand" && pwd)"
    break
  fi
done
if [[ -z "$PROTO" ]]; then
  echo "event-protocol.asd not found (./event-protocol, ../event-protocol, or .qlot/local-projects/)" >&2
  exit 1
fi

export HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-}"
if [[ -z "${HOMEBREW_PREFIX}" && -d /opt/homebrew ]]; then
  export HOMEBREW_PREFIX=/opt/homebrew
fi

# SBCL on Windows needs drive paths; Git Bash gives /d/...
lisp_path() {
  local p="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$p"
  else
    printf '%s' "$p"
  fi
}
msys_path() {
  local p="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -u "$p"
  else
    printf '%s' "$p"
  fi
}
LISP_ROOT="$(lisp_path "$ROOT")"
LISP_PROTO="$(lisp_path "$PROTO")"

# Prefer qlot exec (cl-repository CI style) when a qlfile env is present.
run_lisp() {
  if [[ -d "$ROOT/.qlot" ]] && command -v qlot >/dev/null 2>&1; then
    qlot exec ros \
      -e "(asdf:load-asd #p\"${LISP_PROTO}/event-protocol.asd\")" \
      -e "(asdf:load-asd #p\"${LISP_ROOT}/${SYS}.asd\")" \
      -e "(asdf:load-system \"${SYS}\")" \
      -e '(format t "LOADED~%")' -q
  elif command -v ros >/dev/null 2>&1; then
    ros -e "(asdf:load-asd #p\"${LISP_PROTO}/event-protocol.asd\")" \
        -e "(asdf:load-asd #p\"${LISP_ROOT}/${SYS}.asd\")" \
        -e "(asdf:load-system \"${SYS}\")" \
        -e '(format t "LOADED~%")' -q
  else
    sbcl --non-interactive \
      --eval "(asdf:load-asd #p\"${LISP_PROTO}/event-protocol.asd\")" \
      --eval "(asdf:load-asd #p\"${LISP_ROOT}/${SYS}.asd\")" \
      --eval "(asdf:load-system \"${SYS}\")" \
      --eval '(format t "LOADED~%")'
  fi
}

# Restore grovel-cache if a prior run was interrupted after hiding it.
HIDDEN="$ROOT/.grovel-cache.staging-hidden"
if [[ -d "$HIDDEN" ]]; then
  if [[ -d "$HIDDEN/grovel-cache" ]]; then
    rm -rf "$ROOT/grovel-cache"
    mv "$HIDDEN/grovel-cache" "$ROOT/grovel-cache"
    rm -rf "$HIDDEN"
  elif [[ ! -d "$ROOT/grovel-cache" ]]; then
    mv "$HIDDEN" "$ROOT/grovel-cache"
  else
    rm -rf "$HIDDEN"
  fi
fi

# Hide grovel-cache so ASD runs grovel instead of reusing stale cached output.
if [[ -d "$ROOT/grovel-cache" ]]; then
  mv "$ROOT/grovel-cache" "$ROOT/.grovel-cache.staging-hidden"
  restore_grovel_cache() {
    if [[ -d "$ROOT/.grovel-cache.staging-hidden" ]]; then
      mv "$ROOT/.grovel-cache.staging-hidden" "$ROOT/grovel-cache"
    fi
  }
  trap restore_grovel_cache EXIT
fi

LOG="$(mktemp)"

run_lisp >"$LOG" 2>&1 || { tail -80 "$LOG"; exit 1; }

# Portable (macOS bash 3.2 has no mapfile). Also check Windows LOCALAPPDATA cache.
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/common-lisp"
PROCESSED="$(find "$CACHE" -path "*${SYS}*/grovel.processed-grovel-file" -print0 2>/dev/null | {
  newest=""
  while IFS= read -r -d '' f; do
    [[ -z "$newest" || "$f" -nt "$newest" ]] && newest="$f"
  done
  printf '%s' "$newest"
} || true)"
if [[ -z "$PROCESSED" || ! -f "$PROCESSED" ]] && [[ -n "${LOCALAPPDATA:-}" ]]; then
  PROCESSED="$(find "$(msys_path "$LOCALAPPDATA/common-lisp")" -path "*${SYS}*/grovel.processed-grovel-file" -print0 2>/dev/null | {
    newest=""
    while IFS= read -r -d '' f; do
      [[ -z "$newest" || "$f" -nt "$newest" ]] && newest="$f"
    done
    printf '%s' "$newest"
  } || true)"
fi
if [[ -z "$PROCESSED" || ! -f "$PROCESSED" ]]; then
  echo "could not locate grovel.processed-grovel-file; log:" >&2
  tail -40 "$LOG" >&2
  exit 1
fi

cp -f "$PROCESSED" "$DEST/grovel.cffi.lisp"
echo "staged $DEST/grovel.cffi.lisp from $PROCESSED"
