; APT Utilities -- Print Specifiers
;
; Copyright (C) 2017 Kestrel Institute (http://www.kestrel.edu)
;
; License: A 3-clause BSD license. See the LICENSE file distributed with ACL2.
;
; Author: Alessandro Coglio (coglio@kestrel.edu)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(in-package "APT")

(include-book "kestrel/utilities/error-checking" :dir :system)
(include-book "kestrel/utilities/xdoc-constructors" :dir :system)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defxdoc print-specifier

  :parents (utilities)

  :short "Specifies the kinds of output
          that an APT transformation must print on the screen."

  :long

  (str::cat

   (xdoc::p
    "A transformation operates essentially in two phases:")
   (xdoc::ol
    (xdoc::li
     "It validates and processes the inputs from the user
      and, if no errors occur, constructs an event form.")
    (xdoc::li
     "It submits the event form to ACL2 via @(tsee make-event)."))
   (xdoc::p
    "Following @(tsee make-event) terminology,
     the first phase is an &lsquo;expansion&rsquo; phase.
     The second phase can be called a &lsquo;submission&rsquo; phase.
     The event form contains the main function(s) and theorem(s)
     generated by the transformation,
     along with some ancillary events;
     the main function(s) and theorem(s) can be considered
     the &lsquo;result&rsquo; of the transformation.")

   (xdoc::p
    "During the expansion phase,
     informative messages may be optionally printed on the screen.
     During the submission phase,
     the normal ACL2 output may be optionally printed on the screen.
     Finally, the result of the transformation
     may be optionally printed on the screen.")

   (xdoc::p
    "A print specifier is passed as the @(':print') input to a transformation
     to control the output options above.
     A print specifier is one of the following:")
   (xdoc::ul
    (xdoc::li
     "A list without repetitions of zero or more of
      the keywords @(':expand'), @(':submit'), and @(':result').
      The presence or absence of each keyword indicates whether
      the corresponding output should be printed or not.")
    (xdoc::li
     "One of the keywords @(':expand'), @(':submit'), and @(':result').
      This is an abbreviation for the singleton list with that keyword.")
    (xdoc::li
     "@('t'), which is an abbreviation for the list of all the keywords
      @('(:expand :submit :result)')."))

   (xdoc::p
    "Note that a print specifier does not affect error output.
     Error messages are still printed on the screen when errors occur
     (unless error output is disabled prior to calling the transformation),
     which stop processing.")))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defval *print-specifier-keywords*
  :parents (print-specifier)
  :short "List of keywords used for print specifiers."
  (list :expand :submit :result)
  ///

  (assert-event (symbol-listp *print-specifier-keywords*))

  (assert-event (no-duplicatesp-eq *print-specifier-keywords*)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define canonical-print-specifier-p (x)
  :returns (yes/no booleanp)
  :parents (print-specifier)
  :short "Recognize canonical print specifiers,
          i.e. print specifiers that are lists of keywords."
  :long
  "<p>
   These are the print specifiers that are not abbreviations.
   See @(tsee print-specifier-p) and @(tsee canonicalize-print-specifier).
   </p>"
  (and (symbol-listp x)
       (no-duplicatesp-eq x)
       (subsetp-eq x *print-specifier-keywords*)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define print-specifier-p (x)
  :returns (yes/no booleanp)
  :parents (print-specifier)
  :short "Recognize print specifiers."
  :long
  "<p>
   These are the canonical ones (see @(tsee canonical-print-specifier-p))
   as well as the ones that are abbreviations of canonical ones.
   </p>"
  (or (eq x t)
      (if (member-eq x *print-specifier-keywords*) t nil)
      (canonical-print-specifier-p x))
  ///

  (defrule print-specifier-p-when-canonical-print-specifier-p
    (implies (canonical-print-specifier-p ps)
             (print-specifier-p ps))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define canonicalize-print-specifier ((ps print-specifier-p))
  :returns (cps canonical-print-specifier-p)
  :parents (print-specifier)
  :short "Turn a print specifier into an equivalent canonical one."
  :long
  "<p>
   If the print specifier is already canonical, it is left unchanged.
   Otherwise, the abbreviation is &ldquo;expanded&rdquo;.
   </p>"
  (cond ((canonical-print-specifier-p ps) ps)
        ((member-eq ps *print-specifier-keywords*) (list ps))
        (t *print-specifier-keywords*)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(def-error-checker ensure-is-print-specifier
  ((x "Value to check."))
  "Cause an error if a value is not a print specifier,
   otherwise return an equivalent canonical print specifier."
  (((print-specifier-p x)
    "~@0 must be an APT print specifier.  See :DOC APT::PRINT-SPECIFIER."
    description))
  :parents (print-specifier acl2::error-checking)
  :returns (val (and (implies acl2::erp (equal val error-val))
                     (implies (and (not acl2::erp) error-erp)
                              (canonical-print-specifier-p val))))
  :result (canonicalize-print-specifier x))
