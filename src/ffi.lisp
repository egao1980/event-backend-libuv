(in-package #:event-backend-libuv)

;;; Constants from grovel enums (portable aliases for backend code).

;; defparameter: DEFCONSTANT trips on reload (EQUAL but not EQL integers across images).
(defparameter +uv-run-default+ (foreign-enum-value 'uv-run-mode :default))
(defparameter +uv-run-once+ (foreign-enum-value 'uv-run-mode :once))
(defparameter +uv-run-nowait+ (foreign-enum-value 'uv-run-mode :nowait))
(defparameter +uv-readable+ (foreign-enum-value 'uv-poll-event :readable))
(defparameter +uv-writable+ (foreign-enum-value 'uv-poll-event :writable))
(defparameter +uv-async+ (foreign-enum-value 'uv-handle-type :async))
(defparameter +uv-idle+ (foreign-enum-value 'uv-handle-type :idle))
(defparameter +uv-poll+ (foreign-enum-value 'uv-handle-type :poll))
(defparameter +uv-timer+ (foreign-enum-value 'uv-handle-type :timer))

; libuv itself is loaded at ASDF load by the (:native-library "uv") component.

(defcfun ("uv_loop_size" uv-loop-size) :unsigned-long)
(defcfun ("uv_handle_size" uv-handle-size) :unsigned-long (type :int))
(defcfun ("uv_loop_init" uv-loop-init) :int (loop :pointer))
(defcfun ("uv_loop_close" uv-loop-close) :int (loop :pointer))
(defcfun ("uv_run" uv-run) :int (loop :pointer) (mode :int))
(defcfun ("uv_stop" uv-stop) :void (loop :pointer))
(defcfun ("uv_loop_alive" uv-loop-alive) :int (loop :pointer))
(defcfun ("uv_unref" uv-unref) :void (handle :pointer))
(defcfun ("uv_ref" uv-ref) :void (handle :pointer))

(defcfun ("uv_timer_init" uv-timer-init) :int (loop :pointer) (handle :pointer))
(defcfun ("uv_timer_start" uv-timer-start) :int
  (handle :pointer) (cb :pointer) (timeout :uint64) (repeat :uint64))
(defcfun ("uv_timer_stop" uv-timer-stop) :int (handle :pointer))

(defcfun ("uv_idle_init" uv-idle-init) :int (loop :pointer) (handle :pointer))
(defcfun ("uv_idle_start" uv-idle-start) :int (handle :pointer) (cb :pointer))
(defcfun ("uv_idle_stop" uv-idle-stop) :int (handle :pointer))

(defcfun ("uv_async_init" uv-async-init) :int
  (loop :pointer) (handle :pointer) (cb :pointer))
(defcfun ("uv_async_send" uv-async-send) :int (handle :pointer))

(defcfun ("uv_poll_init" uv-poll-init) :int
  (loop :pointer) (handle :pointer) (fd :int))
#+windows
(defcfun ("uv_poll_init_socket" uv-poll-init-socket) :int
  (loop :pointer) (handle :pointer) (socket :uint64))
(defun uv-poll-init-fd (loop handle fd)
  #+windows (uv-poll-init-socket loop handle fd)
  #-windows (uv-poll-init loop handle fd))
(defcfun ("uv_poll_start" uv-poll-start) :int
  (handle :pointer) (events :int) (cb :pointer))
(defcfun ("uv_poll_stop" uv-poll-stop) :int (handle :pointer))

(defcfun ("uv_close" uv-close) :void (handle :pointer) (cb :pointer))
(defcfun ("uv_strerror" uv-strerror) :string (err :int))

(defun %check (err op)
  (unless (zerop err)
    (error 'event-io-error
           :message (format nil "~A failed: ~A (~D)" op (uv-strerror err) err))))
