(in-package #:event-backend-libuv/tests)

(defun run-conformance ()
  "Set backend maker and run shared event-protocol/conformance suite."
  (setf event-protocol/conformance:*test-backend-maker*
        (lambda () (make-libuv-backend)))
  (rove:run (asdf:find-system "event-protocol/conformance")))
