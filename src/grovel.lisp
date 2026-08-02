;;;; Grovelled against uv.h at overlay build (or local-dev with headers).
;;;; Consumers with cl-repository overlays load grovel-cache/ — no CC required.
;;;;
;;;; Include search: set CPATH or EVENT_PROTOCOL_UV_INCLUDE on builders.
;;;; Local-dev also picks up Homebrew via cc-flags below.
(in-package #:event-backend-libuv)

(let ((uv-include (uiop:getenv "EVENT_PROTOCOL_UV_INCLUDE")))
  (when uv-include
    (cc-flags (format nil "-I~A/" (string-right-trim "/" uv-include)))))

(cc-flags "-I/usr/local/include/"
          "-I/opt/homebrew/include/"
          "-I/usr/include/"
          "-Ic:/include/"
          "-Ic:/include/uv/")

(include "uv.h")

(cenum (uv-run-mode)
  ((:default "UV_RUN_DEFAULT"))
  ((:once "UV_RUN_ONCE"))
  ((:nowait "UV_RUN_NOWAIT")))

(cenum (uv-handle-type)
  ((:async "UV_ASYNC"))
  ((:idle "UV_IDLE"))
  ((:poll "UV_POLL"))
  ((:timer "UV_TIMER")))

(cenum (uv-poll-event)
  ((:readable "UV_READABLE"))
  ((:writable "UV_WRITABLE")))
