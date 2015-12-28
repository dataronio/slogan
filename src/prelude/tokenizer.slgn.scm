;; Copyright (c) 2013-2016 by Vijay Mathew Pandyalakal, All Rights Reserved.

(define-structure port-pos port line col)

(define (port-pos-read-char! pp)
  (let ((c (read-char (port-pos-port pp))))
    (cond ((and (char? c) (char=? c #\newline))
           (port-pos-line-set! pp (+ 1 (port-pos-line pp)))
           (port-pos-col-set! pp 0))
          (else
           (port-pos-col-set! pp (+ 1 (port-pos-col pp)))))
    c))

(define (port-pos-peek-char port) (peek-char (port-pos-port port)))

(define (make-tokenizer port program-text 
                        #!key (compile-mode #f))
  (let ((current-token #f)
        (program-text (if (string? program-text)
                          (string_split program-text #\newline #t)
                          '()))
        (port (make-port-pos port 1 0))
        (pattern-mode #f)
	(quote-mode 0)
	(macro-mode #f)
        (radix 10)
        (lookahead-stack '()))
    (lambda (msg . args)
      (case msg
        ((peek) 
         (if (not current-token)
             (if (= 0 (length lookahead-stack))
                 (set! current-token (next-token port))
                 (begin (set! current-token (car lookahead-stack))
                        (set! lookahead-stack (cdr lookahead-stack)))))
         current-token)
        ((next)
         (if (not current-token)
             (if (= 0 (length lookahead-stack))
                 (next-token port)
                 (let ((tmp (car lookahead-stack)))
                   (set! lookahead-stack (cdr lookahead-stack))
                   tmp))
             (let ((tmp current-token))
               (set! current-token #f)
               tmp)))
        ((get) current-token)
        ((put)
         (if current-token
             (begin (set! lookahead-stack (cons current-token lookahead-stack))
                    (set! current-token #f)))
         (set! lookahead-stack (cons (car args) lookahead-stack)))
        ((has-more?) (char-ready? (port-pos-port port)))
	((get-port) (port-pos-port port))
        ((line) (port-pos-line port))
        ((column) (port-pos-col port))
        ((compile-mode?) compile-mode)
        ((pattern-mode-on) (set! pattern-mode #t))
        ((pattern-mode-off) (set! pattern-mode #f))
        ((pattern-mode?) pattern-mode)
	((quote-mode-on) (set! quote-mode (+ quote-mode 1)))
	((quote-mode-off) (if (not (zero? quote-mode)) 
                              (set! quote-mode (- quote-mode 1))))
	((quote-mode?) (not (zero? quote-mode)))
	((macro-mode-on) (set! macro-mode #t))
	((macro-mode-off) (set! macro-mode #f))
	((macro-mode?) macro-mode)
        ((program-text) program-text)
        ((port-pos) port)
        (else (error "tokenizer received unknown message: " msg))))))

(define (next-token port)
  (let ((c (port-pos-peek-char port)))
    (if (eof-object? c)
        c
        (let ((opr (single-char-operator? c)))
          (if opr (begin (port-pos-read-char! port)
                         (if (and (char-comment-start? c) 
                                  (char-comment-part? (port-pos-peek-char port)))
                             (begin (skip-comment port)
                                    (next-token port))
                             (cdr opr)))
              (cond ((char-whitespace? c)
                     (skip-whitespace port)
                     (next-token port))
                    ((char-numeric? c)
                     (if (char=? c #\0)
                         (begin (port-pos-read-char! port)
                                (read-number-with-radix-prefix port))
                         (read-number port #f)))
                    ((multi-char-operator? c)
                     (read-multi-char-operator port))
                    ((char=? c #\")
                     (read-string port))
		    ((char=? c #\')
		     (port-pos-read-character port))
                    ((char=? c #\.)
                     (port-pos-read-char! port)
                     (if (char-numeric? (port-pos-peek-char port))
                         (read-number port #\.)
                         '*period*))
                    (else (read-name port))))))))

(define *single-char-operators* (list (cons #\+ '*plus*)
                                      (cons #\/ '*backslash*)
                                      (cons #\* '*asterisk*)
                                      (cons #\( '*open-paren*)
                                      (cons #\) '*close-paren*)
                                      (cons #\{ '*open-brace*)
                                      (cons #\} '*close-brace*)
                                      (cons #\[ '*open-bracket*)
                                      (cons #\] '*close-bracket*)
                                      (cons #\# '*hash*)
                                      (cons #\! '*quote*)
                                      (cons #\, '*comma*)
                                      (cons #\: '*colon*)                                      
                                      (cons #\; '*semicolon*)))

(define *single-char-operators-strings* (list (cons "+" '*plus*)
                                              (cons "/" '*backslash*)
                                              (cons "*" '*asterisk*)
                                              (cons "(" '*open-paren*)
                                              (cons ")" '*close-paren*)
                                              (cons "{" '*open-brace*)
                                              (cons "}" '*close-brace*)
                                              (cons "[" '*open-bracket*)
                                              (cons "]" '*close-bracket*)
                                              (cons "#" '*hash*)
                                              (cons "!" '*quote*)
                                              (cons "," '*comma*)
                                              (cons ":" '*colon*)                                      
                                              (cons ";" '*semicolon*)))

(define *multi-char-operators-strings* (list (cons "==" '*equals*)
                                             (cons ">" '*greater-than*)
                                             (cons "<" '*less-than*)
                                             (cons ">=" '*greater-than-equals*)
                                             (cons "<=" '*less-than-equals*)
                                             (cons "&&" '*and*)
                                             (cons "||" '*or*)
                                             (cons "!!" '*unquote*)
                                             (cons "->" '*inserter*)
                                             (cons "<-" '*extractor*)))

(define *special-operators-strings* (list (cons "=" '*assignment*)
                                          (cons "." '*period*)
                                          (cons "-" '*minus*)
                                          (cons "%" '*quasiquote*)
                                          (cons "|" '*pipe*)))

(define (math-operator? sym)
  (or (eq? sym '*plus*)
      (eq? sym '*minus*)
      (eq? sym '*backslash*)
      (eq? sym '*asterisk*)))

(define (single-char-operator? c)
  (and (char? c) (assoc c *single-char-operators*)))

(define (multi-char-operator? c)
  (and (char? c)
       (or (char=? c #\=)
           (char=? c #\<)
           (char=? c #\>)
           (char=? c #\&)
           (char=? c #\-)
           (char=? c #\%)
           (char=? c #\|))))

(define (fetch-operator-string token strs)
  (let loop ((oprs strs))
    (cond ((null? oprs)
           #f)
          ((eq? token (cdar oprs))
           (caar oprs))
          (else (loop (cdr oprs))))))

(define (fetch-single-char-operator-string token)
  (fetch-operator-string token *single-char-operators-strings*))

(define (fetch-multi-char-operator-string token)
  (fetch-operator-string *multi-char-operators-strings*))

(define (fetch-less-than-operator port)
  (let ((c (port-pos-peek-char port)))
    (cond ((char=? c #\=) 
           (port-pos-read-char! port)
           '*less-than-equals*)
          ((char=? c #\-)
           (port-pos-read-char! port)
           '*extractor*)
          (else '*less-than*))))

(define (fetch-operator port 
                        suffix
                        suffix-opr
                        opr)
  (port-pos-read-char! port)
  (if (eq? opr '*less-than*)
      (fetch-less-than-operator port)
      (if (char=? (port-pos-peek-char port) suffix)
          (begin (port-pos-read-char! port)
                 suffix-opr)
          opr)))

(define (tokenizer-error msg #!rest args)
  (error (with-output-to-string 
           '()
           (lambda ()
             (slgn-display msg display-string: #t)
             (let loop ((args args))
               (if (not (null? args))
                   (begin (slgn-display (car args) display-string: #t)
                          (display " ")
                          (loop (cdr args)))))))))

(define (fetch-same-operator port c opr)
  (port-pos-read-char! port)
  (let ((next (port-pos-peek-char port)))
    (cond ((char=? next c)
           (port-pos-read-char! port)
           opr)
          ((eq? opr '*or*)
           '*pipe*)
          ((eq? opr '*unquote*)
           '*quasiquote*)
          (else
           (tokenizer-error 
            "invalid character in operator. expected - "
            c " - found - " next)))))

(define (read-multi-char-operator port)
  (let ((c (port-pos-peek-char port)))
    (cond ((char=? c #\=)
           (fetch-operator port #\= '*equals* '*assignment*))
          ((char=? c #\<)
           (fetch-operator port #\= '*less-than-equals* '*less-than*))
          ((char=? c #\>)
           (fetch-operator port #\= '*greater-than-equals* '*greater-than*))
	  ((or (char=? c #\&)
	       (char=? c #\|)
               (char=? c #\%))
	   (fetch-same-operator port c (cond ((char=? c #\&) '*and*)
                                             ((char=? c #\|) '*or*)
                                             (else '*unquote*))))
          ((char=? c #\-)
           (fetch-operator port #\> '*inserter* '*minus*))
          (else
           (tokenizer-error "expected a valid operator. unexpected character: " (port-pos-read-char! port))))))

(define (numeric-string->number s #!optional (radix 10))
  (string->number (list->string (filter (lambda (c) (not (char=? c #\_))) (string->list s))) radix))

(define (read-number port prefix #!optional (radix 10))
  (let loop ((c (port-pos-peek-char port))
             (prev-c #\space)
             (result (if prefix (list prefix) '())))
    (if (char-valid-in-number? c prev-c)
        (begin (port-pos-read-char! port)
               (loop (port-pos-peek-char port) c
                     (cons c result)))
        (let ((n (numeric-string->number (list->string (reverse result)) radix)))
          (if n n
              (tokenizer-error "read-number failed. invalid number format."))))))

(define (prec-prefix? c)
  (and (string? c)
       (or (string=? c "#e")
           (string=? c "#i"))))

(define (radix-prefix? c)
  (if (char? c)
      (let ((c (char-downcase c)))
        (cond ((char=? c #\x) "#x")
              ((char=? c #\b) "#b")
              ((char=? c #\o) "#o")
              ((char=? c #\d) "#d")
              ((char=? c #\e) "#e")
              ((char=? c #\i) "#i")
              (else #f)))
      #f))
  
(define (read-number-with-radix-prefix port #!optional (radix 10))
  (let ((radix-prefix (radix-prefix? (port-pos-peek-char port))))
    (if (not radix-prefix)
	(read-number port #\0 radix)
        (let ((c (port-pos-read-char! port))
              (result '()))
          (if (and (prec-prefix? radix-prefix)
                   (char=? (port-pos-peek-char port) #\0))
              (begin (port-pos-read-char! port)
                     (let ((radix-prefix2 (radix-prefix? (port-pos-peek-char port))))
                       (if radix-prefix2 
                           (begin (set! radix-prefix (string-append radix-prefix radix-prefix2))
                                  (port-pos-read-char! port))
                           (set! result '(#\0))))))
          (let loop ((c (port-pos-peek-char port))
                     (prev-c c)
                     (result result))
            (if (or (char-valid-in-number? c prev-c)
                    (char-hex-alpha? c))
                (begin (port-pos-read-char! port)
                       (loop (port-pos-peek-char port) c
                             (cons c result)))
                (let ((n (numeric-string->number (string-append radix-prefix (list->string (reverse result))) radix)))
                  (if (not n)
                      (tokenizer-error "read-number-with-radix-prefix failed. invalid number format.")
                      n))))))))

(define (char-valid-in-number? c prev-c)
  (and (char? c)
       (or (char-numeric? c)
           (char=? #\. c)
           (char=? #\_ c)
           (exponent-marker? c)
           (sign-in-number-valid? c prev-c))))

(define (exponent-marker? c)
  (if (char? c)
      (let ((c (char-downcase c)))
        (or (char=? c #\e) (char=? c #\s)
            (char=? c #\f) (char=? c #\d)
            (char=? c #\l)))
      #f))

(define (sign-in-number-valid? c prev-c)
  (if (and (char? prev-c) (char? c))
      (let ((prev-c (char-downcase prev-c)))
        (and (or (char=? #\+ c) 
                 (char=? #\- c))
             (or (exponent-marker? prev-c)
                 (radix-prefix? prev-c))))
      #f))

(define (char-hex-alpha? c)
  (if (char? c)
      (let ((c (char-downcase c)))
        (or (char=? c #\a)
            (char=? c #\b)
            (char=? c #\c)
            (char=? c #\d)
            (char=? c #\e)
            (char=? c #\f)))
      #f))

(define (skip-whitespace port)
  (let loop ((c (port-pos-peek-char port)))
    (if (eof-object? c)
        c
        (if (char-whitespace? c)
            (begin (port-pos-read-char! port)
                   (loop (port-pos-peek-char port)))))))

(define (char-valid-name-start? c)
  (and (char? c) 
       (or (char-alphabetic? c)
           (char=? c #\_)
           (char=? c #\$)
           (char=? c #\?)
           (char=? c #\~)
           (char=? c #\@))))

(define (char-valid-in-name? c)
  (and (char? c) 
       (or (char-valid-name-start? c)
           (char-numeric? c))))

(define (read-name port)
  (cond ((char-valid-name-start? (port-pos-peek-char port))
         (let loop ((c (port-pos-peek-char port))
                    (result '()))
           (if (char-valid-in-name? c)
               (begin (port-pos-read-char! port)
                      (loop (port-pos-peek-char port)
                            (cons c result)))
               (string->symbol (list->string (reverse result))))))
        ((char=? #\` (port-pos-peek-char port))
         (port-pos-read-char! port)
	 (read-sym-with-spaces port))
        (else
         (tokenizer-error "read-name failed at " (port-pos-read-char! port)))))

(define (read-sym-with-spaces port)
  (let loop ((c (port-pos-peek-char port))
	     (chars '()))
    (cond ((char=? c #\`)
	   (port-pos-read-char! port)
	   (if (zero? (length chars))
	       (tokenizer-error "invalid symbol name"))
	   (let ((s (list->string (reverse chars))))
	     (cond ((string=? "&&" s) 'and)
		   ((string=? "||" s) 'or)
		   (else (string->symbol s)))))
	  (else (port-pos-read-char! port)
		(loop (port-pos-peek-char port)
		      (cons c chars))))))

(define (read-string port)
  (let ((c (port-pos-read-char! port)))
    (if (char=? c #\")
        (let loop ((c (port-pos-peek-char port))
                   (result '()))
          (if (char? c)
              (cond ((char=? c #\")
                     (port-pos-read-char! port)
                     (list->string (reverse result)))
                    ((char=? c #\\)
                     (port-pos-read-char! port)
                     (set! c (char->special (port-pos-read-char! port) port))
                     (loop (port-pos-peek-char port) (cons c result)))
                    (else 
                     (set! c (port-pos-read-char! port))
                     (loop (port-pos-peek-char port) (cons c result))))
              (tokenizer-error "string not terminated.")))
        (tokenizer-error "read-string failed at " c))))

(define (char-comment-start? c) (and (char? c) (char=? c #\/)))
(define (char-comment-part? c) (and (char? c)
                                    (or (char-comment-start? c) 
                                        (char=? c #\*))))

(define (skip-comment port)
  (let ((c (port-pos-read-char! port)))
    (if (char-comment-start? c)
        (skip-line-comment port)
        (skip-block-comment port))))

(define (skip-line-comment port)
  (let loop ((c (port-pos-peek-char port)))
    (if (and (char? c)
             (not (char=? c #\newline)))
        (begin (port-pos-read-char! port)
               (loop (port-pos-peek-char port))))))

(define (skip-block-comment port)
  (let loop ((c (port-pos-peek-char port)))
    (if (not (eof-object? c))
        (begin (port-pos-read-char! port)
               (if (char=? c #\*)
                   (if (char=? (port-pos-peek-char port) #\/)
                       (port-pos-read-char! port)
                       (loop (port-pos-peek-char port)))
                   (loop (port-pos-peek-char port)))))))

(define (port-pos-read-character port)
  (if (char=? (port-pos-read-char! port) #\')
      (let ((c (if (char=? (port-pos-peek-char port) #\\)
                   (read-special-character port)
                   (port-pos-read-char! port))))
        (if (not (char=? (port-pos-peek-char port) #\'))
            (if (char=? c #\') 
                #\nul
                (tokenizer-error "invalid character constant."))
            (begin (port-pos-read-char! port)
                   c)))
      (tokenizer-error "not a valid character literal.")))

(define (read-special-character port)
  (port-pos-read-char! port)
  (let ((c (port-pos-read-char! port)))
    (char->special c port)))

(define (read-unicode-literal port num-digits)
  (let loop ((result '())
             (c (port-pos-peek-char port)))
    (if (= (length result) num-digits)
        (eval-unicode-literal (string-append (hexchar-prefix (length result)) (list->string (reverse result))))
        (loop (cons (port-pos-read-char! port) result) (port-pos-peek-char port)))))

(define (eval-unicode-literal s)
  (eval (with-input-from-string s read)))

(define (hexchar-prefix len)
  (cond ((= len 2)
         "#\\x")
        ((= len 4)
         "#\\u")
        ((= len 8)
         "#\\U")
        (else (tokenizer-error "invalid hex encoded character length. " len))))

(define (char->special c port)
  (cond ((char=? c #\n)
         #\newline)
        ((char=? c #\")
         #\")
        ((char=? c #\t)
         #\tab)
        ((char=? c #\r)
         #\return)
        ((char=? c #\\)
         #\\)
        ((char=? c #\b)
         #\backspace)
        ((char=? c #\a)
         #\alarm)
        ((char=? c #\v)
         #\vtab)
        ((char=? c #\e)
         #\esc)
        ((char=? c #\d)
         #\delete)
        ((char=? c #\0)
         #\nul)
        ((char=? c #\u)
         (read-unicode-literal port 4))
        ((char=? c #\x)
         (read-unicode-literal port 2))
        ((char=? c #\U)
         (read-unicode-literal port 8))
        (else (tokenizer-error "invalid escaped character " c))))

(define is_keyword_token reserved-name?)

(define (is_special_token token)
  (let ((cdr-eq? (lambda (p) (eq? token (cdr p)))))
    (or (memp cdr-eq? *special-operators-strings*)
        (memp cdr-eq? *single-char-operators*)
        (memp cdr-eq? *multi-char-operators-strings*))))

(define (special_token_to_string token)
  (let ((cdr-eq? (lambda (p) (eq? token (cdr p)))))
    (find-and-call (lambda (xs) (memp cdr-eq? xs)) 
                   (list *special-operators-strings*
                         *single-char-operators-strings* 
                         *multi-char-operators-strings*)
                   caar
                   (lambda () (error "Not a special token." token)))))

(define (current-token-length tokenizer)
  (let ((token (let ((token (tokenizer 'get)))
                 (cond ((symbol? token)
                        (if (is_special_token token)
                            (special_token_to_string token)
                            (symbol->string token)))
                       ((number? token)
                        (number->string token))
                       ((boolean? token)
                        (if token "true" "false"))
                       (else token)))))
    (if (string? token) (string-length token) 0)))
