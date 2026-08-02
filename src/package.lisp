(defpackage #:event-backend-libuv
  (:use #:cl #:cffi #:event-protocol)
  (:export #:libuv-backend
           #:make-libuv-backend
           #:load-libuv
           #:wake-call
           #:close-loop
           #:libuv-loop
           #:libuv-handle
           #:+uv-run-default+
           #:+uv-run-once+
           #:+uv-run-nowait+
           #:+uv-readable+
           #:+uv-writable+
           #:+uv-async+
           #:+uv-idle+
           #:+uv-poll+
           #:+uv-timer+))
(in-package #:event-backend-libuv)

;; Feature for grovel cc-flags (must be set before grovel-file processes).
(eval-when (:compile-toplevel :load-toplevel :execute)
  (when (uiop:getenv "HOMEBREW_PREFIX")
    (pushnew :homebrew *features*)))

