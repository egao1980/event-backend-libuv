(in-package #:event-backend-libuv)

;;; Default hop-off runner: per-loop cl-stack-executors thread pool.
;;; Do not specialize onto uv_queue_work (ForkJoinPool.commonPool footgun).

(defmethod submit ((backend libuv-backend) (loop libuv-loop) thunk
                   &key callback error-callback executor)
  (call-next-method backend loop thunk
                    :callback callback
                    :error-callback error-callback
                    :executor (or executor
                                  (executor-runner (%ensure-submit-pool loop)))))
