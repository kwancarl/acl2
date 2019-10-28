; SVL - Listener-based Hierachical Symbolic Vector Hardware Analysis Framework
; Copyright (C) 2019 Centaur Technology
;
; License: (An MIT/X11-style license)
;
;   Permission is hereby granted, free of charge, to any person obtaining a
;   copy of this software and associated documentation files (the "Software"),
;   to deal in the Software without restriction, including without limitation
;   the rights to use, copy, modify, merge, publish, distribute, sublicense,
;   and/or sell copies of the Software, and to permit persons to whom the
;   Software is furnished to do so, subject to the following conditions:
;
;   The above copyright notice and this permission notice shall be included in
;   all copies or substantial portions of the Software.
;
;   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
;   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
;   DEALINGS IN THE SOFTWARE.
;
; Original author: Mertcan Temel <mert@utexas.edu>

(in-package "SVL")

(include-book "svl2-flatten")
(include-book "svl")

(progn
  (define svl2-get-module-rank ((modname sv::modname-p)
                                (modules svl2-module-alist-p))
    :returns (res natp)
    (b* ((module (assoc-equal modname modules)))
      (if module
          (nfix (svl2-module->rank (cdr module)))
        0)))

  (define svl2-get-max-occ-rank ((occs svl2-occ-alist-p)
                                 (modules svl2-module-alist-p))
    :returns (res natp)
    (cond ((atom occs)
           0)
          ((equal (svl2-occ-kind (cdar occs)) ':assign)
           (svl2-get-max-occ-rank (cdr occs)
                                  modules))
          (t (max (svl2-get-module-rank (svl2-occ-module->name (cdar occs)) modules)
                  (svl2-get-max-occ-rank (cdr occs) modules)))))

  (define svl2-well-ranked-module ((modname sv::modname-p)
                                   (modules svl2-module-alist-p))
    (and (assoc-equal modname modules) 
         (> (svl2-get-module-rank modname modules)
            (svl2-get-max-occ-rank (svl2-module->occs
                                    (cdr (assoc-equal modname modules)))
                                   modules)))))

(define svl2-start-env ((wires wire-list-p)
                        (vals sv::4veclist-p))
  :returns (res sv::svex-env-p
                :hyp (and (wire-list-p wires)
                          (sv::4veclist-p vals)))
  (if (or (atom wires)
          (atom vals))
      nil
    (hons-acons
     (wire-name (car wires))
     (b* ((wire (car wires)))
       (case-match wire
         ((& size . start)
          (4vec-part-select start size (car vals)))
         (& (car vals))))
     (svl2-start-env (cdr wires) (cdr vals)))))

(define entry-4vec-fix (entry)
  :guard (or (consp entry)
             (not entry))
  :enabled t
  (if entry
      (cdr entry)
    (sv::4vec-x)))

(define entry-svl-env-fix (entry)
  :guard (or (consp entry)
             (not entry))
  :enabled t
  (if entry
      (cdr entry)
    (make-svl-env)))

(define svl2-retrieve-values ((wires wire-list-p)
                              (env-wires sv::svex-env-p))
  :returns (res sv::4veclist-p :hyp (and (wire-list-p wires)
                                         (sv::svex-env-p env-wires)))
  (if (atom wires)
      nil
    (b* ((wire (car wires))
         (value (hons-get (wire-name wire) env-wires)))
      (cons (case-match wire
              ((& w . s)
               (4vec-part-select s w (entry-4vec-fix value)))
              (& (entry-4vec-fix value)))
            (svl2-retrieve-values (cdr wires)
                                  env-wires)))))

#|(define save-lhs-to-env-wires ((val sv::4vec-p)
                               (lhs sv::lhs-p)
                               (env-wires sv::svex-env-p))
  :returns (res sv::svex-env-p
                :hyp (and (sv::4vec-p val)
                          (sv::lhs-p lhs)
                          (sv::svex-env-p env-wires)))
  :verify-guards nil
  (if (atom lhs)
      env-wires
    (b* (((sv::lhrange range) (car lhs))
         (env-wires (save-lhs-to-env-wires (4vec-rsh range.w val)
                                           (cdr lhs)
                                           env-wires))
         ((when (equal (sv::lhatom-kind range.atom) ':z))
          env-wires)
         (old-val (Hons-get (sv::lhatom-var->name range.atom) env-wires)))
      (hons-acons (sv::lhatom-var->name range.atom)
                  (if old-val
                      (sbits (sv::lhatom-var->rsh range.atom)
                             range.w
                             val
                             (cdr old-val))
                    (sbits (sv::lhatom-var->rsh range.atom)
                           range.w
                           val
                           (sv::4vec-x)))
                  env-wires)))
  ///
  (verify-guards save-lhs-to-env-wires))||#





(define svl2-save-mod-outputs ((vals sv::4veclist-p)
                               (wire-list-list wire-list-listp)
                               (env-wires sv::svex-env-p))
  :returns (res sv::svex-env-p
                :hyp (and (sv::4veclist-p vals)
                          (wire-list-listp wire-list-list)
                          (sv::svex-env-p env-wires )))
  (if (or (atom vals)
          (atom wire-list-list))
      env-wires
    (b* ((cur-wire-list (car wire-list-list))
         (cur-val (car vals))
         (env-wires (save-wires-to-env-wires cur-val
                                             cur-wire-list
                                             env-wires)))
      (svl2-save-mod-outputs (cdr vals)
                             (cdr wire-list-list)
                             env-wires))))

(memoize 'svl2-module-alist-p)
(memoize 'svl2-well-ranked-module)

(define create-next-env-for-wires ((delayed-ins SV::SVARLIST-P)
                                   (env-wires sv::svex-env-p))
  :returns (res sv::svex-env-p
                :hyp (and (SV::SVARLIST-P delayed-ins)
                          (sv::svex-env-p env-wires)))
  (if (atom delayed-ins)
      nil
    (b* ((cur (car delayed-ins))
         (cur- (sv::change-svar cur :delay 0)) ;; read the value from evn-wires
         ;; by converting the delay to 0, but save with delay=1 
         (val (entry-4vec-fix (hons-get cur- env-wires))))
      (acons cur
             val
             (create-next-env-for-wires (cdr delayed-ins)
                                        env-wires)))))
                                   

(define svex-env-append ((lst1 sv::svex-env-p) 
                         (lst2 sv::svex-env-p))
  :returns (res sv::svex-env-p
                :hyp (and (sv::svex-env-p lst1)
                          (sv::svex-env-p lst2)))
  (if (atom lst1)
      lst2
    (hons-acons (caar lst1)
                (cdar lst1)
                (svex-env-append (cdr lst1) lst2))))

(acl2::defines
 svl2-run-phase
 (define svl2-run-phase ((modname sv::modname-p)
                         (inputs sv::4veclist-p)
                         (delayed-env svl-env-p)
                         (modules svl2-module-alist-p))
   :verify-guards nil

   ;; :guard (and (assoc-equal modname modules)
   ;;             (svl2-well-ranked-module modname modules))

   :measure (acl2::nat-list-measure
             (list (svl2-get-module-rank modname modules)
                   (cons-count (sv::modname-fix modname))))
   :hints (("Goal"
            :in-theory (e/d (rp::measure-lemmas
                             SVL2-GET-MAX-OCC-RANK
                             SVL2-MODULE->OCCS
                             SV::MODNAME-FIX
                             SVL2-WELL-RANKED-MODULE
                             svl2-occ-module->name) ())))

   :returns (mv (out-vals sv::4veclist-p
                          :hyp (and (sv::4veclist-p inputs)
                                    (svl-env-p delayed-env)
                                    (svl2-module-alist-p modules)))
                (next-delayed-env svl-env-p
                                  :hyp (and (sv::4veclist-p inputs)
                                            (svl-env-p delayed-env)
                                            (svl2-module-alist-p modules))))
   (cond ((not (svl2-well-ranked-module modname modules)) ;; for termination
          (mv
           (cw "Either Module ~p0 is missing or it has invalid ranks~%"
               modname)
           (make-svl-env)))
         (t
          (b* (((svl2-module module) (cdr (assoc-equal modname modules)))
               (env-wires (svl2-start-env module.inputs inputs))
               (env-wires
                (svex-env-append (svl-env->wires delayed-env)
                                 env-wires))
               ((mv env-wires next-delayed-env.modules)
                (svl2-run-phase-occs module.occs
                                     env-wires
                                     (svl-env->modules delayed-env)
                                     modules))
               (out-vals (svl2-retrieve-values module.outputs
                                               env-wires))
               (next-delayed-env (make-svl-env
                                  :wires (create-next-env-for-wires
                                          module.delayed-inputs
                                          env-wires)
                                  :modules next-delayed-env.modules))
               (- (fast-alist-free env-wires)))
            (mv out-vals
                next-delayed-env)))))

 (define svl2-run-phase-occs ((occs svl2-occ-alist-p)
                              (env-wires sv::svex-env-p)
                              (delayed-env-alist svl-env-alist-p)
                              (modules svl2-module-alist-p))
   :measure (acl2::nat-list-measure
             (list (svl2-get-max-occ-rank occs modules)
                   (cons-count occs)))

   :returns (mv (res-env-wires sv::svex-env-p :hyp (and (svl2-occ-alist-p occs)
                                                        (sv::svex-env-p env-wires)
                                                        (svl-env-alist-p delayed-env-alist)
                                                        (svl2-module-alist-p modules)))
                (next-delayed-env.modules SVL-ENV-ALIST-P
                                          :hyp (and (svl2-occ-alist-p occs)
                                                    (sv::svex-env-p env-wires)
                                                    (svl-env-alist-p delayed-env-alist)
                                                    (svl2-module-alist-p modules))))

   (let ((occ-name (caar occs))
         (occ (cdar occs)))
     (cond ((atom occs)
            (mv env-wires nil))
           ((equal (svl2-occ-kind occ) ':assign)
            (b* ((env-wires (hons-acons (svl2-occ-assign->output occ)
                                        (svex-eval (svl2-occ-assign->svex occ)
                                                        env-wires)
                                        env-wires)))
              (svl2-run-phase-occs (cdr occs)
                                   env-wires
                                   delayed-env-alist
                                   modules)))
           (t (b* ((mod-input-vals (sv::svexlist-eval (svl2-occ-module->inputs occ)
                                                           env-wires))
                   (mod.delayed-env (entry-svl-env-fix (hons-get occ-name delayed-env-alist)))
                   ((mv mod-output-vals mod-delayed-env)
                    (svl2-run-phase (svl2-occ-module->name occ)
                                    mod-input-vals
                                    mod.delayed-env
                                    modules))
                   (env-wires (svl2-save-mod-outputs mod-output-vals
                                                     (svl2-occ-module->outputs  occ)
                                                     env-wires))
                   ((mv env-wires rest-delayed-env)
                    (svl2-run-phase-occs (cdr occs)
                                         env-wires
                                         delayed-env-alist
                                         modules)))
                (mv env-wires
                    (if (not (equal mod-delayed-env (make-svl-env)))
                        (hons-acons occ-name
                                    mod-delayed-env
                                    rest-delayed-env)
                      rest-delayed-env)))))))
 ///

 (local
  (defthm svex-env-p-of-hons-gets-fast-alist
    (implies (and (sv::svarlist-p names)
                  (sv::svex-env-p env))
             (sv::svex-env-p (hons-gets-fast-alist names env)))
    :hints (("goal"
             :expand (hons-gets-fast-alist (cdr names) nil)
             :induct (hons-gets-fast-alist names env)
             :do-not-induct t
             :in-theory (e/d (hons-gets-fast-alist
                              sv::svar-p
                              occ-name-p
                              svex-env-p
                              occ-name-list-p)
                             ())))))

 (local
  (defthm guard-lemma1
    (implies (and (SVL2-MODULE-ALIST-P modules)
                  (ASSOC-EQUAL MODNAME MODULES))
             (and (SVL2-MODULE-P (CDR (ASSOC-EQUAL MODNAME MODULES)))
                  (CONSP (ASSOC-EQUAL MODNAME MODULES))))
    :hints (("Goal"
             :in-theory (e/d (SVL2-MODULE-ALIST-P) ())))))

 (verify-guards svl2-run-phase-occs
   :otf-flg t
   :hints (("Goal"
            :in-theory (e/d (svexlist-eval2-is-svexlist-eval
                             svl2-well-ranked-module)
                            ())))))

(defmacro svl2-run-cycle (modnames inputs
                                   delayed-env
                                   modules)
  `(svl2-run-phase ,modnames ,inputs ,delayed-env
                   ,modules))

(defmacro svl2-run-cycle-occs (occs
                               env-wires
                               delayed-env-alist
                               modules)
  `(svl2-run-phase-occs ,occs ,env-wires
                        ,delayed-env-alist
                        ,modules))


(define s-equal ((x)
                 (y))
  :inline t 
  (equal (if (symbolp x) (symbol-name x) x)
         (if (symbolp y) (symbol-name y) y)))

(encapsulate
  nil

  ;; Functions to parse input signal bindings across phases.
  ;; For example:
  ;; (defconst *counter-inputs*
  ;; `(("Clock" 0 ~)
  ;;   ("Reset" 1 1 0 0 1)
  ;;   ("Enable" 0 0 0 0 0 0)
  ;;   ("Load" 0 0 _ _ 0)
  ;;   ("Mode" 0 0 0 1)
  ;;   ("Data[8:0]" data8-10 _ _ data8-12)
  ;;   ("Data[63:9]" data-rest)))
  ;; is parsed and a list of list is created.
  ;; The inner lists contain inputs as svex'es when svl2-run-cycle is to be
  ;; called at each cycle.
  ;; the outer list is as long as the total number of phases.
  
  (define get-max-len (lsts)
  :returns (res natp)
  (if (atom lsts)
      0
    (max (len (car lsts))
         (get-max-len (cdr lsts)))))

(progn

  (define svl2-run-fix-inputs_phases-aux ((cur)
                                          (phase-cnt natp)
                                          (last))
    (cond ((zp phase-cnt) nil)
          ((atom cur)
           (cons last
                 (svl2-run-fix-inputs_phases-aux cur
                                                 (1- phase-cnt)
                                                 last)))
          ((s-equal (car cur) '~)
           (cond ((equal last '0)
                  (cons 1
                        (svl2-run-fix-inputs_phases-aux cur
                                                        (1- phase-cnt)
                                                        1)))
                 ((equal last '1)
                  (cons 0
                        (svl2-run-fix-inputs_phases-aux cur
                                                        (1- phase-cnt)
                                                        0)))
                 ((s-equal last '_)
                  (cons '_
                        (svl2-run-fix-inputs_phases-aux cur
                                                        (1- phase-cnt)
                                                        '_)))
                 (t
                  (cons `(sv::bitnot ,last)
                        (svl2-run-fix-inputs_phases-aux cur
                                                        (1- phase-cnt)
                                                        `(sv::bitnot
                                                          ,last))))))
          (t
           (cons (cond ((s-equal (car cur) '_)
                        `',(sv::4vec-x))
                       (t (car cur)))
                 (svl2-run-fix-inputs_phases-aux (cdr cur)
                                                 (1- phase-cnt)
                                                 (car cur))))))
                                                      
    

  (define svl2-run-fix-inputs_phases ((sig-binds)
                                      (phase-cnt natp))
    (if (atom sig-binds)
        nil
      (cons (svl2-run-fix-inputs_phases-aux (car sig-binds)
                                            phase-cnt
                                            '_)
            (svl2-run-fix-inputs_phases (cdr sig-binds)
                                        phase-cnt)))))

(define get-substr ((str stringp)
                    (start natp)
                    (size natp))
  :verify-guards nil 
  (b* ((chars (take (+ start size) (explode str)))
       (chars (nthcdr start chars)))
    (coerce chars 'string)))

(define svl2-run-simplify-signame ((signame))
  :verify-guards nil
  (b* ((pos-of-[ (str::strpos "[" signame))
       (pos-of-colon (str::strpos ":" signame))
       (pos-of-] (str::strpos "]" signame)))
    (if (and pos-of-[
             pos-of-colon
             pos-of-])
        (mv (get-substr signame 0 pos-of-[)
            (Str::digit-list-value
             (explode
              (get-substr signame
                          (1+ pos-of-[)
                          (+ pos-of-colon (- pos-of-[) -1))))
            (Str::digit-list-value
             (explode
              (get-substr signame
                          (1+ pos-of-colon)
                          (+ pos-of-] (- pos-of-colon) -1)))))
      (mv signame nil nil))))

(progn
  (define svl2-run-fix-inputs_merge-aux (old-binds new-binds start size)
  
    (if (atom new-binds)
        nil
      (b* ((old-val (if (atom old-binds) `',(sv::4vec-x) (car old-binds)))
           (new-bind (car new-binds)))
        (cons `(sv::partinst ,start ,size ,old-val ,new-bind)
              (svl2-run-fix-inputs_merge-aux (if (atom old-binds) nil (cdr old-binds))
                                             (cdr new-binds)
                                             start size)))))

  (define svl2-run-fix-inputs_merge ((signames)
                                     (sig-binds))
    :verify-guards nil
    (if (or (atom signames)
            (atom sig-binds))
        nil
      (b* ((rest (svl2-run-fix-inputs_merge (cdr signames)
                                            (cdr sig-binds)))
           ((mv name b1 b2)
            (svl2-run-simplify-signame (car signames))))
        (cond ((and b1 b2)
               (b* (((mv b1 b2) (if (> b2 b1) (mv b2 b1) (mv b1 b2)))
                    (start b2)
                    (size (+ b1 (- b2) 1))
                    (old-assign (assoc-equal name rest))
                    (new-binds (svl2-run-fix-inputs_merge-aux (cdr old-assign)
                                                              (car sig-binds)
                                                              start
                                                              size)))
                 (put-assoc-equal name new-binds rest)))               
              (t
               (acons (car signames) (car sig-binds) rest)))))))
      


(define svl2-run-fix-inputs ((sig-bind-alist alistp))
  ;; in case an input sig-bind-alist has a key of the form "Data[8:0]"
  ;; merge it to a single binding "Data".
  ;; Also extend "~" and unfinished bindings.
  :verify-guards nil
  (b* ((sig-names (strip-cars sig-bind-alist))
       (sig-binds (strip-cdrs sig-bind-alist))
       (phase-cnt (get-max-len sig-binds))
       (sig-binds (svl2-run-fix-inputs_phases sig-binds phase-cnt))
       (sig-bind-alist (svl2-run-fix-inputs_merge sig-names sig-binds)))
    sig-bind-alist))




(define svl2-generate-inputs_fixorder ((sig-bind-alist alistp)
                                       (wire-names string-listp))
  :verify-guards nil
  (if (atom wire-names)
      nil
    (b* ((entry (assoc-equal (car wire-names) sig-bind-alist))
         (rest (svl2-generate-inputs_fixorder sig-bind-alist
                                              (cdr wire-names))))
      (if entry
          (cons entry rest)
        (progn$ (cw "Warning! Input ~p0 does not have an assigned value. ~%"
                    (car wire-names))
                (acons
                 (car wire-names)
                 (repeat (len (cdar sig-bind-alist))
                         `',(sv::4vec-x))
                 rest))))))


(define transpose (x)
  :verify-guards nil
  (if (or (atom x)
          (atom (car x)))
      nil
    (cons (strip-cars x)
          (transpose (strip-cdrs x)))))
      


(define svl2-generate-inputs ((sig-bind-alist alistp)
                              (input-wires wire-list-p))
  :verify-guards nil
  (b* ((sig-bind-alist (svl2-run-fix-inputs sig-bind-alist))
       (sig-bind-alist (svl2-generate-inputs_fixorder
                        sig-bind-alist (strip-cars input-wires)))
       (inputs (transpose (strip-cdrs sig-bind-alist))))
    inputs)))

;; (svl2-generate-inputs *counter-inputs* '(("Clock") ("Load") ("Data") ("Reset")))


(define svexlist-list-eval2 (x env)
  (if (atom x)
      nil
    (cons (SVEXLIST-EVAL2 (car x) env)
          (svexlist-list-eval2 (cdr x) env))))


(define svl2-run-save-output ((out-alist alistp)
                              (out-bind-alist alistp))
  :verify-guards nil
  (if (atom out-bind-alist)
      (mv nil nil)
    (b* (((mv rest-outputs rest-out-bind-alist)
          (svl2-run-save-output out-alist (cdr out-bind-alist)))
         (this (car out-bind-alist))
         (key (car this))
         (val (cdr this))
         ((when (atom val))
          (mv rest-outputs rest-out-bind-alist))
         ((when (s-equal (car val) '_))
          (mv rest-outputs (acons key (cdr val) rest-out-bind-alist)))
         ((mv signame pos1 pos2)
          (svl2-run-simplify-signame key))
         (out-entry (assoc-equal signame out-alist))
         ((unless out-entry)
          (progn$ (cw "Warning \"~p0\" is not an output signal. ~%" signame)
                  (mv rest-outputs (acons key (cdr val) rest-out-bind-alist))))        
         (out-val (cdr out-entry)) 
         ((unless (and pos1 pos2))
          (mv (acons (car val) out-val rest-outputs)
              (acons key (cdr val) rest-out-bind-alist)))
         ((mv start size) (if (> pos1 pos2)
                              (mv pos2 (+ pos1 (- pos2) 1))
                            (mv pos1 (+ pos2 (- pos1) 1)))))
      (mv (acons (car val) (bits out-val start size) rest-outputs)
          (acons key (cdr val) rest-out-bind-alist))))) 
         
          

(define svl2-run-aux ((modname sv::modname-p)
                      (inputs)
                      (out-wires string-listp)
                      (out-bind-alist alistp)
                      (delayed-env svl-env-p)
                      (modules svl2-module-alist-p))
  :verify-guards nil
  (if (atom inputs)
      (progn$ ;(svl-free-env modname delayed-env modules (expt 2 30))
       nil)
    (b* (((mv out-vals next-delayed-env)
          (svl2-run-phase modname (car inputs) delayed-env modules))
         (out-alist (pairlis$ out-wires out-vals))
         ((mv outputs out-bind-alist) (svl2-run-save-output out-alist out-bind-alist))
         (rest (svl2-run-aux modname (cdr inputs) out-wires out-bind-alist next-delayed-env modules)))
      (append outputs
              rest))))

(define svl2-run ((modname sv::modname-p)
                  (inputs-env sv::svex-env-p) ;; needs to be fast-alist
                  (ins-bind-alist alistp) ;; a constant to tell what input
                  ;; signal should be assigned to what and when
                  (out-bind-alist alistp) ;; same as above but for outputs
                  (modules svl2-module-alist-p))
  :verify-guards nil
  (declare (ignorable out-bind-alist))
  (b* ((module (cdr (assoc-equal modname modules)))
       (input-wires (svl2-module->inputs module))
       (output-wires (strip-cars (svl2-module->outputs module)))
       (inputs-unbound (svl2-generate-inputs ins-bind-alist input-wires))
       (inputs (svexlist-list-eval2 inputs-unbound inputs-env)))
    (svl2-run-aux modname inputs output-wires out-bind-alist (make-svl-env) modules)))



;; :i-am-here

;; (include-book "/Users/user/async/fft/svl-tests/svl-tests")

;; ;;*counter-svl2-design*

;; (progn
;;   (defconst *counter-inputs*
;;     `(("Clock" 0 ~)
;;       ("Reset" 1 1 1 1 1)
;;       ("Enable" 0 0 0 0 0 0 0 0 0 0)
;;       ("Load" 0 1)
;;       ("Mode" 0)
;;       ("Data[8:0]" data8-10)
;;       ("Data[63:9]" data-rest)))

;;   (defconst *counter-outputs*
;;     `(("Count[31:0]" count_low1 _ _ _ count_low2 count_low3 count_low4
;;        count_low5 count_low6 count_low7 count_low8 count_low9 count_low10)
;;       ("Count[63:32]" count_high1 _ _ _ count_high2)))


;;   (value-triple (svl2-run "COUNTER" (make-fast-alist '((data8-10 . -5)
;;                                                        (data8-12 . 5)
;;                                                        (data-rest . 10)))
;;                           *counter-inputs*
;;                           *counter-outputs*
;;                           *counter-svl2-design*)))
          

;; :i-am-here
#|
(make-event
 (b* ((modnames '("full_adder_1$WIDTH=1"
                  "full_adder$WIDTH=1"
                  "booth2_reduction_dadda_17x65_97"
                  "booth2_multiplier_signed_64x32_97"))
      ((mv modules rp::rp-state)
       (svl2-flatten-design modnames
                            *big-sv-design*
                            *big-vl-design2*)))
   (mv nil
       `(defconst *big-svl2-design*
          ',modules)
       state
       rp::rp-state)))

(make-event
 (b* ((modnames '("FullAdder" "LF_127_126" "HalfAdder"))
      ((mv modules rp::rp-state)
       (svl2-flatten-design modnames
                            *signed64-sv-design*
                            *signed64-vl-design2*)))
   (mv nil
       `(defconst *signed64-svl2-design*
          ',modules)
       state
       rp::rp-state)))

(make-event
 (b* ((modnames '("FullAdder" "LF_255_254" "HalfAdder"))
      ((mv modules rp::rp-state)
       (svl2-flatten-design modnames
                            *signed128-sv-design*
                            *signed128-vl-design2*)))
   (mv nil
       `(defconst *signed128-svl2-design*
          ',modules)
       state
       rp::rp-state)))

(make-event
 (b* ((modnames '("FullAdder" "BK_511_510" "HalfAdder"))
      ((mv modules rp::rp-state)
       (svl2-flatten-design modnames
                            *signed256-sv-design*
                            *signed256-vl-design2*)))
   (mv nil
       `(defconst *signed256-svl2-design*
          ',modules)
       state
       rp::rp-state)))

(make-event
 (b* ((modnames '())
      ((mv modules rp::rp-state)
       (svl2-flatten-design modnames
                            *mult-sv-design*
                            *mult-vl-design2*)))
   (mv nil
       `(defconst *mult-svl2-design*
          ',modules)
       state
       rp::rp-state)))

(get-svl2-modules-ports *signed128-svl2-design*)

(time$
 (svl2-run-cycle "Multiplier_15_0_1000"
                 (list 233 45)
                 (make-svl-env)
                 *mult-svl2-design*))

(time$
 (svl2-run-cycle "Mult_64_64"
                 (list 233 45)
                 (make-svl-env)
                 *signed64-svl2-design*))

(time$
 (svl2-run-cycle "Mult_256_256"
                 (list 233 45)
                 (make-svl-env)
                 *signed256-svl2-design*))

(time$
 (svl2-run-cycle "Mult_128_128"
                 (list 233 45)
                 (make-svl-env)
                 *signed128-svl2-design*))

(time$
 (b* (((mv res &)
       (svl2-run-cycle "booth2_multiplier_signed_64x32_97"
                       (list 0 0 233 45)
                       (make-svl-env)
                       *big-svl2-design*)))
   (bits (+ (bits (car res) 0 97 )
                 (bits (car res) 97 97 )) 
             0 97 )))
||#
