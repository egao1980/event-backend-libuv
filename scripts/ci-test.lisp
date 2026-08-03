;;;; CI: install deps via cl-repository-client, then test this checkout.

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

(call-with-ci-muffles
 (lambda ()
   (asdf:load-system "cl-repository-client")))

(defparameter *ci-ql-sources*
  '(("babel" :ql)
    ("trivial-features" :ql)
    ("cl-unicode" :ql))
  "QL pins for cl-repo deps that are intentionally sourced from Quicklisp.")

(cl-repo:add-registry "https://ghcr.io" :namespace "egao1980/cl-systems" :priority :prepend)

(defun ci-quickload (name)
  (format t "~&; ci: ql fallback ~a~%" name)
  (call-with-ci-muffles
   (lambda ()
     (ql:quickload name :silent t)))
  (unless (asdf:find-system name nil)
    (error "ci-quickload: ~a not findable after Quicklisp fallback" name)))

(defun ci-load (name &key version)
  "Load NAME via cl-repo. VERSION nil means cl-repo resolves the newest tag."
  (format t "~&; ci: cl-repo load ~a~@[:~a~]~%" name version)
  (call-with-ci-muffles
   (lambda ()
     (if version
         (cl-repo:load-system name :version version :sources *ci-ql-sources*)
         (cl-repo:load-system name :sources *ci-ql-sources*))))
  (unless (asdf:component-loaded-p name)
    (error "ci-load: ~a did not load" name)))

(defun ci-load-or-ql (name)
  (handler-case
      (ci-load name)
    (error (e)
      (format *error-output* "~&; ci: cl-repo load failed for ~a: ~a~%" name e)
      (ci-quickload name))))

(defun ci-ensure-findable-or-ql (name)
  (unless (asdf:find-system name nil)
    (ci-quickload name))
  (unless (asdf:find-system name nil)
    (error "ci-ensure-findable-or-ql: ~a not findable" name)))

(call-with-ci-muffles
 (lambda ()
   ;; Omit :version so cl-repo picks the newest published tag.
   (ci-load "event-protocol")
   (ci-load-or-ql "cffi")
   (ci-ensure-findable-or-ql "cffi-grovel")
   (unless (uiop:getenv "CI_INSTALL_DEPS_ONLY")
     (ci-ensure-findable-or-ql "rove")
     (asdf:test-system "event-backend-libuv"))))

(uiop:quit 0)
