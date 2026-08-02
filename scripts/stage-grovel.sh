#!/usr/bin/env bash
# Load package + grovel (runs cffi-grovel) and copy processed Lisp into grovel/<os>-<arch>/.
# Usage: ./scripts/stage-grovel.sh event-backend-libuv
# Looks for event-protocol at ./event-protocol/ or ../event-protocol/
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SYS="${1:?system name}"

if [[ -z "${EVENT_PROTOCOL_UV_INCLUDE:-}" && -f "$ROOT/build/event-protocol-uv-include" ]]; then
  export EVENT_PROTOCOL_UV_INCLUDE="$(cat "$ROOT/build/event-protocol-uv-include")"
fi

# MinGW treats \ as escape in -I flags; normalize to forward slashes.
if [[ -n "${EVENT_PROTOCOL_UV_INCLUDE:-}" ]]; then
  if command -v cygpath >/dev/null 2>&1; then
    export EVENT_PROTOCOL_UV_INCLUDE="$(cygpath -m "$EVENT_PROTOCOL_UV_INCLUDE")"
  fi
  export EVENT_PROTOCOL_UV_INCLUDE="${EVENT_PROTOCOL_UV_INCLUDE//\\//}"
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

# MSYS paths + ':' (same as test.yml). Do NOT use D:/... here — ':' is
# ASDF's entry separator, so drive letters get split.
export CL_SOURCE_REGISTRY="$(msys_path "$PROTO")//:$(msys_path "$ROOT")//:${CL_SOURCE_REGISTRY:-}"

# Stage only package + grovel — ffi/backend are irrelevant for cffi-grovel-output.
STAGE_LISP="$(mktemp "${TMPDIR:-/tmp}/stage-grovel.XXXXXX")"
cleanup_stage_lisp() { rm -f "$STAGE_LISP"; }
trap cleanup_stage_lisp EXIT
cat >"$STAGE_LISP" <<EOF
(setf *debugger-hook*
      (lambda (c h)
        (declare (ignore h))
        (format *error-output* "~&UNHANDLED: ~A~%" c)
        (uiop:quit 1)))
(asdf:load-system "cffi-grovel")
;; Drive paths for load-asd (MSYS /d/... fails ASDF on Windows).
(asdf:load-asd #p"${LISP_PROTO}/event-protocol.asd")
(asdf:load-asd #p"${LISP_ROOT}/${SYS}.asd")
(asdf:load-system "event-protocol")
(let* ((sys (asdf:find-system "${SYS}" nil))
       (pkg (and sys (asdf:find-component sys "package")))
       (grovel (and sys (or (asdf:find-component sys "grovel")
                            (asdf:find-component sys "grovel-cached")))))
  (unless (and pkg grovel)
    (error "missing package/grovel components in ~A" "${SYS}"))
  (asdf:operate 'asdf:load-op pkg)
  (asdf:operate 'asdf:load-op grovel))
(format t "GROVEL-STAGED~%")
EOF
LISP_STAGE="$(lisp_path "$STAGE_LISP")"

run_lisp() {
  local load_form="(load #p\"${LISP_STAGE}\")"
  if [[ -d "$ROOT/.qlot" ]] && command -v qlot >/dev/null 2>&1; then
    qlot exec ros -e "$load_form" -q
  elif command -v ros >/dev/null 2>&1; then
    ros -e "$load_form" -q
  else
    sbcl --non-interactive --load "$LISP_STAGE"
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
    cleanup_stage_lisp
    if [[ -d "$ROOT/.grovel-cache.staging-hidden" ]]; then
      mv "$ROOT/.grovel-cache.staging-hidden" "$ROOT/grovel-cache"
    fi
  }
  trap restore_grovel_cache EXIT
fi

LOG="$(mktemp)"
find_processed() {
  local root="$1"
  [[ -d "$root" ]] || return 0
  find "$root" -path "*${SYS}*/grovel.processed-grovel-file" -print0 2>/dev/null | {
    newest=""
    while IFS= read -r -d '' f; do
      [[ -z "$newest" || "$f" -nt "$newest" ]] && newest="$f"
    done
    printf '%s' "$newest"
  } || true
}

run_lisp >"$LOG" 2>&1 || {
  echo "stage-grovel lisp failed; full log:" >&2
  cat "$LOG" >&2
  exit 1
}

# UIOP on Windows: %LOCALAPPDATA%/cache/common-lisp (not %LOCALAPPDATA%/common-lisp).
CACHE_CANDIDATES=(
  "${XDG_CACHE_HOME:-$HOME/.cache}/common-lisp"
)
if [[ -n "${LOCALAPPDATA:-}" ]]; then
  CACHE_CANDIDATES+=(
    "$(msys_path "$LOCALAPPDATA/cache/common-lisp")"
    "$(msys_path "$LOCALAPPDATA/common-lisp")"
  )
fi

PROCESSED=""
for cache in "${CACHE_CANDIDATES[@]}"; do
  PROCESSED="$(find_processed "$cache")"
  if [[ -n "$PROCESSED" && -f "$PROCESSED" ]]; then
    break
  fi
done

if [[ -z "$PROCESSED" || ! -f "$PROCESSED" ]]; then
  echo "could not locate grovel.processed-grovel-file; searched:" >&2
  printf '  %s\n' "${CACHE_CANDIDATES[@]}" >&2
  echo "full log:" >&2
  cat "$LOG" >&2
  exit 1
fi

cp -f "$PROCESSED" "$DEST/grovel.cffi.lisp"
echo "staged $DEST/grovel.cffi.lisp from $PROCESSED"
