;;; Stub for qlot READ of this .asd before cffi-grovel is installed (#. = read-time).
#.(progn
    (unless (find-package "CFFI-GROVEL")
      (make-package "CFFI-GROVEL" :use '())
      (export (intern "GROVEL-FILE" "CFFI-GROVEL") "CFFI-GROVEL"))
    nil)

(defsystem "event-backend-libuv"
  :version "0.1.0"
  :description "libuv backend for event-protocol (default; Windows/linux/darwin)"
  :author "egao1980"
  :license "MIT"
  :defsystem-depends-on ("cffi-grovel")
  :depends-on ("cffi" "event-protocol")
  :serial t
  :pathname "src"
  ;; Prefer overlay grovel-cache/ (no CC). Local-dev falls back to grovel-file.
  :components
  #.(let* ((asd (or *load-truename* *load-pathname*))
           (root (when asd (uiop:pathname-directory-pathname asd)))
           (cache (when root (probe-file (merge-pathnames "grovel-cache/grovel.cffi.lisp" root)))))
      (if cache
          '((:file "package")
            (:file "grovel-cached" :pathname "../grovel-cache/grovel.cffi")
            (:file "ffi")
            (:file "backend"))
          '((:file "package")
            (cffi-grovel:grovel-file "grovel")
            (:file "ffi")
            (:file "backend"))))
  :in-order-to ((test-op (test-op "event-backend-libuv/tests")))
  :properties
  (:cl-repo
   (:cffi-libraries ("libuv")
    :provides ("event-backend-libuv")
    :overlays
    ((:platform (:os "linux" :arch "amd64")
      :layers ((:role "native-library"
                :files (("lib/linux-amd64/libuv.so" . "libuv.so")
                        ("lib/linux-amd64/libuv.so.1" . "libuv.so.1")))
               (:role "cffi-grovel-output"
                :files (("grovel/linux-amd64/grovel.cffi.lisp" . "grovel.cffi.lisp")))))
     (:platform (:os "linux" :arch "arm64")
      :layers ((:role "native-library"
                :files (("lib/linux-arm64/libuv.so" . "libuv.so")
                        ("lib/linux-arm64/libuv.so.1" . "libuv.so.1")))
               (:role "cffi-grovel-output"
                :files (("grovel/linux-arm64/grovel.cffi.lisp" . "grovel.cffi.lisp")))))
     (:platform (:os "darwin" :arch "arm64")
      :layers ((:role "native-library"
                :files (("lib/darwin-arm64/libuv.dylib" . "libuv.dylib")
                        ("lib/darwin-arm64/libuv.1.dylib" . "libuv.1.dylib")))
               (:role "cffi-grovel-output"
                :files (("grovel/darwin-arm64/grovel.cffi.lisp" . "grovel.cffi.lisp")))))
     (:platform (:os "windows" :arch "amd64")
      :layers ((:role "native-library"
                :files (("lib/windows-amd64/libuv.dll" . "libuv.dll")))
               (:role "cffi-grovel-output"
                :files (("grovel/windows-amd64/grovel.cffi.lisp"
                         . "grovel.cffi.lisp")))))))))

(defsystem "event-backend-libuv/tests"
  :depends-on ("event-backend-libuv" "event-protocol/conformance" "rove")
  :pathname "tests"
  :serial t
  :components ((:file "package")
               (:file "conformance"))
  :perform (test-op (o c)
             (unless (symbol-call :event-backend-libuv/tests :run-conformance)
               (error "event-protocol/conformance failed against libuv"))))
