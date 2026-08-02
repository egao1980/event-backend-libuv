(defpackage #:event-backend-libuv/tests
  (:use #:cl #:rove #:event-protocol #:event-backend-libuv)
  (:shadowing-import-from #:event-protocol #:run))
(in-package #:event-backend-libuv/tests)
