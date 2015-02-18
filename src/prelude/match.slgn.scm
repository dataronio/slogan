;; Copyright (c) 2013-2014 by Vijay Mathew Pandyalakal, All Rights Reserved.

(define-structure record-pattern name members)

(define (normalize-list-for-matching lst)
  (if (and (list? lst)
           (not (null? lst)))
      (if (eq? (car lst) 'list)
          (cdr lst)
          (list->record-pattern lst))
      lst))

(define (list->record-pattern lst)
  (if (symbol? (car lst))
      (let ((name (symbol->string (car lst))))
        (if (char=? #\+ (string-ref name 0))
            (let loop ((name (substring name 1 (string-length name)))
                       (lst (cdr lst))
                       (members '()))
              (cond ((null? lst)
                     (make-record-pattern name (reverse members)))
                    (else 
                     (if (keyword? (car lst))
                         (loop name (cddr lst)
                               (cons (cons (keyword->string (car lst)) (cadr lst)) members))
                         (loop name (cdr lst)
                               (cons (car lst) members))))))
            lst))
      lst))

(define (cons? pattern)
  (and (list? pattern)
       (eq? (car pattern) 'cons)))

(define-structure pattern-vars bindings)

(define (match-pattern pattern consequent)
  (let ((bindings (make-pattern-vars '())))
    `(if (unbound? *result*)
         (begin
           ,(if (eq? pattern 'else)
                `(set! *match-found* #t)
                (match-pattern-helper pattern bindings))
           (set! *result* (if *match-found* 
                              ,(if (not (null? (pattern-vars-bindings bindings)))
                                   `(let ,(pattern-vars-bindings bindings)
                                      ,(expand-consequent pattern consequent))
                                   (expand-consequent pattern consequent))
                              '*unbound*))))))

(define (vector-pattern? fname)
  (or (eq? fname 'vector)
      (eq? fname 'u8vector)
      (eq? fname 's8vector)
      (eq? fname 'bit_array)))

(define (vector-test-fn fname)
  (case fname
    ((vector) 'vector?)
    ((u8vector) 'u8vector?)
    ((s8vector) 's8vector?)
    ((bit_array) 'is_bit_array)
    (else (error "Invalid vector constructor." fname))))

(define (vector-len-fn fname)
  (case fname
    ((vector) 'vector-length)
    ((u8vector) 'u8vector-length)
    ((s8vector) 's8vector-length)
    ((bit_array) 'bit_array_length)
    (else (error "Invalid vector constructor." fname))))

(define (vector-to-list-fn fname)
    (case fname
    ((vector) 'vector->list)
    ((u8vector) 'u8vector->list)
    ((s8vector) 's8vector->list)
    ((bit_array) 'bit_array_to_list)
    (else (error "Invalid vector constructor." fname))))

(define (match-pattern-helper pattern bindings)
  (set! pattern (normalize-list-for-matching pattern))
  (cond ((null? pattern)
         `(if (null? *value*)
              (set! *match-found* #t)
              (set! *match-found* #f)))
        ((cons? pattern)
         (set! pattern (cdr pattern))
         `(if (pair? *value*)
              (begin (let ((*value* (first *value*)))
                       ,(match-pattern-helper (car pattern) bindings))
                     (if *match-found*
                         (let ((*value* (rest *value*)))
                           ,(match-pattern-helper (cadr pattern) bindings))))
              (set! *match-found* #f)))
        ((list? pattern)
         (if (eq? (car pattern) 'quote)
             `(if (equal? ,pattern *value*)
                  (set! *match-found* #t)
                  (set! *match-found* #f))
             (if (vector-pattern? (car pattern))
                 (match-vector-pattern (car pattern) (cdr pattern) bindings)
                 (let ((pattern-length (length pattern)))
                   `(if (and (list? *value*)
                             (= ,pattern-length (length *value*)))
                        (begin (let ((*value* (first *value*)))
                                 ,(match-pattern-helper (car pattern) bindings))
                               (if *match-found*
                                   (let ((*value* (rest *value*)))
                                     ,(match-pattern-helper (cdr pattern) bindings))))
                        (set! *match-found* #f))))))
        ((record-pattern? pattern)
         (match-record-pattern pattern))
        ((symbol? pattern)
         (if (not (eq? pattern '_))
             (pattern-vars-bindings-set! bindings (cons (list pattern #f) (pattern-vars-bindings bindings))))
         `(set! *match-found* #t))
        (else `(if (equal? ,pattern *value*)
                   (set! *match-found* #t)
                   (set! *match-found* #f)))))

(define (match-vector-pattern fname pattern bindings)
  (let ((pattern-length (length pattern)))
    `(if (and (,(vector-test-fn fname) *value*)
              (= ,pattern-length (,(vector-len-fn fname) *value*)))
         (begin (let ((*value* (,(vector-to-list-fn fname) *value*)))
                  (set! *conv-value* *value*)
                  (let ((*value* (car *value*)))
                    ,(match-pattern-helper (car pattern) bindings))
                  (if *match-found*
                      (let ((*value* (cdr *value*)))
                        ,(match-pattern-helper (cdr pattern) bindings)))))
         (set! *match-found* #f))))

(define (match-record-pattern pattern)
  (let ((predic (string->symbol (string-append (record-pattern-name pattern) "?"))))
    (let ((prefix `(if (,predic *value*))))
      (let loop ((members (record-pattern-members pattern))
                 (conds '()))
        (cond ((null? members)
               (let ((body '(set! *match-found* #t)))
                 (append prefix (list (if (null? conds) 
                                          `(if #t ,body)
                                          `(if (and ,@(reverse conds)) 
                                               ,body 
                                               (set! *match-found* #f)))))))
              ((symbol? (car members))
               (loop (cdr members) conds))
              ((pair? (car members))
               (let ((accessor (string->symbol (string-append (record-pattern-name pattern)
                                                              "-" (caar members)))))
                 (loop (cdr members) (cons `(equal? ,(cdar members) (,accessor *value*)) conds))))
              (else
               (error "Invalid record pattern: " pattern)))))))

(define (expand-vector-consequent pattern consequent)
  `(let* ((*value* *conv-value*)
          (*rest* (cdr *value*)))
     (set! *value* (car *value*))
     ,(expand-consequent (car pattern) #f)
     (set! *value* *rest*)
     ,(expand-consequent (cdr pattern) consequent)))

(define (expand-consequent pattern consequent)
  (set! pattern (normalize-list-for-matching pattern))
  (cond ((or (null? pattern) (eq? pattern 'else))
         consequent)
        ((cons? pattern)
         (set! pattern (cdr pattern))
         `(let ((*rest* (rest *value*)))
            (set! *value* (first *value*))
            ,(expand-consequent (car pattern) #f)
            (set! *value* *rest*)
            ,(expand-consequent (cadr pattern) consequent)))
        ((list? pattern)
         (if (eq? (car pattern) 'quote)
             consequent
             (if (vector-pattern? (car pattern))
                 (expand-vector-consequent (cdr pattern) consequent)
                 `(let ((*rest* (rest *value*)))
                    (set! *value* (first *value*))
                    ,(expand-consequent (car pattern) #f)
                    (set! *value* *rest*)
                    ,(expand-consequent (cdr pattern) consequent)))))
        ((record-pattern? pattern)
         (expand-rec-consequent pattern consequent))
        ((symbol? pattern)
         (if (eq? pattern '_)
             consequent
             `(begin (set! ,pattern *value*)
                     ,consequent)))
        (else consequent)))

(define (expand-rec-consequent pattern consequent)
  (let loop ((members (record-pattern-members pattern))
             (i 0)
             (bindings '()))
    (cond ((null? members)
           (if (null? bindings)
               consequent
               (append `(let ,(reverse bindings) ,consequent))))
          ((symbol? (car members))
           (if (eq? (car members) '_)
               (loop (cdr members) (+ i 1) bindings)
               (let ((accessor (string->symbol (string-append (record-pattern-name pattern)
                                                              "-" (number->string i)))))
                 (loop (cdr members) (+ i 1) (cons `(,(car members) (,accessor *value*)) bindings)))))
          (else (loop (cdr members) (+ i 1) bindings)))))
