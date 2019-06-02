; Cryptographic Library
;
; Copyright (C) 2019 Kestrel Institute (http://www.kestrel.edu)
;
; License: A 3-clause BSD license. See the LICENSE file distributed with ACL2.
;
; Author: Alessandro Coglio (coglio@kestrel.edu)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(in-package "CRYPTO")

(include-book "definterface-pbkdf2")
(include-book "hmac-sha-512")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(definterface-pbkdf2 pbkdf2-hmac-sha-512
  :hmac hmac-sha-512
  :parents (interfaces)
  :short "PBKDF2 HMAC-SHA-512 interface."
  :long
  (xdoc::topstring
   (xdoc::p
    "We instantiate PBKDF2 with HMAC-SHA-512.")))
