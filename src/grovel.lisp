;;;; Grovelled against uv.h at overlay build (or local-dev with headers).
;;;; Consumers with cl-repository overlays load grovel-cache/ — no CC required.
;;;;
;;;; Include search: set CPATH or EVENT_PROTOCOL_UV_INCLUDE on builders.
;;;; Local-dev also picks up Homebrew via cc-flags below.
;;;;
;;;; Note: this file is DSL for cffi-grovel — only grovel forms (or #. that
;;;; expand to them). Plain LET/WHEN are unknown syntax.
(in-package #:event-backend-libuv)

#.(let* ((uv (uiop:getenv "EVENT_PROTOCOL_UV_INCLUDE"))
         (extra (when (and uv (plusp (length uv)))
                  (list (format nil "-I~A/" (string-right-trim "/" uv))))))
    `(cc-flags ,@extra
               "-I/usr/local/include/"
               "-I/opt/homebrew/include/"
               "-I/usr/include/"
               "-Ic:/include/"
               "-Ic:/include/uv/"))

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
