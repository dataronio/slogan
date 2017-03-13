;; Copyright (C) 2013-2017 by Vijay Mathew Pandyalakal <vijay.the.lisper@gmail.com>

;; Rebind fundamental Scheme functions used in the implementation of the
;; Slogan compiler to new names here, so a Slogan program can freely reuse these
;; names for variables.
;; Use only these new names in the implementation of Slogan compiler and interpreter.
(define scm-car car)
(define scm-cdr cdr)
(define scm-cons cons)
(define scm-caar caar)
(define scm-cdar cdar)
(define scm-cadr cadr)
(define scm-cddr cddr)
(define scm-caddr caddr)
(define scm-cadddr cadddr)
(define scm-cadar cadar)
(define scm-cdadr cdadr)
(define scm-list list)
(define scm-length length)
(define scm-reverse reverse)
(define scm-memq memq)
(define scm-member member)
(define scm-assoc assoc)
(define scm-assq assq)
(define scm-append append)
(define scm-eq? eq?)
(define scm-vector vector)
(define scm-f32vector f32vector)
(define scm-f64vector f64vector)
(define scm-u64vector u64vector)
(define scm-s64vector s64vector)
(define scm-u32vector u32vector)
(define scm-s32vector s32vector)
(define scm-u16vector u16vector)
(define scm-s16vector s16vector)
(define scm-s8vector s8vector)
(define scm-u8vector u8vector)
(define scm-read read)
(define scm-write write)
(define scm-display display)
(define scm-newline newline)
(define scm-print print)
(define scm-println println)
(define scm-exit exit)
(define scm-map map)
(define scm-apply apply)
(define scm-eval eval)
(define scm-not not)
(define scm-load load)
(define scm-quotient quotient)
(define scm-remainder remainder)

(define (identity x) x)
(define scm-identity identity)
(define scm-force force)

;; These reactive-variable releated functions and set! in task.slgn.scm.
(define scm-rvar #f)
(define scm-rbind #f)
(define scm-rget #f)

(define scm-string string)
(define scm-substring substring)
(define scm-floor floor)

(define scm-error error)
(define scm-raise raise)
(define scm-modulo modulo)
(define scm-log log)
(define scm-truncate truncate)
