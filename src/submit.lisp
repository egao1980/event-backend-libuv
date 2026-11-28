(in-package #:event-backend-libuv)

;;; Default hop-off runner: per-loop cl-stack-executors thread pool.
;;; Do not specialize onto uv_queue_work (ForkJoinPool.commonPool footgun).

(defun %unless-loop-closed (loop task)
  "Run TASK (a thunk plus its hop back to LOOP). 0.2.4: CLOSE-EVENT-LOOP no
longer waits for running thunks, so one may finish after LOOP closed. Its
hop back then fails; that failure, and the unhandled-error warning that
follows it, are dropped: nobody is left to deliver to."
  (handler-bind ((warning (lambda (w)
                            (when (libuv-loop-closed-p loop)
                              (muffle-warning w)))))
    (handler-case (funcall task)
      (error (e)
        (unless (libuv-loop-closed-p loop)
          (error e))))))

(defmethod submit ((backend libuv-backend) (loop libuv-loop) thunk
                   &key callback error-callback executor)
  (let ((run (or executor (executor-runner (%ensure-submit-pool loop)))))
    (call-next-method backend loop thunk
                      :callback callback
                      :error-callback error-callback
                      :executor (lambda (task)
                                  (funcall run (lambda () (%unless-loop-closed loop task)))))))
