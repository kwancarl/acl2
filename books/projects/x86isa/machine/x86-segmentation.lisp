;; AUTHOR:
;; Shilpi Goel <shigoel@cs.utexas.edu>

(in-package "X86ISA")
(include-book "x86-linear-memory" :ttags (:undef-flg))

;; ======================================================================

(local (include-book "centaur/bitops/ihs-extensions" :dir :system))

;; ======================================================================

(defxdoc x86-segmentation
  :parents (machine)
  :short "Specification of x86 segmentation."
  :long
  "<p>This includes the translation of effective addresses to linear
   addresses and functions to read and write memory via effective
   addresses.</p>")

(defsection ia32e-segmentation
  :parents (x86-segmentation)
  :short "Specification of Segmentation in the 64-bit Mode"
  )

;; ======================================================================

;; Added by Alessandro Coglio <coglio@kestrel.edu>
(define x86-segment-base-and-bounds
  ((seg-reg (integer-range-p 0 *segment-register-names-len* seg-reg))
   x86)
  :returns (mv (base n32p) (lower-bound n33p) (upper-bound n32p))
  :parents (x86-segmentation)
  :short "Return a segment's base linear address, lower bound, and upper bound."
  :long
  "<p>
   The segment is the one in the given segment register.
   </p>
   <p>
   Even though @('*hidden-segment-register-layout*') uses 64 bits
   for the segment base address,
   addresses coming from segment descriptors are always 32 bits:
   see Intel manual, Mar'17, Vol. 3A, Sec. 3.4.5
   and AMD manual, Apr'16, Vol. 2, Sec. 4-7 and 4-8.
   Thus, this function returns an unsigned 32-bit integer as the base result.
   As an optimization, in 64-bit mode,
   since segment bases for CS, DS, SS, and ES are ignored,
   this function just returns 0 as the base result under these conditions.
   </p>
   <p>
   @('*hidden-segment-register-layout*') uses 32 bits
   for the segment limit,
   which is consistent with the 20 bits in segment descriptors
   when the G (granularity) bit is 1:
   see Intel manual, Mar'17, Vol. 3A, Sec. 3.4.5
   and AMD manual, Apr'16, Vol. 2, Sec. 4-7 and 4-8.
   Thus, the limit is an unsigned 32-bit integer.
   </p>
   <p>
   The lower bound is 0 for code segments, i.e. for the CS register.
   For data (including stack) segments,
   i.e. for the SS, DS, ES, FS, and GS registers,
   the lower bound depends on the E bit:
   if E is 0, the lower bound is 0;
   if E is 1, the segment is an expand-down data segment
   and the lower bound is one plus the segment limit.
   See Intel manual, Mar'17, Vol. 3A, Sec. 3.4.5
   and AMD manual, Apr'16, Vol. 2, Sec. 4.7 and 4-8.
   Since the limit is an unsigned 32-bit (see above),
   adding 1 may produce an unsigned 33-bit result.
   Even though this should not actually happen with well-formed segments,
   this function returns an unsigned 33-bit integer as the lower bound result.
   As an optimization, in 64-bit mode,
   since segment limits and bounds are ignored,
   this function returns 0 as the lower bound;
   the caller must ignore this result in 64-bit mode.
   </p>
   <p>
   The upper bound is the segment limit for code segments,
   i.e. for the CS register.
   For data (including stack) segments,
   i.e. for the SS, DS, ES, FS, and GS registers,
   the upper bound depends on the E and D/B bits:
   if E is 0, the upper bound is the segment limit;
   if E is 1, the segment is an expand-down data segment
   and the upper bound is 2^32-1 if D/B is 1, 2^16-1 if D/B is 0.
   See Intel manual, Mar'17, Vol. 3A, Sec. 3.4.5
   and AMD manual, Apr'16, Vol. 2, Sec. 4.7 and 4-8.
   Since  the limit is an unsigned 32-bit (see above),
   this function returns an unsigned 32-bit integer as the upper bound result.
   As an optimization, in 64-bit mode,
   since segment limits and bounds are ignored,
   this function returns 0 as the upper bound;
   the caller must ignore this result in 64-bit mode.
   </p>"
  (if (64-bit-modep x86)
      (if (or (eql seg-reg *fs*)
              (eql seg-reg *gs*))
          (b* ((hidden (xr :seg-hidden seg-reg x86))
               (base (hidden-seg-reg-layout-slice :base-addr hidden)))
            (mv (n32 base) 0 0))
        (mv 0 0 0))
    (b* ((hidden (xr :seg-hidden seg-reg x86))
         (base (hidden-seg-reg-layout-slice :base-addr hidden))
         (limit (hidden-seg-reg-layout-slice :limit hidden))
         (attr (hidden-seg-reg-layout-slice :attr hidden))
         (d/b (data-segment-descriptor-attributes-layout-slice :d/b attr))
         (e (data-segment-descriptor-attributes-layout-slice :e attr))
         (lower (if e (1+ limit) 0))
         (upper (if e (if d/b #xffffffff #xffff) limit)))
      (mv (n32 base) lower upper))))

;; Added by Alessandro Coglio <coglio@kestrel.edu>
(define ea-to-la ((eff-addr i64p)
                  (seg-reg (integer-range-p 0 *segment-register-names-len* seg-reg))
                  x86)
  :returns (mv flg (lin-addr i48p))
  :parents (x86-segmentation)
  :short "Translate an effective address to a linear address."
  :long
  "<p>
   This translation is illustrated in Intel manual, Mar'17, Vol. 3A, Fig. 3-5,
   as well in AMD mamual, Oct'2013, Vol. 1, Fig. 2-3 and 2-4.
   In addition to the effective address,
   this function takes as input (the index of) a segment register,
   whose corresponding segment selector, with the effective address,
   forms the logical address that is turned into the linear address.
   </p>
   <p>
   This translation is used:
   when fetching instructions,
   in which case the effective address is in RIP, EIP, or IP;
   when accessing the stack implicitly,
   in which case the effective address is in RSP, ESP, or SP;
   and when accessing data explicitly,
   in which case the effective address is calculated by instructions
   via @(tsee x86-effective-addr).
   In the formal model,
   RIP contains a signed 48-bit integer,
   RSP contains a signed 64-bit integer,
   and @(tsee x86-effective-addr) returns a signed 64-bit integer:
   thus, the guard of this function requires @('eff-addr')
   to be a signed 64-bit integer.
   In 64-bit mode, the caller of this function supplies as @('eff-addr')
   the content of RIP,
   the content of RSP,
   or the result of @(tsee x86-effective-address).
   In 32-bit mode, the caller of this function supplies as @('eff-addr')
   the unsigned 32-bit or 16-bit truncation of
   the content of RIP (i.e. EIP or IP),
   the content of RSP (i.e. ESP or SP),
   or the result of @(tsee x86-effective-address);
   the choice between 32-bit and 16-bit is determined by
   default address size and override prefixes.
   </p>
   <p>
   In 32-bit mode, the effective address is checked against
   the lower and upper bounds of the segment.
   In 64-bit mode, this check is skipped.
   </p>
   <p>
   In 32-bit mode,
   the effective address is added to the base address of the segment;
   the result is truncated to 32 bits, in case;
   this truncation should not actually happen with well-formed segments.
   In 64-bit mode,
   the addition of the base address of the segment is performed
   only if the segments are in registers FS and GS;
   the result is truncated to 64 bits, in case;
   this truncation should not actually happen with well-formed segments.
   </p>
   <p>
   If the translation is successful,
   this function returns a signed 48-bit integer
   that represents a canonical linear address.
   In 64-bit mode, the 64-bit linear address that results from the translation
   is checked to be canonical before returning it.
   In 32-bit mode, the 32-bit linear address that results from the translation
   is always canonical.
   If the translation fails,
   including the check that the linear address is canonical,
   a non-@('nil') error flag is returned,
   which provides some information about the failure.
   </p>"
  (if (64-bit-modep x86)
      (if (or (eql seg-reg *fs*)
              (eql seg-reg *gs*))
          (b* (((mv base & &) (x86-segment-base-and-bounds seg-reg x86))
               (lin-addr (i64 (+ base (n64 eff-addr)))))
            (if (canonical-address-p lin-addr)
                (mv nil lin-addr)
              (mv (list :non-canonical-address lin-addr) 0)))
        (mv nil (i48 eff-addr)))
    (b* (((mv base
              lower-bound
              upper-bound) (x86-segment-base-and-bounds seg-reg x86))
         ((unless (and (<= lower-bound eff-addr)
                       (<= eff-addr upper-bound)))
          (mv (list :segment-limit-fail
                    (list seg-reg eff-addr lower-bound upper-bound))
              0))
         (lin-addr (n32 (+ base eff-addr))))
      (mv nil lin-addr)))
  :guard-hints (("Goal" :in-theory (enable x86-segment-base-and-bounds))))

;; ======================================================================

;; Segmentation:

;; LLDT: http://www.ece.unm.edu/~jimp/310/slides/micro_arch2.html
;;       http://www.fermimn.gov.it/linux/quarta/x86/lldt.htm
;;       http://stackoverflow.com/questions/6886112/using-lldt-and-configuring-the-gdt-for-it
;;       http://www.osdever.net/bkerndev/Docs/gdt.htm
;;       http://duartes.org/gustavo/blog/post/memory-translation-and-segmentation/

;; QUESTION:

;; FS and GS segments are given special treatment in that their base
;; addresses are allowed to be non-zero in 64-bit mode.  The hidden
;; portions of the FS and GS registers are mapped to the
;; model-specific registers IA32_FS_BASE and IA32_GS_BASE,
;; respectively---specifically, these registers contain the segment
;; base address.  My question is:

;; 1. When the FS or GS selector is updated to point to a data-segment
;; descriptor in GDT or LDT, is the base address from the descriptor
;; used to update these model-specific registers?

;; 2. Or is the base address in the descriptor ignored completely and
;; we have to update the model-specific registers separately to
;; provide a base address for FS or GS?

;; ======================================================================

;; [TO-DO@Shilpi]: I've written the following predicates by referring
;; to the AMD manuals.  Turns out that segmentation differs
;; significantly in Intel and AMD machines.  Intel defines more fields
;; in the descriptors to be available in 64-bit mode than AMD.  Also,
;; Intel defines a descriptor --- the Task gate --- that is not
;; available in AMD machines at all.  I need to read chapters 5, 6,
;; and 7 from Intel Vol. 3 to figure out how segmentation is done on
;; Intel machines.

;; Predicates to determine valid user descriptors (in IA32e mode):

;; Code Segment Descriptor:

(define ia32e-valid-code-segment-descriptor-p
  ((descriptor :type (unsigned-byte 64)))
  :parents (ia32e-segmentation)
  :short "Recognizer for a valid code segment descriptor"

  (b* (((when (not (equal (code-segment-descriptor-layout-slice :msb-of-type
                                                                descriptor)
                          1)))
        (mv nil (cons :Invalid-Segment-Type descriptor)))

       ;; User segment?
       ((when (not (equal (code-segment-descriptor-layout-slice :s descriptor) 1)))
        (mv nil (cons :Invalid-Segment-Type descriptor)))

       ;; Segment Present?
       ((when (not (equal (code-segment-descriptor-layout-slice :p descriptor) 1)))
        (mv nil (cons :Segment-Not-Present descriptor)))

       ;; IA32e Mode is on?
       ((when (not (equal (code-segment-descriptor-layout-slice :l descriptor) 1)))
        (mv nil (cons :IA32e-Mode-Off descriptor)))

       ;; Default operand size of 32 bit and default address size of
       ;; 64 bits when no error below.
       ((when (not (equal (code-segment-descriptor-layout-slice :d descriptor) 0)))
        (mv nil (cons :IA32e-Default-Operand-Size-Incorrect descriptor))))
    (mv t 0)))

;; Data Segment Descriptor:

(define ia32e-valid-data-segment-descriptor-p
  ((descriptor :type (unsigned-byte 64)))
  :parents (ia32e-segmentation)
  :short "Recognizer for a valid data segment descriptor"

  (b* (((when (not (equal (data-segment-descriptor-layout-slice :msb-of-type
                                                                descriptor)
                          0)))
        (mv nil (cons :Invalid-Type descriptor)))

       ;; User segment?
       ((when (not (equal (data-segment-descriptor-layout-slice :s descriptor) 1)))
        (mv nil (cons :Invalid-Segment-Type descriptor)))

       ;; Segment is present.
       ((when (not (equal (data-segment-descriptor-layout-slice :p descriptor) 1)))
        (mv nil (cons :Segment-Not-Present descriptor)))

       ;; IA32e Mode is on?
       ((when (not (equal (data-segment-descriptor-layout-slice :l descriptor) 1)))
        (mv nil (cons :IA32e-Mode-Off descriptor))))
      (mv t 0)))

;; Predicates to determine valid system descriptors (in IA32e mode):

;; 64-bit LDT Descriptor:

(define ia32e-valid-ldt-segment-descriptor-p
  ((descriptor :type (unsigned-byte 128)))
  :parents (ia32e-segmentation)
  :short "Recognizer for a valid LDT segment descriptor"


  (b* ((type (system-segment-descriptor-layout-slice :type descriptor))
       ;; Valid type: 64-bit LDT?
       ((when (not (equal type #x2)))
        (mv nil (cons :Invalid-Type descriptor)))

       ;; System Segment?
       ((when (not (equal (system-segment-descriptor-layout-slice :s descriptor) 0)))
        (mv nil (cons :Invalid-Segment-Type descriptor)))

       ;; Segment Present?
       ((when (not (equal (system-segment-descriptor-layout-slice :p descriptor) 1)))
        (mv nil (cons :Segment-Not-Present descriptor)))

       ;; All zeroes?
       ((when (not (equal (system-segment-descriptor-layout-slice :all-zeroes? descriptor) 0)))
        (mv nil (cons :All-Zeroes-Absent descriptor))))

      (mv t 0)))

;; Available 64-bit TSS, and Busy 64-bit TSS Descriptor (in IA32e mode):

(define ia32e-valid-available-tss-segment-descriptor-p
  ((descriptor :type (unsigned-byte 128)))
  :parents (ia32e-segmentation)
  :short "Recognizer for a valid Available TSS segment descriptor"

  (b* ((type (system-segment-descriptor-layout-slice :type descriptor))
       ((when (not (equal type #x9)))
        (mv nil (cons :Invalid-Type descriptor)))

       ;; System Segment?
       ((when (not (equal (system-segment-descriptor-layout-slice :s descriptor) 0)))
        (mv nil (cons :Invalid-Segment-Type descriptor)))

       ((when (not (equal (system-segment-descriptor-layout-slice :p descriptor) 1)))
        (mv nil (cons :Segment-Not-Present descriptor)))

       ((when (not (equal (system-segment-descriptor-layout-slice :all-zeroes? descriptor) 0)))
        (mv nil (cons :All-Zeroes-Absent descriptor))))
      (mv t 0)))

(define ia32e-valid-busy-tss-segment-descriptor-p
  ((descriptor :type (unsigned-byte 128)))
  :parents (ia32e-segmentation)
  :short "Recognizer for a valid Busy TSS segment descriptor"

  (b* ((type (system-segment-descriptor-layout-slice :type descriptor))
       ((when (not (equal type #xB)))
        (mv nil (cons :Invalid-Type descriptor)))

       ;; System Segment?
       ((when (not (equal (system-segment-descriptor-layout-slice :s descriptor) 0)))
        (mv nil (cons :Invalid-Segment-Type descriptor)))

       ((when (not (equal (system-segment-descriptor-layout-slice :p descriptor) 1)))
        (mv nil (cons :Segment-Not-Present descriptor)))

       ((when (not (equal (system-segment-descriptor-layout-slice :all-zeroes? descriptor) 0)))
        (mv nil (cons :All-Zeroes-Absent descriptor))))
      (mv t 0)))

;; 64-bit mode Call Gate:

(define ia32e-valid-call-gate-segment-descriptor-p
  ((descriptor :type (unsigned-byte 128)))
  :parents (ia32e-segmentation)
  :short "Recognizer for a valid Call Gate segment descriptor"

  (b* ((type (call-gate-descriptor-layout-slice :type descriptor))
       ((when (not (equal type #xC)))
        (mv nil (cons :Invalid-Type descriptor)))
       ((when (not (equal (call-gate-descriptor-layout-slice :s descriptor) 0)))
        (mv nil (cons :Invalid-Segment-Type descriptor)))
       ((when (not (equal (call-gate-descriptor-layout-slice :p descriptor) 1)))
        (mv nil (cons :Segment-Not-Present descriptor)))
       ((when (not (equal (call-gate-descriptor-layout-slice :all-zeroes? descriptor) 0)))
        (mv nil (cons :All-Zeroes-Absent descriptor))))
      (mv t 0)))

;; 64-bit Interrupt and Trap Gate Descriptor:

(define ia32e-valid-interrupt-gates-segment-descriptor-p
  ((descriptor :type (unsigned-byte 128)))
  :parents (ia32e-segmentation)
  :short "Recognizer for a valid Interrupt Gate segment descriptor"

  (b* ((type (interrupt/trap-gate-descriptor-layout-slice :type descriptor))
       ((when (not (equal type #xE)))
        (mv nil (cons :Invalid-Type descriptor)))
       ((when (not (equal (interrupt/trap-gate-descriptor-layout-slice :s descriptor) 0)))
        (mv nil (cons :Invalid-Segment-Type descriptor)))
       ((when (not (equal (interrupt/trap-gate-descriptor-layout-slice :p descriptor) 1)))
        (mv nil (cons :Segment-Not-Present descriptor))))
    (mv t 0)))

(define ia32e-valid-trap-gates-segment-descriptor-p
  ((descriptor :type (unsigned-byte 128)))
  :parents (ia32e-segmentation)
  :short "Recognizer for a valid Trap Gate segment descriptor"

  (b* ((type (interrupt/trap-gate-descriptor-layout-slice :type descriptor))
       ((when (not (equal type #xF)))
        (mv nil (cons :Invalid-Type descriptor)))
       ((when (not (equal (interrupt/trap-gate-descriptor-layout-slice :s descriptor) 0)))
        (mv nil (cons :Invalid-Segment-Type descriptor)))
       ((when (not (equal (interrupt/trap-gate-descriptor-layout-slice :p descriptor) 1)))
        (mv nil (cons :Segment-Not-Present descriptor))))
      (mv t 0)))

;; ======================================================================

;; Given a descriptor, we consolidate the various flags contributing
;; to the attribute field in the hidden portions of the segment
;; registers.

;; Code Segment:
(define make-code-segment-attr-field
  ((descriptor  :type (unsigned-byte 64)))
  :parents (ia32e-segmentation)
  :short "Constructor for the Code Segment attribute field"

  :guard-hints (("Goal" :in-theory (e/d () (unsigned-byte-p))))

  (b* ((a
        (code-segment-descriptor-layout-slice :a descriptor))
       (r
        (code-segment-descriptor-layout-slice :r descriptor))
       (c
        (code-segment-descriptor-layout-slice :c descriptor))
       (msb-of-type
        (code-segment-descriptor-layout-slice :msb-of-type descriptor))
       (s
        (code-segment-descriptor-layout-slice :s descriptor))
       (dpl
        (code-segment-descriptor-layout-slice :dpl descriptor))
       (p
        (code-segment-descriptor-layout-slice :p descriptor))
       (avl
        (code-segment-descriptor-layout-slice :avl descriptor))
       (l
        (code-segment-descriptor-layout-slice :l descriptor))
       (g
        (code-segment-descriptor-layout-slice :g descriptor)))

    (!code-segment-descriptor-attributes-layout-slice
     :a a
     (!code-segment-descriptor-attributes-layout-slice
      :r r
      (!code-segment-descriptor-attributes-layout-slice
       :c c
       (!code-segment-descriptor-attributes-layout-slice
        :msb-of-type msb-of-type
        (!code-segment-descriptor-attributes-layout-slice
         :s s
         (!code-segment-descriptor-attributes-layout-slice
          :dpl dpl
          (!code-segment-descriptor-attributes-layout-slice
           :p p
           (!code-segment-descriptor-attributes-layout-slice
            :avl avl
            (!code-segment-descriptor-attributes-layout-slice
             :l l
             (!code-segment-descriptor-attributes-layout-slice
              :g g
              0)))))))))))

  ///

  (defthm-usb n16p-make-code-segment-attr
    :hyp (unsigned-byte-p 64 descriptor)
    :bound 16
    :concl (make-code-segment-attr-field descriptor)
    :hints-l (("Goal" :in-theory (e/d* () (make-code-segment-attr-field))))
    :gen-type t
    :gen-linear t))

;; Data Segment:
(define make-data-segment-attr-field
  ((descriptor  :type (unsigned-byte 64)))
  :parents (ia32e-segmentation)
  :short "Constructor for the Data Segment attribute field"

  :guard-hints (("Goal" :in-theory (e/d () (unsigned-byte-p))))

  (b* ((a
        (data-segment-descriptor-layout-slice :a descriptor))
       (w
        (data-segment-descriptor-layout-slice :w descriptor))
       (e
        (data-segment-descriptor-layout-slice :e descriptor))
       (msb-of-type
        (data-segment-descriptor-layout-slice :msb-of-type descriptor))
       (s
        (data-segment-descriptor-layout-slice :s descriptor))
       (dpl
        (data-segment-descriptor-layout-slice :dpl descriptor))
       (p
        (data-segment-descriptor-layout-slice :p descriptor))
       (avl
        (data-segment-descriptor-layout-slice :avl descriptor))
       (l
        (code-segment-descriptor-layout-slice :l descriptor))
       (d/b
        (data-segment-descriptor-layout-slice :d/b descriptor))
       (g
        (data-segment-descriptor-layout-slice :g descriptor)))

    (!data-segment-descriptor-attributes-layout-slice
     :a a
     (!data-segment-descriptor-attributes-layout-slice
      :w w
      (!data-segment-descriptor-attributes-layout-slice
       :e e
       (!data-segment-descriptor-attributes-layout-slice
        :msb-of-type msb-of-type
        (!data-segment-descriptor-attributes-layout-slice
         :s s
         (!data-segment-descriptor-attributes-layout-slice
          :dpl dpl
          (!data-segment-descriptor-attributes-layout-slice
           :p p
           (!data-segment-descriptor-attributes-layout-slice
            :avl avl
            (!data-segment-descriptor-attributes-layout-slice
             :d/b d/b
             (!data-segment-descriptor-attributes-layout-slice
              :l l
              (!data-segment-descriptor-attributes-layout-slice
               :g g
               0))))))))))))

  ///

  (defthm-usb n16p-make-data-segment-attr
    :hyp (unsigned-byte-p 64 descriptor)
    :bound 16
    :concl (make-data-segment-attr-field descriptor)
    :hints-l (("Goal" :in-theory (e/d* () (make-data-segment-attr-field))))
    :gen-type t
    :gen-linear t))

;; System Segment:
(define make-system-segment-attr-field
  ((descriptor  :type (unsigned-byte 128)))

  :parents (ia32e-segmentation)
  :short "Constructor for the System Segment attribute field"
  :guard-hints (("Goal" :in-theory (e/d ()
                                        (unsigned-byte-p))))

  (b* ((type
        (system-segment-descriptor-layout-slice :type descriptor))
       (s
        (system-segment-descriptor-layout-slice :s descriptor))
       (dpl
        (system-segment-descriptor-layout-slice :dpl descriptor))
       (p
        (system-segment-descriptor-layout-slice :p descriptor))
       (avl
        (system-segment-descriptor-layout-slice :avl descriptor))
       (g
        (system-segment-descriptor-layout-slice :g descriptor)))

    (!system-segment-descriptor-attributes-layout-slice
     :type type
     (!system-segment-descriptor-attributes-layout-slice
      :s s
      (!system-segment-descriptor-attributes-layout-slice
       :dpl dpl
       (!system-segment-descriptor-attributes-layout-slice
        :p p
        (!system-segment-descriptor-attributes-layout-slice
         :avl avl
         (!system-segment-descriptor-attributes-layout-slice
          :g g
          0)))))))

  ///

  (defthm-usb n16p-make-system-segment-attr
    :hyp (unsigned-byte-p 128 descriptor)
    :bound 16
    :concl (make-system-segment-attr-field descriptor)
    :hints-l (("Goal" :in-theory (e/d* () (make-system-segment-attr-field))))
    :gen-type t
    :gen-linear t))

;; ======================================================================