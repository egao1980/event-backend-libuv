(in-package #:event-backend-libuv)

(defvar *uv-callbacks* (make-hash-table :test #'eql))
(defvar *uv-closing* (make-hash-table :test #'eql))

(defun %addr (ptr) (pointer-address ptr))

(defun %register (ptr kind data)
  (setf (gethash (%addr ptr) *uv-callbacks*) (cons kind data))
  ptr)

(defun %unregister (ptr)
  (remhash (%addr ptr) *uv-callbacks*))

(defun %lookup (ptr)
  (gethash (%addr ptr) *uv-callbacks*))

(defun %assert-loop-open (loop)
  (when (libuv-loop-closed-p loop)
    (error "libuv loop is closed"))
  loop)

(defun %free-ptr (ptr)
  (when (and (pointerp ptr) (not (null-pointer-p ptr)))
    (foreign-free ptr)))

;;; sb-ext:atomic-exchange is missing on some SBCL Windows builds (e.g. 2.4.11);
;;; compare-and-swap is the portable SBCL primitive for cons-cell places.
(defun %steal-wake-queue (loop)
  "Atomically take and clear LOOP's wake-queue (newest-first)."
  #+sbcl
  (return-from %steal-wake-queue
    (loop for old = (slot-value loop 'wake-queue)
          when (eq (sb-ext:compare-and-swap
                    (slot-value loop 'wake-queue) old nil)
                   old)
            return old))
  (shiftf (libuv-loop-wake-queue loop) nil))

(defun %push-wake-queue (loop function)
  "Atomically push FUNCTION onto LOOP's wake-queue."
  #+sbcl
  (return-from %push-wake-queue
    (loop for old = (slot-value loop 'wake-queue)
          when (eq (sb-ext:compare-and-swap
                    (slot-value loop 'wake-queue)
                    old (cons function old))
                   old)
            return function))
  (push function (libuv-loop-wake-queue loop)))

(defun %abort-handle (ptr)
  (when (and (pointerp ptr) (not (null-pointer-p ptr)))
    (let ((entry (%lookup ptr)))
      (if entry
          (let* ((eh (getf (cdr entry) :event-handle))
                 (loop (or (getf (cdr entry) :loop)
                           (when eh (slot-value eh 'loop))))
                 (loop-ptr (and loop (libuv-loop-ptr loop))))
            (when eh
              (setf (slot-value eh 'ptr) (null-pointer)))
            (%close-handle ptr)
            (when (and loop (not (libuv-loop-closed-p loop))
                       loop-ptr (not (null-pointer-p loop-ptr)))
              (let ((addr (%addr ptr)))
                (dotimes (i 64)
                  (unless (gethash addr *uv-closing*)
                    (return))
                  (uv-run loop-ptr +uv-run-once+)))))
          (progn
            (%unregister ptr)
            (%free-ptr ptr))))))

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
  (let ((entry (%lookup handle)))
    (when entry
      (let ((eh (getf (cdr entry) :event-handle)))
        (when eh
          (setf (slot-value eh 'ptr) (null-pointer))))))
  (remhash (%addr handle) *uv-closing*)
  (%unregister handle)
  (foreign-free handle))

(defun %close-handle (ptr)
  (when (and (pointerp ptr) (not (null-pointer-p ptr)))
    (let ((addr (%addr ptr)))
      (unless (gethash addr *uv-closing*)
        (setf (gethash addr *uv-closing*) t)
        (uv-close ptr (callback %uv-close-cb))))))

(defcallback %uv-timer-cb :void ((handle :pointer))
  (let ((entry (%lookup handle)))
    (when entry
      (let* ((data (cdr entry))
             (fn (getf data :fn))
             (eh (getf data :event-handle)))
        (uv-timer-stop handle)
        (unwind-protect
             (when (and fn eh (not (event-handle-canceled-p eh)))
               (handler-case (funcall fn)
                 (error (e) (warn "timer callback error: ~A" e))))
          (%close-handle handle))))))

(defcallback %uv-idle-cb :void ((handle :pointer))
  (let ((entry (%lookup handle)))
    (when entry
      (let* ((data (cdr entry))
             (fn (getf data :fn))
             (eh (getf data :event-handle)))
        (uv-idle-stop handle)
        (unwind-protect
             (when (and fn eh (not (event-handle-canceled-p eh)))
               (handler-case (funcall fn)
                 (error (e) (warn "idle callback error: ~A" e))))
          (%close-handle handle))))))

(defcallback %uv-async-cb :void ((handle :pointer))
  (let ((entry (%lookup handle)))
    (when entry
      (let ((loop (getf (cdr entry) :loop)))
        (dolist (fn (nreverse (%steal-wake-queue loop)))
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
          (handler-case
              (if (minusp status)
                  (funcall fn :error status)
                  (funcall fn :ok))
            (error (e) (warn "poll callback error: ~A" e))))))))

(defmethod make-event-loop ((backend libuv-backend) &key)
  (load-libuv)
  (let* ((loop-ptr (foreign-alloc :uint8 :count (uv-loop-size)))
         (async-ptr (foreign-alloc :uint8 :count (uv-handle-size +uv-async+)))
         (loop-inited nil)
         (done nil))
    (unwind-protect
         (progn
           (%check (uv-loop-init loop-ptr) "uv_loop_init")
           (setf loop-inited t)
           (let ((loop (make-instance 'libuv-loop
                                      :backend backend
                                      :ptr loop-ptr
                                      :async async-ptr)))
             (%check (uv-async-init loop-ptr async-ptr (callback %uv-async-cb))
                     "uv_async_init")
             (uv-unref async-ptr)
             (%register async-ptr :async (list :loop loop))
             (setf done t)
             loop))
      (unless done
        (when loop-inited
          (ignore-errors (uv-loop-close loop-ptr)))
        (%free-ptr loop-ptr)
        (%free-ptr async-ptr)))))

(defmethod run ((backend libuv-backend) (loop libuv-loop) &key (stop-when-idle t))
  (%assert-loop-open loop)
  (with-event-loop-var (loop)
    (let ((ptr (libuv-loop-ptr loop))
          (async (libuv-loop-async loop)))
      (unless stop-when-idle
        (uv-ref async))
      (unwind-protect
           (uv-run ptr +uv-run-default+)
        (unless stop-when-idle
          (uv-unref async)))))
  loop)

(defmethod stop ((backend libuv-backend) (loop libuv-loop))
  (%assert-loop-open loop)
  (uv-stop (libuv-loop-ptr loop))
  loop)

(defmethod defer ((backend libuv-backend) (loop libuv-loop) function &key)
  (%assert-loop-open loop)
  (let* ((ptr (foreign-alloc :uint8 :count (uv-handle-size +uv-idle+)))
         (eh (make-instance 'libuv-handle :loop loop :ptr ptr :kind :idle))
         (done nil))
    (unwind-protect
         (progn
           (%check (uv-idle-init (libuv-loop-ptr loop) ptr) "uv_idle_init")
           (%register ptr :idle (list :fn function :event-handle eh))
           (%check (uv-idle-start ptr (callback %uv-idle-cb)) "uv_idle_start")
           (setf done t)
           eh)
      (unless done
        (%abort-handle ptr)))))

(defmethod sleep* ((backend libuv-backend) (loop libuv-loop) seconds &key callback)
  (%assert-loop-open loop)
  (let* ((ptr (foreign-alloc :uint8 :count (uv-handle-size +uv-timer+)))
         (eh (make-instance 'libuv-handle :loop loop :ptr ptr :kind :timer))
         (ms (max 0 (round (* seconds 1000))))
         (fn (or callback (lambda ())))
         (done nil))
    (unwind-protect
         (progn
           (%check (uv-timer-init (libuv-loop-ptr loop) ptr) "uv_timer_init")
           (%register ptr :timer (list :fn fn :event-handle eh))
           (%check (uv-timer-start ptr (callback %uv-timer-cb) ms 0) "uv_timer_start")
           (setf done t)
           eh)
      (unless done
        (%abort-handle ptr)))))

(defmethod cancel ((backend libuv-backend) (handle libuv-handle))
  (call-next-method)
  (let ((ptr (libuv-handle-ptr handle)))
    ;; Idempotent: timer/idle callbacks already uv_close + free the handle.
    ;; Never uv_*_stop a handle already in uv_close — libuv asserts
    ;; (uv_poll_stop: !uv__is_closing) which abort()s past ignore-errors.
    (let ((entry (%lookup ptr))
          (addr (and (pointerp ptr) (not (null-pointer-p ptr)) (%addr ptr))))
      (when (and addr entry (eq handle (getf (cdr entry) :event-handle))
                 (not (gethash addr *uv-closing*)))
        (case (libuv-handle-kind handle)
          (:timer (ignore-errors (uv-timer-stop ptr)))
          (:idle (ignore-errors (uv-idle-stop ptr)))
          (:poll (ignore-errors (uv-poll-stop ptr))))
        (%close-handle ptr))))
  handle)


(defmethod register-io ((backend libuv-backend) (loop libuv-loop) fd direction callback &key)
  (%assert-loop-open loop)
  (let* ((ptr (foreign-alloc :uint8 :count (uv-handle-size +uv-poll+)))
         (eh (make-instance 'libuv-handle :loop loop :ptr ptr :kind :poll))
         (events (ecase direction
                   (:read +uv-readable+)
                   (:write +uv-writable+)
                   (:read-write (logior +uv-readable+ +uv-writable+))))
         (done nil))
    (unwind-protect
         (progn
           (%check (uv-poll-init-fd (libuv-loop-ptr loop) ptr fd) "uv_poll_init")
           (%register ptr :poll (list :fn callback :event-handle eh))
           (%check (uv-poll-start ptr events (callback %uv-poll-cb)) "uv_poll_start")
           (setf done t)
           eh)
      (unless done
        (%abort-handle ptr)))))

(defmethod wake ((backend libuv-backend) (loop libuv-loop))
  (%assert-loop-open loop)
  (%check (uv-async-send (libuv-loop-async loop)) "uv_async_send")
  loop)

(defun wake-call (loop function)
  "Enqueue FUNCTION on LOOP and wake it (safe from other threads on SBCL)."
  (%push-wake-queue loop function)
  (wake (event-loop-backend loop) loop)
  loop)

(defun close-loop (loop)
  "Close async + loop after RUN has returned (drain pending uv_close)."
  (unless (libuv-loop-closed-p loop)
    (let ((async (libuv-loop-async loop))
          (ptr (libuv-loop-ptr loop)))
      (ignore-errors (%close-handle async))
      ;; uv_close is async — run until uv_loop_close succeeds (or give up).
      (dotimes (i 64)
        (uv-run ptr +uv-run-once+)
        (let ((err (uv-loop-close ptr)))
          (when (zerop err)
            (foreign-free ptr)
            (setf (libuv-loop-closed-p loop) t
                  (slot-value loop 'ptr) (null-pointer)
                  (slot-value loop 'async) (null-pointer))
            (return-from close-loop loop))))
      (%check (uv-loop-close ptr) "uv_loop_close")))
  loop)

