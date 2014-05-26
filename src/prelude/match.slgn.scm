(define (normalize-list-for-matching lst)
  (if (and (list? lst)
           (not (null? lst)))
      (if (eq? (car lst) 'list)
          (cdr lst)
          (list->record-pattern lst))
      lst))

(define-structure record-pattern name members)

(define (list->record-pattern lst)
  (let ((name (symbol->string (car lst))))
    (let loop ((lst (cdr lst))
               (members '()))
      (cond ((null? lst)
             (make-record-pattern name (reverse members)))
            (else 
	     (if (keyword? (car lst))
		 (loop (cddr lst)
		       (cons (cons (keyword->string (car lst)) (cadr lst)) members))
		 (loop (cdr lst)
		       (cons (car lst) members))))))))

(define (match-pattern pattern value consequent tokenizer)
  (set! pattern (normalize-list-for-matching pattern))
  `((match? ',pattern ,value) (eval (bind-pattern-vars 
                                     ',pattern 
                                     ,value
                                     ',consequent))))

(define (normalize-list-pattern pattern)
  (if (and (list? pattern)
           (not (null? pattern)))
      (if (eq? (car pattern) 'list)
          (set! pattern (cdr pattern))))
  pattern)

(define (bind-pattern-vars pattern value body)
  (set! pattern (normalize-list-pattern pattern))
  (cond ((or (null? pattern) 
             (null? value))
         body)
        ((and (symbol? pattern)
              (not (slgn-symbol? pattern))
              (not (eq? pattern '_)))
         `(let ((,pattern ,value)) ,body))
        ((list? pattern)
         (if (eq? (car pattern) '__)
             `(let ((,(cadr pattern) ,(cdr value))) ,body)
             (bind-pattern-vars (car pattern)
                                (car value)
                                (bind-pattern-vars (cdr pattern)
                                                   (cdr value)
                                                   body))))
	((record-pattern? pattern)
	 (bind-record-pattern-vars (record-pattern-name pattern)
				   (record-pattern-members pattern)
				   value body))
        (else body)))

(define (bind-record-pattern-vars name members value body)
  (cond ((null? members)
	 body)
	((list? members)
	 (bind-record-pattern-vars 
	  name (car members) value
	  (bind-record-pattern-vars 
	   name (cdr members) value body)))
	(else (if (and (not (pair? members))
		       (not (eq? members '_)))
		  (let ((accessor (string->symbol (string-append 
						   name "-" 
						   (symbol->string members)))))
		    (let ((v ((eval accessor) value)))
		      `(let ((,members ,v)) ,body)))
		  body))))

(define (match? pattern value)
  (set! pattern (normalize-list-pattern pattern))
  (cond ((symbol? pattern) #t)
        ((and (null? pattern) (null? value)) #t)
        ((and (list? pattern) (list? value))
         (cond ((= (length pattern) (length value))
                (and (match? (car pattern) (car value))
                     (match? (cdr pattern) (cdr value))))
               ((eq? (car pattern) '__)
                (match? (cadr pattern) value))
               (else #f)))
        ((record-pattern? pattern)
         (match-record-pattern? pattern value))
        (else (equal? pattern value))))

(define (match-record-pattern? pattern value)
  (let ((predic (eval (string->symbol (string-append (record-pattern-name pattern) "?")))))
    (cond ((predic value)
           (let loop ((members (record-pattern-members pattern)))
             (if (null? members)
                 #t
		 (if (pair? (car members))
                     (let ((afn (eval (string->symbol (string-append 
                                                       (record-pattern-name pattern) 
                                                       "-" 
                                                       (car (car members)))))))
                       (if (equal? (cdr (car members)) (afn value))
                           (loop (cdr members))
                           #f))
		     (loop (cdr members))))))
           (else #f))))
