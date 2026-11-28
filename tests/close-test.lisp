(in-package #:event-backend-libuv/tests)

;;; 0.2.4 (cl-stack-code#59): CLOSE-EVENT-LOOP does not wait for a SUBMIT
;;; thunk that is still running (a blocked HTTP request kept a CLI turn alive
;;; after its timeout). The thunk's late result is dropped: the loop is closed.

(defun %elapsed-since (start)
  (/ (- (get-internal-real-time) start) internal-time-units-per-second))

(defun %wait-for (box seconds)
  (loop with start = (get-internal-real-time)
        until (or (car box) (> (%elapsed-since start) seconds))
        do (sleep 0.01))
  (car box))

(deftest close-does-not-wait-for-a-running-submit
  (let* ((eb (make-libuv-backend))
         (el (make-event-loop eb))
         (release (list nil))
         (started (list nil))
         (finished (list nil))
         (delivered (list nil)))
    (unwind-protect
         (progn
           (submit eb el
                   (lambda ()
                     (setf (car started) t)
                     (%wait-for release 5)
                     (setf (car finished) t)
                     :late)
                   :callback (lambda (value) (setf (car delivered) (list :value value)))
                   :error-callback (lambda (e) (setf (car delivered) (list :error e))))
           (ok (%wait-for started 5) "the thunk runs")
           (sleep* eb el 0.05 :callback (lambda () (stop eb el)))
           (run eb el :stop-when-idle nil)
           (let ((start (get-internal-real-time)))
             (close-event-loop eb el)
             (ok (< (%elapsed-since start) 1)
                 (format nil "close returned after ~,2f s" (%elapsed-since start))))
           (setf (car release) t)
           (ok (%wait-for finished 5) "the thunk still finishes")
           (sleep 0.2)
           (ok (null (car delivered)) "its result is dropped"))
      (setf (car release) t))))

(deftest close-then-close-is-idempotent-with-a-busy-submit
  (let* ((eb (make-libuv-backend))
         (el (make-event-loop eb))
         (release (list nil))
         (started (list nil)))
    (unwind-protect
         (progn
           (submit eb el (lambda () (setf (car started) t) (%wait-for release 5)))
           (%wait-for started 5)
           (close-event-loop eb el)
           (ok (progn (close-event-loop eb el) t) "a second close is a no-op"))
      (setf (car release) t))))

(defun run-local ()
  "This repo's own tests (beside the shared conformance suite)."
  (rove:run-suite :event-backend-libuv/tests))
