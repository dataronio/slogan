;;;============================================================================

;;; File: "_t-univ.scm"

;;; Copyright (c) 2011-2013 by Marc Feeley, All Rights Reserved.
;;; Copyright (c) 2012 by Eric Thivierge, All Rights Reserved.

(include "generic.scm")

(include-adt "_envadt.scm")
(include-adt "_gvmadt.scm")
(include-adt "_ptreeadt.scm")
(include-adt "_sourceadt.scm")

(define univ-enable-jump-destination-inlining? #f)
(set! univ-enable-jump-destination-inlining? #t)

(define (univ-null-representation ctx)
  'natural)

(define (univ-boolean-representation ctx)
  'natural)

(define (univ-char-representation ctx)
  'class)

(define (univ-fixnum-representation ctx)
  'natural)

(define (univ-flonum-representation ctx)
  'class)

(define (univ-vector-representation ctx)
  (case (target-name (ctx-target ctx))
    ((php)
     'class)
    (else
     'natural)))

(define (univ-string-representation ctx)
  'class)

(define (univ-symbol-representation ctx)
  'host)

(define (univ-tostr-method-name ctx)
  (case (target-name (ctx-target ctx))

    ((js)
     'toString)

    ((php)
     '__toString)

    ((python)
     '__str__)

    ((ruby)
     'to_s)

    (else
     (compiler-internal-error
      "univ-tostr-method-name, unknown target"))))

;;;----------------------------------------------------------------------------
;;
;; "Universal" back-end.

;; Initialization/finalization of back-end.

(define (univ-setup target-language file-extension)
  (let ((targ (make-target 9 target-language 0)))

    (define (begin! info-port)

      (target-dump-set!
       targ
       (lambda (procs output c-intf module-descr unique-name options)
         (univ-dump targ procs output c-intf module-descr unique-name options)))

      (target-nb-regs-set! targ univ-nb-gvm-regs)

      (target-prim-info-set!
       targ
       (lambda (name)
         (univ-prim-info targ name)))

      (target-label-info-set!
       targ
       (lambda (nb-parms closed?)
         (univ-label-info targ nb-parms closed?)))

      (target-jump-info-set!
       targ
       (lambda (nb-args)
         (univ-jump-info targ nb-args)))

      (target-frame-constraints-set!
       targ
       (make-frame-constraints univ-frame-reserve univ-frame-alignment))

      (target-proc-result-set!
       targ
       (make-reg 1))

      (target-task-return-set!
       targ
       (make-reg 0))

      (target-switch-testable?-set!
       targ
       (lambda (obj)
         (univ-switch-testable? targ obj)))

      (target-eq-testable?-set!
       targ
       (lambda (obj)
         (univ-eq-testable? targ obj)))

      (target-object-type-set!
       targ
       (lambda (obj)
         (univ-object-type targ obj)))

      (target-file-extension-set!
       targ
       file-extension)

      #f)

    (define (end!)
      #f)

    (target-begin!-set! targ begin!)
    (target-end!-set! targ end!)
    (target-add targ)))

(univ-setup 'js     ".js")
(univ-setup 'python ".py")
(univ-setup 'ruby   ".rb")
(univ-setup 'php    ".php")

;;;----------------------------------------------------------------------------

;; Generation of textual target code.

(define (univ-indent . rest)
  (cons '$$indent$$ rest))

(define (univ-display x port)

  (define indent-level 0)
  (define after-newline? #t)

  (define (indent)
    (if after-newline?
        (begin
          (display (make-string (* 2 indent-level) #\space) port)
          (set! after-newline? #f))))

  (define (disp x)

    (cond ((string? x)
           (let loop1 ((i 0))
             (let loop2 ((j i))

               (define (display-substring limit)
                 (if (< i limit)
                     (begin
                       (indent)
                       (if (and (= i 0) (= limit (string-length x)))
                           (display x port)
                           (display (substring x i limit) port)))))

               (if (< j (string-length x))

                   (let ((c (string-ref x j))
                         (j+1 (+ j 1)))
                       (if (char=? c #\newline)
                           (begin
                             (display-substring j+1)
                             (set! after-newline? #t)
                             (loop1 j+1))
                           (loop2 j+1)))

                   (display-substring j)))))

          ((symbol? x)
           (disp (symbol->string x)))

          ((char? x)
           (disp (string x)))

          ((null? x))

          ((pair? x)
           (if (eq? (car x) '$$indent$$)
               (begin
                 (set! indent-level (+ indent-level 1))
                 (disp (cdr x))
                 (set! indent-level (- indent-level 1)))
               (begin
                 (disp (car x))
                 (disp (cdr x)))))

          ((vector? x)
           (disp (vector->list x)))

          (else
           (indent)
           (display x port))))

   (disp x))

;;;----------------------------------------------------------------------------

;; ***** PROCEDURE CALLING CONVENTION

(define univ-nb-gvm-regs 5)
(define univ-nb-arg-regs 3)

(define (univ-label-info targ nb-parms closed?)

;; After a GVM "entry-point" or "closure-entry-point" label, the following
;; is true:
;;
;;  * return address is in GVM register 0
;;
;;  * if nb-parms <= nb-arg-regs
;;
;;      then parameter N is in GVM register N
;;
;;      else parameter N is in
;;               GVM register N-F, if N > F
;;               GVM stack slot N, if N <= F
;;           where F = nb-parms - nb-arg-regs
;;
;;  * for a "closure-entry-point" GVM register nb-arg-regs+1 contains
;;    a pointer to the closure object
;;
;;  * other GVM registers contain an unspecified value

  (let ((nb-stacked (max 0 (- nb-parms univ-nb-arg-regs))))

    (define (location-of-parms i)
      (if (> i nb-parms)
          '()
          (cons (cons i
                      (if (> i nb-stacked)
                          (make-reg (- i nb-stacked))
                          (make-stk i)))
                (location-of-parms (+ i 1)))))

    (let ((x (cons (cons 'return 0) (location-of-parms 1))))
      (make-pcontext nb-stacked
                     (if closed?
                         (cons (cons 'closure-env
                                     (make-reg (+ univ-nb-arg-regs 1)))
                               x)
                         x)))))

(define (univ-jump-info targ nb-args)

;; After a GVM "jump" instruction with argument count, the following
;; is true:
;;
;;  * the return address is in GVM register 0
;;
;;  * if nb-args <= nb-arg-regs
;;
;;      then argument N is in GVM register N
;;
;;      else argument N is in
;;               GVM register N-F, if N > F
;;               GVM stack slot N, if N <= F
;;           where F = nb-args - nb-arg-regs
;;
;;  * GVM register nb-arg-regs+1 contains a pointer to the closure object
;;    if a closure is being jumped to
;;
;;  * other GVM registers contain an unspecified value

  (let ((nb-stacked (max 0 (- nb-args univ-nb-arg-regs))))

    (define (location-of-args i)
      (if (> i nb-args)
          '()
          (cons (cons i
                      (if (> i nb-stacked)
                          (make-reg (- i nb-stacked))
                          (make-stk i)))
                (location-of-args (+ i 1)))))

    (make-pcontext nb-stacked
                   (cons (cons 'return (make-reg 0))
                         (location-of-args 1)))))

;; The frame constraints are defined by the parameters
;; univ-frame-reserve and univ-frame-alignment.

(define univ-frame-reserve 0) ;; no extra slots reserved
(define univ-frame-alignment 1) ;; no alignment constraint

;; ***** PRIMITIVE PROCEDURE DATABASE

(define (univ-prim-info targ name)
  (univ-prim-info* name))

(define (univ-prim-info* name)
  (table-ref univ-prim-proc-table name #f))

(define univ-prim-proc-table (make-table))

(define (univ-prim-proc-add! x)
  (let ((name (string->canonical-symbol (car x))))
    (table-set! univ-prim-proc-table
                name
                (apply make-proc-obj (car x) #f #t #f (cdr x)))))

(for-each univ-prim-proc-add! prim-procs)

(univ-prim-proc-add! '("##inline-host-statement" (1) #t 0 0 (#f) extended))
(univ-prim-proc-add! '("##inline-host-expression" (1) #t 0 0 (#f) extended))

(define (univ-switch-testable? targ obj)
  ;;(pretty-print (list 'univ-switch-testable? 'targ obj))
  #f);;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (univ-eq-testable? targ obj)
  ;;(pretty-print (list 'univ-eq-testable? 'targ obj))
  #f);;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (univ-object-type targ obj)
  ;;(pretty-print (list 'univ-object-type 'targ obj))
  'bignum);;;;;;;;;;;;;;;;;;;;;;;;;

;; ***** TARGET CODE EMITTERS

(define-macro (^ . forms)
  (if (null? forms)
      `'()
      `(list ,@forms)))

(define-macro (^var-declaration name #!optional (expr #f))
  `(univ-emit-var-declaration ctx ,name ,expr))

(define-macro (^expr-statement expr)
  `(univ-emit-expr-statement ctx ,expr))

(define-macro (^if test true #!optional (false #f))
  `(univ-emit-if ctx ,test ,true ,false))

(define-macro (^if-expr expr1 expr2 expr3)
  `(univ-emit-if-expr ctx ,expr1 ,expr2 ,expr3))

(define-macro (^while test body)
  `(univ-emit-while ctx ,test ,body))

(define-macro (^eq? expr1 expr2)
  `(univ-emit-eq? ctx ,expr1 ,expr2))

(define-macro (^+ expr1 #!optional (expr2 #f))
  `(univ-emit-+ ctx ,expr1 ,expr2))

(define-macro (^- expr1 #!optional (expr2 #f))
  `(univ-emit-- ctx ,expr1 ,expr2))

(define-macro (^* expr1 expr2)
  `(univ-emit-* ctx ,expr1 ,expr2))

(define-macro (^/ expr1 expr2)
  `(univ-emit-/ ctx ,expr1 ,expr2))

(define-macro (^<< expr1 expr2)
  `(univ-emit-<< ctx ,expr1 ,expr2))

(define-macro (^>> expr1 expr2)
  `(univ-emit->> ctx ,expr1 ,expr2))

(define-macro (^bitnot expr)
  `(univ-emit-bitnot ctx ,expr))

(define-macro (^bitand expr1 expr2)
  `(univ-emit-bitand ctx ,expr1 ,expr2))

(define-macro (^bitior expr1 expr2)
  `(univ-emit-bitior ctx ,expr1 ,expr2))

(define-macro (^bitxor expr1 expr2)
  `(univ-emit-bitxor ctx ,expr1 ,expr2))

(define-macro (^= expr1 expr2)
  `(univ-emit-= ctx ,expr1 ,expr2))

(define-macro (^!= expr1 expr2)
  `(univ-emit-!= ctx ,expr1 ,expr2))

(define-macro (^< expr1 expr2)
  `(univ-emit-< ctx ,expr1 ,expr2))

(define-macro (^<= expr1 expr2)
  `(univ-emit-<= ctx ,expr1 ,expr2))

(define-macro (^> expr1 expr2)
  `(univ-emit-> ctx ,expr1 ,expr2))

(define-macro (^>= expr1 expr2)
  `(univ-emit->= ctx ,expr1 ,expr2))

(define-macro (^not expr)
  `(univ-emit-not ctx ,expr))

(define-macro (^&& expr1 expr2)
  `(univ-emit-&& ctx ,expr1 ,expr2))

(define-macro (^and expr1 expr2)
  `(univ-emit-and ctx ,expr1 ,expr2))

(define-macro (^or expr1 expr2)
  `(univ-emit-or ctx ,expr1 ,expr2))

(define-macro (^concat expr1 expr2)
  `(univ-emit-concat ctx ,expr1 ,expr2))

(define-macro (^tostr expr)
  `(univ-emit-tostr ctx ,expr))

(define-macro (^parens expr)
  `(univ-emit-parens ctx ,expr))

(define-macro (^local-var name)
  `(univ-emit-local-var ctx ,name))

(define-macro (^global-var name)
  `(univ-emit-global-var ctx ,name))

(define-macro (^global-prim-function name)
  `(univ-emit-global-prim-function ctx ,name))

(define-macro (^global-function name)
  `(univ-emit-global-function ctx ,name))

(define-macro (^prefix name)
  `(univ-emit-prefix ctx ,name))

(define-macro (^assign loc expr)
  `(univ-emit-assign ctx ,loc ,expr))

(define-macro (^inc-by loc expr #!optional (embed #f))
  `(univ-emit-inc-by ctx ,loc ,expr ,embed))

(define-macro (^array-length expr)
  `(univ-emit-array-length ctx ,expr))

(define-macro (^array-shrink! expr1 expr2)
  `(univ-emit-array-shrink! ctx ,expr1 ,expr2))

(define-macro (^array-index expr1 expr2)
  `(univ-emit-array-index ctx ,expr1 ,expr2))

(define-macro (^prop-index expr1 expr2)
  `(univ-emit-prop-index ctx ,expr1 ,expr2))

(define-macro (^get obj name)
  `(univ-emit-get ctx ,obj ,name))

(define-macro (^set obj name val)
  `(univ-emit-set ctx ,obj ,name ,val))

(define-macro (^obj obj)
  `(univ-emit-obj ctx ,obj))

(define-macro (^array-literal elems)
  `(univ-emit-array-literal ctx ,elems))

(define-macro (^call-prim name . params)
  `(univ-emit-call-prim ctx ,name ,@params))

(define-macro (^call name . params)
  `(univ-emit-call ctx ,name ,@params))

(define-macro (^apply name params)
  `(univ-emit-apply ctx ,name ,params))

(define-macro (^this)
  `(univ-emit-this ctx))

(define-macro (^this-member name)
  `(univ-emit-this-member ctx ,name))

(define-macro (^new class . params)
  `(univ-emit-new ctx ,class ,@params))

(define-macro (^typeof type expr)
  `(univ-emit-typeof ctx ,type ,expr))

(define-macro (^instanceof class expr)
  `(univ-emit-instanceof ctx ,class ,expr))

(define-macro (^getopnd opnd)
  `(univ-emit-getopnd ctx ,opnd))

(define-macro (^setloc loc val)
  `(univ-emit-setloc ctx ,loc ,val))

(define-macro (^prim-function-declaration name params header attribs body)
  `(^function-declaration
    ,name
    ,params
    ,header
    ,attribs
    ,body
    #t))

(define-macro (^function-declaration name params header attribs body #!optional (prim? #f))
  `(univ-emit-function-declaration
    ctx
    ,name
    ,params
    (lambda (ctx) ,header)
    (lambda (ctx) ,attribs)
    (lambda (ctx) ,body)
    ,prim?))

(define-macro (^class-declaration name fields methods)
  `(univ-emit-class-declaration
    ctx
    ,name
    ,fields
    ,methods))

(define-macro (^getreg num)
  `(univ-emit-getreg ctx ,num))

(define-macro (^setreg num val)
  `(univ-emit-setreg ctx ,num ,val))

(define-macro (^getstk offset)
  `(univ-emit-getstk ctx ,offset))

(define-macro (^setstk offset val)
  `(univ-emit-setstk ctx ,offset ,val))

(define-macro (^getclo closure index)
  `(univ-emit-getclo ctx ,closure ,index))

(define-macro (^setclo closure index val)
  `(univ-emit-setclo ctx ,closure ,index ,val))

(define-macro (^getglo name)
  `(univ-emit-getglo ctx ,name))

(define-macro (^setglo name val)
  `(univ-emit-setglo ctx ,name ,val))

(define-macro (^return expr)
  `(univ-emit-return ctx ,expr))

(define-macro (^null)
  `(univ-emit-null ctx))

(define-macro (^null-box val)
  `(univ-emit-null-box ctx ,val))

(define-macro (^null-unbox null)
  `(univ-emit-null-unbox ctx ,null))

(define-macro (^bool val)
  `(univ-emit-bool ctx ,val))

(define-macro (^boolean-box val)
  `(univ-emit-boolean-box ctx ,val))

(define-macro (^boolean-unbox boolean)
  `(univ-emit-boolean-unbox ctx ,boolean))

(define-macro (^boolean? val)
  `(univ-emit-boolean? ctx ,val))

(define-macro (^chr val)
  `(univ-emit-chr ctx ,val))

(define-macro (^char-box val)
  `(univ-emit-char-box ctx ,val))

(define-macro (^char-unbox char)
  `(univ-emit-char-unbox ctx ,char))

(define-macro (^chr-fromint val)
  `(univ-emit-chr-fromint ctx ,val))

(define-macro (^chr-toint val)
  `(univ-emit-chr-toint ctx ,val))

(define-macro (^chr-tostr val)
  `(univ-emit-chr-tostr ctx ,val))

(define-macro (^char? val)
  `(univ-emit-char? ctx ,val))

(define-macro (^int val)
  `(univ-emit-int ctx ,val))

(define-macro (^fixnum-box val)
  `(univ-emit-fixnum-box ctx ,val))

(define-macro (^fixnum-unbox fixnum)
  `(univ-emit-fixnum-unbox ctx ,fixnum))

(define-macro (^fixnum? val)
  `(univ-emit-fixnum? ctx ,val))

(define-macro (^dict alist)
  `(univ-emit-dict ctx ,alist))

(define-macro (^member expr name)
  `(univ-emit-member ctx ,expr ,name))

(define-macro (^pair? expr)
  `(univ-emit-pair? ctx ,expr))

(define-macro (^cons expr1 expr2)
  `(univ-emit-cons ctx ,expr1 ,expr2))

(define-macro (^getcar expr)
  `(univ-emit-getcar ctx ,expr))

(define-macro (^getcdr expr)
  `(univ-emit-getcdr ctx ,expr))

(define-macro (^setcar expr1 expr2)
  `(univ-emit-setcar ctx ,expr1 ,expr2))

(define-macro (^setcdr expr1 expr2)
  `(univ-emit-setcdr ctx ,expr1 ,expr2))

(define-macro (^float val)
  `(univ-emit-float ctx ,val))

(define-macro (^float-fromint val)
  `(univ-emit-float-fromint ctx ,val))

(define-macro (^float-toint val)
  `(univ-emit-float-toint ctx ,val))

(define-macro (^float-abs val)
  `(univ-emit-float-abs ctx ,val))

(define-macro (^float-floor val)
  `(univ-emit-float-floor ctx ,val))

(define-macro (^float-ceiling val)
  `(univ-emit-float-ceiling ctx ,val))

(define-macro (^float-truncate val)
  `(univ-emit-float-truncate ctx ,val))

(define-macro (^float-round-half-up val)
  `(univ-emit-float-round-half-up ctx ,val))

(define-macro (^float-round-half-towards-0 val)
  `(univ-emit-float-round-half-towards-0 ctx ,val))

(define-macro (^float-round-half-to-even val)
  `(univ-emit-float-round-half-to-even ctx ,val))

(define-macro (^float-mod val1 val2)
  `(univ-emit-float-mod ctx ,val1 ,val2))

(define-macro (^float-exp val)
  `(univ-emit-float-exp ctx ,val))

(define-macro (^float-log val)
  `(univ-emit-float-log ctx ,val))

(define-macro (^float-sin val)
  `(univ-emit-float-sin ctx ,val))

(define-macro (^float-cos val)
  `(univ-emit-float-cos ctx ,val))

(define-macro (^float-tan val)
  `(univ-emit-float-tan ctx ,val))

(define-macro (^float-asin val)
  `(univ-emit-float-asin ctx ,val))

(define-macro (^float-acos val)
  `(univ-emit-float-acos ctx ,val))

(define-macro (^float-atan val)
  `(univ-emit-float-atan ctx ,val))

(define-macro (^float-expt val1 val2)
  `(univ-emit-float-expt ctx ,val1 ,val2))

(define-macro (^float-sqrt val)
  `(univ-emit-float-sqrt ctx ,val))

(define-macro (^float-integer? val)
  `(univ-emit-float-integer? ctx ,val))

(define-macro (^float-finite? val)
  `(univ-emit-float-finite? ctx ,val))

(define-macro (^float-infinite? val)
  `(univ-emit-float-infinite? ctx ,val))

(define-macro (^float-nan? val)
  `(univ-emit-float-nan? ctx ,val))

(define-macro (^flonum-box val)
  `(univ-emit-flonum-box ctx ,val))

(define-macro (^flonum-unbox flonum)
  `(univ-emit-flonum-unbox ctx ,flonum))

(define-macro (^flonum? val)
  `(univ-emit-flonum? ctx ,val))

(define-macro (^vector-box val)
  `(univ-emit-vector-box ctx ,val))

(define-macro (^vector-unbox vector)
  `(univ-emit-vector-unbox ctx ,vector))

(define-macro (^vector? val)
  `(univ-emit-vector? ctx ,val))

(define-macro (^vector-length val)
  `(univ-emit-vector-length ctx ,val))

(define-macro (^vector-shrink! val1 val2)
  `(univ-emit-vector-shrink! ctx ,val1 ,val2))

(define-macro (^vector-ref val1 val2)
  `(univ-emit-vector-ref ctx ,val1 ,val2))

(define-macro (^vector-set! val1 val2 val3)
  `(univ-emit-vector-set! ctx ,val1 ,val2 ,val3))

(define-macro (^str val)
  `(univ-emit-str ctx ,val))

(define-macro (^string-box val)
  `(univ-emit-string-box ctx ,val))

(define-macro (^string-unbox string)
  `(univ-emit-string-unbox ctx ,string))

(define-macro (^string? val)
  `(univ-emit-string? ctx ,val))

(define-macro (^string-length val)
  `(univ-emit-string-length ctx ,val))

(define-macro (^string-shrink! val1 val2)
  `(univ-emit-string-shrink! ctx ,val1 ,val2))

(define-macro (^string-ref val1 val2)
  `(univ-emit-string-ref ctx ,val1 ,val2))

(define-macro (^string-set! val1 val2 val3)
  `(univ-emit-string-set! ctx ,val1 ,val2 ,val3))

(define-macro (^sym val)
  `(univ-emit-sym ctx ,val))

(define-macro (^symbol-box val)
  `(univ-emit-symbol-box ctx ,val))

(define-macro (^symbol-unbox symbol)
  `(univ-emit-symbol-unbox ctx ,symbol))

(define-macro (^symbol? val)
  `(univ-emit-symbol? ctx ,val))

(define-macro (^symtostr val)
  `(univ-emit-symtostr ctx ,val))

(define-macro (^box? val)
  `(univ-emit-box? ctx ,val))

(define-macro (^box val)
  `(univ-emit-box ctx ,val))

(define-macro (^unbox val)
  `(univ-emit-unbox ctx ,val))

(define-macro (^setbox val1 val2)
  `(univ-emit-setbox ctx ,val1 ,val2))

(define-macro (^procedure? val)
  `(univ-emit-procedure? ctx ,val))

(define (univ-emit-var-declaration ctx name #!optional (expr #f))
  (case (target-name (ctx-target ctx))

    ((js)
     (^ "var " name (if expr (^ " = " expr) (^)) ";\n"))

    ((python ruby)
     (^ name " = " (or expr (^obj #f)) "\n"))

    ((php)
     (^ name " = " (or expr (^obj #f)) ";\n"))

    (else
     (compiler-internal-error
      "univ-emit-expr-statement, unknown target"))))

(define (univ-emit-expr-statement ctx expr)
  (case (target-name (ctx-target ctx))

    ((js php)
     (^ expr ";\n"))

    ((python ruby)
     (^ expr "\n"))

    (else
     (compiler-internal-error
      "univ-emit-expr-statement, unknown target"))))

(define (univ-emit-if ctx test true #!optional (false #f))
  (case (target-name (ctx-target ctx))

    ((js php)
     (^ "if (" test ") {\n"
        (univ-indent true)
        (if false
            (^ "} else {\n"
               (univ-indent false))
            (^))
        "}\n"))

    ((python)
     (^ "if " test ":\n"
        (univ-indent true)
        (if false
            (^ "else:\n"
                  (univ-indent false))
            (^))))

    ((ruby)
     (^ "if " test "\n"
        (univ-indent true)
        (if false
            (^ "else\n"
               (univ-indent false))
            (^))
        "end\n"))

    (else
     (compiler-internal-error
      "univ-emit-if, unknown target"))))

(define (univ-emit-if-expr ctx expr1 expr2 expr3)
  (case (target-name (ctx-target ctx))

    ((js ruby)
     (^ expr1 " ? " expr2 " : " expr3))

    ((php)
     (^parens (^ expr1 " ? " expr2 " : " expr3)))

    ((python)
     (^ expr2 " if " expr1 " else " expr3))

    (else
     (compiler-internal-error
      "univ-emit-if-expr, unknown target"))))

(define (univ-emit-while ctx test body)
  (case (target-name (ctx-target ctx))

    ((js php)
     (^ "while (" test ") {\n"
        (univ-indent body)
        "}\n"))

    ((python)
     (^ "while " test ":\n"
        (univ-indent body)))

    ((ruby)
     (^ "while " test "\n"
        (univ-indent body)
        "end\n"))

    (else
     (compiler-internal-error
      "univ-emit-while, unknown target"))))

(define (univ-emit-eq? ctx expr1 expr2)
  (case (target-name (ctx-target ctx))

    ((js php)
     (^ expr1 " === " expr2))

    ((python)
     (^ expr1 " is " expr2))

    ((ruby)
     (^ expr1 ".equal?(" expr2 ")"))

    (else
     (compiler-internal-error
      "univ-emit-eq?, unknown target"))))

(define (univ-emit-+ ctx expr1 #!optional (expr2 #f))
  (case (target-name (ctx-target ctx))

    ((js php python ruby)
     (if expr2
         (^ expr1 " + " expr2)
         (^ "+ " expr1)))

    (else
     (compiler-internal-error
      "univ-emit-+, unknown target"))))

(define (univ-emit-- ctx expr1 #!optional (expr2 #f))
  (case (target-name (ctx-target ctx))

    ((js php python ruby)
     (if expr2
         (^ expr1 " - " expr2)
         (^ "- " expr1)))

    (else
     (compiler-internal-error
      "univ-emit--, unknown target"))))

(define (univ-emit-* ctx expr1 expr2)
  (case (target-name (ctx-target ctx))

    ((js php python ruby)
     (^ expr1 " * " expr2))

    (else
     (compiler-internal-error
      "univ-emit-*, unknown target"))))

(define (univ-emit-/ ctx expr1 expr2)
  (case (target-name (ctx-target ctx))

    ((js php python ruby)
     (^ expr1 " / " expr2))

    (else
     (compiler-internal-error
      "univ-emit-/, unknown target"))))

(define (univ-wrap+ ctx expr1 expr2)
  (case (target-name (ctx-target ctx))

    ((js)
     (^>> (^<< (^parens (^+ expr1 expr2))
               univ-tag-bits)
          univ-tag-bits))

    ((python)
     (^>> (^member (^call-prim
                    "ctypes.c_int32"
                    (^<< (^parens (^+ expr1 expr2))
                         univ-tag-bits))
                   "value")
          univ-tag-bits))

    ((ruby php)
     (let ((maxfix+1
            (arithmetic-shift 1
                              (- univ-word-bits (+ 1 univ-tag-bits)))))
       (^- (^parens (^bitand (^parens (^+ (^+ expr1 expr2)
                                          maxfix+1))
                             (- (* 2 maxfix+1) 1)))
           maxfix+1)))

    (else
     (compiler-internal-error
      "univ-wrap+, unknown target"))))

(define (univ-wrap- ctx expr1 #!optional (expr2 #f))
  (case (target-name (ctx-target ctx))

    ((js)
     (^>> (^<< (^parens (if expr2
                            (^- expr1 expr2)
                            (^- expr1)))
               univ-tag-bits)
          univ-tag-bits))

    ((python)
     (^>> (^member (^call-prim
                    "ctypes.c_int32"
                    (^<< (^parens (if expr2
                                      (^- expr1 expr2)
                                      (^- expr1)))
                         univ-tag-bits))
                   "value")
          univ-tag-bits))

    ((ruby php)
     (let ((maxfix+1
            (arithmetic-shift 1
                              (- univ-word-bits (+ 1 univ-tag-bits)))))
       (^- (^parens (^bitand (^parens (^+ (if expr2
                                              (^- expr1 expr2)
                                              (^- expr1))
                                          maxfix+1))
                             (- (* 2 maxfix+1) 1)))
           maxfix+1)))

    (else
     (compiler-internal-error
      "univ-wrap-, unknown target"))))

(define (univ-wrap* ctx expr1 expr2)
  (case (target-name (ctx-target ctx))

    ((js)
     (^>> (^parens
           (^<< (^parens
                 (^+ (^* (^parens (^bitand expr1 #xffff))
                         expr2)
                     (^* (^parens (^bitand expr1 #xffff0000))
                         (^parens (^bitand expr2 #xffff)))))
                univ-tag-bits))
          univ-tag-bits))

    ((python)
     (^>> (^member (^call-prim
                    "ctypes.c_int32"
                    (^<< (^parens (^* expr1 expr2))
                         univ-tag-bits))
                   "value")
          univ-tag-bits))

    ((ruby php)
     (let ((maxfix+1
            (arithmetic-shift 1
                              (- univ-word-bits (+ 1 univ-tag-bits)))))
       (^- (^parens (^bitand (^parens (^+ (^* expr1 expr2)
                                          maxfix+1))
                             (- (* 2 maxfix+1) 1)))
           maxfix+1)))

    (else
     (compiler-internal-error
      "univ-wrap*, unknown target"))))

(define (univ-emit-<< ctx expr1 expr2)
  (case (target-name (ctx-target ctx))

    ((js php python ruby)
     (^ expr1 " << " expr2))

    (else
     (compiler-internal-error
      "univ-emit-<<, unknown target"))))

(define (univ-emit->> ctx expr1 expr2)
  (case (target-name (ctx-target ctx))

    ((js php python ruby)
     (^ expr1 " >> " expr2))

    (else
     (compiler-internal-error
      "univ-emit->>, unknown target"))))

(define (univ-emit-bitnot ctx expr)
  (case (target-name (ctx-target ctx))

    ((js php python ruby)
     (^ "~ " expr))

    (else
     (compiler-internal-error
      "univ-emit-bitnot, unknown target"))))

(define (univ-emit-bitand ctx expr1 expr2)
  (case (target-name (ctx-target ctx))

    ((js php python ruby)
     (^ expr1 " & " expr2))

    (else
     (compiler-internal-error
      "univ-emit-bitand, unknown target"))))

(define (univ-emit-bitior ctx expr1 expr2)
  (case (target-name (ctx-target ctx))

    ((js php python ruby)
     (^ expr1 " | " expr2))

    (else
     (compiler-internal-error
      "univ-emit-bitior, unknown target"))))

(define (univ-emit-bitxor ctx expr1 expr2)
  (case (target-name (ctx-target ctx))

    ((js php python ruby)
     (^ expr1 " ^ " expr2))

    (else
     (compiler-internal-error
      "univ-emit-bitxor, unknown target"))))

(define (univ-emit-= ctx expr1 expr2)
  (case (target-name (ctx-target ctx))

    ((js)
     (^ expr1 " === " expr2))

    ((python ruby php)
     (^ expr1 " == " expr2))

    (else
     (compiler-internal-error
      "univ-emit-=, unknown target"))))

(define (univ-emit-!= ctx expr1 expr2)
  (case (target-name (ctx-target ctx))

    ((js)
     (^ expr1 " !== " expr2))

    ((python ruby php)
     (^ expr1 " != " expr2))

    (else
     (compiler-internal-error
      "univ-emit-!=, unknown target"))))

(define (univ-emit-< ctx expr1 expr2)
  (univ-emit-comparison ctx " < " expr1 expr2))

(define (univ-emit-<= ctx expr1 expr2)
  (univ-emit-comparison ctx " <= " expr1 expr2))

(define (univ-emit-> ctx expr1 expr2)
  (univ-emit-comparison ctx " > " expr1 expr2))

(define (univ-emit->= ctx expr1 expr2)
  (univ-emit-comparison ctx " >= " expr1 expr2))

(define (univ-emit-comparison ctx comp expr1 expr2)
  (case (target-name (ctx-target ctx))

    ((js python ruby php)
     (^ expr1 comp expr2))

    (else
     (compiler-internal-error
      "univ-emit-comparison, unknown target"))))

(define (univ-emit-not ctx expr)
  (case (target-name (ctx-target ctx))

    ((js php ruby)
     (^ "!" expr))

    ((python)
     (^ "not " expr))

    (else
     (compiler-internal-error
      "univ-emit-not, unknown target"))))

(define (univ-emit-&& ctx expr1 expr2)
  (case (target-name (ctx-target ctx))

    ((js ruby php)
     (^ expr1 " && " expr2))

    ((python)
     (^ expr1 " and " expr2))

    (else
     (compiler-internal-error
      "univ-emit-&&, unknown target"))))

(define (univ-emit-and ctx expr1 expr2)
  (case (target-name (ctx-target ctx))

    ((js ruby)
     (^ expr1 " && " expr2))

    ((python)
     (^ expr1 " and " expr2))

    ((php)
     (^ expr1 " ? " expr2 " : false"))

    (else
     (compiler-internal-error
      "univ-emit-and, unknown target"))))

(define (univ-emit-or ctx expr1 expr2)
  (case (target-name (ctx-target ctx))

    ((js ruby php)
     (^ expr1 " || " expr2)) ;; TODO: PHP || operator always yields a boolean

    ((python)
     (^ expr1 " or " expr2))

    (else
     (compiler-internal-error
      "univ-emit-or, unknown target"))))

(define (univ-emit-concat ctx expr1 expr2)
  (case (target-name (ctx-target ctx))

    ((js python ruby)
     (^ expr1 " + " expr2))

    ((php)
     (^ expr1 " . " expr2))

    (else
     (compiler-internal-error
      "univ-emit-concat, unknown target"))))

(define (univ-emit-tostr ctx expr)
  (case (target-name (ctx-target ctx))

    ((js)
     (^ expr ".toString()"))

    ((python)
     (^ "str(" expr ")"))

    ((php)
     (^ "(string)" expr))

    ((ruby)
     (^ expr ".to_s"))

    (else
     (compiler-internal-error
      "univ-emit-tostr, unknown target"))))

(define (univ-emit-parens ctx expr)
  (case (target-name (ctx-target ctx))

    ((js ruby php python)
     (^ "(" expr ")"))

    (else
     (compiler-internal-error
      "univ-emit-parens, unknown target"))))

(define (univ-emit-local-var ctx name)
  (case (target-name (ctx-target ctx))

    ((js python ruby)
     name)

    ((php)
     (^ "$" name))

    (else
     (compiler-internal-error
      "univ-emit-local-var, unknown target"))))

(define (univ-emit-global-var ctx name)
  (case (target-name (ctx-target ctx))

    ((js python)
     name)

    ((php ruby)
     (^ "$" name))

    (else
     (compiler-internal-error
      "univ-emit-global-var, unknown target"))))

(define (univ-emit-global-prim-function ctx name)
  (case (target-name (ctx-target ctx))

    ((js php python ruby)
     name)

    (else
     (compiler-internal-error
      "univ-emit-global-prim-function, unknown target"))))

(define (univ-emit-global-function ctx name)
  (case (target-name (ctx-target ctx))

    ((js python)
     name)

    ((php ruby)
     (^ "$" name))

    (else
     (compiler-internal-error
      "univ-emit-global-function, unknown target"))))

(define (univ-emit-prefix ctx name)
  (^ "Gambit_" name))

(define (univ-emit-assign ctx loc expr)
  (^ loc " = " expr))

(define (univ-emit-inc-by ctx loc expr #!optional (embed #f))

  (define (embed-read x)
    (if embed
        (embed x)
        (^)))

  (define (embed-expr x)
    (if embed
        (embed x)
        (^expr-statement x)))

  (define (inc-general loc expr)
    (if (and (number? expr) (< expr 0))
        (^ loc " -= " (- expr))
        (^ loc " += " expr)))

  (if (equal? expr 0)

      (embed-read loc)

      (case (target-name (ctx-target ctx))

        ((js php)
         (cond ((equal? expr 1)
                (embed-expr (^ "++" loc)))
               ((equal? expr -1)
                (embed-expr (^ "--" loc)))
               (else
                (embed-expr (^parens (inc-general loc expr))))))

        ((python)
         (^ (^expr-statement (inc-general loc expr))
            (embed-read loc)))

        ((ruby)
         (embed-expr (^parens (inc-general loc expr))))

        (else
         (compiler-internal-error
          "univ-emit-inc-by, unknown target")))))

(define (univ-emit-array-length ctx expr)
  (case (target-name (ctx-target ctx))

    ((js ruby)
     (^ expr ".length"))

    ((php)
     (^ "count(" expr ")"))

    ((python)
     (^ "len(" expr ")"))

    (else
     (compiler-internal-error
      "univ-emit-array-length, unknown target"))))

(define (univ-emit-array-shrink! ctx expr1 expr2)
  (case (target-name (ctx-target ctx))

    ((js)
     (^assign (^ expr1 ".length") expr2))

    ((php)
     (^ "array_splice(" expr1 "," expr2 ")"))

    ((python)
     (^ expr1 "[" expr2 ":len(" expr1 ")] = []"))

    ((ruby)
     (^ expr1 ".slice!(" expr2 "," expr1 ".length)"))

    (else
     (compiler-internal-error
      "univ-emit-array-shrink!, unknown target"))))

(define (univ-emit-array-index ctx expr1 expr2)
  (^ expr1 "[" expr2 "]"))

(define (univ-emit-prop-index ctx expr1 expr2)
  (^ expr1 "[" expr2 "]"))

(define (univ-emit-get ctx obj name)
  (case (target-name (ctx-target ctx))

    ((js python ruby)
     (^prop-index obj (^str name)))

    ((php)
     (^call-prim
      (^global-prim-function (^prefix "get"))
      obj
      (^str name)))

    (else
     (compiler-internal-error
      "univ-emit-get, unknown target"))))

(define (univ-emit-set ctx obj name val)
  (case (target-name (ctx-target ctx))

    ((js python ruby)
     (^assign (^prop-index obj (^str name)) val))

    ((php)
     (^call-prim
      (^global-prim-function (^prefix "set"))
      obj
      (^str name)
      val))

    (else
     (compiler-internal-error
      "univ-emit-set, unknown target"))))


;; ***** DUMPING OF A COMPILATION MODULE

(define (univ-dump targ procs output c-intf module-descr unique-name options)

  (call-with-output-file
      output
    (lambda (port)

      (univ-display
       (runtime-system (make-ctx targ #f))
       port)

      (univ-dump-procs targ procs port)

      (univ-display
       (entry-point (make-ctx targ #f) (list-ref procs 0))
       port)))

  #f)

(define (univ-dump-procs targ procs port)

  (let ((proc-seen (queue-empty))
        (proc-left (queue-empty)))

    (define (scan-obj obj)
      (if (and (proc-obj? obj)
               (proc-obj-code obj)
               (not (memq obj (queue->list proc-seen))))
          (begin
            (queue-put! proc-seen obj)
            (queue-put! proc-left obj))))

    (define (dump-proc p)

      (define (scan-bbs bbs)
        (let* ((bb-done (make-stretchable-vector #f))
               (bb-todo (queue-empty)))

          (define (todo-lbl-num! n)
            (queue-put! bb-todo (lbl-num->bb n bbs)))

          (define (scan-bb ctx bb)
            (if (stretchable-vector-ref bb-done (bb-lbl-num bb))
                (^)
                (begin
                  (stretchable-vector-set! bb-done (bb-lbl-num bb) #t)
                  (scan-bb-all ctx bb))))

          (define (scan-bb-all ctx bb)
            (scan-gvm-label
             ctx
             (bb-label-instr bb)
             (lambda (ctx)
               (scan-bb-all-except-label ctx bb))))

          (define (scan-bb-all-except-label ctx bb)
            (let loop ((lst (bb-non-branch-instrs bb))
                       (rev-res '()))
              (if (pair? lst)
                  (loop (cdr lst)
                        (cons (scan-gvm-instr ctx (car lst))
                              rev-res))
                  (reverse
                   (cons (scan-gvm-instr ctx (bb-branch-instr bb))
                         rev-res)))))

          (define (scan-gvm-label ctx gvm-instr proc)

            (define (frame-info gvm-instr)
              (let* ((frame
                      (gvm-instr-frame gvm-instr))
                     (fs
                      (frame-size frame))
                     (vars
                      (reverse (frame-slots frame)))
                     (link
                      (pos-in-list ret-var vars)))
                (vector fs link)))

            (with-stack-base-offset
             ctx
             (- (frame-size (gvm-instr-frame gvm-instr)))
             (lambda (ctx)
               (let ((id (gvm-bb-use ctx (label-lbl-num gvm-instr) (ctx-ns ctx))))
                 (^ "\n"
                    (^function-declaration

                     ;; name
                     id

                     ;; params
                     '()

                     ;; header
                     (case (label-type gvm-instr)

                       ((simple)
                        (^ "\n"))

                       ((entry)
                        (if (label-entry-rest? gvm-instr)
                            (^ " "
                               (univ-comment
                                ctx
                                (if (label-entry-closed? gvm-instr)
                                    "closure-entry-point (+rest)\n"
                                    "entry-point (+rest)\n")))
                            (^ " "
                               (univ-comment
                                ctx
                                (if (label-entry-closed? gvm-instr)
                                    "closure-entry-point\n"
                                    "entry-point\n")))))

                       ((return)
                        (^ " "
                           (univ-comment ctx "return-point\n")))

                       ((task-entry)
                        (^ " "
                           (univ-comment ctx "task-entry-point\n")))

                       ((task-return)
                        (^ " "
                           (univ-comment ctx "task-return-point\n")))

                       (else
                        (compiler-internal-error
                         "scan-gvm-label, unknown label type")))

                     ;; attribs
                     (append
                      (if (memq (label-type gvm-instr) '(entry return))
                          (list (cons "id" (^str id)))
                          '())
                      (if (eq? (label-type gvm-instr) 'return)
                          (let ((info (frame-info gvm-instr)))
                            (list (cons "fs" (vector-ref info 0))
                                  (cons "link" (+ (vector-ref info 1) 1))))
                          '()))

                     ;; body
                     (^ (case (label-type gvm-instr)

                          ((entry)
                           (if (label-entry-rest? gvm-instr)
                               (^if (^not (^&&
                                           (univ-emit-call-prim
                                            ctx
                                            (^prefix "buildrest")
                                            (label-entry-nb-parms gvm-instr))
                                           (^= (gvm-state-nargs-use ctx 'rd)
                                               (label-entry-nb-parms gvm-instr))))
                                    (univ-emit-return-call-prim
                                     ctx
                                     (^global-prim-function (^prefix "wrong_nargs"))
                                     id))
                               (^if (^!= (gvm-state-nargs-use ctx 'rd)
                                         (label-entry-nb-parms gvm-instr))
                                    (univ-emit-return-call-prim
                                     ctx
                                     (^global-prim-function (^prefix "wrong_nargs"))
                                     id))))

                          (else
                           (^)))

                        (proc ctx))))))))

          (define (scan-gvm-instr ctx gvm-instr)

            ;; TODO: combine with scan-gvm-opnd
            (define (scan-opnd gvm-opnd)
              (cond ((not gvm-opnd))
                    ((lbl? gvm-opnd)
                     (todo-lbl-num! (lbl-num gvm-opnd)))
                    ((obj? gvm-opnd)
                     (scan-obj (obj-val gvm-opnd)))
                    ((clo? gvm-opnd)
                     (scan-opnd (clo-base gvm-opnd)))))

            ;;(write-gvm-instr gvm-instr ##stderr-port)(newline ##stderr-port);;;;;;;;;;;;;;;;;;

            ;; TODO: combine with scan-gvm-opnd
            (case (gvm-instr-type gvm-instr)

              ((apply)
               (for-each scan-opnd (apply-opnds gvm-instr))
               (if (apply-loc gvm-instr)
                   (scan-opnd (apply-loc gvm-instr))))

              ((copy)
               (scan-opnd (copy-opnd gvm-instr))
               (scan-opnd (copy-loc gvm-instr)))

              ((close)
               (for-each (lambda (parms)
                           (scan-opnd (closure-parms-loc parms))
                           (scan-opnd (make-lbl (closure-parms-lbl parms)))
                           (for-each scan-opnd (closure-parms-opnds parms)))
                         (close-parms gvm-instr)))

              ((ifjump)
               (for-each scan-opnd (ifjump-opnds gvm-instr)))

              ((switch)
               (scan-opnd (switch-opnd gvm-instr))
               (for-each (lambda (c) (scan-obj (switch-case-obj c)))
                         (switch-cases gvm-instr)))

              ((jump)
               (scan-opnd (jump-opnd gvm-instr))))

            (case (gvm-instr-type gvm-instr)

              ((apply)
               (let ((loc (apply-loc gvm-instr))
                     (prim (apply-prim gvm-instr))
                     (opnds (apply-opnds gvm-instr)))
                 (let ((proc (proc-obj-inline prim)))
                   (if (not proc)

                       (compiler-internal-error
                        "scan-gvm-instr, unknown 'prim'" prim)

                       (proc
                        ctx
                        (lambda (result)
                          (cond (loc ;; result is needed?
                                 (^setloc loc (or result (^obj #f)))) ;;TODO: use void
                                ;; if result is not needed, don't generate expression
                                ;;(result
                                ;; (^expr-statement result))
                                (else
                                 (^))))
                        opnds)))))

              ((copy)
               (let ((loc (copy-loc gvm-instr))
                     (opnd (copy-opnd gvm-instr)))
                 (if opnd
                     (begin
                       (scan-gvm-opnd ctx loc);;;;;;;;;;;;;;;; needed?
                       (scan-gvm-opnd ctx opnd)
                       (^setloc loc (^getopnd opnd)))
                     (^))))

              ((close)
               (let ()

                 (define (alloc lst rev-loc-names)
                   (if (pair? lst)

                       (let* ((parms (car lst))
                              (lbl (closure-parms-lbl parms))
                              (loc (closure-parms-loc parms))
                              (opnds (closure-parms-opnds parms)))
                         (univ-closure-alloc
                          ctx
                          lbl
                          (map (lambda (opnd)
                                 (cond ((assv opnd rev-loc-names) => cdr)
                                       ((memv opnd (map closure-parms-loc lst))
                                        (^bool #f))
                                       (else
                                        (^getopnd opnd))))
                               opnds)
                          (lambda (name)
                            (alloc (cdr lst)
                                   (cons (cons loc name)
                                         rev-loc-names)))))

                       (init (close-parms gvm-instr) (reverse rev-loc-names))))

                 (define (init lst loc-names)
                   (if (pair? lst)

                       (let* ((parms (car lst))
                              (loc (closure-parms-loc parms))
                              (opnds (closure-parms-opnds parms))
                              (loc-name (assv loc loc-names)))
                         (let loop ((i 1) ;; 0
                                    (opnds opnds) ;; (cons (make-lbl lbl) opnds)
                                    (rev-code '()))
                           (if (pair? opnds)
                               (let ((opnd (car opnds)))
                                 (loop (+ i 1)
                                       (cdr opnds)
                                       (cons (if (and (assv opnd loc-names)
                                                      (memv opnd (map closure-parms-loc lst)))
                                                 (^setclo
                                                  (cdr loc-name)
                                                  i
                                                  (cdr (assv opnd loc-names)))
                                                 (^))
                                             rev-code)))
                               (^ (reverse rev-code)
                                  (init (cdr lst) loc-names)))))

                       (map
                        (lambda (loc-name)
                          (let* ((loc (car loc-name))
                                 (name (cdr loc-name)))
                            (^setloc loc name)))
                        loc-names)))

                 (alloc (close-parms gvm-instr) '())))

              ((ifjump)
               ;; TODO
               ;; (ifjump-poll? gvm-instr)
               (let ((test (ifjump-test gvm-instr))
                     (opnds (ifjump-opnds gvm-instr))
                     (true (ifjump-true gvm-instr))
                     (false (ifjump-false gvm-instr))
                     (fs (frame-size (gvm-instr-frame gvm-instr))))

                 (let ((proc (proc-obj-test test)))
                   (if (not proc)

                       (compiler-internal-error
                        "scan-gvm-instr, unknown 'test'" test)


                       (proc
                        ctx
                        (lambda (result)
                          (^if result
                               (jump-to-label ctx true fs)
                               (jump-to-label ctx false fs)))
                        opnds)))))

              ((switch)
               ;; TODO
               ;; (switch-opnd gvm-instr)
               ;; (switch-cases gvm-instr)
               ;; (switch-poll? gvm-instr)
               ;; (switch-default gvm-instr)
               (univ-throw ctx "\"switch GVM instruction unimplemented\""))

              ((jump)
               ;; TODO
               ;; (jump-safe? gvm-instr)
               ;; test: (jump-poll? gvm-instr)

               (let ((nb-args (jump-nb-args gvm-instr))
                     (poll? (jump-poll? gvm-instr))
                     (safe? (jump-safe? gvm-instr))
                     (opnd (jump-opnd gvm-instr))
                     (fs (frame-size (gvm-instr-frame gvm-instr))))

                 (or (and (obj? opnd)
                          (proc-obj? (obj-val opnd))
                          nb-args
                          (let* ((proc (obj-val opnd))
                                 (jump-inliner (proc-obj-jump-inline proc)))
                            (and jump-inliner
                                 (jump-inliner ctx nb-args poll? safe? fs))))

                     (^ (if nb-args
                            (^expr-statement
                             (^assign (gvm-state-nargs-use ctx 'wr) nb-args))
                            (^))

                        (or (and (lbl? opnd)
                                 (not poll?)
                                 (jump-to-label ctx (lbl-num opnd) fs))

                            (with-stack-pointer-adjust
                             ctx
                             (+ fs
                                (ctx-stack-base-offset ctx))
                             (lambda (ctx)
                               (univ-emit-return-poll
                                ctx
                                (scan-gvm-opnd ctx opnd)
                                poll?
                                (case (target-name (ctx-target ctx))
                                  ((js)
                                   ;; avoid call optimization on JavaScript
                                   ;; globals, because the underlying
                                   ;; JavaScript VM uses a counterproductive
                                   ;; speculative optimization (which slows
                                   ;; down fib by a factor of 10!)
                                   (not (reg? opnd)))
                                  ((php)
                                   ;; avoid call optimization on PHP
                                   ;; because it generates syntactically
                                   ;; incorrect code (PHP grammar issue)
                                   #f)
                                  (else
                                   #t))))))))))

              (else
               (compiler-internal-error
                "scan-gvm-instr, unknown 'gvm-instr':"
                gvm-instr))))

          (define (jump-to-label ctx n jump-fs)

            (cond ((and (ctx-allow-jump-destination-inlining? ctx)
                        (let* ((bb (lbl-num->bb n bbs))
                               (label-instr (bb-label-instr bb)))
                          (and (eq? (label-type label-instr) 'simple)
                               (or (= (length (bb-precedents bb)) 1)
                                   (= (length (bb-non-branch-instrs bb)) 0))))) ;; very short destination bb?
                   (let* ((bb (lbl-num->bb n bbs))
                          (label-instr (bb-label-instr bb))
                          (label-fs (frame-size (gvm-instr-frame label-instr))))
                     (with-stack-pointer-adjust
                      ctx
                      (+ jump-fs
                         (ctx-stack-base-offset ctx))
                      (lambda (ctx)
                        (with-stack-base-offset
                         ctx
                         (- label-fs)
                         (lambda (ctx)
                           (with-allow-jump-destination-inlining?
                            ctx
                            (= (length (bb-precedents bb)) 1) ;; #f
                            (lambda (ctx)
                              (scan-bb-all-except-label ctx bb)))))))))

                  (else
                   (with-stack-pointer-adjust
                    ctx
                    (+ jump-fs
                       (ctx-stack-base-offset ctx))
                    (lambda (ctx)
                      (univ-emit-return-call
                       ctx
                       (scan-gvm-opnd ctx (make-lbl n))))))))

          (define (scan-gvm-opnd ctx gvm-opnd)
            (if (lbl? gvm-opnd)
                (todo-lbl-num! (lbl-num gvm-opnd)))
            (^getopnd gvm-opnd));;;;;;;;;;;;;;;;;;;;;;;scan-gvm-loc ?

          (let ((ctx (make-ctx targ (proc-obj-name p))))

            (todo-lbl-num! (bbs-entry-lbl-num bbs))

            (let loop ((rev-res '()))
              (if (queue-empty? bb-todo)
                  (reverse rev-res)
                  (loop (cons (scan-bb ctx (queue-get! bb-todo))
                              rev-res)))))))

      (let ((ctx (make-ctx targ (proc-obj-name p))))
        (^ "\n"
           (univ-comment
            ctx
            (^ "-------------------------------- #<"
               (if (proc-obj-primitive? p)
                   "primitive"
                   "procedure")
               " "
               (object->string (string->canonical-symbol (proc-obj-name p)))
               "> =\n"))
           (let ((x (proc-obj-code p)))
             (if (bbs? x)
                 (scan-bbs x)
                 (^))))))

    (for-each scan-obj procs)

    (let loop ((rev-res '()))
      (if (queue-empty? proc-left)

          (univ-display
           (reverse (append rev-res *constants*))
           port)

          (loop (cons (dump-proc (queue-get! proc-left))
                      rev-res))))))

(define closure-count 0)

#;
(define (univ-closure-alloc ctx lbl nb-closed-vars cont)
  (case (target-name (ctx-target ctx))

    ((js python ruby)
     (set! closure-count (+ closure-count 1))
     (let ((name (string-append "closure" (number->string closure-count))))
       (^ (^function-declaration
           name
           '()
           "\n"
           '()
           (^ (univ-emit-assign ctx
                                (^getopnd (make-reg (+ univ-nb-arg-regs 1)))
                                name)
              (univ-emit-return-call ctx (gvm-lbl-use ctx (make-lbl lbl)))))
          (cont name))))

    (else
     (compiler-internal-error
      "univ-closure-alloc, unknown target"))))

(define (univ-separated-list sep lst)
  (if (pair? lst)
      (if (pair? (cdr lst))
          (list (car lst) sep (univ-separated-list sep (cdr lst)))
          (car lst))
      '()))

(define (univ-map-index f lst)

  (define (mp f lst i)
    (if (pair? lst)
        (cons (f (car lst) i)
              (mp f (cdr lst) (+ i 1)))
        '()))

  (mp f lst 0))

(define (univ-closure-alloc ctx lbl exprs cont)
  (let ((count (ctx-serial-num ctx)))
    (ctx-serial-num-set! ctx (+ count 1))
    (let ((name
           (^local-var (string-append "closure" (number->string count)))))
      (^ (^var-declaration
          name
          (^call-prim
           (^global-prim-function (^prefix "closure_alloc"))
           (^dict
            (univ-map-index (lambda (x i)
                              (cons (string-append "v"
                                                   (number->string i))
                                    x))
                            (cons (gvm-lbl-use ctx (make-lbl lbl))
                                  exprs)))))
         (cont name)))))

(define (make-ctx target ns)
  (vector target
          ns
          0
          0
          univ-enable-jump-destination-inlining?
          (make-resource-set)
          (make-resource-set)
          (make-resource-set)))

(define (ctx-target ctx)                   (vector-ref ctx 0))
(define (ctx-target-set! ctx x)            (vector-set! ctx 0 x))

(define (ctx-ns ctx)                       (vector-ref ctx 1))
(define (ctx-ns-set! ctx x)                (vector-set! ctx 1 x))

(define (ctx-stack-base-offset ctx)        (vector-ref ctx 2))
(define (ctx-stack-base-offset-set! ctx x) (vector-set! ctx 2 x))

(define (ctx-serial-num ctx)               (vector-ref ctx 3))
(define (ctx-serial-num-set! ctx x)        (vector-set! ctx 3 x))

(define (ctx-allow-jump-destination-inlining? ctx)        (vector-ref ctx 4))
(define (ctx-allow-jump-destination-inlining?-set! ctx x) (vector-set! ctx 4 x))

(define (ctx-resources-used-rd ctx)        (vector-ref ctx 5))
(define (ctx-resources-used-rd-set! ctx x) (vector-set! ctx 5 x))

(define (ctx-resources-used-wr ctx)        (vector-ref ctx 6))
(define (ctx-resources-used-wr-set! ctx x) (vector-set! ctx 6 x))

(define (ctx-globals-used ctx)             (vector-ref ctx 7))
(define (ctx-globals-used-set! ctx x)      (vector-set! ctx 7 x))

(define (with-stack-base-offset ctx n proc)
  (let ((save (ctx-stack-base-offset ctx)))
    (ctx-stack-base-offset-set! ctx n)
    (let ((result (proc ctx)))
      (ctx-stack-base-offset-set! ctx save)
      result)))

(define (with-stack-pointer-adjust ctx n proc)
  (^ (if (equal? n 0)
         (^)
         (^inc-by (begin
                    (gvm-state-sp-use ctx 'rd)
                    (gvm-state-sp-use ctx 'wr))
                  n))
     (with-stack-base-offset
      ctx
      (- (ctx-stack-base-offset ctx) n)
      proc)))

(define (with-allow-jump-destination-inlining? ctx allow? proc)
  (let ((save (ctx-allow-jump-destination-inlining? ctx)))
    (ctx-allow-jump-destination-inlining?-set! ctx allow?)
    (let ((result (proc ctx)))
      (ctx-allow-jump-destination-inlining?-set! ctx save)
      result)))

(define (with-new-resources-used ctx proc)
  (let ((save-rsrc-rd (ctx-resources-used-rd ctx))
        (save-rsrc-wr (ctx-resources-used-wr ctx))
        (save-glob-rd (ctx-globals-used ctx)))
    (ctx-resources-used-rd-set! ctx (make-resource-set))
    (ctx-resources-used-wr-set! ctx (make-resource-set))
    (ctx-globals-used-set! ctx (make-resource-set))
    (let ((result (proc ctx)))
      (ctx-resources-used-rd-set! ctx save-rsrc-rd)
      (ctx-resources-used-wr-set! ctx save-rsrc-wr)
      (ctx-globals-used-set! ctx save-glob-rd)
      result)))

(define (make-resource-set)
  (make-table))

(define (resource-set-add! set element)
  (table-set! set element #t))

(define (resource-set-member? set element)
  (table-ref set element #f))

(define (resource-set->list set)
  (map car (table->list set)))

(define (use-resource-rd ctx resource)
  (resource-set-add! (ctx-resources-used-rd ctx) resource))

(define (use-resource-wr ctx resource)
  (resource-set-add! (ctx-resources-used-wr ctx) resource))

(define (use-global ctx global)
  (resource-set-add! (ctx-globals-used ctx) global))

(define (use-resource ctx dir resource)
  (if (eq? dir 'rd)
      (use-resource-rd ctx resource)
      (use-resource-wr ctx resource)))

(define (gvm-state-pollcount ctx)
  (^global-var (^prefix "pollcount")))

(define (gvm-state-nargs ctx)
  (^global-var (^prefix "nargs")))

(define (gvm-state-reg ctx num)
  (^global-var (^prefix (^ "r" num))))

(define (gvm-state-stack ctx)
  (^global-var (^prefix "stack")))

(define (gvm-state-sp ctx)
  (^global-var (^prefix "sp")))

(define (gvm-state-glo ctx)
  (^global-var (^prefix "glo")))

(define (gvm-state-pollcount-use ctx dir)
  (use-resource ctx dir 'pollcount)
  (gvm-state-pollcount ctx))

(define (gvm-state-nargs-use ctx dir)
  (use-resource ctx dir 'nargs)
  (gvm-state-nargs ctx))

(define (gvm-state-reg-use ctx dir num)
  (use-resource ctx dir num)
  (gvm-state-reg ctx num))

(define (gvm-state-stack-use ctx dir)
  (use-resource ctx dir 'stack)
  (gvm-state-stack ctx))

(define (gvm-state-sp-use ctx dir)
  (use-resource ctx dir 'sp)
  (gvm-state-sp ctx))

(define (gvm-state-glo-use ctx dir)
  (use-resource ctx dir 'glo)
  (gvm-state-glo ctx))

(define (univ-emit-getreg ctx num)
  (gvm-state-reg-use ctx 'rd num))

(define (univ-emit-setreg ctx num val)
  (^expr-statement
   (^assign
    (gvm-state-reg-use ctx 'wr num)
    val)))

(define (univ-stk-location ctx offset)
  (^array-index
   (gvm-state-stack-use ctx 'rd)
   (^ (gvm-state-sp-use ctx 'rd)
      (cond ((= offset 0)
             (^))
            ((< offset 0)
             (^ offset))
            (else
             (^ "+" offset))))))

(define (univ-emit-getstk ctx offset)
  (univ-stk-location ctx offset))

(define (univ-emit-setstk ctx offset val)
  (^expr-statement
   (^assign
    (univ-stk-location ctx offset)
    val)))

(define (univ-clo-obj-name ctx closure index)
  (cons (case (target-name (ctx-target ctx))
          ((php)
           (^member closure "slots"))
          (else
           (^call closure (^bool #t))))
        (string-append "v" (number->string index))))

(define (univ-emit-getclo ctx closure index)
  (let ((obj-name (univ-clo-obj-name ctx closure index)))
    (^get (car obj-name)
          (cdr obj-name))))

(define (univ-emit-setclo ctx closure index val)
  (let ((obj-name (univ-clo-obj-name ctx closure index)))
    (^expr-statement
     (^set (car obj-name)
           (cdr obj-name)
           val))))

(define (univ-glo-location ctx name)
  (^prop-index
   (gvm-state-glo-use ctx 'rd)
   (^str (symbol->string name))))

(define (univ-emit-getglo ctx name)
  (univ-glo-location ctx name))

(define (univ-emit-setglo ctx name val)
  (^expr-statement
   (^assign
    (univ-glo-location ctx name)
    val)))

(define (univ-emit-getopnd ctx gvm-opnd)

  (cond ((reg? gvm-opnd)
         (^getreg (reg-num gvm-opnd)))

        ((stk? gvm-opnd)
         (^getstk (+ (stk-num gvm-opnd) (ctx-stack-base-offset ctx))))

        ((glo? gvm-opnd)
         (^getglo (glo-name gvm-opnd)))

        ((clo? gvm-opnd)
         (^getclo (^getopnd (clo-base gvm-opnd))
                  (clo-index gvm-opnd)))

        ((lbl? gvm-opnd)
         (gvm-lbl-use ctx gvm-opnd))

        ((obj? gvm-opnd)
         (^obj (obj-val gvm-opnd)))

        (else
         (compiler-internal-error
          "univ-emit-getopnd, unknown 'gvm-opnd':"
          gvm-opnd))))

(define (univ-emit-getopnds ctx gvm-opnds)
  (map (lambda (gvm-opnd) (univ-emit-getopnd ctx gvm-opnd))
       gvm-opnds))

(define (univ-emit-setloc ctx gvm-loc val)

  (cond ((reg? gvm-loc)
         (^setreg (reg-num gvm-loc)
                  val))

        ((stk? gvm-loc)
         (^setstk (+ (stk-num gvm-loc) (ctx-stack-base-offset ctx))
                  val))

        ((glo? gvm-loc)
         (^setglo (glo-name gvm-loc)
                  val))

        ((clo? gvm-loc)
         (^setclo (^getopnd (clo-base gvm-loc))
                  (clo-index gvm-loc)
                  val))

        (else
         (compiler-internal-error
          "univ-emit-setloc, unknown 'gvm-loc':"
          gvm-loc))))

(define (univ-emit-obj ctx obj)

  (^parens;;TODO: remove (only needed in cases like new Gambit_Char(33)->code in PHP)

  (cond ((boolean? obj)
         (^boolean-box (^bool obj)))

        ((number? obj)
         (univ-emit-number ctx obj))

        ((char? obj)
         (^char-box (^chr obj)))

        ((string? obj)
         (^string-box
          (^array-literal
           (map (lambda (c) (^int (char->integer c)))
                (string->list obj)))))

        ((symbol? obj)
         (^symbol-box (^sym obj)))

        ((null? obj)
         (^null-box (^null)))

        ((void-object? obj)
         (^ "undefined"))

        ((undefined? obj)
         (univ-undefined ctx))

        ((proc-obj? obj)
         (gvm-proc-use ctx (proc-obj-name obj)))

        ((pair? obj)
         (^cons (^obj (car obj))
                (^obj (cdr obj))))

        ((vector? obj)
         (^vector-box
          (^array-literal
           (map (lambda (x) (^obj x))
                (vector->list obj)))))

        (else
         (^ "UNIMPLEMENTED_OBJECT("
            (object->string obj)
            ")")))))

(define (univ-emit-number ctx obj)
  (if (exact? obj)
      (cond ((integer? obj)
             ;; TODO: bignums
             (^fixnum-box (^int obj)))
            (else
             ;; TODO: exact rationals and complex
             (compiler-internal-error
              "univ-emit-number, unsupported exact number:" obj)))
      (cond ((real? obj)
             (^flonum-box (^float obj)))
            (else
             ;; TODO: inexact complex
             (compiler-internal-error
              "univ-emit-number, unsupported inexact number:" obj)))))

(define (univ-emit-array-literal ctx elems)
  (case (target-name (ctx-target ctx))

    ((js python ruby)
     (^ "[" (univ-separated-list "," elems) "]"))

    ((php)
     (^apply (^global-prim-function "array") elems))

    (else
     (compiler-internal-error
      "univ-emit-array-literal, unknown target"))))

;;==================================================================

(define *constants* '())

;; =============================================================================

(define (gvm-lbl-use ctx lbl)
  (gvm-bb-use ctx (lbl-num lbl) (ctx-ns ctx)))

(define (gvm-proc-use ctx name)
  (gvm-bb-use ctx 1 name))

(define (gvm-bb-use ctx num ns)
  (let ((global (lbl->id ctx num ns)))
    (use-global ctx global)
    global))

(define (lbl->id ctx num ns)
  (^global-function (^prefix (^ "bb" num "_" (scheme-id->c-id ns)))))

(define (univ-emit-empty-dict ctx)
  (case (target-name (ctx-target ctx))
    ((js python ruby)
     (^ "{}"))
    ((php)
     (^ "array()"))
    (else
     (compiler-internal-error
      "univ-emit-empty-dict, unknown target"))))

(define (univ-emit-empty-extensible-array ctx)
  (case (target-name (ctx-target ctx))
    ((js ruby)
     (^ "[]"))
    ((python)
     (^ "{}"))
    ((php)
     (^ "array()"))
    (else
     (compiler-internal-error
      "univ-emit-empty-extensible-array, unknown target"))))

(define (runtime-system ctx)
  (let ((target (target-name (ctx-target ctx))))
    (^ (case target

         ((js)
          (^))

         ((php)
          (^ "<?php\n\n"))

         ((python)
          (^ "#! /usr/bin/python\n"
             "\n"
             "from array import array\n"
             "import ctypes\n"
             "import time\n"
             "import math\n"
             "\n"))

         ((ruby)
          (^ "# encoding: utf-8\n"
             "\n"))

         (else
          (compiler-internal-error
           "runtime-system, unknown target")))

       (case (univ-null-representation ctx)

         ((class)
          (^class-declaration
           (^prefix "Null")
           '((val #f))
           '()))

         (else
          (^)))

       (case (univ-boolean-representation ctx)

         ((class)
          (^class-declaration
           (^prefix "Boolean")
           '((val #f))
           '()))

         (else
          (^)))

       (case (univ-char-representation ctx)

         ((class)
          (^class-declaration
           (^prefix "Char")
           '((code #f))
           (list
            (list (univ-tostr-method-name ctx)
                  '()
                  (case target

                    ((js)
                     (^return
                      (^call-prim
                       (^member "String" "fromCharCode")
                       (^this-member "code"))))

                    ((php python)
                     (^return
                      (^call-prim
                       (^global-prim-function "chr")
                       (^this-member "code"))))

                    ((ruby)
                     (^return
                      (^call-prim
                       (^member
                        (^this-member "code")
                        "chr"))))

                    (else
                     (compiler-internal-error
                      "runtime-system, unknown target")))))))

         (else
          (^)))

       (case (univ-fixnum-representation ctx)

         ((class)
          (^class-declaration
           (^prefix "Fixnum")
           '((val #f))
           '()))

          (else
           (^)))

       (case (univ-flonum-representation ctx)

         ((class)
          (^class-declaration
           (^prefix "Flonum")
           '((val #f))
           '()))

         (else
          (^)))

       (case (univ-vector-representation ctx)

         ((class)
          (^class-declaration
           (^prefix "Vector")
           '((elems #f))
           '()))

         (else
          (^)))

       (case (univ-string-representation ctx)

         ((class)
          (^class-declaration
           (^prefix "String")
           '((codes #f))
           (list
            (list (univ-tostr-method-name ctx)
                  '()
                  (case target

                    ((js)
                     (^return
                      (^call-prim
                       (^member (^member "String" "fromCharCode") "apply")
                       (^null)
                       (^this-member "codes"))))

                    ((php)
                     (^return
                      (^call-prim
                       (^global-prim-function "join")
                       (^call-prim
                        (^global-prim-function "array_map")
                        (^str "chr")
                        (^this-member "codes")))))

                    ((python)
                     (^return
                      (^call-prim
                       (^member (^str "") "join")
                       (^call-prim
                        (^global-prim-function "map")
                        (^global-prim-function "chr")
                        (^this-member "codes")))))

                    ((ruby)
                     ;;TODO: add anonymous function
                     (^return
                      (^call-prim
                       (^member
                        (^ (^member (^this-member "codes") "map")
                           " {|x| x.chr}")
                        "join"))))

                    (else
                     (compiler-internal-error
                      "runtime-system, unknown target")))))))

         (else
          (^)))

       (case (univ-symbol-representation ctx)

         ((class)
          (^class-declaration
           (^prefix "Symbol")
           '((str #f))
           '()))

         (else
          (^)))

       (^class-declaration
        (^prefix "Pair")
        '((car #f) (cdr #f))
        '())

       (^class-declaration
        (^prefix "Box")
        '((val #f))
        '())

#|
//JavaScript toString method:
Gambit_Pair.prototype.toString = function () {
  return this.car.toString() + this.car.toString();
};

/* PHP toString method: */
  public function __toString() {
    return $this->car . $this->cdr;
  }

# Python toString method:
  def __str__(self):
    return self.car + self.cdr

# Ruby toString method:
  def to_s
    @car.to_s + @cdr.to_s
  end
|#

       (case target

         ((js python ruby)
          (^))

         ((php)
          (^
#<<EOF
class Gambit_closure {

  function __construct($slots) {
    $this->slots = $slots;
  }

  function __invoke() {
    global $Gambit_r4;
    $Gambit_r4 = $this;
    return $this->slots["v0"];
  }
}

function Gambit_closure_alloc($slots) {
  return new Gambit_closure($slots);
}

function Gambit_get($obj,$name) {
  return $obj[$name];
}

function Gambit_set(&$obj,$name,$val) {
  $obj[$name] = $val;
}


EOF
))

         (else
          (compiler-internal-error
           "runtime-system, unknown target")))

       (^var-declaration (^global-var (^prefix "glo")) (univ-emit-empty-dict ctx));;;;;;;;;;;;;;;;;;;;;
       (^var-declaration (^global-var (^prefix "r0")) (^obj #f))
       (^var-declaration (^global-var (^prefix "r1")))
       (^var-declaration (^global-var (^prefix "r2")))
       (^var-declaration (^global-var (^prefix "r3")))
       (^var-declaration (^global-var (^prefix "r4")))
       (^var-declaration (^global-var (^prefix "stack")) (univ-emit-empty-extensible-array ctx));;;;;;;;;;;;;;;;;;;;;;;
       (^var-declaration (^global-var (^prefix "sp")) -1)
       (^var-declaration (^global-var (^prefix "nargs")) 0)
       (^var-declaration (^global-var (^prefix "temp1")) (^obj #f))
       (^var-declaration (^global-var (^prefix "temp2")) (^obj #f))
       (^var-declaration (^global-var (^prefix "pollcount")) 100)

       "\n"

       (^prim-function-declaration
        (^global-prim-function (^prefix "trampoline"))
        (list (cons (^local-var "pc") #f))
        "\n"
        '()
        (^while (^!= (^local-var "pc") (^obj #f))
                (^expr-statement
                 (^assign (^local-var "pc")
                          (^call (^local-var "pc"))))))

       "\n"

       (case (target-name (ctx-target ctx))

         ((php)
          (^))

         (else
          (^ (^prim-function-declaration
              (^global-prim-function (^prefix "closure_alloc"))
              (list (cons (^local-var "slots") #f))
              "\n"
              '()
              (^ (^function-declaration
                  (^local-var "closure")
                  (list (cons (^local-var "msg") #t))
                  "\n"
                  '()
                  (^ (^if (^= (^local-var "msg") (^bool #t))
                          (^return (^local-var "slots")))
                     (^setreg (+ univ-nb-arg-regs 1)
                              (^local-var "closure"))
                     (^return (^get (^local-var "slots") "v0"))))
                 (^return (^local-var "closure"))))

             "\n")))

       (^prim-function-declaration
        (^global-prim-function (^prefix "poll"))
        (list (cons (^local-var "dest") #f))
        "\n"
        '()
        (^ (^expr-statement
            (^assign (gvm-state-pollcount-use ctx 'wr)
                     100))
           (^return (^local-var "dest"))))

       "\n"

       (^prim-function-declaration
        (^global-prim-function (^prefix "println"))
        (list (cons (^local-var "obj") #f))
        "\n"
        '()
        (case (target-name (ctx-target ctx))
          ((js python)
           (^expr-statement (^call-prim "print" (^local-var "obj"))))
          ((ruby php)
           (^ (^expr-statement (^call-prim "print" (^local-var "obj")))
              (^expr-statement (^call-prim "print" "\"\\n\""))))
          (else
           (compiler-internal-error
            "runtime-system, unknown target"))))

       "\n"

       (^prim-function-declaration
        (^global-prim-function (^prefix "strtocodes"))
        (list (cons (^local-var "str") #f))
        "\n"
        '()
        (case (target-name (ctx-target ctx))
          ((js)
;;TODO: clean up
"
    var codes = [];
    for (var i=0; i < str.length; i++) {
        codes.push(str.charCodeAt(i));
    }
    return codes;
")
          ((php python ruby)
           (^return (^array-literal '(67 68 69)))) ;; TODO: implement
          (else
           (compiler-internal-error
            "runtime-system, unknown target"))))

       "\n"

       (^prim-function-declaration
        (^global-prim-function (^prefix "tostr"))
        (list (cons (^local-var "obj") #f))
        "\n"
        '()
        (^if (^eq? (^local-var "obj")
                   (^obj #f))
             (^return (^str "#f"))
             (^if (^eq? (^local-var "obj")
                        (^obj #t))
                  (^return (^str "#t"))
                  (^if (^eq? (^local-var "obj")
                             (^obj '()))
                       (^return (^str ""))
                       (^if (^pair? (^local-var "obj"))
                            (^return (^concat
                                      (^call-prim
                                       (^global-prim-function (^prefix "tostr"))
                                       (^member (^local-var "obj") "car"))
                                      (^call-prim
                                       (^global-prim-function (^prefix "tostr"))
                                       (^member (^local-var "obj") "cdr"))))
;;                            (^if (^char? (^local-var "obj"))
;;                                 (^return (^chr-tostr (^char-unbox (^local-var "obj"))))
                                 (^if (^flonum? (^local-var "obj"))
                                      (^return (^tostr (^flonum-unbox (^local-var "obj"))))
;;                                      (^if (^string? (^local-var "obj"))
;;                                           (^return (^tostr (^string-unbox (^local-var "obj"))))
                                           (^return (^tostr (^local-var "obj")))))))))
;;)
;;)

       "\n"

       (^function-declaration
        (gvm-proc-use ctx "println")
        '()
        "\n"
        '()
        (^ (^expr-statement
            (^call-prim
             (^global-prim-function (^prefix "println"))
             (^call-prim
              (^global-prim-function (^prefix "tostr"))
              (^getreg 1))))
           (^return (^getreg 0))))

       "\n"

       (^setglo 'println
                (gvm-proc-use ctx "println"))

       "\n"

       (^var-declaration
        (^global-var (^prefix "start_time"))
        (case (target-name (ctx-target ctx))

          ((js)
           (^call-prim (^member (^new "Date") "getTime")))

          ((php)
           (^call-prim "microtime" (^bool #t)))

          ((python)
           (^call-prim (^member "time" "time")))

          ((ruby)
           (^new "Time"))

          (else
           (compiler-internal-error
            "runtime-system, unknown target"))))

       "\n"

       (^function-declaration
        (gvm-proc-use ctx "real-time-milliseconds")
        '()
        "\n"
        '()
        (^ (case (target-name (ctx-target ctx))

             ((js)
              (^setreg 1 (^- (^call-prim (^member (^new "Date") "getTime"))
                             (^global-var (^prefix "start_time")))))

             ((php)
              (^ "global " (^global-var (^prefix "start_time")) ";\n"
                 (^setreg 1 (^ "(int)"
                               (^parens
                                (^* 1000
                                    (^parens
                                    (^- (^call-prim "microtime" (^bool #t))
                                        (^global-var (^prefix "start_time"))))))))))

             ((python)
              (^setreg 1 (^call-prim
                          "int"
                          (^* 1000
                              (^parens
                               (^- (^call-prim (^member "time" "time"))
                                   (^global-var (^prefix "start_time"))))))))

             ((ruby)
              (^setreg 1 (^call-prim
                          (^member
                           (^parens
                            (^* 1000
                                (^parens
                                 (^- (^new "Time")
                                     (^global-var (^prefix "start_time"))))))
                           "floor"))))

             (else
              (compiler-internal-error
               "runtime-system, unknown target")))
           (^return (^getreg 0))))

       "\n"

       (^setglo 'real-time-milliseconds
                (gvm-proc-use ctx "real-time-milliseconds"))

       "\n"

       (^prim-function-declaration
        (^global-prim-function (^prefix "make_vector"))
        (list (cons (^local-var "len") #f)
              (cons (^local-var "init") #f))
        "\n"
        '()
        (case (target-name (ctx-target ctx))

          ((js)
           ;; TODO: add for loop constructor
           (^ (^var-declaration (^local-var "elems")
                                (^new "Array" (^local-var "len")))
              "
               for (var i=0; i<len; i++) {
                 elems[i] = init;
               }
              "
              (^return (^vector-box (^local-var "elems")))))

          ((php)
           (^return
            (^vector-box
             (^call-prim
              (^global-prim-function "array_fill")
              (^int 0)
              (^local-var "len")
              (^local-var "init")))))

          ((python)
           ;; TODO: add literal array constructor
           (^return
            (^vector-box
             (^* (^ "[" (^local-var "init") "]") (^local-var "len")))))

          ((ruby)
           (^return
            (^vector-box
             (^call-prim (^member "Array" "new")
                         (^local-var "len")
                         (^local-var "init")))))

          (else
           (compiler-internal-error
            "runtime-system, unknown target"))))

       "\n"

       (^prim-function-declaration
        (^global-prim-function (^prefix "make_string"))
        (list (cons (^local-var "len") #f)
              (cons (^local-var "init") #f))
        "\n"
        '()
        (case (target-name (ctx-target ctx))

          ((js)
           ;; TODO: add for loop constructor
           (^ (^var-declaration (^local-var "codes")
                                (^new "Array" (^local-var "len")))
              "
               for (var i=0; i<len; i++) {
                 codes[i] = init;
               }
              "
              (^return (^string-box (^local-var "codes")))))

          ((php)
           (^return
            (^string-box
             (^call-prim
              (^global-prim-function "array_fill")
              (^int 0)
              (^local-var "len")
              (^local-var "init")))))

          ((python)
           ;; TODO: add literal array constructor
           (^return
            (^string-box
             (^* (^ "[" (^local-var "init") "]") (^local-var "len")))))

          ((ruby)
           (^return
            (^string-box
             (^call-prim (^member "Array" "new")
                         (^local-var "len")
                         (^local-var "init")))))

          (else
           (compiler-internal-error
            "runtime-system, unknown target"))))

       "\n"

       )))

#;
(define (runtime-system-old ctx)
  (case (target-name (ctx-target ctx))

    ((python)                               ;rts js
     (let ((R0 (^operand (make-reg 0)))
           (R1 (^operand (make-reg 1)))
           (R2 (^operand (make-reg 2)))
           (R3 (^operand (make-reg 3)))
           (R4 (^operand (make-reg 4))))
       (^

"#! /usr/bin/python

from array import array
import ctypes

"

        (^var-declaration (^prefix "glo") "{}")
        (^var-declaration (^prefix "r0") (^obj #f))
        (^var-declaration (^prefix "r1"))
        (^var-declaration (^prefix "r2"))
        (^var-declaration (^prefix "r3"))
        (^var-declaration (^prefix "r4"))
        (^var-declaration (^prefix "stack") "{}")
        (^var-declaration (^prefix "sp") -1)
        (^var-declaration (^prefix "nargs") 0)
        (^var-declaration (^prefix "temp1") (^obj #f))
        (^var-declaration (^prefix "temp2") (^obj #f))
        (^var-declaration (^prefix "pollcount") 100)

        "\n"

        (^prim-function-declaration
         (^global-prim-function (^prefix "trampoline"))
         "pc"
         "\n"
         '()
         (univ-indent
          (^while (^!= "pc" (^obj #f))
                  (^expr-statement
                   (^assign "pc" (^call "pc"))))))

        (^prim-function-declaration
         (^global-prim-function (^prefix "println"))
         "obj"
         "\n"
         '()
         (univ-indent
          (^expr-statement (^call "print" "obj"))))

        (^function-declaration
         (gvm-proc-use ctx "println")
         ""
         "\n"
         '()
         (univ-indent
          (^ (^if (^eq? R1 (^obj #f))
                  (^expr-statement
                   (^call-prim
                    (^global-prim-function (^prefix "println"))
                    (^str "#f")))
                  (^if (^eq? R1 (^obj #t))
                       (^expr-statement
                        (^call-prim
                         (^global-prim-function (^prefix "println"))
                         (^str "#t")))
                       (^expr-statement
                        (^call-prim
                         (^global-prim-function (^prefix "println"))
                         R1))))
             (^return R0))))

        (^setglo 'println
                 (gvm-proc-use ctx "println"))

)))

    ((js-old)                               ;rts js
     (let ((R0 (^operand (make-reg 0)))
           (R1 (^operand (make-reg 1)))
           (R2 (^operand (make-reg 2)))
           (R3 (^operand (make-reg 3)))
           (R4 (^operand (make-reg 4))))
       (^ "
function Gambit_heapify(ra) {

  if (Gambit_sp > 0) { // stack contains at least one frame

    var fs = ra.fs, link = ra.link;
    var chain = Gambit_stack;

    if (Gambit_sp > fs) { // stack contains at least two frames
      chain = Gambit_stack.slice(Gambit_sp - fs, Gambit_sp + 1);
      chain[0] = ra;
      Gambit_sp = Gambit_sp - fs;
      var prev_frame = chain, prev_link = link;
      ra = prev_frame[prev_link]; fs = ra.fs; link = ra.link;

      while (Gambit_sp > fs) {
        var frame = Gambit_stack.slice(Gambit_sp - fs, Gambit_sp + 1);
        frame[0] = ra;
        Gambit_sp = Gambit_sp - fs;
        prev_frame[prev_link] = frame;
        prev_frame = frame; prev_link = link;
        ra = prev_frame[prev_link]; fs = ra.fs; link = ra.link;
      }

      prev_frame[prev_link] = Gambit_stack;
    }

    Gambit_stack.length = fs + 1;
    Gambit_stack[link] = Gambit_stack[0];
    Gambit_stack[0] = ra;

    Gambit_stack = [chain];
    Gambit_sp = 0;
  }

  return Gambit_underflow;
}

function Gambit_underflow() {

  var frame = Gambit_stack[0];

  if (frame === false) // end of continuation?
    return false; // terminate trampoline

  var ra = frame[0], fs = ra.fs, link = ra.link;
  Gambit_stack = frame.slice(0, fs + 1);
  Gambit_sp = fs;
  Gambit_stack[0] = frame[link];
  Gambit_stack[link] = Gambit_underflow;

  return ra;
}
Gambit_underflow.fs = 0;

var Gambit_glo = {};
var " R0 " = Gambit_underflow;
var " R1 " = false;
var " R2 " = false;
var " R3 " = false;
var " R4 " = false;
var Gambit_stack = [];
var Gambit_sp = 0;
var Gambit_nargs = 0;
var Gambit_temp1 = false;
var Gambit_temp2 = false;
var Gambit_poll;
var Gambit_printout;

Gambit_stack[0] = false;

var Gambit_pollcount = 1;

//if (this.hasOwnProperty('setTimeout')) {
//  Gambit_poll = function (dest) {
//                  Gambit_pollcount = 100;
//                  Gambit_stack.length = Gambit_sp + 1;
//                  setTimeout(function () { Gambit_trampoline(dest); }, 1);
//                  return false;
//                };
//} else {
  Gambit_poll = function (dest) {
                  Gambit_pollcount = 100;
                  Gambit_stack.length = Gambit_sp + 1;
                  return dest;
                };
//}

var iobuffer = \"\";

function Gambit_printout(text) {
  if (text === \"\\n\") {
    print(iobuffer);
    iobuffer = \"\";
  } else {
    iobuffer += text;
  }
//  if (text === \"\\n\")
//    document.write(\"<br/>\");
//  else
//    document.write(text);
}

function Gambit_buildrest ( f ) {    // nb formal args
                                     // *** assume (= univ-nb-arg-regs 3) for now ***
    var nb_static_args = f - 1;
    var nb_rest_args = Gambit_nargs - nb_static_args;
    var rest = null;
    var Gambit_reg = [];
    Gambit_reg[1] = " R1 ";
    Gambit_reg[2] = " R2 ";
    Gambit_reg[3] = " R3 ";


    if (Gambit_nargs < nb_static_args)  // Wrong number of args
        return false;

    // simple case, all in reg
    if ((Gambit_nargs <= 3) && (nb_static_args < 3)) {
        for (var i = nb_static_args + 1; i < nb_static_args + nb_rest_args + 1; i++) {
            rest = Gambit_cons(Gambit_reg[i], rest);
        }

        Gambit_reg[nb_static_args + 1] = rest;
        Gambit_nargs -= (nb_rest_args - 1);

        " R1 " = Gambit_reg[1];
        " R2 " = Gambit_reg[2];
        " R3 " = Gambit_reg[3];

        return true;
    }

    // rest is empty
    if ((Gambit_nargs >= 3) && (nb_rest_args === 0)) { // only append '()
        var spill_loc = nb_static_args - 2;        // univ-nb-arg-regs - 1
        Gambit_sp += 1;
        Gambit_stack[Gambit_sp] = Gambit_reg[1];
        Gambit_reg[1] = Gambit_reg[2];
        Gambit_reg[2] = Gambit_reg[3];
        Gambit_reg[3] = null;
        Gambit_nargs += 1;

        " R1 " = Gambit_reg[1];
        " R2 " = Gambit_reg[2];
        " R3 " = Gambit_reg[3];

        return true;
    }

    // general case
    for (var i = 1; i <= 3; i++) {
        Gambit_stack[Gambit_sp + i] = Gambit_reg[i];
    }
    Gambit_sp += 3;
    for (var i = 0; i < nb_rest_args; i++) {
        rest = Gambit_cons(Gambit_stack[Gambit_sp - i], rest);
    }
    Gambit_sp -= nb_rest_args;
    Gambit_stack[Gambit_sp + 1] = rest;
    Gambit_sp += 1;

    switch (nb_static_args) {
    case 0:
        Gambit_reg[1] = Gambit_stack[Gambit_sp];
        Gambit_sp -= 1;
        break;
    case 1:
        Gambit_reg[2] = Gambit_stack[Gambit_sp];
        Gambit_reg[1] = Gambit_stack[Gambit_sp - 1];
        Gambit_sp -= 2;
        break;
    default:
        for (var i = 3; i > 0; i--) {
            Gambit_reg[i] = Gambit_stack[Gambit_sp - 3 + i];
        }
        Gambit_sp -= 3;
        break;
    }
    Gambit_nargs = f;

    " R1 " = Gambit_reg[1];
    " R2 " = Gambit_reg[2];
    " R3 " = Gambit_reg[3];

    return true;
}

function Gambit_wrong_nargs(fn) {
    Gambit_printout(\"*** wrong number of arguments (\"+Gambit_nargs+\") when calling\");
    Gambit_printout(fn);
    return false;
}

function closure_alloc(slots) {

  function self(msg) {
    if (msg === false) return slots;
    " R4 " = self;
    return slots.v0;
  }

  return self;
}

// Flonum
function Gambit_Flonum(val) {
    this.val = val;
}

Gambit_Flonum.prototype.toString = function ( ) {
    if (parseFloat(this.val) == parseInt(this.val)) {
        return this.val + \".\";
    } else {
        return this.val;
    }
}

// Pair, List
function Gambit_Pair ( car, cdr ) {
    this.car = car;
    this.cdr = cdr;
}

function Gambit_pairp ( p ) {
    return (p instanceof Gambit_Pair);
}

Gambit_Pair.prototype.toString = function ( ) {
    return Gambit_write(this);
//    return (\"(\" + Gambit_println(this.car) + \" . \" +  Gambit_println(this.cdr) + \")\");
}

Gambit_Pair.prototype.println = function ( ) {
    return Gambit_println(this.car) + Gambit_println(this.cdr);
}

function Gambit_nullp ( o ) {
    return o === null;
}

// cons
function Gambit_cons ( a, b ) {
    return new Gambit_Pair(a, b);
}

// car
function Gambit_car ( p ) {
    return p.car;
}

// cdr
function Gambit_cdr ( p ) {
    return p.cdr;
}

// caar
function Gambit_caar ( p ) {
    return p.car.car;
}

// cadr
function Gambit_cadr ( p ) {
    return p.cdr.car;
}

// cdar
function Gambit_cdar ( p ) {
    return p.car.cdr;
}

// cddr
function Gambit_cddr ( p ) {
    return p.cdr.cdr;
}

// caaar
function Gambit_caaar ( p ) {
    return p.car.car.car;
}

// caadr
function Gambit_caadr ( p ) {
    return p.cdr.car.car;
}

// cadar
function Gambit_cadar ( p ) {
    return p.car.cdr.car;
}

// caddr
function Gambit_caddr ( p ) {
    return p.cdr.cdr.car;
}

// cdaar
function Gambit_cdaar ( p ) {
    return p.car.car.cdr;
}

// cdadr
function Gambit_cdadr ( p ) {
    return p.cdr.car.cdr;
}

// cddar
function Gambit_cddar ( p ) {
    return p.car.cdr.cdr;
}

// cdddr
function Gambit_cdddr ( p ) {
    return p.cdr.cdr.cdr;
}

// caaaar
function Gambit_caaaar ( p ) {
    return p.car.car.car.car;
}

// caaadr
function Gambit_caaadr ( p ) {
    return p.cdr.car.car.car;
}

// caadar
function Gambit_caadar ( p ) {
    return p.car.cdr.car.car;
}

// caaddr
function Gambit_caaddr ( p ) {
    return p.cdr.cdr.car.car;
}

// cadaar
function Gambit_cadaar ( p ) {
    return p.car.car.cdr.car;
}

// cadadr
function Gambit_cadadr ( p ) {
    return p.cdr.car.cdr.car;
}

// caddar
function Gambit_caddar ( p ) {
    return p.car.cdr.cdr.car;
}

// cadddr
function Gambit_cadddr ( p ) {
    return p.cdr.cdr.cdr.car;
}

// cdaaar
function Gambit_cdaaar ( p ) {
    return p.car.car.car.cdr;
}

// cdaadr
function Gambit_cdaadr ( p ) {
    return p.cdr.car.car.cdr;
}

// cdadar
function Gambit_cdadar ( p ) {
    return p.car.cdr.car.cdr;
}

// cdaddr
function Gambit_cdaddr ( p ) {
    return p.cdr.cdr.car.cdr;
}

// cddaar
function Gambit_cddaar ( p ) {
    return p.car.car.cdr.cdr;
}

// cddadr
function Gambit_cddadr ( p ) {
    return p.cdr.car.cdr.cdr;
}

// cdddar
function Gambit_cdddar ( p ) {
    return p.car.cdr.cdr.cdr;
}

// cddddr
function Gambit_cddddr ( p ) {
    return p.cdr.cdr.cdr.cdr;
}

// set-car!
function Gambit_setcar ( p, a ) {
    p.car = a;
}

// set-cdr!
function Gambit_setcdr ( p, b ) {
    p.cdr = b;
}


Gambit_list = function ( ) {
    var listaux = function (a, n, lst) {
        if (n === 0) {
            return Gambit_cons(a[0], lst);
        } else {
            return listaux(a, n-1, Gambit_cons(a[n], lst));
        }
    }

//    var res = listaux(arguments, arguments.length - 1, null);

    return listaux(arguments, arguments.length - 1, null);
}

Gambit_length = function ( h ) {
    var len = 0;
//    var h = this;

    while (h !== null) {
        len += 1;
        h = h.cdr;
    }

    return len;
}


// Char
var Gambit_chars = {}
function Gambit_Char(charcode) {
    this.charcode = charcode;
}

Gambit_Char.fxToChar = function ( charcode ) {
    var ch = Gambit_chars[charcode];

    if (!ch) {
        Gambit_chars[charcode] = new Gambit_Char(charcode);
        ch = Gambit_chars[charcode];
    }

    return ch;
}

Gambit_Char.charToFx = function ( c ) {
    return c.charcode;
}

Gambit_Char.prototype.toString = function ( ) {
    return \"#\\\\\"  + String.fromCharCode(this.charcode);
}

Gambit_Char.prototype.print = function ( ) {
    return String.fromCharCode(this.charcode);
}

// String
var Gambit_String = function ( ) {
    this.chars = new Array(arguments.length);
    for (i = 0; i < arguments.length; i++) {
        this.chars[i] = arguments[i];
    }
}

Gambit_String.makestring = function ( n, ch ) {
    var s = new Gambit_String();
    for (i = 0; i < n; i++) {
        s.chars[i] = ch;
    }

    return s;
}

Gambit_String.listToString = function ( lst ) {
    var len = Gambit_length(lst);
    var s = Gambit_String.makestring(len);
    var h = lst;
    for (i = 0; i < len; i++) {
        s.chars[i] = h.car;
        h = h.cdr;
    }

    return s;
}

Gambit_String.stringToList = function ( s ) {
    var len = s.stringlength();

    var listaux = function (a, n, lst) {
        if (n === 0) {
            return Gambit_cons(a[0], lst);
        } else {
            return listaux(a, n-1, Gambit_cons(a[n], lst));
        }
    }

    return listaux(s.chars, len - 1, null);
}

Gambit_String.jsstringToString = function ( s ) {
    var len = s.length;
    var s2 = Gambit_String.makestring(len, Gambit_Char.fxToChar(0));
    for (i = 0; i < len; i++) {
        s2.chars[i] = Gambit_Char.fxToChar(s.charCodeAt(i));
    }

    return s2;
}

Gambit_String.prototype.stringlength = function ( ) {
    return this.chars.length;
}

// string-ref
Gambit_String.prototype.stringref = function ( n ) {
    return this.chars[n];
}

// string-set!
Gambit_String.prototype.stringset = function ( n, ch ) {  // ch: Char
    this.chars[n] = ch;
}

Gambit_String.prototype.toString = function ( ) {
    var s = \"\\\"\";
    for (i = 0; i < this.stringlength(); i++) {
        s = s.concat(this.stringref(i).print());
    }
    s += \"\\\"\"

    return s;
}

Gambit_String.prototype.print = function ( ) {
    var s = \"\";
    for (i = 0; i < this.stringlength(); i++) {
        s = s.concat(this.stringref(i).print());
    }

    return s;
}

var Gambit_stringappend = function ( ) {
    var totallen = 0;
    var lens = [];

    for (i = 0; i < arguments.length; i++) {
        lens[i] = arguments[i].stringlength();
        totallen += lens[i];
    }

    var s = Gambit_String.makestring(totallen);
    var partlen = 0;
    for (i = 0; i < lens.length; i++) {
        var len = lens[i];
        for (j = 0; j < len; j++) {
            s.stringset(partlen + j, arguments[i].stringref(j));
        }
        partlen += len;
    }

    return s;
}
" (univ-emit-getglo ctx 'string-append) " = Gambit_stringappend;

// Vector
var Gambit_Vector = function ( ) {
    this.a = new Array(arguments.length);
    for (i = 0; i < arguments.length; i++) {
        this.a[i] = arguments[i];
    }
}

// make-vector
Gambit_Vector.makevector = function ( n, val ) {
    var v = new Gambit_Vector();

    for (var i = 0; i < n; i++) {
        v.a[i] = val;
    }

    return v;
}

// vector-length
Gambit_Vector.prototype.vectorlength = function ( ) {
    return this.a.length;
}

// vector-ref
Gambit_Vector.prototype.vectorref = function ( n ) {
    return this.a[n];
}

// vector-set!
Gambit_Vector.prototype.vectorset = function ( n, v ) {
    this.a[n] = v;
}

Gambit_Vector.prototype.toString = function ( ) {
    var res = \"#(\";

    if (this.vectorlength() > 0) {
        res += Gambit_toString(this.a[0]);
    }

    for (var i = 1; i<this.a.length; i++) {
        res += \", \";
        res += Gambit_toString(this.a[i]);
    }
    res += \")\"
    return res;
}

Gambit_Vector.prototype.println = function ( ) {
    var res = \"\";
    for (var i = 0; i<this.a.length; i++) {
        res += Gambit_println(this.a[i]);
    }

    return res;
}

// Symbol
var Gambit_syms = {};
function Gambit_Symbol(s) {
    this.symbolToString = function ( ) { return s; }
    this.toString = function ( ) { return s; }
}

Gambit_Symbol.stringToSymbol = function ( s ) {
    var sym = Gambit_syms[s];

    if (!sym) {
        Gambit_syms[s] = new Gambit_Symbol(s);
        sym = Gambit_syms[s];
    }

    return sym;
}

var Gambit_kwds = {};
function Gambit_Keyword(s) {
    s = s + \":\";

    this.keywordToString = function( ) { return s.substring(0, s.length-1); }
    this.toString = function( ) { return s; }
}

Gambit_Keyword.stringToKeyword = function(s) {
    var kwd = Gambit_kwds[s];

    if (!kwd) {
        Gambit_kwds[s] = new Gambit_Keyword(s);
        kwd = Gambit_kwds[s];
    }

    return kwd;
}

// Primitives

function Gambit_write ( obj ) {
    if (obj === false)
        Gambit_printout(\"#f\");
    else if (obj === true)
        Gambit_printout(\"#t\");
    else if (obj === null)
        Gambit_printout(\"()\");
    else if (obj instanceof Gambit_Flonum)
        Gambit_printout(obj.toString());
    else if (obj instanceof Gambit_String)
        Gambit_printout(\"\\\"\" + obj.toString() + \"\\\"\");
    else if (obj instanceof Gambit_Char)
        Gambit_printout(obj.toString());
    else if (obj instanceof Gambit_Pair) {
        Gambit_printout(\"(\");
        Gambit_write(obj.car);
        Gambit_writelist(obj.cdr);
    }
    else if (obj instanceof Array)
        Gambit_printout(obj.toString());
    else if (obj instanceof Gambit_Symbol)
        Gambit_printout(obj.symbolToString());
    else if (obj instanceof Gambit_Keyword)
        Gambit_printout(obj.keywordToString());
    else
        Gambit_printout(obj);
}

function Gambit_bb1_write ( ) { // write
    if (Gambit_nargs !== 1) {
        return Gambit_wrong_nargs(Gambit_bb1_write);
    }

    Gambit_write(Gambit_reg1);

    return Gambit_reg0;
}

" (univ-emit-getglo ctx 'write) " = Gambit_bb1_write;

function Gambit_writelist ( obj ) {
    if (obj === null) {
        Gambit_printout(\")\");
    } else {
        if (obj instanceof Gambit_Pair) {
            Gambit_printout(\" \");
            Gambit_write(obj.car);
            Gambit_writelist(obj.cdr);
        } else {
            Gambit_printout(\" . \");
            Gambit_write(obj);
            Gambit_printout(\")\");
        }
    }
}

function Gambit_bb1_writelist ( ) { // write-list
    if (Gambit_nargs !== 1) {
        return Gambit_wrong_nargs(Gambit_bb1_writelist);
    }

    Gambit_writelist(Gambit_reg1);

    return Gambit_reg0;
}

" (univ-emit-getglo ctx 'write-list) " = Gambit_bb1_writelist;

function Gambit_print ( obj ) {
    if (obj === false)
        Gambit_printout(\"#f\");
    else if (obj === true)
        Gambit_printout(\"#t\");
    else if (obj === null)
        Gambit_printout(\"\");
    else if (obj instanceof Gambit_Flonum)
        Gambit_printout(obj.toString());
    else if (obj instanceof Gambit_String)
        Gambit_printout(obj.print());
    else if (obj instanceof Gambit_Char)
        Gambit_printout(obj.print());
    else if (obj instanceof Gambit_Pair) {
        Gambit_print(obj.car);
        Gambit_print(obj.cdr);
    }
    else if (obj instanceof Array) {
        for (i = 0; i < obj.length; i++) {
            Gambit_print(obj[i]);
        }
    }
    else if (obj instanceof Gambit_Symbol)
        Gambit_printout(obj.symbolToString());
    else if (obj instanceof Gambit_Keyword)
        Gambit_printout(obj.keywordToString());
    else
        Gambit_printout(obj);
}

function Gambit_bb1_print ( ) { // print
    if (Gambit_nargs !== 1) {
        return Gambit_wrong_nargs(Gambit_bb1_print);
    }

    Gambit_print(" R1 ");

    return " R0 ";
}

" (univ-emit-getglo ctx 'print) " = Gambit_bb1_print;

function Gambit_println ( obj ) {
    Gambit_print(obj);
    Gambit_printout(\"\\n\");
}

function Gambit_bb1_println ( ) { // println
    if (Gambit_nargs !== 1) {
        return Gambit_wrong_nargs(Gambit_bb1_println);
    }

    Gambit_println(" R1 ");

    return " R0 ";
}

" (univ-emit-getglo ctx 'println) " = Gambit_bb1_println;

function Gambit_bb1_newline ( ) { // newline
    if (Gambit_nargs !== 0) {
        return Gambit_wrong_nargs(Gambit_bb1_newline);
    }

    Gambit_printout(\"\\n\");

    return " R0 ";
}

" (univ-emit-getglo ctx 'newline) " = Gambit_bb1_newline;

function Gambit_bb1_display ( ) { // display
    if (Gambit_nargs !== 1) {
        return Gambit_wrong_nargs(Gambit_bb1_display);
    }

    Gambit_write(" R1 ");

    return " R0 ";
}

" (univ-emit-getglo ctx 'display) " = Gambit_bb1_display;

function Gambit_bb1_prettyprint ( ) { // prettyprint
    if (Gambit_nargs !== 1) {
        return Gambit_wrong_nargs(Gambit_bb1_prettyprint);
    }

    Gambit_write(" R1 ");
    Gambit_printout(\"\\n\");

    return " R0 ";
}

" (univ-emit-getglo ctx 'prettyprint) " = Gambit_bb1_prettyprint;

function Gambit_bb1_pp ( ) { // pp
    if (Gambit_nargs !== 1) {
        return Gambit_wrong_nargs(Gambit_bb1_pp);
    }

    Gambit_write(" R1 ");
    Gambit_printout(\"\\n\");

    return " R0 ";
}

" (univ-emit-getglo ctx 'pp) " = Gambit_bb1_pp;

function Gambit_bb1_real_2d_time_2d_milliseconds ( ) { // real-time-milliseconds
    if (Gambit_nargs !== 0) {
        return Gambit_wrong_nargs(Gambit_bb1_display);
    }

    " R1 " = new Date();

    return " R0 ";
}

" (univ-emit-getglo ctx 'real-time-milliseconds) " = Gambit_bb1_real_2d_time_2d_milliseconds;


// Continuations
function Gambit_Continuation(frame, denv) {
    this.frame = frame;
    this.denv = denv;
}


// Obsolete
function Gambit_dump_cont(sp, ra) {
    Gambit_printout(\"------------------------\");
    while (ra !== false) {
        Gambit_printout(\"sp=\"+Gambit_sp + \" fs=\"+ra.fs + \" link=\"+ra.link);
        Gambit_sp = Gambit_sp-ra.fs;
        ra = Gambit_stack[Gambit_sp+ra.link+1];
    }
    Gambit_printout(\"------------------------\");
}

function Gambit_continuation_capture1() {
  var receiver = " R1 ";
  " R0 " = Gambit_heapify(" R0 ");
  " R1 " = new Gambit_Continuation(Gambit_stack[0], false);
  Gambit_nargs = 1;
  return receiver;
}

function Gambit_continuation_capture2() {
  var receiver = " R1 ";
  " R0 " = Gambit_heapify(" R0 ");
  " R1 " = new Gambit_Continuation(Gambit_stack[0], false);
  Gambit_nargs = 2;
  return receiver;
}

function Gambit_continuation_capture3() {
  var receiver = " R1 ";
  " R0 " = Gambit_heapify(" R0 ");
  " R1 " = new Gambit_Continuation(Gambit_stack[0], false);
  Gambit_nargs = 3;
  return receiver;
}

function Gambit_continuation_capture4() {
  var receiver = Gambit_stack[Gambit_sp--];
  " R0 " = Gambit_heapify(" R0 ");
  Gambit_stack[++Gambit_sp] = new Gambit_Continuation(Gambit_stack[0], false);
  Gambit_nargs = 4;
  return receiver;
}

function Gambit_continuation_graft_no_winding2() {
  var proc = " R2 ";
  var cont = " R1 ";
  Gambit_sp = 0;
  Gambit_stack[0] = cont.frame;
  " R0 " = Gambit_underflow;
  Gambit_nargs = 0;
  return proc;
}

function Gambit_continuation_graft_no_winding3() {
  var proc = " R2 ";
  var cont = " R1 ";
  Gambit_sp = 0;
  Gambit_stack[0] = cont.frame;
  " R0 " = Gambit_underflow;
  " R1 " = " R3 ";
  Gambit_nargs = 1;
  return proc;
}

function Gambit_continuation_graft_no_winding4() {
  var proc = " R1 ";
  var cont = Gambit_stack[Gambit_sp];
  Gambit_sp = 0;
  Gambit_stack[0] = cont.frame;
  " R0 " = Gambit_underflow;
  " R1 " = " R2 ";
  " R2 " = " R3 ";
  Gambit_nargs = 2;
  return proc;
}

function Gambit_continuation_graft_no_winding5() {
  var proc = Gambit_stack[Gambit_sp];
  var cont = Gambit_stack[Gambit_sp-1];
  Gambit_sp = 0;
  Gambit_stack[0] = cont.frame;
  " R0 " = Gambit_underflow;
  Gambit_nargs = 3;
  return proc;
}

function Gambit_continuation_return_no_winding2() {
  var cont = " R1 ";
  Gambit_sp = 0;
  Gambit_stack[0] = cont.frame;
  " R0 " = Gambit_underflow;
  " R1 " = " R2 ";
  return " R0 ";
}

function Gambit_bb1__23__23_continuation_3f_() { // ##continuation?
  if (Gambit_nargs !== 1) {
    return Gambit_wrong_nargs(Gambit_bb1__23__23_continuation_3f_);
  }
  " R1 " = " R1 " instanceof Gambit_Continuation;
  return " R0 ";
}

" (univ-emit-getglo ctx '##continuation?) " = Gambit_bb1__23__23_continuation_3f_;


function Gambit_bb1__23__23_continuation_2d_frame() { // ##continuation-frame
  if (Gambit_nargs !== 1) {
    return Gambit_wrong_nargs(Gambit_bb1__23__23_continuation_2d_frame);
  }
  " R1 " = " R1 ".frame;
  return " R0 ";
}

" (univ-emit-getglo ctx '##continuation-frame) " = Gambit_bb1__23__23_continuation_2d_frame;


function Gambit_bb1__23__23_continuation_2d_denv() { // ##continuation-denv
  if (Gambit_nargs !== 1) {
    return Gambit_wrong_nargs(Gambit_bb1__23__23_continuation_2d_denv);
  }
  " R1 " = " R1 ".denv;
  return " R0 ";
}

" (univ-emit-getglo ctx '##continuation-denv) " = Gambit_bb1__23__23_continuation_2d_denv;


function Gambit_bb1__23__23_continuation_2d_fs() { // ##continuation-fs
  if (Gambit_nargs !== 1) {
    return Gambit_wrong_nargs(Gambit_bb1__23__23_continuation_2d_fs);
  }
  " R1 " = " R1 ".frame[0].fs;
  return " R0 ";
}

" (univ-emit-getglo ctx '##continuation-fs) " = Gambit_bb1__23__23_continuation_2d_fs;


function Gambit_bb1__23__23_frame_2d_fs() { // ##frame-fs
  if (Gambit_nargs !== 1) {
    return Gambit_wrong_nargs(Gambit_bb1__23__23_frame_2d_fs);
  }
  " R1 " = " R1 "[0].fs;
  return " R0 ";
}

" (univ-emit-getglo ctx '##frame-fs) " = Gambit_bb1__23__23_frame_2d_fs;


function Gambit_bb1__23__23_return_2d_fs() { // ##return-fs
  if (Gambit_nargs !== 1) {
    return Gambit_wrong_nargs(Gambit_bb1__23__23_return_2d_fs);
  }
  " R1 " = " R1 ".fs;
  return " R0 ";
}

" (univ-emit-getglo ctx '##return-fs) " = Gambit_bb1__23__23_return_2d_fs;


function Gambit_bb1__23__23_return_2d_link() { // ##return-link
  if (Gambit_nargs !== 1) {
    return Gambit_wrong_nargs(Gambit_bb1__23__23_return_2d_link);
  }
  " R1 " = " R1 ".link-1;
  return " R0 ";
}

" (univ-emit-getglo ctx '##return-link) " = Gambit_bb1__23__23_return_2d_link;


function Gambit_bb1__23__23_return_2d_id() { // ##return-id
  if (Gambit_nargs !== 1) {
    return Gambit_wrong_nargs(Gambit_bb1__23__23_return_2d_id);
  }
  " R1 " = " R1 ".id;
  return " R0 ";
}

" (univ-emit-getglo ctx '##return-id) " = Gambit_bb1__23__23_return_2d_id;


function Gambit_bb1__23__23_continuation_2d_link() { // ##continuation-link
  if (Gambit_nargs !== 1) {
    return Gambit_wrong_nargs(Gambit_bb1__23__23_continuation_2d_link);
  }
  " R1 " = " R1 ".frame[0].link-1;
  return " R0 ";
}

" (univ-emit-getglo ctx '##continuation-link) " = Gambit_bb1__23__23_continuation_2d_link;


function Gambit_bb1__23__23_frame_2d_link() { // ##frame-link
  if (Gambit_nargs !== 1) {
    return Gambit_wrong_nargs(Gambit_bb1__23__23_frame_2d_link);
  }
  " R1 " = " R1 "[0].link-1;
  return " R0 ";
}
" (univ-emit-getglo ctx '##frame-link) " = Gambit_bb1__23__23_frame_2d_link;

function Gambit_bb1__23__23_continuation_2d_ret() { // ##continuation-ret
  if (Gambit_nargs !== 1) {
    return Gambit_wrong_nargs(Gambit_bb1__23__23_continuation_2d_ret);
  }
  " R1 " = " R1 ".frame[0];
  return " R0 ";
}

" (univ-emit-getglo ctx '##continuation-ret) " = Gambit_bb1__23__23_continuation_2d_ret;


function Gambit_bb1__23__23_frame_2d_ret() { // ##frame-ret
  if (Gambit_nargs !== 1) {
    return Gambit_wrong_nargs(Gambit_bb1__23__23_frame_2d_ret);
  }
  " R1 " = " R1 "[0];
  return " R0 ";
}

" (univ-emit-getglo ctx '##frame-ret) " = Gambit_bb1__23__23_frame_2d_ret;


function Gambit_bb1__23__23_continuation_2d_ref() { // ##continuation-ref
  if (Gambit_nargs !== 2) {
    return Gambit_wrong_nargs(Gambit_bb1__23__23_continuation_2d_ref);
  }
  " R1 " = " R1 ".frame[" R2 "];
  return " R0 ";
}

" (univ-emit-getglo ctx '##continuation-ref) " = Gambit_bb1__23__23_continuation_2d_ref;


function Gambit_bb1__23__23_frame_2d_ref() { // ##frame-ref
  if (Gambit_nargs !== 2) {
    return Gambit_wrong_nargs(Gambit_bb1__23__23_frame_2d_ref);
  }
  " R1 " = " R1 "[" R2 "];
  return " R0 ";
}

" (univ-emit-getglo ctx '##frame-ref) " = Gambit_bb1__23__23_frame_2d_ref;


function Gambit_bb1__23__23_continuation_2d_slot_2d_live_3f_() { // ##continuation-slot-live?
  if (Gambit_nargs !== 2) {
    return Gambit_wrong_nargs(Gambit_bb1__23__23_continuation_2d_slot_2d_live_3f_);
  }
  " R1 " = true;
  return " R0 ";
}

" (univ-emit-getglo ctx '##continuation-slot-live?) " = Gambit_bb1__23__23_continuation_2d_slot_2d_live_3f_;


function Gambit_bb1__23__23_frame_2d_slot_2d_live_3f_() { // ##frame-slot-live?
  if (Gambit_nargs !== 2) {
    return Gambit_wrong_nargs(Gambit_bb1__23__23_frame_2d_slot_2d_live_3f_);
  }
  " R1 " = true;
  return " R0 ";
}

" (univ-emit-getglo ctx '##frame-slot-live?) " = Gambit_bb1__23__23_frame_2d_slot_2d_live_3f_;


function Gambit_bb1__23__23_continuation_2d_next() { // ##continuation-next
  if (Gambit_nargs !== 1) {
    return Gambit_wrong_nargs(Gambit_bb1__23__23_continuation_2d_next);
  }
  var frame = " R1 ".frame;
  var denv = " R1 ".denv;
  var next_frame = frame[frame[0].link];
  if (next_frame === false)
    " R1 " = false;
  else
    " R1 " = new Gambit_Continuation(next_frame, denv);
  return " R0 ";
}

" (univ-emit-getglo ctx '##continuation-next) " = Gambit_bb1__23__23_continuation_2d_next;


function Gambit_trampoline(pc) {
  while (pc !== false) {
    pc = pc();
  }
}

"

)))

    ((python-old)                           ;rts py
#<<EOF
#! /usr/bin/python

from array import array
import ctypes

Gambit_glo = {}
Gambit_reg = {0:False}
Gambit_stack = {}
Gambit_sp = -1
Gambit_nargs = 0
Gambit_temp1 = False
Gambit_temp2 = False

#
# char
#
class Gambit_Char:
  chars = {}
  def __init__ ( self,  c ):
    self.c = c

  def __str__ ( self ):
    return self.c

# ##fx->char
def Gambit_fxToChar ( i ):
  if Gambit_Char.chars.has_key(i):
    return Gambit_Char.chars[i]
  else:
    Gambit_Char.chars[i] = Gambit_Char(unichr(i))
    return Gambit_Char.chars[i]

# ##fx<-char
def Gambit_charToFx ( c ):
  return ord(c.c)

# char?
def Gambit_charp ( c ):
  return (isinstance(c, Char))

#
# Pair
#
class Gambit_Pair:
  def __init__ ( self, car, cdr ):
    self.car = car
    self.cdr = cdr

  def __str__ ( self ):
    res = "(" + self.car
    if (self.cdr is not None):
      res += " . " + self.cdr
    res += ")"

    return res

  def __eq__ ( self, p ):
    return self is p

  def car ( self ):
    return self.car

  def cdr ( self ):
    return self.cdr

  def setcar ( self, newcar ):
    self.car = newcar

  def setcdr ( self, newcdr ):
    self.cdr = newcdr

def Gambit_cons ( a, b ):
  return Gambit_Pair(a, b)

def Gambit_list ( *args ):
  n = len(args)
  lst = None

  while n > 0:
    lst = Gambit_cons(args[n-1], lst)
    n -= 1

  return lst

#
# String
#
class Gambit_String:
  def __init__ ( self, *args ):
    self.chars = array('u', list(args))

  def __getitem__ ( self, n ):
    return self.chars[n]

  def __setitem__ ( self, n, c ):
    self.chars[n] = c.c

  def __len__ ( self ):
    return len(self.chars)

  def __eq__ ( self, s ):
    self.chars == s.chars

  def __str__ ( self ):
    return "".join(self.chars)

def Gambit_makestring ( n, c ):
  args = [c.c]*n
  return Gambit_String(*args)

def Gambit_stringp ( s ):
  return isinstance(s, String)


def Gambit_bb1_println(): # println
  global Gambit_glo, Gambit_reg, Gambit_stack, Gambit_sp, Gambit_nargs, Gambit_temp1, Gambit_temp2
  if Gambit_nargs != 1:
    raise "wrong number of arguments"
  if Gambit_reg[1] is False:
    print("#f")
  elif Gambit_reg[1] is True:
    print("#t")
  elif isinstance(Gambit_reg[1], float) and (int(Gambit_reg[1]) == round(Gambit_reg[1])):
    print(str(int(Gambit_reg[1])) + '.')
  else:
    print(Gambit_reg[1])
  return " R0 ";

Gambit_glo["println"] = Gambit_bb1_println


def Gambit_poll(wakeup):
  return wakeup


def Gambit_trampoline(pc):
  while pc != False:
    pc = pc()

EOF
)

    ((ruby)                             ;rts rb
#<<EOF
# encoding: utf-8

$Gambit_glo = {}
$Gambit_reg = {0=>false}
$Gambit_stack = {}
$Gambit_sp = -1
$Gambit_nargs = 0
$Gambit_temp1 = false
$Gambit_temp2 = false

$Gambit_chars = {}
class Gambit_Char
  def initialize ( code )
    @code = code
  end
  def code
    @code
  end
  def to_s
    @code.chr
  end
end

def Gambit_fxToChar ( i )
  if $Gambit_chars.has_key?(i)
    return $Gambit_chars[i]
  else
    c = Gambit_Char.new(i)
    $Gambit_chars[i] = c
    return c
  end
end

def Gambit_charToFx ( c )
  return c.code
end

$Gambit_bb1_println = lambda { # println
  if $Gambit_nargs != 1
    raise "wrong number of arguments"
  end

  if $Gambit_reg[1] == false
    print("#f")
  elsif $Gambit_reg[1] == true
    print("#t")
  elsif $Gambit_reg[1].equal?(nil)
    print("")
  elsif $Gambit_reg[1].class == Float && $Gambit_reg[1] == $Gambit_reg[1].round
    print($Gambit_reg[1].round.to_s() + ".")
  else
    print($Gambit_reg[1])
  end

  print("\n")
  return $Gambit_reg[0]
}

$Gambit_glo["println"] = $Gambit_bb1_println


def Gambit_poll(wakeup)
  return wakeup
end


def Gambit_trampoline(pc)
  while pc != false
    pc = pc.call
  end
end

EOF
)

    ((php)                              ;rts php
#<<EOF
??????????????????????????????????
EOF
)

    ((dart)                               ;rts dart
     (let ((R0 (^operand (make-reg 0)))
           (R1 (^operand (make-reg 1)))
           (R2 (^operand (make-reg 2)))
           (R3 (^operand (make-reg 3)))
           (R4 (^operand (make-reg 4))))
       (^ "
function Gambit_heapify(ra) {

  if (Gambit_sp > 0) { // stack contains at least one frame

    var fs = ra.fs, link = ra.link;
    var chain = Gambit_stack;

    if (Gambit_sp > fs) { // stack contains at least two frames
      chain = Gambit_stack.slice(Gambit_sp - fs, Gambit_sp + 1);
      chain[0] = ra;
      Gambit_sp = Gambit_sp - fs;
      var prev_frame = chain, prev_link = link;
      ra = prev_frame[prev_link]; fs = ra.fs; link = ra.link;

      while (Gambit_sp > fs) {
        var frame = Gambit_stack.slice(Gambit_sp - fs, Gambit_sp + 1);
        frame[0] = ra;
        Gambit_sp = Gambit_sp - fs;
        prev_frame[prev_link] = frame;
        prev_frame = frame; prev_link = link;
        ra = prev_frame[prev_link]; fs = ra.fs; link = ra.link;
      }

      prev_frame[prev_link] = Gambit_stack;
    }

    Gambit_stack.length = fs + 1;
    Gambit_stack[link] = Gambit_stack[0];
    Gambit_stack[0] = ra;

    Gambit_stack = [chain];
    Gambit_sp = 0;
  }

  return Gambit_underflow;
}

function Gambit_underflow() {

  var frame = Gambit_stack[0];

  if (frame == false) // end of continuation?
    return false; // terminate trampoline

  var ra = frame[0], fs = ra.fs, link = ra.link;
  Gambit_stack = frame.slice(0, fs + 1);
  Gambit_sp = fs;
  Gambit_stack[0] = frame[link];
  Gambit_stack[link] = Gambit_underflow;

  return ra;
}

var Gambit_glo;
var Gambit_stack;
var Gambit_sp = 0;
var " R0 " = Gambit_underflow;
var " R1 " = false;
var " R2 " = false;
var " R3 " = false;
var " R4 " = false;
var Gambit_nargs = 0;
var Gambit_temp1 = false;
var Gambit_temp2 = false;
var Gambit_pollcount = 1;

function Gambit_poll(dest) {
  Gambit_pollcount = 100;
//  Gambit_stack.length = Gambit_sp + 1;
  return dest;
}

function Gambit_printout(text) {
  if (text != \"\\n\")
    print(text);
}

function Gambit_wrong_nargs(fn) {
    Gambit_printout(\"*** wrong number of arguments (\"+Gambit_nargs+\") when calling\");
    Gambit_printout(fn);
    return false;
}

function closure_alloc(slots) {

  function self(msg) {
    if (msg == false) return slots;
    " R4 " = self;
    return slots.v0;
  }

  return self;
}

function Gambit_trampoline(pc) {
  while (pc != false) {
    pc = pc();
  }
}

"

)))

    (else
     (compiler-internal-error
      "runtime-system, unknown target"))))

(define (entry-point ctx main-proc)
  (let ((entry (gvm-proc-use ctx (proc-obj-name main-proc))))
    (^ "\n"
       (univ-comment ctx "--------------------------------\n")
       "\n"

       (case (target-name (ctx-target ctx))

         ((js php python ruby)
          (^expr-statement
           (^call-prim
            (^global-prim-function (^prefix "trampoline"))
            entry)))

         (else
          (compiler-internal-error
           "entry-point, unknown target"))))))

;;;----------------------------------------------------------------------------

(define (univ-emit-function-declaration ctx name params gen-header gen-attribs gen-body #!optional (prim? #f))
  (with-new-resources-used
   ctx
   (lambda (ctx)
     (let* ((header (gen-header ctx))
            (attribs (gen-attribs ctx))
            (body (gen-body ctx))
            (globals (resource-set->list (ctx-globals-used ctx))))

       (define (used? x)
         (or (resource-set-member? (ctx-resources-used-rd ctx) x)
             (resource-set-member? (ctx-resources-used-wr ctx) x)))

       (define (add! x)
         (set! globals (cons x globals)))

       (let loop ((num (- univ-nb-gvm-regs 1)))
         (if (>= num 0)
             (begin
               (if (used? num) (add! (gvm-state-reg ctx num)))
               (loop (- num 1)))))

       (if (used? 'sp)        (add! (gvm-state-sp ctx)))
       (if (used? 'stack)     (add! (gvm-state-stack ctx)))
       (if (used? 'glo)       (add! (gvm-state-glo ctx)))
       (if (used? 'nargs)     (add! (gvm-state-nargs ctx)))
       (if (used? 'pollcount) (add! (gvm-state-pollcount ctx)))

       (univ-emit-function-declaration*
        ctx
        name
        params
        header
        attribs
        globals
        body
        prim?)))))

(define (univ-emit-function-declaration* ctx name params header attribs globals body prim?)
  (case (target-name (ctx-target ctx))

    ((js)
     (^ "function " name "("
        (univ-separated-list
         ","
         (map car params))
        ") {" (univ-indent (^ header body)) "}\n"
        (map (lambda (attrib)
               (^expr-statement
                (^assign (^ name "." (car attrib))
                         (cdr attrib))))
             attribs)))

    ((php)
     (let ((decl
            (^ "function " (if prim? name "") "("
               (univ-separated-list
                ","
                (map (lambda (x)
                       (^ (car x) (if (cdr x) (^ "=" (^bool #f)) (^))))
                     params))
               ") {"
               (univ-indent
                (^ header
                   (map (lambda (attrib)
                          (^ "static "
                             (^expr-statement
                              (^assign (^local-var (car attrib))
                                       (cdr attrib)))))
                        attribs)

                   (if (null? globals)
                       (^)
                       (^ "global "
                          (univ-separated-list
                           ", "
                           globals)
                          ";\n"))
                   body))
               "}")))
       (if prim?
           (^ decl "\n")
           (^expr-statement (^assign name decl)))))


    ((python)
     (^ "def " name "("
        (univ-separated-list
         ","
         (map (lambda (x)
                (^ (car x) (if (cdr x) (^ "=" (^bool #f)) (^))))
              params))
        "):"
        (univ-indent
         (^ header
            (if (null? globals)
                (^)
                (^ "global "
                   (univ-separated-list
                    ", "
                    globals)
                   "\n"))
            body))
        (map (lambda (attrib)
               (^expr-statement
                (^assign (^ name "." (car attrib))
                         (cdr attrib))))
             attribs)))

    ((ruby)
     (let ((parameters
            (univ-separated-list
             ","
             (map (lambda (x)
                    (^ (car x) (if (cdr x) (^ "=" (^bool #f)) (^))))
                  params))))

       (^ (if prim?

              (^ "def " name "(" parameters ")"
                 (univ-indent (^ header body))
                 "end\n")

              (^expr-statement
               (^assign
                name
                (^ "lambda {"
                   (if (null? params)
                       (^)
                       (^ "|" parameters "|"))
                   (univ-indent (^ header body))
                   "}"))))

          (if (pair? attribs)
              (^ "class << " name "; attr_accessor :" (car (car attribs))
                 (map (lambda (attrib)
                        (^ ", :" (car attrib)))
                      (cdr attribs))
                 "; end\n"
                 (map (lambda (attrib)
                        (^expr-statement
                         (^assign (^ name "." (car attrib))
                                  (cdr attrib))))
                      attribs))
              (^)))))

    (else
     (compiler-internal-error
      "univ-emit-function-declaration*, unknown target"))))

(define (univ-emit-class-declaration ctx name fields methods)
  (case (target-name (ctx-target ctx))

    ((js)
     (^ "function " name "("
        (univ-separated-list
         ","
         (map car (keep (lambda (field) (not (cadr field))) fields)))
        ") {\n"
        (univ-indent
         (map (lambda (field)
                (let ((field-name (car field))
                      (field-init (cadr field)))
                  (^expr-statement
                   (^assign (^this-member field-name)
                            (or field-init (^local-var field-name))))))
              fields))
        "}\n"
        (map (lambda (method)
               (^ "\n"
                  name ".prototype." (car method) " = function ("
                  (univ-separated-list "," (cadr method))
                  ") {\n"
                  (univ-indent (caddr method))
                  "}\n"))
             methods)
        "\n"))

    ((php)
     (^ "class " name " {\n\n"
        (if (pair? fields)
            (^ (univ-indent
                (map (lambda (field) (^ "public $" (car field) ";\n")) fields))
               "\n")
            (^))
        (univ-indent
         (^ "public function __construct("
            (univ-separated-list
             ","
             (map (lambda (x) (^local-var x)) (map car (keep (lambda (field) (not (cadr field))) fields))))
            ") {\n"
            (univ-indent
             (map (lambda (field)
                    (let ((field-name (car field))
                          (field-init (cadr field)))
                      (^expr-statement
                       (^assign (^this-member field-name)
                                (or field-init (^local-var field-name))))))
                  fields))
            "}\n"))
        (map (lambda (method)
               (^ "\n"
                  (univ-indent
                   (^ "public function " (car method) "("
                      (univ-separated-list "," (map (lambda (x) (^local-var x)) (cadr method)))
                      ") {\n"
                      (univ-indent (caddr method))
                      "}\n"))))
             methods)
        "}\n\n"))

    ((python)
     (^ "class " name ":\n\n"
        (univ-indent
         (^ "def __init__("
            (univ-separated-list
             ","
             (cons (^this)
                   (map car (keep (lambda (field) (not (cadr field))) fields))))
            "):\n"
            (univ-indent
             (map (lambda (field)
                    (let ((field-name (car field))
                          (field-init (cadr field)))
                      (^expr-statement
                       (^assign (^this-member field-name)
                                (or field-init (^local-var field-name))))))
                  fields))))
        "\n"
        (map (lambda (method)
               (^ "\n"
                  (univ-indent
                   (^ "def " (car method) "("
                      (univ-separated-list "," (cons 'self (cadr method)))
                      "):\n"
                      (univ-indent (caddr method))))))
             methods)
        "\n"))

    ((ruby)
     (^ "class " name "\n\n"
        (if (pair? fields)
            (^ (univ-indent
                (^ "attr_accessor "
                   (univ-separated-list
                    ","
                    (map (lambda (field) (^ ":" (car field))) fields))
                   "\n"))
               "\n")
            (^))
        (univ-indent
         (^ "def initialize("
            (univ-separated-list
             ","
             (map car (keep (lambda (field) (not (cadr field))) fields)))
            ")\n"
            (univ-indent
             (map (lambda (field)
                    (let ((field-name (car field))
                          (field-init (cadr field)))
                      (^expr-statement
                       (^assign (^this-member field-name)
                                (or field-init (^local-var field-name))))))
                  fields))
            "end\n"))
        (map (lambda (method)
               (^ "\n"
                  (univ-indent
                   (^ "def " (car method) "(" ;; TODO: no parameter list when no parameters
                      (univ-separated-list "," (cadr method))
                      ")\n"
                      (univ-indent (caddr method))
                      "end\n"))))
             methods)
        "\nend\n\n"))

    (else
     (compiler-internal-error
      "univ-emit-class-declaration, unknown target"))))

(define (univ-comment ctx comment)
  (case (target-name (ctx-target ctx))

    ((js php)
     (^ "// " comment))

    ((python ruby)
     (^ "# " comment))

    (else
     (compiler-internal-error
      "univ-comment, unknown target"))))

(define (univ-emit-return-call-prim ctx expr . params)
  (univ-emit-return ctx (apply univ-emit-call-prim (cons ctx (cons expr params)))))

(define (univ-emit-return-call ctx expr . params)
  (univ-emit-return ctx (apply univ-emit-call (cons ctx (cons expr params)))))

(define (univ-emit-return ctx expr)
  (case (target-name (ctx-target ctx))

    ((js php)
     (^ "return " expr ";\n"))

    ((python ruby)
     (^ "return " expr "\n"))

    (else
     (compiler-internal-error
      "univ-emit-return, unknown target"))))

(define (univ-emit-null ctx)
  (case (target-name (ctx-target ctx))

    ((js)
     (^ "null"))

    ((python)
     (^ "None"))

    ((ruby)
     (^ "nil"))

    ((php)
     (^ "NULL"))

    (else
     (compiler-internal-error
      "univ-emit-null, unknown target"))))

(define (univ-emit-null-box ctx expr)
  (case (univ-null-representation ctx)

    ((class)
     (^new (^prefix "Null") expr))

    (else
     expr)))

(define (univ-emit-null-unbox ctx expr)
  (case (univ-null-representation ctx)

    ((class)
     (^member expr "val"))

    (else
     expr)))

(define (univ-emit-bool ctx val)
  (case (target-name (ctx-target ctx))

    ((js ruby php)
     (^ (if val "true" "false")))

    ((python)
     (^ (if val "True" "False")))

    (else
     (compiler-internal-error
      "univ-emit-bool, unknown target"))))

(define (univ-emit-boolean-box ctx expr)
  (case (univ-boolean-representation ctx)

    ((class)
     (^new (^prefix "Boolean") expr))

    (else
     expr)))

(define (univ-emit-boolean-unbox ctx expr)
  (case (univ-boolean-representation ctx)

    ((class)
     (^member expr "val"))

    (else
     expr)))

(define (univ-emit-boolean? ctx expr)
  (case (univ-boolean-representation ctx)

    ((class)
     (^instanceof (^prefix "Boolean") expr))

    (else
     (case (target-name (ctx-target ctx))

       ((js)
        (^typeof "boolean" expr))

       ((php)
        (^call-prim "is_bool" expr))

       ((python)
        (^instanceof "bool" expr))

       ((ruby)
        (^or (^instanceof "FalseClass" expr)
             (^instanceof "TrueClass" expr)))

       (else
        (compiler-internal-error
         "univ-emit-boolean?, unknown target"))))))

(define (univ-emit-chr ctx val)
  (^ (char->integer val)))

(define (univ-emit-char-box ctx expr)
  (case (univ-char-representation ctx)

    ((class)
     (^new (^prefix "Char") expr))

    (else
     expr)))

(define (univ-emit-char-unbox ctx expr)
  (case (univ-char-representation ctx)

    ((class)
     (^member expr "code"))

    (else
     expr)))

(define (univ-emit-chr-fromint ctx expr)
  (case (target-name (ctx-target ctx))

    ((js php python ruby)
     expr)

    (else
     (compiler-internal-error
      "univ-emit-chr-fromint, unknown target"))))

(define (univ-emit-chr-toint ctx expr)
  (case (target-name (ctx-target ctx))

    ((js php python ruby)
     expr)

    (else
     (compiler-internal-error
      "univ-emit-chr-toint, unknown target"))))

(define (univ-emit-chr-tostr ctx expr)
  (case (target-name (ctx-target ctx))

    ((js)
     (^call-prim (^member "String" "fromCharCode") expr))

    ((php)
     (^call-prim "chr" expr))

    ((python)
     (^call-prim "unichr" expr))

    ((ruby)
     (^ expr ".chr"))

    (else
     (compiler-internal-error
      "univ-emit-chr-tostr, unknown target"))))

(define (univ-emit-char? ctx expr)
  (case (univ-char-representation ctx)

    ((class)
     (^instanceof (^prefix "Char") expr))

    (else
     (case (target-name (ctx-target ctx))
       (else
        (compiler-internal-error
         "univ-emit-char?, unknown target"))))))

(define (univ-emit-int ctx val)
  (^ val))

(define (univ-emit-fixnum-box ctx expr)
  (case (univ-fixnum-representation ctx)

    ((class)
     (^new (^prefix "Fixnum") expr))

    (else
     expr)))

(define (univ-emit-fixnum-unbox ctx expr)
  (case (univ-fixnum-representation ctx)

    ((class)
     (^member expr "val"))

    (else
     expr)))

(define (univ-emit-fixnum? ctx expr)
  (case (univ-fixnum-representation ctx)

    ((class)
     (^instanceof (^prefix "Fixnum") expr))

    (else
     (case (target-name (ctx-target ctx))

       ((js)
        (^typeof "number" expr))

       ((php)
        (^call-prim "is_int" expr))

       ((python)
        (^and (^instanceof "int" expr)
              (^not (^instanceof "bool" expr))))

       ((ruby)
        (^instanceof "Fixnum" expr))

       (else
        (compiler-internal-error
         "univ-emit-fixnum?, unknown target"))))))

(define (univ-emit-dict ctx alist)

  (define (dict alist sep open close)
    (^ open
       (univ-separated-list
        ","
        (map (lambda (x) (^ (^str (car x)) sep (cdr x))) alist))
       close))

  (case (target-name (ctx-target ctx))

    ((js python)
     (dict alist ":" "{" "}"))

    ((php)
     (dict alist "=>" "array(" ")"))

    ((ruby)
     (dict alist "=>" "{" "}"))

    (else
     (compiler-internal-error
      "univ-emit-dict, unknown target"))))

(define (univ-emit-member ctx expr name)
  (case (target-name (ctx-target ctx))

    ((js python ruby)
     (^ expr "." name))

    ((php)
     (^ expr "->" name))

    (else
     (compiler-internal-error
      "univ-emit-member, unknown target"))))

(define (univ-emit-pair? ctx expr)
  (^instanceof (^prefix "Pair") expr))

(define (univ-emit-cons ctx expr1 expr2)
  (^new (^prefix "Pair") expr1 expr2))

(define (univ-emit-getcar ctx expr)
  (^member expr "car"))

(define (univ-emit-getcdr ctx expr)
  (^member expr "cdr"))

(define (univ-emit-setcar ctx expr1 expr2)
  (^expr-statement
   (^assign (^member expr1 "car") expr2)))

(define (univ-emit-setcdr ctx expr1 expr2)
  (^expr-statement
   (^assign (^member expr1 "cdr") expr2)))

(define (univ-emit-float ctx val)
  ;; TODO: generate correct syntax
  (^
   (let ((str (number->string val)))
     (cond ((and (string=? str "-0.")
                 (eq? (target-name (ctx-target ctx)) 'php))
            ;; it is strange that in PHP -0.0 is the same as 0.0
            "0.0*-1")
           ((char=? (string-ref str 0) #\.)
            (string-append "0" str))
           ((and (char=? (string-ref str 0) #\-)
                 (char=? (string-ref str 1) #\.))
            (string-append "-0" (substring str 1 (string-length str))))
           ((char=? (string-ref str (- (string-length str) 1)) #\.)
            (string-append str "0"))
           (else
            str)))))

(define (univ-emit-float-fromint ctx expr)
  (case (target-name (ctx-target ctx))

    ((js)
     expr)

    ((php)
     (^ "(float)(" expr ")"))

    ((python)
     (^ "float(" expr ")"))

    ((ruby)
     (^ expr ".to_f"))

    (else
     (compiler-internal-error
      "univ-emit-float-fromint, unknown target"))))

(define (univ-emit-float-toint ctx expr)
  (case (target-name (ctx-target ctx))

    ((js)
     (^float-truncate expr))

    ((php)
     (^ "(int)(" expr ")"))

    ((python)
     (^ "int(" expr ")"))

    ((ruby)
     (^ expr ".to_i"))

    (else
     (compiler-internal-error
      "univ-emit-float-fromint, unknown target"))))

(define (univ-emit-float-abs ctx expr)
  (case (target-name (ctx-target ctx))

    ((js)
     (^ "Math.abs(" expr ")"))

    ((php)
     (^ "abs(" expr ")"))

    ((python)
     (^ "math.fabs(" expr ")"))

    ((ruby)
     (^ expr ".abs"))

    (else
     (compiler-internal-error
      "univ-emit-float-abs, unknown target"))))

(define (univ-emit-float-floor ctx expr)
  (case (target-name (ctx-target ctx))

    ((js)
     (^ "Math.floor(" expr ")"))

    ((php)
     (^ "floor(" expr ")"))

    ((python)
     (^ "math.floor(" expr ")"))

    ((ruby)
     (^ expr ".floor"))

    (else
     (compiler-internal-error
      "univ-emit-float-floor, unknown target"))))

(define (univ-emit-float-ceiling ctx expr)
  (case (target-name (ctx-target ctx))

    ((js)
     (^ "Math.ceil(" expr ")"))

    ((php)
     (^ "ceil(" expr ")"))

    ((python)
     (^ "math.ceil(" expr ")"))

    ((ruby)
     (^ expr ".ceil"))

    (else
     (compiler-internal-error
      "univ-emit-float-ceiling, unknown target"))))

(define (univ-emit-float-truncate ctx expr)
  (case (target-name (ctx-target ctx))

    ((js php)
     (^if-expr (^< expr (^float targ-inexact-+0))
               (^float-ceiling expr)
               (^float-floor expr)))

    ((python)
     (^ "int(" expr ")"))

    ((ruby)
     (^ expr ".truncate"))

    (else
     (compiler-internal-error
      "univ-emit-float-truncate, unknown target"))))

(define (univ-emit-float-round-half-up ctx expr)
  (case (target-name (ctx-target ctx))

    ((js)
     (^ "Math.round(" expr ")"))

    (else
     (compiler-internal-error
      "univ-emit-float-round-half-up, unknown target"))))

(define (univ-emit-float-round-half-towards-0 ctx expr)
  (case (target-name (ctx-target ctx))

    ((php)
     (^ "round(" expr ")"))

    ((python)
     (^ "round(" expr ")"))

    ((ruby)
     (^ expr ".round"))

    (else
     (compiler-internal-error
      "univ-emit-float-round-half-towards-0, unknown target"))))

(define (univ-emit-float-round-half-to-even ctx expr)
  (case (target-name (ctx-target ctx))

    ((js)
     (^- (^float-round-half-up expr)
         (^parens
          (^if-expr (^&& (^!= (^float-mod expr (^float targ-inexact-+2))
                              (^float targ-inexact-+1/2))
                         (^!= (^float-mod expr (^float targ-inexact-+2))
                              (^float -1.5)));;;;;;;;;;;;;;;;
                    (^float targ-inexact-+0)
                    (^float targ-inexact-+1)))))

    ((php python ruby)
     (^+ (^float-round-half-towards-0 expr)
         (^- (^parens
              (^if-expr (^= (^float-mod expr (^float targ-inexact-+2))
                            (^float (- targ-inexact-+1/2)));;;;;;;;;;;;;;;;;
                        (^float targ-inexact-+1)
                        (^float targ-inexact-+0)))
             (^parens
              (^if-expr (^= (^float-mod expr (^float targ-inexact-+2))
                            (^float targ-inexact-+1/2))
                        (^float targ-inexact-+1)
                        (^float targ-inexact-+0))))))

    (else
     (compiler-internal-error
      "univ-emit-float-round-half-to-even, unknown target"))))

#|
JS:
for (var i=-8; i<=8; i++) print(i*0.5," ",(i*0.5)%2," ",Math.round(i*0.5));
-4    0   -4
-3.5 -1.5 -3 -1
-3   -1   -3
-2.5 -0.5 -2
-2    0   -2
-1.5 -1.5 -1 -1
-1   -1   -1
-0.5 -0.5  0
0     0    0
0.5   0.5  1 -1
1     1    1
1.5   1.5  2
2     0    2
2.5   0.5  3 -1
3     1    3
3.5   1.5  4
4     0    4

PHP:
i*0.5, fmod(i*0.5,2), round(i*0.5)
-4    0   -4
-3.5 -1.5 -4
-3   -1   -3
-2.5 -0.5 -3 +1
-2    0   -2
-1.5 -1.5 -2
-1   -1   -1
-0.5 -0.5 -1 +1
0     0    0
0.5   0.5  1 -1
1     1    1
1.5   1.5  2
2     0    2
2.5   0.5  3 -1
3     1    3
3.5   1.5  4
4     0    4

Python:
for i in range(-8,8):
  print '%f %f %f' % ((i*0.5),math.fmod(i*0.5,2),round(i*0.5))
-4    0   -4
-3.5 -1.5 -4
-3   -1   -3
-2.5 -0.5 -3 +1
-2    0   -2
-1.5 -1.5 -2
-1   -1   -1
-0.5 -0.5 -1 +1
0     0    0
0.5   0.5  1 -1
1     1    1
1.5   1.5  2
2     0    2
2.5   0.5  3 -1
3     1    3
3.5   1.5  4
4     0    4

Ruby:
(-8..8).each {|i| puts (i*0.5),(i*0.5).remainder(2),(i*0.5).round}
-4.0 -0.0 -4
-3.5 -1.5 -4
-3.0 -1.0 -3
-2.5 -0.5 -3 +1
-2.0 -0.0 -2
-1.5 -1.5 -2
-1.0 -1.0 -1
-0.5 -0.5 -1 +1
 0.0  0.0  0
 0.5  0.5  1 -1
 1.0  1.0  1
 1.5  1.5  2
 2.0  0.0  2
 2.5  0.5  3 -1
 3.0  1.0  3
 3.5  1.5  4
 4.0  0.0  4
|#

(define (univ-emit-float-mod ctx expr1 expr2)
  (case (target-name (ctx-target ctx))

    ((js)
     (^ expr1 " % " expr2))

    ((php)
     (^ "fmod(" expr1 "," expr2 ")"))

    ((python)
     (^ "math.fmod(" expr1 "," expr2 ")"))

    ((ruby)
     (^ expr1 ".remainder(" expr2 ")"))

    (else
     (compiler-internal-error
      "univ-emit-float-fmod, unknown target"))))

(define (univ-emit-float-exp ctx expr)
  (case (target-name (ctx-target ctx))

    ((js ruby)
     (^ "Math.exp(" expr ")"))

    ((php)
     (^ "exp(" expr ")"))

    ((python)
     (^ "math.exp(" expr ")"))

    (else
     (compiler-internal-error
      "univ-emit-float-exp, unknown target"))))

(define (univ-emit-float-log ctx expr)
  (case (target-name (ctx-target ctx))

    ((js ruby)
     (^ "Math.log(" expr ")"))

    ((php)
     (^ "log(" expr ")"))

    ((python)
     (^ "math.log(" expr ")"))

    (else
     (compiler-internal-error
      "univ-emit-float-log, unknown target"))))

(define (univ-emit-float-sin ctx expr)
  (case (target-name (ctx-target ctx))

    ((js ruby)
     (^ "Math.sin(" expr ")"))

    ((php)
     (^ "sin(" expr ")"))

    ((python)
     (^ "math.sin(" expr ")"))

    (else
     (compiler-internal-error
      "univ-emit-float-sin, unknown target"))))

(define (univ-emit-float-cos ctx expr)
  (case (target-name (ctx-target ctx))

    ((js ruby)
     (^ "Math.cos(" expr ")"))

    ((php)
     (^ "cos(" expr ")"))

    ((python)
     (^ "math.cos(" expr ")"))

    (else
     (compiler-internal-error
      "univ-emit-float-cos, unknown target"))))

(define (univ-emit-float-tan ctx expr)
  (case (target-name (ctx-target ctx))

    ((js ruby)
     (^ "Math.tan(" expr ")"))

    ((php)
     (^ "tan(" expr ")"))

    ((python)
     (^ "math.tan(" expr ")"))

    (else
     (compiler-internal-error
      "univ-emit-float-tan, unknown target"))))

(define (univ-emit-float-asin ctx expr)
  (case (target-name (ctx-target ctx))

    ((js ruby)
     (^ "Math.asin(" expr ")"))

    ((php)
     (^ "asin(" expr ")"))

    ((python)
     (^ "math.asin(" expr ")"))

    (else
     (compiler-internal-error
      "univ-emit-float-asin, unknown target"))))

(define (univ-emit-float-acos ctx expr)
  (case (target-name (ctx-target ctx))

    ((js ruby)
     (^ "Math.acos(" expr ")"))

    ((php)
     (^ "acos(" expr ")"))

    ((python)
     (^ "math.acos(" expr ")"))

    (else
     (compiler-internal-error
      "univ-emit-float-acos, unknown target"))))

(define (univ-emit-float-atan ctx expr)
  (case (target-name (ctx-target ctx))

    ((js ruby)
     (^ "Math.atan(" expr ")"))

    ((php)
     (^ "atan(" expr ")"))

    ((python)
     (^ "math.atan(" expr ")"))

    (else
     (compiler-internal-error
      "univ-emit-float-atan, unknown target"))))

(define (univ-emit-float-expt ctx expr1 expr2)
  (case (target-name (ctx-target ctx))

    ((js)
     (^ "Math.pow(" expr1 "," expr2 ")"))

    ((php)
     (^ "pow(" expr1 "," expr2 ")"))

    ((python)
     (^ "math.pow(" expr1 "," expr2 ")"))

    ((ruby)
     (^ expr1 " ** " expr2))

    (else
     (compiler-internal-error
      "univ-emit-float-expt, unknown target"))))

(define (univ-emit-float-sqrt ctx expr)
  (case (target-name (ctx-target ctx))

    ((js ruby)
     (^ "Math.sqrt(" expr ")"))

    ((php)
     (^ "sqrt(" expr ")"))

    ((python)
     (^ "math.sqrt(" expr ")"))

    (else
     (compiler-internal-error
      "univ-emit-float-sqrt, unknown target"))))

#;
(
;; PHP Math functions
abs
acos
acosh
asin
asinh
atan2
atan
atanh
base_ convert
bindec
ceil
cos
cosh
decbin
dechex
decoct
deg2rad
exp
expm1
floor
fmod
getrandmax
hexdec
hypot
is_ finite
is_ infinite
is_ nan
lcg_ value
log10
log1p
log
max
min
mt_ getrandmax
mt_ rand
mt_ srand
octdec
pi
pow
rad2deg
rand
round
sin
sinh
sqrt
srand
tan
tanh
)

(define (univ-emit-float-integer? ctx expr)
  (^&& (^not (^parens (^float-infinite? expr)))
       (^= expr (^float-floor expr))))

(define (univ-emit-float-finite? ctx expr)
  (case (target-name (ctx-target ctx))

    ((php)
     (^call-prim "is_finite" expr))

    (else
     ;;TODO: move constants elsewhere
     (^&& (^>= expr (^float -1.7976931348623151e308))
          (^<= expr (^float 1.7976931348623151e308))))))

(define (univ-emit-float-infinite? ctx expr)
  (case (target-name (ctx-target ctx))

    ((php)
     (^call-prim "is_infinite" expr))

    (else
     ;;TODO: move constants elsewhere
     (^or (^< expr (^float -1.7976931348623151e308))
          (^> expr (^float 1.7976931348623151e308))))))

(define (univ-emit-float-nan? ctx expr)
  (case (target-name (ctx-target ctx))

    ((php)
     (^call-prim "is_nan" expr))

    (else
     (^!= expr expr))))

(define (univ-emit-flonum-box ctx expr)
  (case (univ-flonum-representation ctx)

    ((class)
     (^new (^prefix "Flonum") expr))

    (else
     expr)))

(define (univ-emit-flonum-unbox ctx expr)
  (case (univ-flonum-representation ctx)

    ((class)
     (^member expr "val"))

    (else
     expr)))

(define (univ-emit-flonum? ctx expr)
  (case (univ-flonum-representation ctx)

    ((class)
     (^instanceof (^prefix "Flonum") expr))

    (else
     (case (target-name (ctx-target ctx))

       ((js)
        (^typeof "number" expr))

       ((php)
        (^ "is_float(" expr ")"))

       ((python)
        (^ "isinstance(" expr ", float)"))

       ((ruby)
        (^ expr ".class == Float"))

       (else
        (compiler-internal-error
         "univ-emit-flonum?, unknown target"))))))

(define (univ-emit-vector-box ctx expr)
  (case (univ-vector-representation ctx)

    ((class)
     (^new (^prefix "Vector") expr))

    (else
     expr)))

(define (univ-emit-vector-unbox ctx expr)
  (case (univ-vector-representation ctx)

    ((class)
     (^member expr "elems"))

    (else
     expr)))

(define (univ-emit-vector? ctx expr)
  (case (univ-vector-representation ctx)

    ((class)
     (^instanceof (^prefix "Vector") expr))

    (else
     (case (target-name (ctx-target ctx))

       ((js ruby)
        (^instanceof "Array" expr))

       ((php)
        (^call-prim "is_array" expr))

       ((python)
        (^instanceof "list" expr))

       (else
        (compiler-internal-error
         "univ-emit-vector?, unknown target"))))))

(define (univ-emit-vector-length ctx expr)
  (^array-length (^vector-unbox expr)))

(define (univ-emit-vector-shrink! ctx expr1 expr2)
  (^expr-statement
   (^array-shrink! (^vector-unbox expr1) expr2)))

(define (univ-emit-vector-ref ctx expr1 expr2)
  (^array-index (^vector-unbox expr1) expr2))

(define (univ-emit-vector-set! ctx expr1 expr2 expr3)
  (^expr-statement
   (^assign (^array-index (^vector-unbox expr1) expr2) expr3)))

(define (univ-emit-str ctx val)
  ;; TODO: generate correct escapes for the target language
  (^ "'" val "'"))

(define (univ-emit-string-box ctx expr)
  (case (univ-string-representation ctx)

    ((class)
     (^new (^prefix "String") expr))

    (else
     expr)))

(define (univ-emit-string-unbox ctx expr)
  (case (univ-string-representation ctx)

    ((class)
     (^member expr "codes"))

    (else
     expr)))

(define (univ-emit-string? ctx expr)
  (case (univ-string-representation ctx)

    ((class)
     (^instanceof (^prefix "String") expr))

    (else
     (case (target-name (ctx-target ctx))

       ((js)
        (^typeof "string" expr))

       ((php)
        (^call-prim "is_string" expr))

       ((python)
        (^instanceof "str" expr))

       ((ruby)
        (^instanceof "String" expr))

       (else
        (compiler-internal-error
         "univ-emit-string?, unknown target"))))))

(define (univ-emit-string-length ctx expr)
  (case (univ-string-representation ctx)

    ((class)
     (^array-length (^string-unbox expr)))

    (else
     (compiler-internal-error
      "univ-emit-string-length, unknown target"))))

(define (univ-emit-string-shrink! ctx expr1 expr2)
  (case (univ-string-representation ctx)

    ((class)
     (^expr-statement
      (^array-shrink! (^string-unbox expr1) (^fixnum-unbox expr2))))

    (else
     (compiler-internal-error
      "univ-emit-string-shrink!, unknown target"))))

(define (univ-emit-string-ref ctx expr1 expr2)
  (case (univ-string-representation ctx)

    ((class)
     (^array-index expr1 expr2))

    (else
     (case (target-name (ctx-target ctx))

       ((js)
        (^call-prim (^member expr1 "charCodeAt") expr2))

       ((php)
        (^call-prim "uniord" (^call-prim "substr" expr1 expr2 (^int 1))))

       ((python)
        (^call-prim "ord" (^ expr1 "[" expr2 "]")))

       ((ruby)
        (^ expr1 "[" expr2 "]" ".ord"))

       (else
        (compiler-internal-error
         "univ-emit-string-ref, unknown target"))))))

(define (univ-emit-string-set! ctx expr1 expr2 expr3)
  (case (univ-string-representation ctx)

    ((class)
     (^expr-statement
      (^assign (^array-index expr1 expr2) expr3)))

    (else
     ;; mutable strings do not exist in js, php, python and ruby
     (compiler-internal-error
      "univ-emit-string-set!, unknown target"))))

(define (univ-emit-sym ctx val)
  ;; TODO: generate correct escapes for the target language
  (^ "'" val "'"))

(define (univ-emit-symbol-box ctx expr)
  (case (univ-symbol-representation ctx)

    ((class)
     (^new (^prefix "Symbol") expr))

    (else
     expr)))

(define (univ-emit-symbol-unbox ctx expr)
  (case (univ-symbol-representation ctx)

    ((class)
     (^member expr "str"))

    (else
     expr)))

(define (univ-emit-symbol? ctx expr)
  (case (univ-symbol-representation ctx)

    ((class)
     (^instanceof (^prefix "Symbol") expr))

    (else
     (case (target-name (ctx-target ctx))

       ((js)
        (^typeof "string" expr))

       ((php)
        (^call-prim "is_string" expr))

       ((python)
        (^instanceof "str" expr))

       ((ruby)
        (^instanceof "Symbol" expr))

       (else
        (compiler-internal-error
         "univ-emit-symbol?, unknown target"))))))

(define (univ-emit-symtostr ctx expr)
  (^call-prim
   (^global-prim-function (^prefix "strtocodes"))
   expr))

(define (univ-emit-box? ctx expr)
  (^instanceof (^prefix "Box") expr))

(define (univ-emit-box ctx expr)
  (^new (^prefix "Box") expr))

(define (univ-emit-unbox ctx expr)
  (^member expr "val"))

(define (univ-emit-setbox ctx expr1 expr2)
  (^expr-statement
   (^assign (^member expr1 "val") expr2)))

(define (univ-emit-procedure? ctx expr)
  (case (target-name (ctx-target ctx))

    ((js)
     (^typeof "function" expr))

    ((python)
     (^ "hasattr(" expr ", '__call__')"))

    (else
     (compiler-internal-error
      "univ-emit-procedure?, unknown target"))))

(define (univ-emit-call-prim ctx name . params)
  (univ-emit-apply ctx name params))

(define (univ-emit-call ctx name . params)
  (case (target-name (ctx-target ctx))

    ((js python php)
     (univ-emit-apply-aux ctx name params "(" ")"))

    ((ruby)
     (univ-emit-apply-aux ctx name params "[" "]"))

    (else
     (compiler-internal-error
      "univ-emit-call, unknown target"))))

(define (univ-emit-apply ctx name params)
  (univ-emit-apply-aux ctx name params "(" ")"))

(define (univ-emit-apply-aux ctx name params open close)
  (^ name
     open
     (univ-separated-list "," params)
     close))

(define (univ-emit-this ctx)
  (case (target-name (ctx-target ctx))

    ((js php)
     (^ "this"))

    ((python)
     (^ "self"))

    (else
     (compiler-internal-error
      "univ-emit-this, unknown target"))))

(define (univ-emit-this-member ctx name)
  (case (target-name (ctx-target ctx))

    ((js php python)
     (^member (^local-var (^this)) name))

    ((ruby)
     (^ "@" name))

    (else
     (compiler-internal-error
      "univ-emit-this-member, unknown target"))))

(define (univ-emit-new ctx class . params)
  (case (target-name (ctx-target ctx))

    ((js php)
     (^ "new " (^apply class params)))

    ((python)
     (^apply class params))

    ((ruby)
     (^apply (^ class ".new") params))

    (else
     (compiler-internal-error
      "univ-emit-new, unknown target"))))

(define (univ-emit-typeof ctx type expr)
  (case (target-name (ctx-target ctx))

    ((js)
     (^eq? (^ "typeof " expr) (^str type)))

    (else
     (compiler-internal-error
      "unit-emit-typeof, unknown target"))))

(define (univ-emit-instanceof ctx class expr)
  (case (target-name (ctx-target ctx))

    ((js php)
     (^ expr " instanceof " class))

    ((python)
     (^call-prim "isinstance" expr class))

    ((ruby)
     (^ expr ".class == " class))

    (else
     (compiler-internal-error
      "unit-emit-instanceof, unknown target"))))

(define (univ-emit-return-poll ctx expr poll? call?)
  (if poll?

      (^inc-by (begin
                 (gvm-state-pollcount-use ctx 'rd)
                 (gvm-state-pollcount-use ctx 'wr))
               -1
               (lambda (inc)
                 (^if (^= inc 0)
                      (univ-emit-return-call-prim
                       ctx
                       (^global-prim-function (^prefix "poll"))
                       expr)
                      (if call?
                          (univ-emit-return-call ctx expr)
                          (univ-emit-return ctx expr)))))

      (if call?
          (univ-emit-return-call ctx expr)
          (univ-emit-return ctx expr))))

(define (univ-throw ctx expr)
  (case (target-name (ctx-target ctx))

    ((js php)
     (^ "throw " expr ";\n"))

    ((python ruby)
     (^ "raise " expr "\n"))

    (else
     (compiler-internal-error
      "univ-throw, unknown target"))))

(define (univ-fxquotient ctx expr1 expr2)
  (case (target-name (ctx-target ctx))

    ((js)
     (^ (^parens (^ expr1 " / " expr2)) " | 0"))

    ((php)
     (^ "(int)(" expr1 " / " expr2 ")"))

    ((python)
     (^call-prim "int" (^/ (^call-prim "float" expr1)
                           (^call-prim "float" expr2))))

    ((ruby)
     (^ (^parens (^ (^ expr1 ".to_f") "/" (^ expr2 ".to_f"))) ".to_int"))

    (else
     (compiler-internal-error
      "univ-fxquotient, unknown target"))))

(define (univ-fxmodulo ctx expr1 expr2)
  (case (target-name (ctx-target ctx))

    ((js php)
     (^ (^parens (^ (^parens (^ expr1 " % " expr2)) " + " expr2)) " % " expr2))

    ((python ruby)
     (^ expr1 " % " expr2))

    (else
     (compiler-internal-error
      "univ-fxmodulo, unknown target"))))

(define (univ-fxremainder ctx expr1 expr2)
  (case (target-name (ctx-target ctx))

    ((js php)
     (^ expr1 " % " expr2))

    ((python)
     (^- expr1
         (^* (^call-prim "int" (^/ (^call-prim "float" expr1)
                                   (^call-prim "float" expr2)))
             expr2)))

    ((ruby)
     (^ expr1 ".remainder(" expr2 ")"))

    (else
     (compiler-internal-error
      "univ-fxremainder, unknown target"))))

(define (univ-define-prim
         name
         proc-safe?
         apply-gen
         #!optional
         (ifjump-gen #f)
         (jump-gen #f))
  (let ((prim (univ-prim-info* (string->canonical-symbol name))))

    (if apply-gen
        (begin

          (proc-obj-inlinable?-set!
           prim
           (lambda (env)
             (or proc-safe?
                 (not (safe? env)))))

          (proc-obj-inline-set! prim apply-gen)))

    (if ifjump-gen
        (begin

          (proc-obj-testable?-set!
           prim
           (lambda (env)
             (or proc-safe?
                 (not (safe? env)))))

          (proc-obj-test-set! prim ifjump-gen)))

    (if jump-gen
        (begin

          (proc-obj-jump-inlinable?-set!
           prim
           (lambda (env)
             #t))

          (proc-obj-jump-inline-set!
           prim
           jump-gen)))))

(define (univ-define-prim-bool name proc-safe? ifjump-gen)
  (univ-define-prim
   name
   proc-safe?
   (lambda (ctx return . opnds)
     (apply ifjump-gen
            (cons ctx
                  (cons (lambda (result) (return (^boolean-box result)))
                        opnds))))
   ifjump-gen))

;;TODO: remove
#;
(define (univ-string ctx obj)

  (case (target-name (ctx-target ctx))

    ((js)
     (^ (^prefix "String.jsstringToString")
        "("
        (object->string obj)
        ")"))

    ;; ((js)
    ;;  (^ "new "
    ;;     (univ-emit-apply ctx
    ;;                      (^prefix "String")
    ;;                      (map (lambda (ch) (univ-char ctx ch))
    ;;                           (string->list obj)))))

    ((python)
     (^ (^prefix "String")
        "(*list(unicode("
        (object->string obj)
        ")))"))

    ((ruby php)                         ;TODO: complete
     (^ (object->string obj)))

    (else
     (compiler-internal-error
      "univ-string, unknown target"))))

;;;TODO: remove
#;
(define (univ-symbol ctx obj)

  (case (target-name (ctx-target ctx))

    ((js)
     (^ (^prefix "Symbol.stringToSymbol")
        "("
        (univ-string ctx (symbol->string obj))
        ")"))

    ((python ruby php)                         ;TODO: complete
     (^ (object->string obj)))

    (else
     (compiler-internal-error
      "univ-symbol, unknown target"))))

(define (undefined? obj)
  (eq? obj 'undefined))

(define (univ-undefined ctx)

  (case (target-name (ctx-target ctx))

    ((js)
     (^ "undefined"))

    ((python)
     (^ "None"))

    ((ruby)
     (^ "nil"))

    ((php)                                ;TODO: complete
     (^))

    (else
     (compiler-internal-error
      "univ-undefined, unknown target"))))


;; (define (univ-list ctx obj)             ;obj is a non-null list

;;   (define (make-list n elt)
;;     (vector->list (make-vector n elt)))

;;   (define (zip lst1 lst2)
;;     (define (zip-aux lst1 lst2 lst)
;;       (cond ((null? lst1)
;;              (append lst lst2))
;;             ((null? lst2)
;;              (append lst lst1))
;;             (else
;;              (cons (car lst1)
;;                    (cons (car lst2)
;;                          (zip-aux (cdr lst1) (cdr lst2) lst))))))

;;     (zip-aux lst1 lst2 '()))

;;   (case (target-name (ctx-target ctx))

;;     ((js python)
;;      (let ((tobj (map (lambda (o) (univ-emit-obj ctx o))
;;                       obj))
;;            (sep (make-list (- (length obj) 1) ", ")))
;;        (^ (^prefix "List(")
;;           (zip tobj sep)
;;           ")")))

;;     ((python ruby php)                         ;TODO: complete
;;      (^ (object->string obj)))

;;     (else
;;      (compiler-internal-error
;;       "univ-list, unknown target"))))



;; =============================================================================

;;; Primitive procedures

;; TODO move elsewhere
(define (univ-fold-left
         op0
         op1
         op2
         #!optional
         (unbox (lambda (ctx x) x))
         (box (lambda (ctx x) x)))
  (make-translated-operand-generator
   (lambda (ctx return . args)
     (return
      (cond ((null? args)
             (box ctx (op0 ctx)))
            ((null? (cdr args))
             (box ctx (op1 ctx (unbox ctx (car args)))))
            (else
             (let loop ((lst (cddr args))
                        (res (op2 ctx
                                  (unbox ctx (car args))
                                  (unbox ctx (cadr args)))))
               (if (null? lst)
                   (box ctx res)
                   (loop (cdr lst)
                         (op2 ctx
                              (^parens res)
                              (unbox ctx (car lst))))))))))))

(define (univ-fold-left-compare
         op0
         op1
         op2
         #!optional
         (unbox (lambda (ctx x) x))
         (box (lambda (ctx x) x)))
  (make-translated-operand-generator
   (lambda (ctx return . args)
     (return
      (cond ((null? args)
             (box ctx (op0 ctx)))
            ((null? (cdr args))
             (box ctx (op1 ctx (unbox ctx (car args)))))
            (else
             (let loop ((lst (cdr args))
                        (res (op2 ctx
                                  (unbox ctx (car args))
                                  (unbox ctx (cadr args)))))
               (let ((rest (cdr lst)))
                 (if (null? rest)
                     (box ctx res)
                     (loop rest
                           (^&& (^parens res)
                                (op2 ctx
                                     (unbox ctx (car lst))
                                     (unbox ctx (car rest))))))))))))))

(define (make-translated-operand-generator proc)
  (lambda (ctx return opnds)
    (apply proc (cons ctx (cons return (univ-emit-getopnds ctx opnds))))))

;;----------------------------------------------------------------------------

(univ-define-prim "##type" #t
  (make-translated-operand-generator
   (lambda (ctx return arg1)
     (return (^obj 0)))));;TODO: implement

(univ-define-prim "##type-cast" #t
  (make-translated-operand-generator
   (lambda (ctx return arg1 arg2)
     (return arg1))));;TODO: implement

(univ-define-prim "##subtype" #t
  (make-translated-operand-generator
   (lambda (ctx return arg1)
     (return (^obj 0)))));;TODO: implement

(univ-define-prim "##subtype-set!" #t
  (make-translated-operand-generator
   (lambda (ctx return arg1 arg2)
     (return #f))));;TODO: implement

(univ-define-prim-bool "##not" #t
  (make-translated-operand-generator
   (lambda (ctx return arg1)
     (return (^eq? arg1 (^obj #f))))))

(univ-define-prim-bool "##boolean?" #t
  (make-translated-operand-generator
   (lambda (ctx return arg1)
     (return
      (case (target-name (ctx-target ctx))

        ((js)
         (^typeof "boolean" arg1))

        ((php)
         (^call-prim "is_bool" arg1))

        ((python)
         (^instanceof "bool" arg1))

        ((ruby)
         (^or (^instanceof "FalseClass" arg1)
              (^instanceof "TrueClass" arg1)))

        (else
         (compiler-internal-error
          "##boolean?, unknown target")))))))

(univ-define-prim-bool "##null?" #t
  (make-translated-operand-generator
   (lambda (ctx return arg1)
     (return (^eq? arg1 (^obj '()))))))

(univ-define-prim-bool "##unbound?" #t
  (make-translated-operand-generator
   (lambda (ctx return arg1)
     (return (^bool #f)))));;TODO: implement

(univ-define-prim-bool "##eq?" #t
  (make-translated-operand-generator
   (lambda (ctx return arg1 arg2)
     (return (^eq? arg1 arg2)))))

;;TODO: ("##eqv?"               (2)   #f ()    0    boolean extended)
;;TODO: ("##equal?"             (2)   #f ()    0    boolean extended)
;;TODO: ("##eof-object?"        (1)   #f ()    0    boolean extended)

(univ-define-prim-bool "##fixnum?" #t
  (make-translated-operand-generator
   (lambda (ctx return arg1)
     (return (^fixnum? arg1)))))

;;TODO: ("##special?"                 (1)   #f ()    0    boolean extended)

(univ-define-prim-bool "##pair?" #t
  (make-translated-operand-generator
   (lambda (ctx return arg1)
     (return (^pair? arg1)))))

;; TODO: test ##pair-mutable?

(univ-define-prim-bool "##pair-mutable?" #t
  (make-translated-operand-generator
   (lambda (ctx return arg1)
     (return (^obj #t))))) ;; there are no immutable data (currently)

;;TODO: ("##subtyped?"                (1)   #f ()    0    boolean extended)

;; TODO: test ##subtyped-mutable?

(univ-define-prim-bool "##subtyped-mutable?" #t
  (make-translated-operand-generator
   (lambda (ctx return arg1)
     (return (^obj #t))))) ;; there are no immutable data (currently)

;;TODO: ("##subtyped.vector?"         (1)   #f ()    0    boolean extended)
;;TODO: ("##subtyped.symbol?"         (1)   #f ()    0    boolean extended)
;;TODO: ("##subtyped.flonum?"         (1)   #f ()    0    boolean extended)
;;TODO: ("##subtyped.bignum?"         (1)   #f ()    0    boolean extended)

(univ-define-prim-bool "##vector?" #t
  (make-translated-operand-generator
   (lambda (ctx return arg1)
     (return (^vector? arg1)))))

;;TODO: ("##ratnum?"                  (1)   #f ()    0    boolean extended)
;;TODO: ("##cpxnum?"                  (1)   #f ()    0    boolean extended)
;;TODO: ("##structure?"               (1)   #f ()    0    boolean extended)

;; TODO: test box? primitive

(univ-define-prim-bool "##box?" #t
  (make-translated-operand-generator
   (lambda (ctx return arg1)
     (return (^box? arg1)))))

;;TODO: ("##values?"                  (1)   #f ()    0    boolean extended)
;;TODO: ("##meroon?"                  (1)   #f ()    0    boolean extended)
;;TODO: ("##jazz?"                    (1)   #f ()    0    boolean extended)

(univ-define-prim-bool "##symbol?" #t
  (make-translated-operand-generator
   (lambda (ctx return arg1)
     (return (^symbol? arg1)))))

;;TODO: ("##keyword?"                 (1)   #f ()    0    boolean extended)
;;TODO: ("##frame?"                   (1)   #f ()    0    boolean extended)
;;TODO: ("##continuation?"            (1)   #f ()    0    boolean extended)
;;TODO: ("##promise?"                 (1)   #f ()    0    boolean extended)
;;TODO: ("##will?"                    (1)   #f ()    0    boolean extended)
;;TODO: ("##gc-hash-table?"           (1)   #f ()    0    boolean extended)
;;TODO: ("##mem-allocated?"           (1)   #f ()    0    boolean extended)

;; TODO: test ##procedure?

(univ-define-prim-bool "##procedure?" #t
  (make-translated-operand-generator
   (lambda (ctx return arg1)
     (return (^procedure? arg1)))))

;;TODO: ("##return?"                  (1)   #f ()    0    boolean extended)
;;TODO: ("##foreign?"                 (1)   #f ()    0    boolean extended)

(univ-define-prim-bool "##string?" #t
  (make-translated-operand-generator
   (lambda (ctx return arg1)
     (return (^string? arg1)))))

;;TODO: ("##s8vector?"                (1)   #f ()    0    boolean extended)
;;TODO: ("##u8vector?"                (1)   #f ()    0    boolean extended)
;;TODO: ("##s16vector?"               (1)   #f ()    0    boolean extended)
;;TODO: ("##u16vector?"               (1)   #f ()    0    boolean extended)
;;TODO: ("##s32vector?"               (1)   #f ()    0    boolean extended)
;;TODO: ("##u32vector?"               (1)   #f ()    0    boolean extended)
;;TODO: ("##s64vector?"               (1)   #f ()    0    boolean extended)
;;TODO: ("##u64vector?"               (1)   #f ()    0    boolean extended)
;;TODO: ("##f32vector?"               (1)   #f ()    0    boolean extended)
;;TODO: ("##f64vector?"               (1)   #f ()    0    boolean extended)

(univ-define-prim-bool "##flonum?" #t
  (make-translated-operand-generator
   (lambda (ctx return arg1)
     (return (^flonum? arg1)))))

;;TODO: ("##bignum?"                  (1)   #f ()    0    boolean extended)

(univ-define-prim-bool "##char?" #t
  (make-translated-operand-generator
   (lambda (ctx return arg1)
     (return (^char? arg1)))))

;;TODO: ("##closure?"                 (1)   #f ()    0    boolean extended)
;;TODO: ("##subprocedure?"            (1)   #f ()    0    boolean extended)
;;TODO: ("##return-dynamic-env-bind?" (1)   #f ()    0    boolean extended)
;;TODO: ("##number?"                  (1)   #f ()    0    boolean extended)
;;TODO: ("##complex?"                 (1)   #f ()    0    boolean extended)
;;TODO: ("##real?"                    (1)   #f ()    0    boolean extended)
;;TODO: ("##rational?"                (1)   #f ()    0    boolean extended)
;;TODO: ("##integer?"                 (1)   #f ()    0    boolean extended)
;;TODO: ("##exact?"                   (1)   #f ()    0    boolean extended)
;;TODO: ("##inexact?"                 (1)   #f ()    0    boolean extended)

;;TODO: make variadic, complete, clean up and test
(univ-define-prim "##fxmax" #t
  (make-translated-operand-generator
   (lambda (ctx return arg1 arg2)
     (return (^if-expr (^> (^fixnum-unbox arg1) (^fixnum-unbox arg2))
                       arg1
                       arg2)))))

;;TODO: make variadic, complete, clean up and test
(univ-define-prim "##fxmin" #t
  (make-translated-operand-generator
   (lambda (ctx return arg1 arg2)
     (return (^if-expr (^< (^fixnum-unbox arg1) (^fixnum-unbox arg2))
                       arg1
                       arg2)))))

(univ-define-prim "##fxwrap+" #f
  (univ-fold-left
   (lambda (ctx)           (^int 0))
   (lambda (ctx arg1)      arg1)
   (lambda (ctx arg1 arg2) (univ-wrap+ ctx arg1 arg2))
   univ-emit-fixnum-unbox
   univ-emit-fixnum-box))

(univ-define-prim "##fx+" #f
  (univ-fold-left
   (lambda (ctx)           (^int 0))
   (lambda (ctx arg1)      arg1)
   (lambda (ctx arg1 arg2) (^+ arg1 arg2))
   univ-emit-fixnum-unbox
   univ-emit-fixnum-box))

;;TODO: complete, clean up and test, and add boxing/unboxing of fixnums
(univ-define-prim "##fx+?" #f
  (make-translated-operand-generator
   (lambda (ctx return arg1 arg2)
     (return
      (case (target-name (ctx-target ctx))

        ((js)
         (^ "(" (^global-var (^prefix "temp2")) " = (" (^global-var (^prefix "temp1")) " = "
            arg1
            " + "
            arg2
            ")<<"
            univ-tag-bits
            ">>"
            univ-tag-bits
            ") === " (^global-var (^prefix "temp1")) " && " (^global-var (^prefix "temp2"))))

        ((python)
         (^ "(lambda temp1: (lambda temp2: temp1 == temp2 and temp2)(ctypes.c_int32(temp1<<"
            univ-tag-bits
            ").value>>"
            univ-tag-bits
            "))("
            arg1
            " + "
            arg2
            ")"))

        ((php ruby)
         (^and (^parens
                (^= (^parens
                     (^assign (^global-var (^prefix "temp2"))
                              (^-
                               (^parens
                                (^bitand
                                 (^parens
                                  (^+
                                   (^parens
                                    (^assign (^global-var (^prefix "temp1"))
                                             (^+ arg1
                                                 arg2)))
                                   (expt 2 (- univ-word-bits (+ 1 univ-tag-bits)))))
                                 (- (expt 2 (- univ-word-bits univ-tag-bits)) 1)))
                               (expt 2 (- univ-word-bits (+ 1 univ-tag-bits))))))
                    (^global-var (^prefix "temp1"))))
               (^global-var (^prefix "temp2"))))

        (else
         (compiler-internal-error
          "##fx+?, unknown target")))))))

(univ-define-prim "##fxwrap*" #f
  (univ-fold-left
   (lambda (ctx)           (^int 1))
   (lambda (ctx arg1)      arg1)
   (lambda (ctx arg1 arg2) (univ-wrap* ctx arg1 arg2))
   univ-emit-fixnum-unbox
   univ-emit-fixnum-box))

(univ-define-prim "##fx*" #f
  (univ-fold-left
   (lambda (ctx)           (^int 1))
   (lambda (ctx arg1)      arg1)
   (lambda (ctx arg1 arg2) (^* arg1 arg2))
   univ-emit-fixnum-unbox
   univ-emit-fixnum-box))

;;TODO: complete, clean up and test, and add boxing/unboxing of fixnums
(univ-define-prim "##fx*?" #f
  (make-translated-operand-generator
   (lambda (ctx return arg1 arg2)
     (return
      (case (target-name (ctx-target ctx))

        ((js)
         (^ "(" (^global-var (^prefix "temp2")) " = (" (^global-var (^prefix "temp1")) " = "
            arg1
            " * "
            arg2
            ")<<"
            univ-tag-bits
            ">>"
            univ-tag-bits
            ") === " (^global-var (^prefix "temp1")) " && " (^global-var (^prefix "temp2"))))

        ((python)
         (^ "(lambda temp1: (lambda temp2: temp1 == temp2 and temp2)(ctypes.c_int32(temp1<<"
            univ-tag-bits
            ").value>>"
            univ-tag-bits
            "))("
            arg1
            " * "
            arg2
            ")"))

        ((php ruby)
         (^and (^parens
                (^= (^parens
                     (^assign (^global-var (^prefix "temp2"))
                              (^-
                               (^parens
                                (^bitand
                                 (^parens
                                  (^+
                                   (^parens
                                    (^assign (^global-var (^prefix "temp1"))
                                             (^* arg1
                                                 arg2)))
                                   (expt 2 (- univ-word-bits (+ 1 univ-tag-bits)))))
                                 (- (expt 2 (- univ-word-bits univ-tag-bits)) 1)))
                               (expt 2 (- univ-word-bits (+ 1 univ-tag-bits))))))
                    (^global-var (^prefix "temp1"))))
               (^global-var (^prefix "temp2"))))

        (else
         (compiler-internal-error
          "##fx*?, unknown target")))))))

(univ-define-prim "##fxwrap-" #f
  (univ-fold-left
   #f ;; 0 arguments impossible
   (lambda (ctx arg1)      (univ-wrap- ctx arg1))
   (lambda (ctx arg1 arg2) (univ-wrap- ctx arg1 arg2))
   univ-emit-fixnum-unbox
   univ-emit-fixnum-box))

(univ-define-prim "##fx-" #f
  (univ-fold-left
   #f ;; 0 arguments impossible
   (lambda (ctx arg1)      (^- arg1))
   (lambda (ctx arg1 arg2) (^- arg1 arg2))
   univ-emit-fixnum-unbox
   univ-emit-fixnum-box))

;;TODO: complete, clean up and test, and add boxing/unboxing of fixnums
(univ-define-prim "##fx-?" #f
  (make-translated-operand-generator
   (lambda (ctx return arg1 #!optional (arg2 #f))
     (return
      (case (target-name (ctx-target ctx))

        ((js)
         (if arg2
             (^ "(" (^global-var (^prefix "temp2")) " = (" (^global-var (^prefix "temp1")) " = "
                arg1
                " - "
                arg2
                ")<<"
                univ-tag-bits
                ">>"
                univ-tag-bits
                ") === " (^global-var (^prefix "temp1")) " && " (^global-var (^prefix "temp2")))
             (^ "(" (^global-var (^prefix "temp2")) " = (" (^global-var (^prefix "temp1")) " = "
                "- "
                arg1
                ")<<"
                univ-tag-bits
                ">>"
                univ-tag-bits
                ") === " (^global-var (^prefix "temp1")) " && " (^global-var (^prefix "temp2")))))

        ((python)
         (^ "(lambda temp1: (lambda temp2: temp1 == temp2 and temp2)(ctypes.c_int32(temp1<<"
            univ-tag-bits
            ").value>>"
            univ-tag-bits
            "))("
            arg1
            " - "
            arg2
            ")"))

        ((ruby)
         (^ "(" (^global-var (^prefix "temp2")) " = (((" (^global-var (^prefix "temp1")) " = "
            arg1
            " - "
            arg2
            ") + "
            (expt 2 (- univ-word-bits (+ 1 univ-tag-bits)))
            ") & "
            (- (expt 2 (- univ-word-bits univ-tag-bits)) 1)
            ") - "
            (expt 2 (- univ-word-bits (+ 1 univ-tag-bits)))
            ") == " (^global-var (^prefix "temp1")) " && " (^global-var (^prefix "temp2"))))

        ((php)
         (^ "((" (^global-var (^prefix "temp2")) " = (((" (^global-var (^prefix "temp1")) " = "
            arg1
            " - "
            arg2
            ") + "
            (expt 2 (- univ-word-bits (+ 1 univ-tag-bits)))
            ") & "
            (- (expt 2 (- univ-word-bits univ-tag-bits)) 1)
            ") - "
            (expt 2 (- univ-word-bits (+ 1 univ-tag-bits)))
            ") === " (^global-var (^prefix "temp1")) ") ? " (^global-var (^prefix "temp2")) " : False"))

        (else
         (compiler-internal-error
          "##fx-?, unknown target")))))))

;;TODO: ("##fxwrapquotient"              (2)   #f ()    0    fixnum  extended)

(univ-define-prim "##fxquotient" #f
  (make-translated-operand-generator
   (lambda (ctx return arg1 arg2)
     (return
      (^fixnum-box (univ-fxquotient
                    ctx
                    (^fixnum-unbox arg1)
                    (^fixnum-unbox arg2)))))))

(univ-define-prim "##fxremainder" #f
  (make-translated-operand-generator
   (lambda (ctx return arg1 arg2)
     (return
      (^fixnum-box (univ-fxremainder
                    ctx
                    (^fixnum-unbox arg1)
                    (^fixnum-unbox arg2)))))))

(univ-define-prim "##fxmodulo" #f
  (make-translated-operand-generator
   (lambda (ctx return arg1 arg2)
     (return
      (^fixnum-box (univ-fxmodulo
                    ctx
                    (^fixnum-unbox arg1)
                    (^fixnum-unbox arg2)))))))

(univ-define-prim "##fxnot" #f
  (make-translated-operand-generator
   (lambda (ctx return arg)
     (return
      (^fixnum-box (^bitand (^bitnot (^fixnum-unbox arg))
                            (- (expt 2 univ-tag-bits))))))))

(univ-define-prim "##fxand" #f
  (univ-fold-left
   (lambda (ctx)           (^int -1))
   (lambda (ctx arg1)      arg1)
   (lambda (ctx arg1 arg2) (^bitand arg1 arg2))
   univ-emit-fixnum-unbox
   univ-emit-fixnum-box))

(univ-define-prim "##fxior" #f
  (univ-fold-left
   (lambda (ctx)           (^int 0))
   (lambda (ctx arg1)      arg1)
   (lambda (ctx arg1 arg2) (^bitior arg1 arg2))
   univ-emit-fixnum-unbox
   univ-emit-fixnum-box))

(univ-define-prim "##fxxor" #f
  (univ-fold-left
   (lambda (ctx)           (^int 0))
   (lambda (ctx arg1)      arg1)
   (lambda (ctx arg1 arg2) (^bitxor arg1 arg2))
   univ-emit-fixnum-unbox
   univ-emit-fixnum-box))

;;TODO: ("##fxnot"                       (1)   #f ()    0    fixnum  extended)
;;TODO: ("##fxand"                       0     #f ()    0    fixnum  extended)
;;TODO: ("##fxior"                       0     #f ()    0    fixnum  extended)
;;TODO: ("##fxxor"                       0     #f ()    0    fixnum  extended)

;;TODO: ("##fxif"                        (3)   #f ()    0    fixnum  extended)
;;TODO: ("##fxbit-count"                 (1)   #f ()    0    fixnum  extended)
;;TODO: ("##fxlength"                    (1)   #f ()    0    fixnum  extended)
;;TODO: ("##fxfirst-bit-set"             (1)   #f ()    0    fixnum  extended)
;;TODO: ("##fxbit-set?"                  (2)   #f ()    0    fixnum  extended)
;;TODO: ("##fxwraparithmetic-shift"      (2)   #f ()    0    fixnum  extended)
;;TODO: ("##fxarithmetic-shift"          (2)   #f ()    0    fixnum  extended)
;;TODO: ("##fxarithmetic-shift?"         (2)   #f ()    0    #f      extended)
;;TODO: ("##fxwraparithmetic-shift-left" (2)   #f ()    0    fixnum  extended)
;;TODO: ("##fxarithmetic-shift-left"     (2)   #f ()    0    fixnum  extended)
;;TODO: ("##fxarithmetic-shift-left?"    (2)   #f ()    0    #f      extended)
;;TODO: ("##fxarithmetic-shift-right"    (2)   #f ()    0    fixnum  extended)
;;TODO: ("##fxarithmetic-shift-right?"   (2)   #f ()    0    #f      extended)
;;TODO: ("##fxwraplogical-shift-right"   (2)   #f ()    0    fixnum  extended)
;;TODO: ("##fxwraplogical-shift-right?"  (2)   #f ()    0    #f      extended)
;;TODO: ("##fxwrapabs"                   (1)   #f ()    0    fixnum  extended)
;;TODO: ("##fxabs"                       (1)   #f ()    0    fixnum  extended)
;;TODO: ("##fxabs?"                      (1)   #f ()    0    #f      extended)

(univ-define-prim-bool "##fxzero?" #t
  (make-translated-operand-generator
   (lambda (ctx return arg1)
     (return (^= (^fixnum-unbox arg1) (^int 0))))))

(univ-define-prim-bool "##fxpositive?" #t
  (make-translated-operand-generator
   (lambda (ctx return arg1)
     (return (^> (^fixnum-unbox arg1) (^int 0))))))

(univ-define-prim-bool "##fxnegative?" #t
  (make-translated-operand-generator
   (lambda (ctx return arg1)
     (return (^< (^fixnum-unbox arg1) (^int 0))))))

(univ-define-prim-bool "##fxodd?" #t
  (make-translated-operand-generator
   (lambda (ctx return arg1)
     (return (^= (^parens (^bitand (^fixnum-unbox arg1) (^int 1)))
                 (^int 1))))))

(univ-define-prim-bool "##fxeven?" #t
  (make-translated-operand-generator
   (lambda (ctx return arg1)
     (return (^= (^parens (^bitand (^fixnum-unbox arg1) (^int 1)))
                 (^int 0))))))

(univ-define-prim-bool "##fx=" #f
  (univ-fold-left-compare
   (lambda (ctx)           (^bool #t))
   (lambda (ctx arg1)      (^bool #t))
   (lambda (ctx arg1 arg2) (^= arg1 arg2))
   univ-emit-fixnum-unbox))

(univ-define-prim-bool "##fx<" #f
  (univ-fold-left-compare
   (lambda (ctx)           (^bool #t))
   (lambda (ctx arg1)      (^bool #t))
   (lambda (ctx arg1 arg2) (^< arg1 arg2))
   univ-emit-fixnum-unbox))

(univ-define-prim-bool "##fx>" #f
  (univ-fold-left-compare
   (lambda (ctx)           (^bool #t))
   (lambda (ctx arg1)      (^bool #t))
   (lambda (ctx arg1 arg2) (^> arg1 arg2))
   univ-emit-fixnum-unbox))

(univ-define-prim-bool "##fx<=" #f
  (univ-fold-left-compare
   (lambda (ctx)           (^bool #t))
   (lambda (ctx arg1)      (^bool #t))
   (lambda (ctx arg1 arg2) (^<= arg1 arg2))
   univ-emit-fixnum-unbox))

(univ-define-prim-bool "##fx>=" #f
  (univ-fold-left-compare
   (lambda (ctx)           (^bool #t))
   (lambda (ctx arg1)      (^bool #t))
   (lambda (ctx arg1 arg2) (^>= arg1 arg2))
   univ-emit-fixnum-unbox))

(univ-define-prim "##fx->char" #f
  (make-translated-operand-generator
   (lambda (ctx return arg)
     (return (^char-box (^chr-fromint (^fixnum-unbox arg)))))))

(univ-define-prim "##fx<-char" #f
  (make-translated-operand-generator
   (lambda (ctx return arg)
     (return (^fixnum-box (^chr-toint (^char-unbox arg)))))))

;;TODO: ("##fixnum->char"                (1)   #f ()    0    char    extended)
;;TODO: ("##char->fixnum"                (1)   #f ()    0    fixnum  extended)
;;TODO: ("##flonum->fixnum"              (1)   #f ()    0    fixnum  extended)
;;TODO: ("##fixnum->flonum"              (1)   #f ()    0    real    extended)
;;TODO: ("##fixnum->flonum-exact?"       (1)   #f ()    0    boolean extended)

(univ-define-prim "##fl->fx" #f
  (make-translated-operand-generator
   (lambda (ctx return arg)
     (return (^fixnum-box (^float-toint (^flonum-unbox arg)))))))

(univ-define-prim "##fl<-fx" #f
  (make-translated-operand-generator
   (lambda (ctx return arg)
     (return (^flonum-box (^float-fromint (^fixnum-unbox arg)))))))

;;TODO: make variadic, complete, clean up and test
(univ-define-prim "##flmax" #t
  (make-translated-operand-generator
   (lambda (ctx return arg1 arg2)
     (return (^if-expr (^> (^flonum-unbox arg1) (^flonum-unbox arg2))
                       arg1
                       arg2)))))

;;TODO: make variadic, complete, clean up and test
(univ-define-prim "##flmin" #t
  (make-translated-operand-generator
   (lambda (ctx return arg1 arg2)
     (return (^if-expr (^< (^flonum-unbox arg1) (^flonum-unbox arg2))
                       arg1
                       arg2)))))

(univ-define-prim "##fl+" #f
  (univ-fold-left
   (lambda (ctx)           (^float targ-inexact-+0))
   (lambda (ctx arg1)      arg1)
   (lambda (ctx arg1 arg2) (^+ arg1 arg2))
   univ-emit-flonum-unbox
   univ-emit-flonum-box))

(univ-define-prim "##fl*" #f
  (univ-fold-left
   (lambda (ctx)           (^float targ-inexact-+1))
   (lambda (ctx arg1)      arg1)
   (lambda (ctx arg1 arg2) (^* arg1 arg2))
   univ-emit-flonum-unbox
   univ-emit-flonum-box))

(univ-define-prim "##fl-" #f
  (univ-fold-left
   #f ;; 0 arguments impossible
   (lambda (ctx arg1)      (^- arg1))
   (lambda (ctx arg1 arg2) (^- arg1 arg2))
   univ-emit-flonum-unbox
   univ-emit-flonum-box))

(univ-define-prim "##fl/" #f
  (univ-fold-left
   #f ;; 0 arguments impossible
   (lambda (ctx arg1)      (univ-ieee/ ctx (^float targ-inexact-+1) arg1))
   (lambda (ctx arg1 arg2) (univ-ieee/ ctx arg1 arg2))
   univ-emit-flonum-unbox
   univ-emit-flonum-box))

(define (univ-ieee/ ctx arg1 arg2)
  (case (target-name (ctx-target ctx))

    ((python)
     ;;TODO: cleanup the Python code
     (^if-expr (^= arg2 (^float targ-inexact-+0))
               (^if-expr (^= arg1 (^float targ-inexact-+0))
                         "float('nan')"
                         (^ "math.copysign(float('inf')," (^* arg1 arg2) ")"))
               (^/ arg1 arg2)))

    ((php)
     ;;TODO: cleanup the PHP code
     (^if-expr (^= arg2 (^float targ-inexact-+0))
               (^if-expr (^= arg1 (^float targ-inexact-+0))
                         "NAN"
                         (^if-expr (^eq? (^call-prim "strval" (^* arg1 (^float targ-inexact-+0)))
                                         (^call-prim "strval" arg2))
                                   "INF"
                                   "-INF"))
               (^/ arg1 arg2)))

    (else
     (^/ arg1 arg2))))

(univ-define-prim "##flabs" #f
  (make-translated-operand-generator
   (lambda (ctx return arg)
     (return (^flonum-box (^float-abs (^flonum-unbox arg)))))))

(univ-define-prim "##flfloor" #f
  (make-translated-operand-generator
   (lambda (ctx return arg)
     (return (^flonum-box (^float-floor (^flonum-unbox arg)))))))

(univ-define-prim "##flceiling" #f
  (make-translated-operand-generator
   (lambda (ctx return arg)
     (return (^flonum-box (^float-ceiling (^flonum-unbox arg)))))))

(univ-define-prim "##fltruncate" #f
  (make-translated-operand-generator
   (lambda (ctx return arg)
     (return (^flonum-box (^float-truncate (^flonum-unbox arg)))))))

(univ-define-prim "##flround" #f
  (make-translated-operand-generator
   (lambda (ctx return arg)
     (return (^flonum-box (^float-round-half-to-even (^flonum-unbox arg)))))))

(univ-define-prim "##flexp" #f
  (make-translated-operand-generator
   (lambda (ctx return arg)
     (return (^flonum-box (^float-exp (^flonum-unbox arg)))))))

(univ-define-prim "##fllog" #f
  (make-translated-operand-generator
   (lambda (ctx return arg)
     (return (^flonum-box (^float-log (^flonum-unbox arg)))))))

(univ-define-prim "##flsin" #f
  (make-translated-operand-generator
   (lambda (ctx return arg)
     (return (^flonum-box (^float-sin (^flonum-unbox arg)))))))

(univ-define-prim "##flcos" #f
  (make-translated-operand-generator
   (lambda (ctx return arg)
     (return (^flonum-box (^float-cos (^flonum-unbox arg)))))))

(univ-define-prim "##fltan" #f
  (make-translated-operand-generator
   (lambda (ctx return arg)
     (return (^flonum-box (^float-tan (^flonum-unbox arg)))))))

(univ-define-prim "##flasin" #f
  (make-translated-operand-generator
   (lambda (ctx return arg)
     (return (^flonum-box (^float-asin (^flonum-unbox arg)))))))

(univ-define-prim "##flacos" #f
  (make-translated-operand-generator
   (lambda (ctx return arg)
     (return (^flonum-box (^float-acos (^flonum-unbox arg)))))))

(univ-define-prim "##flatan" #f
  (make-translated-operand-generator
   (lambda (ctx return arg)
     (return (^flonum-box (^float-atan (^flonum-unbox arg)))))))

(univ-define-prim "##flexpt" #f
  (make-translated-operand-generator
   (lambda (ctx return arg1 arg2)
     (return (^flonum-box (^float-expt (^flonum-unbox arg1) (^flonum-unbox arg2)))))))

(univ-define-prim "##flsqrt" #f
  (make-translated-operand-generator
   (lambda (ctx return arg)
     (return (^flonum-box (^float-sqrt (^flonum-unbox arg)))))))

;;TODO: ("##flcopysign"                  (2)   #f ()    0    real    extended)

(univ-define-prim-bool "##flinteger?" #t
  (make-translated-operand-generator
   (lambda (ctx return arg)
     (return (^float-integer? (^flonum-unbox arg))))))

(univ-define-prim-bool "##flzero?" #t
  (make-translated-operand-generator
   (lambda (ctx return arg)
     (return (^= (^flonum-unbox arg) (^float targ-inexact-+0))))))

(univ-define-prim-bool "##flpositive?" #t
  (make-translated-operand-generator
   (lambda (ctx return arg)
     (return (^> (^flonum-unbox arg) (^float targ-inexact-+0))))))

(univ-define-prim-bool "##flnegative?" #t
  (make-translated-operand-generator
   (lambda (ctx return arg)
     (return (^< (^flonum-unbox arg) (^float targ-inexact-+0))))))

(univ-define-prim-bool "##flodd?" #t
  (make-translated-operand-generator
   (lambda (ctx return arg)
     (return (^&& (^float-integer? (^flonum-unbox arg))
                  (^!= (^flonum-unbox arg)
                       (^* (^float targ-inexact-+2)
                           (^float-floor
                            (^parens (^* (^float targ-inexact-+1/2)
                                         (^flonum-unbox arg)))))))))))

(univ-define-prim-bool "##fleven?" #t
  (make-translated-operand-generator
   (lambda (ctx return arg)
     (return (^&& (^float-integer? (^flonum-unbox arg))
                  (^= (^flonum-unbox arg)
                      (^* (^float targ-inexact-+2)
                          (^float-floor
                           (^parens (^* (^float targ-inexact-+1/2)
                                        (^flonum-unbox arg)))))))))))

(univ-define-prim-bool "##flfinite?" #t
  (make-translated-operand-generator
   (lambda (ctx return arg)
     (return (^float-finite? (^flonum-unbox arg))))))

(univ-define-prim-bool "##flinfinite?" #t
  (make-translated-operand-generator
   (lambda (ctx return arg)
     (return (^float-infinite? (^flonum-unbox arg))))))

(univ-define-prim-bool "##flnan?" #t
  (make-translated-operand-generator
   (lambda (ctx return arg)
     (return (^float-nan? (^flonum-unbox arg))))))

(univ-define-prim-bool "##fl<-fx-exact?" #t
  (make-translated-operand-generator
   (lambda (ctx return arg)
     (return (^bool #t)))))

(univ-define-prim-bool "##fl=" #f
  (univ-fold-left-compare
   (lambda (ctx)           (^bool #t))
   (lambda (ctx arg1)      (^bool #t))
   (lambda (ctx arg1 arg2) (^= arg1 arg2))
   univ-emit-flonum-unbox))

(univ-define-prim-bool "##fl<" #f
  (univ-fold-left-compare
   (lambda (ctx)           (^bool #t))
   (lambda (ctx arg1)      (^bool #t))
   (lambda (ctx arg1 arg2) (^< arg1 arg2))
   univ-emit-flonum-unbox))

(univ-define-prim-bool "##fl>" #f
  (univ-fold-left-compare
   (lambda (ctx)           (^bool #t))
   (lambda (ctx arg1)      (^bool #t))
   (lambda (ctx arg1 arg2) (^> arg1 arg2))
   univ-emit-flonum-unbox))

(univ-define-prim-bool "##fl<=" #f
  (univ-fold-left-compare
   (lambda (ctx)           (^bool #t))
   (lambda (ctx arg1)      (^bool #t))
   (lambda (ctx arg1 arg2) (^<= arg1 arg2))
   univ-emit-flonum-unbox))

(univ-define-prim-bool "##fl>=" #f
  (univ-fold-left-compare
   (lambda (ctx)           (^bool #t))
   (lambda (ctx arg1)      (^bool #t))
   (lambda (ctx arg1 arg2) (^>= arg1 arg2))
   univ-emit-flonum-unbox))

(univ-define-prim-bool "##char=?" #f
  ;;TODO: implement as eq? if chars are interned
  (univ-fold-left-compare
   (lambda (ctx)           (^bool #t))
   (lambda (ctx arg1)      (^bool #t))
   (lambda (ctx arg1 arg2) (^= arg1 arg2))
   univ-emit-char-unbox))

(univ-define-prim-bool "##char<?" #f
  (univ-fold-left-compare
   (lambda (ctx)           (^bool #t))
   (lambda (ctx arg1)      (^bool #t))
   (lambda (ctx arg1 arg2) (^< arg1 arg2))
   univ-emit-char-unbox))

(univ-define-prim-bool "##char>?" #f
  (univ-fold-left-compare
   (lambda (ctx)           (^bool #t))
   (lambda (ctx arg1)      (^bool #t))
   (lambda (ctx arg1 arg2) (^> arg1 arg2))
   univ-emit-char-unbox))

(univ-define-prim-bool "##char<=?" #f
  (univ-fold-left-compare
   (lambda (ctx)           (^bool #t))
   (lambda (ctx arg1)      (^bool #t))
   (lambda (ctx arg1 arg2) (^<= arg1 arg2))
   univ-emit-char-unbox))

(univ-define-prim-bool "##char>=?" #f
  (univ-fold-left-compare
   (lambda (ctx)           (^bool #t))
   (lambda (ctx arg1)      (^bool #t))
   (lambda (ctx arg1 arg2) (^>= arg1 arg2))
   univ-emit-char-unbox))

;;TODO: ("##char-alphabetic?"             (1)   #f ()    0    boolean extended)
;;TODO: ("##char-numeric?"                (1)   #f ()    0    boolean extended)
;;TODO: ("##char-whitespace?"             (1)   #f ()    0    boolean extended)
;;TODO: ("##char-upper-case?"             (1)   #f ()    0    boolean extended)
;;TODO: ("##char-lower-case?"             (1)   #f ()    0    boolean extended)
;;TODO: ("##char-upcase"                  (1)   #f ()    0    char    extended)
;;TODO: ("##char-downcase"                (1)   #f ()    0    char    extended)

(univ-define-prim "##cons" #t
  (make-translated-operand-generator
   (lambda (ctx return arg1 arg2)
     (return (^cons arg1 arg2)))))

(univ-define-prim "##set-car!" #f
  (make-translated-operand-generator
   (lambda (ctx return arg1 arg2)
     (^ (^setcar arg1 arg2)
        (return arg1)))))

(univ-define-prim "##set-cdr!" #f
  (make-translated-operand-generator
   (lambda (ctx return arg1 arg2)
     (^ (^setcdr arg1 arg2)
        (return arg1)))))

(define (univ-cxxxxr-init)
  (let cxxxxr-loop ((n #b10))
    (if (<= n #b11111)
        (let ()

          (define (ad-name prefix x)
            (if (>= x #b10)
                (string-append (ad-name prefix (quotient x 2))
                               (string (string-ref "ad" (modulo x 2))))
                prefix))

          (univ-define-prim (string-append (ad-name "##c" n) "r") #f
            (make-translated-operand-generator
             (lambda (ctx return arg)

               (define (ad-expr expr x)
                 (if (>= x #b10)
                     (ad-expr (if (= (modulo x 2) 0)
                                  (^getcar expr)
                                  (^getcdr expr))
                              (quotient x 2))
                     expr))

               (return (ad-expr arg n)))))

          (cxxxxr-loop (+ n 1))))))

(univ-cxxxxr-init)

(univ-define-prim "##list" #t
  (make-translated-operand-generator
   (lambda (ctx return . args)
     (let loop ((lst (reverse args))
                (result (^obj '())))
       (if (pair? lst)
           (loop (cdr lst)
                 (^cons (car lst)
                        result))
           (return result))))))

;; TODO: test box primitives

(univ-define-prim "##box" #t
  (make-translated-operand-generator
   (lambda (ctx return arg1)
     (return (^box arg1)))))

(univ-define-prim "##unbox" #f
  (make-translated-operand-generator
   (lambda (ctx return arg1)
     (return (^unbox arg1)))))

(univ-define-prim "##set-box!" #f
  (make-translated-operand-generator
   (lambda (ctx return arg1 arg2)
     (^ (^setbox arg1 arg2)
        (return arg1)))))

;;TODO: ("##make-will"                    (2)   #t ()    0    #f      extended)
;;TODO: ("##will-testator"                (1)   #f ()    0    (#f)    extended)

;;TODO: ("##gc-hash-table-ref"            (2)   #f ()    0    (#f)    extended)
;;TODO: ("##gc-hash-table-set!"           (3)   #t ()    0    (#f)    extended)
;;TODO: ("##gc-hash-table-rehash!"        (2)   #t ()    0    (#f)    extended)

;;TODO: ("##values"                       0     #f ()    0    (#f)    extended)

(univ-define-prim "##vector" #f
  (make-translated-operand-generator
   (lambda (ctx return . args)
     (return (^vector-box (^array-literal args))))))

(univ-define-prim "##make-vector" #f
  (make-translated-operand-generator
   (lambda (ctx return arg1 #!optional (arg2 #f))
     (return
      (^call-prim
       (^global-prim-function (^prefix "make_vector"))
       (^fixnum-unbox arg1)
       (if arg2
           arg2
           (^fixnum-box (^int 0))))))))

(univ-define-prim "##vector-length" #f
  (make-translated-operand-generator
   (lambda (ctx return arg)
     (return (^fixnum-box (^vector-length arg))))))

(univ-define-prim "##vector-ref" #f
  (make-translated-operand-generator
   (lambda (ctx return arg1 arg2)
     (return (^vector-ref arg1
                          (^fixnum-unbox arg2))))))

(univ-define-prim "##vector-set!" #f
  (make-translated-operand-generator
   (lambda (ctx return arg1 arg2 arg3)
     (^ (^vector-set! arg1
                      (^fixnum-unbox arg2)
                      arg3)
        (return arg1)))))

(univ-define-prim "##vector-shrink!" #f
  (make-translated-operand-generator
   (lambda (ctx return arg1 arg2)
     (^ (^vector-shrink! arg1
                         (^fixnum-unbox arg2))
        (return arg1)))))

(univ-define-prim "##string" #f
  (make-translated-operand-generator
   (lambda (ctx return . args)
     (return
      (^string-box (^array-literal (map (lambda (x) (^char-unbox x)) args)))))))

(univ-define-prim "##make-string" #f
  (make-translated-operand-generator
   (lambda (ctx return arg1 #!optional (arg2 #f))
     (return
      (^call-prim
       (^global-prim-function (^prefix "make_string"))
       (^fixnum-unbox arg1)
       (if arg2
           (^char-unbox arg2)
           (^chr-fromint 0)))))))

(univ-define-prim "##string-length" #f
  (make-translated-operand-generator
   (lambda (ctx return arg)
     (return (^fixnum-box (^string-length arg))))))

(univ-define-prim "##string-ref" #f
  (make-translated-operand-generator
   (lambda (ctx return arg1 arg2)
     (return (^char-box (^string-ref (^string-unbox arg1)
                                     (^fixnum-unbox arg2)))))))

(univ-define-prim "##string-set!" #f
  (make-translated-operand-generator
   (lambda (ctx return arg1 arg2 arg3)
     (^ (^string-set! (^string-unbox arg1)
                      (^fixnum-unbox arg2)
                      (^char-unbox arg3))
        (return arg1)))))

(univ-define-prim "##string-shrink!" #f
  (make-translated-operand-generator
   (lambda (ctx return arg1 arg2)
     (^ (^string-shrink! arg1
                         (^fixnum-unbox arg2))
        (return arg1)))))

;;TODO: ("##s8vector"                     0     #f ()    0    #f      extended)
;;TODO: ("##make-s8vector"                (2)   #f ()    0    #f      extended)
;;TODO: ("##s8vector-length"              (1)   #f ()    0    fixnum  extended)
;;TODO: ("##s8vector-ref"                 (2)   #f ()    0    fixnum  extended)
;;TODO: ("##s8vector-set!"                (3)   #t ()    0    #f      extended)
;;TODO: ("##s8vector-shrink!"             (2)   #t ()    0    #f      extended)

;;TODO: ("##u8vector"                     0     #f ()    0    #f      extended)
;;TODO: ("##make-u8vector"                (2)   #f ()    0    #f      extended)
;;TODO: ("##u8vector-length"              (1)   #f ()    0    fixnum  extended)
;;TODO: ("##u8vector-ref"                 (2)   #f ()    0    fixnum  extended)
;;TODO: ("##u8vector-set!"                (3)   #t ()    0    #f      extended)
;;TODO: ("##u8vector-shrink!"             (2)   #t ()    0    #f      extended)

;;TODO: ("##s16vector"                    0     #f ()    0    #f      extended)
;;TODO: ("##make-s16vector"               (2)   #f ()    0    #f      extended)
;;TODO: ("##s16vector-length"             (1)   #f ()    0    fixnum  extended)
;;TODO: ("##s16vector-ref"                (2)   #f ()    0    fixnum  extended)
;;TODO: ("##s16vector-set!"               (3)   #t ()    0    #f      extended)
;;TODO: ("##s16vector-shrink!"            (2)   #t ()    0    #f      extended)

;;TODO: ("##u16vector"                    0     #f ()    0    #f      extended)
;;TODO: ("##make-u16vector"               (2)   #f ()    0    #f      extended)
;;TODO: ("##u16vector-length"             (1)   #f ()    0    fixnum  extended)
;;TODO: ("##u16vector-ref"                (2)   #f ()    0    fixnum  extended)
;;TODO: ("##u16vector-set!"               (3)   #t ()    0    #f      extended)
;;TODO: ("##u16vector-shrink!"            (2)   #t ()    0    #f      extended)

;;TODO: ("##s32vector"                    0     #f ()    0    #f      extended)
;;TODO: ("##make-s32vector"               (2)   #f ()    0    #f      extended)
;;TODO: ("##s32vector-length"             (1)   #f ()    0    fixnum  extended)
;;TODO: ("##s32vector-ref"                (2)   #f ()    0    fixnum  extended)
;;TODO: ("##s32vector-set!"               (3)   #t ()    0    #f      extended)
;;TODO: ("##s32vector-shrink!"            (2)   #t ()    0    #f      extended)

;;TODO: ("##u32vector"                    0     #f ()    0    #f      extended)
;;TODO: ("##make-u32vector"               (2)   #f ()    0    #f      extended)
;;TODO: ("##u32vector-length"             (1)   #f ()    0    fixnum  extended)
;;TODO: ("##u32vector-ref"                (2)   #f ()    0    fixnum  extended)
;;TODO: ("##u32vector-set!"               (3)   #t ()    0    #f      extended)
;;TODO: ("##u32vector-shrink!"            (2)   #t ()    0    #f      extended)

;;TODO: ("##s64vector"                    0     #f ()    0    #f      extended)
;;TODO: ("##make-s64vector"               (2)   #f ()    0    #f      extended)
;;TODO: ("##s64vector-length"             (1)   #f ()    0    fixnum  extended)
;;TODO: ("##s64vector-ref"                (2)   #f ()    0    fixnum  extended)
;;TODO: ("##s64vector-set!"               (3)   #t ()    0    #f      extended)
;;TODO: ("##s64vector-shrink!"            (2)   #t ()    0    #f      extended)

;;TODO: ("##u64vector"                    0     #f ()    0    #f      extended)
;;TODO: ("##make-u64vector"               (2)   #f ()    0    #f      extended)
;;TODO: ("##u64vector-length"             (1)   #f ()    0    fixnum  extended)
;;TODO: ("##u64vector-ref"                (2)   #f ()    0    fixnum  extended)
;;TODO: ("##u64vector-set!"               (3)   #t ()    0    #f      extended)
;;TODO: ("##u64vector-shrink!"            (2)   #t ()    0    #f      extended)

;;TODO: ("##f32vector"                    0     #f ()    0    #f      extended)
;;TODO: ("##make-f32vector"               (2)   #f ()    0    #f      extended)
;;TODO: ("##f32vector-length"             (1)   #f ()    0    fixnum  extended)
;;TODO: ("##f32vector-ref"                (2)   #f ()    0    real    extended)
;;TODO: ("##f32vector-set!"               (3)   #t ()    0    #f      extended)
;;TODO: ("##f32vector-shrink!"            (2)   #t ()    0    #f      extended)

;;TODO: ("##f64vector"                    0     #f ()    0    #f      extended)
;;TODO: ("##make-f64vector"               (2)   #f ()    0    #f      extended)
;;TODO: ("##f64vector-length"             (1)   #f ()    0    fixnum  extended)
;;TODO: ("##f64vector-ref"                (2)   #f ()    0    real    extended)
;;TODO: ("##f64vector-set!"               (3)   #t ()    0    #f      extended)
;;TODO: ("##f64vector-shrink!"            (2)   #t ()    0    #f      extended)

;;TODO: ("##structure-direct-instance-of?"(2)   #f ()    0    boolean extended)
;;TODO: ("##structure-instance-of?"       (2)   #f ()    0    boolean extended)
;;TODO: ("##structure-type"               (1)   #f ()    0    (#f)    extended)
;;TODO: ("##structure-type-set!"          (2)   #t ()    0    (#f)    extended)
;;TODO: ("##structure"                    1     #f ()    0    (#f)    extended)
;;TODO: ("##structure-ref"                (4)   #f ()    0    (#f)    extended)
;;TODO: ("##structure-set!"               (5)   #t ()    0    (#f)    extended)
;;TODO: ("##direct-structure-ref"         (4)   #f ()    0    (#f)    extended)
;;TODO: ("##direct-structure-set!"        (5)   #t ()    0    (#f)    extended)
;;TODO: ("##unchecked-structure-ref"      (4)   #f ()    0    (#f)    extended)
;;TODO: ("##unchecked-structure-set!"     (5)   #t ()    0    (#f)    extended)

;;TODO: ("##type-id"                      (1)   #f ()    0    #f      extended)
;;TODO: ("##type-name"                    (1)   #f ()    0    #f      extended)
;;TODO: ("##type-flags"                   (1)   #f ()    0    #f      extended)
;;TODO: ("##type-super"                   (1)   #f ()    0    #f      extended)
;;TODO: ("##type-fields"                  (1)   #f ()    0    #f      extended)

;; TODO: test ##symbol->string primitive

(univ-define-prim "##symbol->string" #f
  (make-translated-operand-generator
   (lambda (ctx return arg1)
     (return (^string-box (^symtostr (^symbol-unbox arg1)))))))

;;TODO: ("##keyword->string"              (1)   #f ()    0    string  extended)

;;TODO: ("##closure-length"               (1)   #f ()    0    fixnum  extended)
;;TODO: ("##closure-code"                 (1)   #f ()    0    #f      extended)
;;TODO: ("##closure-ref"                  (2)   #f ()    0    (#f)    extended)
;;TODO: ("##closure-set!"                 (3)   #t ()    0    #f      extended)

;;TODO: ("##subprocedure-id"              (1)   #f ()    0    #f      extended)
;;TODO: ("##subprocedure-parent"          (1)   #f ()    0    #f      extended)

;;TODO: ("##procedure-info"               (1)   #f ()    0    #f      extended)

;;TODO: ("##make-promise"                 (1)   #f 0     0    (#f)    extended)
;;TODO: ("##force"                        (1)   #t 0     0    #f      extended)

;;TODO: ("##void"                         (0)   #f ()    0    #f      extended)

;;TODO: ("current-thread"                 (0)   #f ()    0    #f      extended)
;;TODO: ("##current-thread"               (0)   #f ()    0    #f      extended)
;;TODO: ("##run-queue"                    (0)   #f ()    0    #f      extended)

;;TODO: ("##thread-save!"                 1     #t ()    1113 (#f)    extended)
;;TODO: ("##thread-restore!"              2     #t ()    2203 #f      extended)

;;TODO: ("##continuation-capture"         1     #t ()    1113 (#f)    extended)
;;TODO: ("##continuation-graft"           2     #t ()    2203 #f      extended)
;;TODO: ("##continuation-graft-no-winding" 2     #t ()    2203 #f      extended)
;;TODO: ("##continuation-return"           (2)   #t ()    0    #f      extended)
;;TODO: ("##continuation-return-no-winding"(2)   #t ()    0    #f      extended)

;;TODO: ("##apply"                         (2)   #t ()    0    (#f)    extended)
;;TODO: ("##call-with-current-continuation"1     #t ()    1113 (#f)    extended)
;;TODO: ("##make-global-var"               (1)   #t ()    0    #f      extended)
;;TODO: ("##global-var-ref"                (1)   #f ()    0    (#f)    extended)
;;TODO: ("##global-var-primitive-ref"      (1)   #f ()    0    (#f)    extended)
;;TODO: ("##global-var-set!"               (2)   #t ()    0    #f      extended)
;;TODO: ("##global-var-primitive-set!"     (2)   #t ()    0    #f      extended)

;;TODO: ("##first-argument"                1     #f ()    0    (#f)    extended)
;;TODO: ("##check-heap-limit"              (0)   #t ()    0    (#f)    extended)

;;TODO: ("##quasi-append"                  0     #f 0     0    list    extended)
;;TODO: ("##quasi-list"                    0     #f ()    0    list    extended)
;;TODO: ("##quasi-cons"                    (2)   #f ()    0    pair    extended)
;;TODO: ("##quasi-list->vector"            (1)   #f 0     0    vector  extended)
;;TODO: ("##quasi-vector"                  0     #f ()    0    vector  extended)
;;TODO: ("##case-memv"                     (2)   #f 0     0    list    extended)

;;TODO: ("##bignum.negative?"              (1)   #f ()    0    boolean extended)
;;TODO: ("##bignum.adigit-length"          (1)   #f ()    0    integer extended)
;;TODO: ("##bignum.adigit-inc!"            (2)   #t ()    0    integer extended)
;;TODO: ("##bignum.adigit-dec!"            (2)   #t ()    0    integer extended)
;;TODO: ("##bignum.adigit-add!"            (5)   #t ()    0    integer extended)
;;TODO: ("##bignum.adigit-sub!"            (5)   #t ()    0    integer extended)
;;TODO: ("##bignum.mdigit-length"          (1)   #f ()    0    integer extended)
;;TODO: ("##bignum.mdigit-ref"             (2)   #f ()    0    integer extended)
;;TODO: ("##bignum.mdigit-set!"            (3)   #t ()    0    #f      extended)
;;TODO: ("##bignum.mdigit-mul!"            (6)   #t ()    0    integer extended)
;;TODO: ("##bignum.mdigit-div!"            (6)   #t ()    0    integer extended)
;;TODO: ("##bignum.mdigit-quotient"        (3)   #f ()    0    integer extended)
;;TODO: ("##bignum.mdigit-remainder"       (4)   #f ()    0    integer extended)
;;TODO: ("##bignum.mdigit-test?"           (4)   #f ()    0    boolean extended)

;;TODO: ("##bignum.adigit-ones?"           (2)   #f ()    0    boolean extended)
;;TODO: ("##bignum.adigit-zero?"           (2)   #f ()    0    boolean extended)
;;TODO: ("##bignum.adigit-negative?"       (2)   #f ()    0    boolean extended)
;;TODO: ("##bignum.adigit-="               (3)   #f ()    0    boolean extended)
;;TODO: ("##bignum.adigit-<"               (3)   #f ()    0    boolean extended)
;;TODO: ("##bignum.->fixnum"               (1)   #f ()    0    integer extended)
;;TODO: ("##bignum.<-fixnum"               (1)   #f ()    0    integer extended)
;;TODO: ("##bignum.adigit-shrink!"         (2)   #t ()    0    #f      extended)
;;TODO: ("##bignum.adigit-copy!"           (4)   #t ()    0    #f      extended)
;;TODO: ("##bignum.adigit-cat!"            (7)   #t ()    0    #f      extended)
;;TODO: ("##bignum.adigit-bitwise-and!"    (4)   #t ()    0    #f      extended)
;;TODO: ("##bignum.adigit-bitwise-ior!"    (4)   #t ()    0    #f      extended)
;;TODO: ("##bignum.adigit-bitwise-xor!"    (4)   #t ()    0    #f      extended)
;;TODO: ("##bignum.adigit-bitwise-not!"    (2)   #t ()    0    #f      extended)

;;TODO: ("##bignum.fdigit-length"          (1)   #f ()    0    integer extended)
;;TODO: ("##bignum.fdigit-ref"             (2)   #f ()    0    integer extended)
;;TODO: ("##bignum.fdigit-set!"            (3)   #t ()    0    #f      extended)

;;----------------------------------------------------------------------------

;;TODO: clean up and integrate to above

(univ-define-prim "##inline-host-statement" #f

  (lambda (ctx return opnds)
    (if (and (= (length opnds) 1)
             (obj? (car opnds))
             (string? (obj-val (car opnds))))
        (^ (obj-val (car opnds))
           (return #f))
        (compiler-internal-error "##inline-host-statement requires a constant string argument"))))

(univ-define-prim "##inline-host-expression" #f

  (lambda (ctx return opnds)
    (if (and (= (length opnds) 1)
             (obj? (car opnds))
             (string? (obj-val (car opnds))))
        (return (obj-val (car opnds)))
        (compiler-internal-error "##inline-host-expression requires a constant string argument"))))

#|
;;(univ-define-prim "string-append" #f (lambda (ctx return opnds) (return (^))))

(univ-define-prim "list->string" #f

  (lambda (ctx return opnds)
    (return
     (case (target-name (ctx-target ctx))

       ((js)
        (^ "new "
           (univ-emit-apply ctx
                            (^prefix "String.listToString")
                            (list (^getopnd (list-ref opnds 0))))))

       ((python ruby php)               ;TODO: complete
        (^))

       (else
        (compiler-internal-error
         "list->string, unknown target"))))))

(univ-define-prim "symbol->string" #f

  (lambda (ctx return opnds)
    (return
     (case (target-name (ctx-target ctx))

       ((js)
        (^ (^getopnd (list-ref opnds 0))
           ".symbolToString()"))

       ((python ruby php)               ;TODO: complete
        (^))

       (else
        (compiler-internal-error
         "symbol->string, unknown target"))))))

(univ-define-prim "string->symbol" #f

  (lambda (ctx return opnds)
    (return
     (case (target-name (ctx-target ctx))

       ((js)
        (^ (^prefix "Symbol.stringToSymbol")
           "("
           (^getopnd (list-ref opnds 0))
           ")"))

       ((python ruby php)               ;TODO: complete
        (^))

       (else
        (compiler-internal-error
         "string->symbol, unknown target"))))))

(univ-define-prim "string->list" #f

  (lambda (ctx return opnds)
    (return
     (case (target-name (ctx-target ctx))

       ((js)
        (^ (^prefix "String.stringToList")
           "("
           (^getopnd (list-ref opnds 0))
           ")"))

       ((python ruby php)               ;TODO: complete
        (^))

       (else
        (compiler-internal-error
         "string->list, unknown target"))))))

(univ-define-prim "string-append" #f

  (lambda (ctx return opnds)
    (return
     (case (target-name (ctx-target ctx))

       ((js)
        (^ (univ-emit-apply ctx
                            (^prefix "stringappend")
                            (map (lambda (opnd) (^getopnd opnd))
                                 opnds)
                            )))

       ((python ruby php)               ;TODO: complete
        (^))

       (else
        (compiler-internal-error
         "string-append, unknown target"))))))

(univ-define-prim "number->string" #f

  (lambda (ctx return opnds)
    (return
     (case (target-name (ctx-target ctx))

       ((js)
        (^ (^prefix "String.jsstringToString")
           "(("
           (^getopnd (list-ref opnds 0))
           ").toString())"))

       ((python ruby php)               ;TODO: complete
        (^))

       (else
        (compiler-internal-error
         "number->string, unknown target"))))))


(univ-define-prim-bool "##char?" #t

  (lambda (ctx return opnds)
    (return
     (case (target-name (ctx-target ctx))

       ((js php)
        (^ (^getopnd (list-ref opnds 0))
           " instanceof "
           (^prefix "Char")))

       ((python)
        (^ "isinstance("
           (^getopnd (list-ref opnds 0))
           ", "
           (^prefix "Char")
           ")"))

       ((ruby)
        (^ (^getopnd (list-ref opnds 0))
           ".class == "
           (^prefix "Char")))

       (else
        (compiler-internal-error
         "##char?, unknown target"))))))

(univ-define-prim-bool "##number?" #t

  (lambda (ctx return opnds)
    (return
     (case (target-name (ctx-target ctx))

       ((js php)
        (^ "typeof("
           (^getopnd (list-ref opnds 0))
           ") == \"number\""))

       ((python ruby php)
        (^))

       (else
        (compiler-internal-error
         "##number?, unknown target"))))))

(univ-define-prim-bool "##symbol?" #t

  (lambda (ctx return opnds)
    (return
     (case (target-name (ctx-target ctx))

       ((js php)
        (^ (^getopnd (list-ref opnds 0))
           " instanceof "
           (^prefix "Symbol")))

       ((python)
        (^ "isinstance("
           (^getopnd (list-ref opnds 0))
           ", "
           (^prefix "Symbol")
           ")"))

       ((ruby)
        (^ (^getopnd (list-ref opnds 0))
           ".class == "
           (^prefix "Symbol")))
       ((php)
        (^))

       (else
        (compiler-internal-error
         "##symbol?, unknown target"))))))

(univ-define-prim-bool "##mem-allocated?" #t

  (lambda (ctx return opnds)
    (return
     (case (target-name (ctx-target ctx))

       ((js)
        (^ "true"))

       ((python ruby php)
        (^))

       (else
        (compiler-internal-error
         "##mem-allocated?, unknown target"))))))

(univ-define-prim "##subtype" #t

  (lambda (ctx return opnds)
    (return
     (case (target-name (ctx-target ctx))

       ((js python ruby js)
        (^ "1"))

       (else
        (compiler-internal-error
         "##subtype, unknown target"))))))
|#

(define univ-tag-bits 2)
(define univ-word-bits 32)

(univ-define-prim "##continuation-capture" #f

  #f
  #f

  (lambda (ctx nb-args poll? safe? fs)
    (univ-jump-inline ctx
                      nb-args
                      1
                      4
                      poll?
                      safe?
                      fs
                      "continuation_capture")))

(univ-define-prim "##continuation-graft-no-winding" #f

  #f
  #f

  (lambda (ctx nb-args poll? safe? fs)
    (univ-jump-inline ctx
                      nb-args
                      2
                      6
                      poll?
                      safe?
                      fs
                      "continuation_graft_no_winding")))

(univ-define-prim "##continuation-return-no-winding" #f

  #f
  #f

  (lambda (ctx nb-args poll? safe? fs)
    (univ-jump-inline ctx
                      nb-args
                      2
                      2
                      poll?
                      safe?
                      fs
                      "continuation_return_no_winding")))

(define (univ-jump-inline ctx nb-args min-args max-args poll? safe? fs name)
  (and (>= nb-args min-args)
       (<= nb-args max-args)
       (with-stack-pointer-adjust
        ctx
        (+ fs
           (ctx-stack-base-offset ctx))
        (lambda (ctx)
          (univ-emit-return-poll
           ctx
           (^ (^prefix
               (string-append name
                              (number->string nb-args)))
              "()")
           poll?
           #t)))))

;;;============================================================================
