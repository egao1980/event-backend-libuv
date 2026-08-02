#!/usr/bin/env bash
# Clean ubuntu:24.04 linux/amd64 smoke against GHCR event-backend-libuv.
# Proves: native + grovel-cache load without C toolchain / libuv-dev.
set -euo pipefail

VERSION="${1:-0.1.0}"
IMAGE="ghcr.io/egao1980/cl-systems/event-backend-libuv:${VERSION}"
CACHE="${CACHE:-/tmp/event-backend-libuv-smoke-cache}"
PKG="$CACHE/pkg/event-backend-libuv-${VERSION}"
PROTO="$CACHE/event-protocol"
QL="$CACHE/quicklisp"

mkdir -p "$CACHE/pull" "$CACHE/pkg"
if [[ ! -f "$PKG/native/libuv.so" && ! -f "$PKG/native/libuv.so.1" ]]; then
  command -v oras >/dev/null || { echo "need oras" >&2; exit 1; }
  rm -rf "$CACHE/pull"/* "$CACHE/pkg"/*
  oras pull --platform linux/amd64 "$IMAGE" -o "$CACHE/pull/"
  for f in "$CACHE/pull"/*.tar.gz; do tar -xzf "$f" -C "$CACHE/pkg/"; done
  # oras may nest under event-backend-libuv-<ver>/
  if [[ ! -d "$PKG" ]]; then
    found="$(find "$CACHE/pkg" -maxdepth 2 -type d -name 'event-backend-libuv-*' | head -1)"
    [[ -n "$found" ]] || { echo "package dir missing after oras pull" >&2; exit 1; }
    PKG="$found"
  fi
fi

[[ -f "$PKG/grovel-cache/grovel.cffi.lisp" ]] || {
  echo "missing grovel-cache/grovel.cffi.lisp under $PKG" >&2
  find "$PKG" -maxdepth 3 -type f | head -40 >&2
  exit 1
}

if [[ ! -f "$PROTO/event-protocol.asd" ]]; then
  command -v git >/dev/null || { echo "need git to fetch event-protocol" >&2; exit 1; }
  rm -rf "$PROTO"
  git clone --depth 1 https://github.com/egao1980/event-protocol.git "$PROTO"
fi

SMOKE_LISP="$CACHE/smoke.lisp"
cat >"$SMOKE_LISP" <<'EOF'
(require :asdf) (require :uiop)
(defvar *pkg* (uiop:getenv "EVENT_BACKEND_LIBUV_ROOT"))
(defvar *proto* (uiop:getenv "EVENT_PROTOCOL_ROOT"))
(asdf:initialize-source-registry
 `(:source-registry
   (:directory ,(uiop:ensure-directory-pathname *pkg*))
   (:directory ,(uiop:ensure-directory-pathname *proto*))
   :inherit-configuration))
;; Avoid ql local-projects index writes when /ql is reused across runs.
(when (find-package :ql)
  (ignore-errors (setf (symbol-value (find-symbol "*LOCAL-PROJECT-DIRECTORIES*" :ql)) nil)))
(ql:quickload "cffi" :silent t)
(asdf:load-system "event-protocol")
(asdf:load-system "event-backend-libuv")
(let* ((make (find-symbol "MAKE-LIBUV-BACKEND" :event-backend-libuv))
       (run (find-symbol "RUN" :event-protocol))
       (make-loop (find-symbol "MAKE-EVENT-LOOP" :event-protocol))
       (defer (find-symbol "DEFER" :event-protocol))
       (sleep* (find-symbol "SLEEP*" :event-protocol))
       (stop (find-symbol "STOP" :event-protocol))
       (backend (funcall make))
       (loop (funcall make-loop backend))
       (seen nil))
  (funcall defer backend loop (lambda () (setf seen :deferred)))
  (funcall sleep* backend loop 0.05
           :callback (lambda ()
                       (unless (eq seen :deferred)
                         (error "defer did not run before sleep callback"))
                       (setf seen :slept)
                       (funcall stop backend loop)))
  (funcall run backend loop :stop-when-idle t)
  (unless (eq seen :slept)
    (error "smoke failed: seen=~S" seen)))
(format t "~&SMOKE OK (libuv overlay, no toolchain)~%")
(uiop:quit 0)
EOF

if [[ ! -f "$QL/setup.lisp" ]]; then
  docker run --rm --platform linux/amd64 \
    -e DEBIAN_FRONTEND=noninteractive \
    -v "$QL:/ql" \
    ubuntu:24.04 \
    bash -c 'apt-get update -qq && apt-get install -y -qq ca-certificates curl sbcl >/dev/null \
      && curl -fsSL -o /tmp/ql.lisp https://beta.quicklisp.org/quicklisp.lisp \
      && sbcl --noinform --non-interactive --load /tmp/ql.lisp \
           --eval "(quicklisp-quickstart:install :path #p\"/ql/\")" \
           --eval "(ql:quickload \"cffi\" :silent t)" >/dev/null'
fi

# Package + protocol stay read-only; Quicklisp needs write for fasls / indexes.
docker run --rm --platform linux/amd64 \
  -e DEBIAN_FRONTEND=noninteractive \
  -e EVENT_BACKEND_LIBUV_ROOT=/opt/event-backend-libuv \
  -e EVENT_PROTOCOL_ROOT=/opt/event-protocol \
  -e LD_LIBRARY_PATH=/opt/event-backend-libuv/native \
  -v "$PKG:/opt/event-backend-libuv:ro" \
  -v "$PROTO:/opt/event-protocol:ro" \
  -v "$QL:/ql" \
  -v "$SMOKE_LISP:/opt/smoke.lisp:ro" \
  ubuntu:24.04 \
  bash -c 'apt-get update -qq && apt-get install -y -qq ca-certificates sbcl >/dev/null \
    && if dpkg -l libuv1-dev 2>/dev/null | grep -q ^ii; then echo FAIL:libuv1-dev; exit 1; fi \
    && if command -v gcc >/dev/null; then echo FAIL:gcc-present; exit 1; fi \
    && sbcl --noinform --non-interactive --load /ql/setup.lisp --load /opt/smoke.lisp'
