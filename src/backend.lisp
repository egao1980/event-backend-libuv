(in-package #:event-backend-libuv)

(defvar *uv-callbacks* (make-hash-table :test #'eql))

(defun %addr (ptr) (pointer-address ptr))

(defun %register (ptr kind data)
  (setf (gethash (%addr ptr) *uv-callbacks*) (cons kind data))
  ptr)

(defun %unregister (ptr)
  (remhash (%addr ptr) *uv-callbacks*))

(defun %lookup (ptr)
  (gethash (%addr ptr) *uv-callbacks*))

(defclass libuv-backend (event-backend)
  ()
  (:default-initargs :name "libuv"))

(defun make-libuv-backend ()
  (load-libuv)
  (make-instance 'libuv-backend))

(defclass libuv-loop (event-loop)
  ((ptr :initarg :ptr :reader libuv-loop-ptr)
   (async :initarg :async :reader libuv-loop-async)
   (wake-queue :initform nil :accessor libuv-loop-wake-queue)
   (closed :initform nil :accessor libuv-loop-closed-p)))

(defclass libuv-handle (event-handle)
  ((ptr :initarg :ptr :reader libuv-handle-ptr)
   (kind :initarg :kind :reader libuv-handle-kind)))

(defcallback %uv-close-cb :void ((handle :pointer))
  (%unregister handle)
  (foreign-free handle))

(defun %close-handle (ptr)
  (when (and (pointerp ptr) (not (null-pointer-p ptr)))
    (uv-close ptr (callback %uv-close-cb))))

(defcallback %uv-timer-cb :void ((handle :pointer))
  (let ((entry (%lookup handle)))
    (when entry
      (let* ((data (cdr entry))
             (fn (getf data :fn))
             (eh (getf data :event-handle)))
        (uv-timer-stop handle)
        (when (and fn eh (not (event-handle-canceled-p eh)))
          (funcall fn))
        (%close-handle handle)))))

(defcallback %uv-idle-cb :void ((handle :pointer))
  (let ((entry (%lookup handle)))
    (when entry
      (let* ((data (cdr entry))
             (fn (getf data :fn))
             (eh (getf data :event-handle)))
        (uv-idle-stop handle)
        (when (and fn eh (not (event-handle-canceled-p eh)))
          (funcall fn))
        (%close-handle handle)))))

(defcallback %uv-async-cb :void ((handle :pointer))
  (let ((entry (%lookup handle)))
    (when entry
      (let ((loop (getf (cdr entry) :loop)))
        (dolist (fn (nreverse (shiftf (libuv-loop-wake-queue loop) nil)))
          (handler-case (funcall fn)
            (error (e)
              (warn "wake callback error: ~A" e))))))))

(defcallback %uv-poll-cb :void ((handle :pointer) (status :int) (events :int))
  (declare (ignore events))
  (let ((entry (%lookup handle)))
    (when entry
      (let* ((data (cdr entry))
             (fn (getf data :fn))
             (eh (getf data :event-handle)))
        (when (and fn eh (not (event-handle-canceled-p eh)))
          (if (minusp status)
              (funcall fn :error status)
              (funcall fn :ok)))))))

(defmethod make-event-loop ((backend libuv-backend) &key)
  (load-libuv)
  (let* ((loop-ptr (foreign-alloc :uint8 :count (uv-loop-size)))
         (async-ptr (foreign-alloc :uint8 :count (uv-handle-size +uv-async+))))
    (%check (uv-loop-init loop-ptr) "uv_loop_init")
    (let ((loop (make-instance 'libuv-loop
                               :backend backend
                               :ptr loop-ptr
                               :async async-ptr)))
      (%check (uv-async-init loop-ptr async-ptr (callback %uv-async-cb))
              "uv_async_init")
      (uv-unref async-ptr)
      (%register async-ptr :async (list :loop loop))
      loop)))

(defmethod run ((backend libuv-backend) (loop libuv-loop) &key (stop-when-idle t))
  (declare (ignore stop-when-idle))
  (with-event-loop-var (loop)
    (uv-run (libuv-loop-ptr loop) +uv-run-default+))
  loop)

(defmethod stop ((backend libuv-backend) (loop libuv-loop))
  (uv-stop (libuv-loop-ptr loop))
  loop)

(defmethod defer ((backend libuv-backend) (loop libuv-loop) function &key)
  (let* ((ptr (foreign-alloc :uint8 :count (uv-handle-size +uv-idle+)))
         (eh (make-instance 'libuv-handle :loop loop :ptr ptr :kind :idle)))
    (%check (uv-idle-init (libuv-loop-ptr loop) ptr) "uv_idle_init")
    (%register ptr :idle (list :fn function :event-handle eh))
    (%check (uv-idle-start ptr (callback %uv-idle-cb)) "uv_idle_start")
    eh))

(defmethod sleep* ((backend libuv-backend) (loop libuv-loop) seconds &key callback)
  (let* ((ptr (foreign-alloc :uint8 :count (uv-handle-size +uv-timer+)))
         (eh (make-instance 'libuv-handle :loop loop :ptr ptr :kind :timer))
         (ms (max 0 (round (* seconds 1000))))
         (fn (or callback (lambda ()))))
    (%check (uv-timer-init (libuv-loop-ptr loop) ptr) "uv_timer_init")
    (%register ptr :timer (list :fn fn :event-handle eh))
    (%check (uv-timer-start ptr (callback %uv-timer-cb) ms 0) "uv_timer_start")
    eh))

(defmethod cancel ((backend libuv-backend) (handle libuv-handle))
  (call-next-method)
  (let ((ptr (libuv-handle-ptr handle)))
    ;; Idempotent: timer/idle callbacks already uv_close + free the handle.
    (when (and (pointerp ptr) (not (null-pointer-p ptr)) (%lookup ptr))
      (case (libuv-handle-kind handle)
        (:timer (ignore-errors (uv-timer-stop ptr)))
        (:idle (ignore-errors (uv-idle-stop ptr)))
        (:poll (ignore-errors (uv-poll-stop ptr))))
      (%close-handle ptr)))
  handle)


(defmethod register-io ((backend libuv-backend) (loop libuv-loop) fd direction callback &key)
  (let* ((ptr (foreign-alloc :uint8 :count (uv-handle-size +uv-poll+)))
         (eh (make-instance 'libuv-handle :loop loop :ptr ptr :kind :poll))
         (events (ecase direction
                   (:read +uv-readable+)
                   (:write +uv-writable+)
                   (:read-write (logior +uv-readable+ +uv-writable+)))))
    (%check (uv-poll-init (libuv-loop-ptr loop) ptr fd) "uv_poll_init")
    (%register ptr :poll (list :fn callback :event-handle eh))
    (%check (uv-poll-start ptr events (callback %uv-poll-cb)) "uv_poll_start")
    eh))

(defmethod wake ((backend libuv-backend) (loop libuv-loop))
  (%check (uv-async-send (libuv-loop-async loop)) "uv_async_send")
  loop)

(defun wake-call (loop function)
  "Enqueue FUNCTION on LOOP and wake it (safe from other threads on SBCL)."
  #+sbcl (sb-ext:atomic-push function (slot-value loop 'wake-queue))
  #-sbcl (push function (libuv-loop-wake-queue loop))
  (wake (event-loop-backend loop) loop)
  loop)

(defun close-loop (loop)
  "Close async + loop after RUN has returned (drain pending uv_close)."
  (unless (libuv-loop-closed-p loop)
    (let ((async (libuv-loop-async loop))
          (ptr (libuv-loop-ptr loop)))
      (ignore-errors (%close-handle async))
      ;; uv_close is async — run until uv_loop_close succeeds (or give up).
      (loop for i below 64
            do (uv-run ptr +uv-run-default+)
               (let ((err (uv-loop-close ptr)))
                 (when (zerop err)
                   (foreign-free ptr)
                   (setf (libuv-loop-closed-p loop) t)
                   (return-from close-loop loop)))
            finally (%check (uv-loop-close ptr) "uv_loop_close"))))
  loop)

