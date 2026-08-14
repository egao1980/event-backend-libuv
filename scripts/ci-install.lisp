;;;; Phase 1: install SUT dependency closure via cl-repository-client.

(setf *debugger-hook*
      (lambda (c h)
        (declare (ignore h))
        (format *error-output* "~&UNHANDLED: ~A~%" c)
        (uiop:quit 1)))

(setf asdf:*compile-file-failure-behaviour* :warn)

(defun call-with-ci-muffles (fn)
  #+sbcl
  (handler-bind ((sb-ext:defconstant-uneql
                  (lambda (c)
                    (declare (ignore c))
                    (let ((r (find-restart 'continue)))
                      (when r (invoke-restart r))))))
    (funcall fn))
  #-sbcl
  (funcall fn))

(call-with-ci-muffles (lambda () (asdf:load-system "cl-repository-client")))

(cl-repo:add-registry "https://ghcr.io" :namespace "egao1980/cl-systems" :priority :prepend)

(defparameter *ci-ql-sources*
  '(("babel" :ql)
    ("trivial-features" :ql)
    ("cl-unicode" :ql)))

(defun ci-quickload (name)
  (format t "~&; ci: ql fallback ~a~%" name)
  (call-with-ci-muffles (lambda () (ql:quickload name :silent t)))
  (unless (asdf:find-system name nil)
    (error "ci-quickload: ~a not findable after Quicklisp fallback" name)))

(defun ci-load (name)
  (format t "~&; ci: cl-repo load ~a~%" name)
  (call-with-ci-muffles
   (lambda ()
     (cl-repo:load-system name :sources *ci-ql-sources*)))
  (unless (asdf:component-loaded-p name)
    (error "ci-load: ~a did not load" name)))

(call-with-ci-muffles
 (lambda ()
   (ci-load "event-protocol")
   (handler-case (ci-load "cffi")
     (error (e)
       (format *error-output* "~&; ci: cl-repo load failed for cffi: ~a~%" e)
       (ci-quickload "cffi")))
   (unless (asdf:find-system "cffi-grovel" nil)
     (ci-quickload "cffi-grovel"))))

(format t "~&; ci: install phase done~%")
(uiop:quit 0)
