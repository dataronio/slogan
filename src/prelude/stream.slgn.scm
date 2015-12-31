;; Copyright (c) 2013-2016 by Vijay Mathew Pandyalakal, All Rights Reserved.

(define-structure text-transcoder codec eol-style error-handling-mode)

(define *supported-codecs* '(ISO_8859_1 
                             ASCII UTF_8 UTF_16 UTF_16LE
                             UTF_16BE UCS_2 UCS_2LE UCS_2BE 
			     UCS_4 UCS_4LE UCS_4BE))

(define (validate-codec codec)
  (if (not (symbol? codec))
      (error "Codec must be a symbol."))
  (if (not (memq (string->symbol (string_upcase (symbol->string codec)))
                 *supported-codecs*))
      (error "Unsupported codec." codec))
  codec)

(define *error-modes* '(replace raise ignore))

(define (validate-error-handling-mode mode)
  (if (memq mode *error-modes*) mode
      (error "Invalid error handling mode." mode)))

(define *eol-styles* '(lf cr crlf))

(define (validate-eol-style eol-style)
  (if (memq eol-style *eol-styles*) eol-style
      (error "Unsupported eol-style." eol-style)))

(define (error-handling-mode->boolean mode) (eq? mode 'replace))

(define (eol-style->encoding eol-style)
  (if (eq? eol-style 'crlf) 'cr-lf
      eol-style))

(define (transcoder codec #!optional (eol-style 'crlf) (error-handling-mode 'ignore))
  (make-text-transcoder (validate-codec codec) (validate-eol-style eol-style) 
                        (validate-error-handling-mode error-handling-mode)))

(define (transcoder_codec t) (text-transcoder-codec t))
(define (transcoder_eol_style t) (text-transcoder-eol-style t))
(define (transcoder_error_handling_mode t) (text-transcoder-error-handling-mode t))

(define (get-stream-option options key #!optional default)
  (if (list? options)
      (if (memq key options) #t
          default)
      default))

(define (get-codec-from-transcoder tcoder)
  (if tcoder (text-transcoder-codec tcoder)
      #f))

(define (get-error-handling-mode-from-transcoder tcoder)
  (if tcoder 
      (let ((em (text-transcoder-error-handling-mode tcoder)))
	(if (eq? em 'ignore) #f
	    (error-handling-mode->boolean em)))
      #f))

(define (get-eol-encoding-from-transcoder tcoder)
  (if tcoder (eol-style->encoding (text-transcoder-eol-style tcoder))
      'cr-lf))

(define (get-buffering-for-stream bmode)
  (if bmode
      (case bmode
        ((block) #t)
        ((none) #f)
        ((line) 'line)
        (else (error "Invalid buffer-mode." bmode)))
      bmode))

(define (replace-underscores sym) (slgn-symbol->scm-sym/kw sym string->symbol))

(define (open-file-stream-helper path direction options buffer-mode tcoder permissions)
  (let ((settings (list path: path direction: direction)))
    (let ((opt (get-stream-option options 'append)))
      (if opt (set! settings (append settings (list append: opt)))))
    (if (not (eq? direction 'input))
        (let ((opt (get-stream-option options 'create)))
          (if opt (set! settings (append settings (list create: #t)))
              (let ((opt (get-stream-option options 'no_create)))
                (if opt (set! settings (append settings (list create: #f)))
                    (let ((opt (get-stream-option options 'maybe_create)))
                      (if opt (set! settings (append settings (list create: 'maybe))))))))))
    (let ((opt (get-stream-option options 'truncate)))
      (if opt (set! settings (append settings (list truncate: opt)))))
    (let ((opt (get-codec-from-transcoder tcoder)))
      (if opt (set! settings (append settings (list char-encoding: (replace-underscores opt))))))
    (let ((opt (get-error-handling-mode-from-transcoder tcoder)))
      (if opt (set! settings (append settings (list char-encoding-errors: opt)))))
    (let ((opt (get-eol-encoding-from-transcoder tcoder)))
      (if opt (set! settings (append settings (list eol-encoding: opt)))))
    (if permissions (set! settings (append settings (list permissions: permissions))))
    (open-file (append settings (list buffering: (get-buffering-for-stream buffer-mode))))))

(define (open_file_input_stream path #!optional options buffer-mode tcoder)
  (open-file-stream-helper path 'input options buffer-mode tcoder #f))

(define (open_file_output_stream path #!optional options buffer-mode tcoder (permissions #o666))
  (open-file-stream-helper path 'output options buffer-mode tcoder permissions))

(define (open_file_input_output_stream path #!optional options buffer-mode tcoder (permissions #o666))
  (open-file-stream-helper path 'input-output options buffer-mode tcoder permissions))

(define current_input_stream current-input-port)
(define current_output_stream current-output-port)
(define current_error_stream current-error-port)

(define (open-byte-stream-helper openfn invalue tcoder)
  (if (not tcoder)
      (openfn invalue)
      (let ((settings (list init: invalue)))
        (let ((opt (get-codec-from-transcoder tcoder)))
          (if opt (set! settings (append settings (list char-encoding: (replace-underscores opt))))))
        (let ((opt (get-error-handling-mode-from-transcoder tcoder)))
          (if opt (set! settings (append settings (list char-encoding-errors: opt)))))
        (let ((opt (get-eol-encoding-from-transcoder tcoder)))
          (if opt (set! settings (append settings (list eol-encoding: opt)))))
        (openfn settings))))

(define (open_byte_array_input_stream byte_array #!optional tcoder)
  (open-byte-stream-helper open-input-u8vector byte_array tcoder))

(define (open_byte_array_output_stream #!optional tcoder)
  (open-byte-stream-helper open-output-u8vector '() tcoder))

(define (open_string_input_stream str)
  (open-byte-stream-helper open-input-string str #f))

(define (open_string_output_stream)
  (open-byte-stream-helper open-output-string '() #f))

(define get_output_string get-output-string)
(define get_output_bytes get-output-u8vector)

(define is_stream port?)
(define is_input_stream input-port?)
(define is_output_stream output-port?)
(define close_stream close-port)
(define close_input_stream close-input-port)
(define close_output_stream close-output-port)

(define (stream_position p)
  (if (input-port? p)
      (input-port-byte-position p)
      (output-port-byte-position p)))

(define (stream_has_position p)
  (with-exception-catcher 
   (lambda (e) #f)
   (lambda () (if (stream_position p) #t #f))))

(define (whence->integer w)
  (case w
    ((beginning) 0)
    ((current) 1)
    ((end) 2)
    (else (error "Invalid whence for stream position change." w))))

(define (set_stream_position p pos #!optional (whence 'beginning))
  (if (input-port? p)
      (input-port-byte-position p pos (whence->integer whence))
      (output-port-byte-position p pos (whence->integer whence))))

(define (safely-close-stream p)
  (if (port? p)
      (with-exception-catcher
       (lambda (e) #f)
       (lambda () (close-port p)))))

(define (call_with_stream p proc)
  (with-exception-catcher
   (lambda (e)
     (safely-close-stream p)
     (raise e))
   (lambda () 
     (let ((r (proc p))) 
       (safely-close-stream p)
       r))))

(define (eof_object) #!eof)
(define is_eof_object eof-object?)

(define *def-buf-sz* 1024)

(define read_byte read-u8)

(define (read-n-helper p n initfn rdfn subfn)
  (let ((r (initfn n)))
    (let ((n (rdfn r 0 n p n)))
      (if (zero? n) #!eof
          (subfn r 0 n)))))
  
(define (check-array-for-eof arr lenfn)
  (if (or (eof-object? arr) (zero? (lenfn arr))) #!eof arr))

(define (read_n_bytes n #!optional (p (current-input-port)))
  (check-array-for-eof 
   (read-n-helper p n make-u8vector read-subu8vector subu8vector)
   u8vector-length))

(define (read-all-helper p init rdfn apndfn bufsz)
  (let loop ((r init)
             (nr (rdfn bufsz p)))
    (if (eof-object? nr) r
        (loop (apndfn r nr)
              (rdfn bufsz p)))))

(define (read_all_bytes #!optional (p (current-input-port)) (bufsz *def-buf-sz*))
  (check-array-for-eof 
   (read-all-helper p (make-u8vector 0) read_n_bytes u8vector-append bufsz)
   u8vector-length))

(define read_char read-char)
(define peek_char peek-char)

(define (read_n_chars n #!optional (p (current-input-port)))
  (check-array-for-eof 
   (read-n-helper p n make-string read-substring substring)
   string-length))

(define (read_all_chars #!optional (p (current-input-port)) (bufsz *def-buf-sz*))
  (check-array-for-eof 
   (read-all-helper p "" read_n_chars string-append bufsz)
   string-length))

(define read_line read-line)
(define read_all read-all)

(define write_byte write-u8)

(define (write_bytes bytes #!optional (p (current-output-port)))
  (write-subu8vector bytes 0 (u8vector-length bytes) p))

(define (write_n_bytes bytes start end #!optional (p (current-output-port)))
  (write-subu8vector bytes start end p))

(define write_char write-char)

(define (write_chars str #!optional (p (current-output-port)))
  (write-substring str 0 (string-length str) p))

(define (write_n_chars str start end #!optional (p (current-output-port)))
  (write-substring str start end p))

(define flush_output_stream force-output)

(define (open-process-stream-helper path direction arguments environment
                                    directory stdin_redirection
                                    stdout_redirection stderr_redirection
                                    pseudo_terminal show_console
                                    tcoder)
  (let ((settings (list path: path 
                        direction: direction
                        arguments: arguments 
                        environment: environment
                        directory: directory 
                        stdin-redirection: stdin_redirection
                        stdout-redirection: stdout_redirection 
                        stderr-redirection: stderr_redirection 
                        pseudo-terminal: pseudo_terminal
                        show-console: show_console)))
    (let ((opt (get-codec-from-transcoder tcoder)))
      (if opt (set! settings (append settings (list char-encoding: (replace-underscores opt))))))
    (let ((opt (get-error-handling-mode-from-transcoder tcoder)))
      (if opt (set! settings (append settings (list char-encoding-errors: opt)))))
    (let ((opt (get-eol-encoding-from-transcoder tcoder)))
      (if opt (set! settings (append settings (list eol-encoding: opt)))))
    (open-process settings)))

(define (open_process_stream path #!key (direction 'input_output) (arguments '()) environment
                             directory (stdin_redirection #t) (stdout_redirection #t)
                             stderr_redirection pseudo_terminal
                             show_console transcoder)
  (if (eq? direction 'input_output) (set! direction 'input-output))
  (open-process-stream-helper path direction arguments environment directory stdin_redirection
                              stdout_redirection stderr_redirection pseudo_terminal show_console
                              transcoder))

(define process_pid process-pid)
(define process_status process-status)

(define (open_tcp_client_stream addr #!key port_number keep_alive (coalesce #t) transcoder)
  (let ((settings (list)))
    (if (string? addr)
        (set! settings (append settings (list server-address: addr)))
        (set! port_number addr))
    (if (integer? port_number)
        (set! settings (append settings (list port-number: port_number))))
    (set! settings (append settings (list keep-alive: keep_alive coalesce: coalesce)))
    (let ((opt (get-codec-from-transcoder transcoder)))
      (if opt (set! settings (append settings (list char-encoding: (replace-underscores opt))))))
    (let ((opt (get-error-handling-mode-from-transcoder transcoder)))
      (if opt (set! settings (append settings (list char-encoding-errors: opt)))))
    (let ((opt (get-eol-encoding-from-transcoder transcoder)))
      (if opt (set! settings (append settings (list eol-encoding: opt)))))
    (open-tcp-client settings)))

(define (open-tcp-server-helper fn addr port_number backlog reuse_address transcoder #!optional cbfn)
  (let ((settings (list)))
    (if (string? addr)
        (set! settings (append settings (list server-address: addr)))
        (set! port_number addr))
    (if (integer? port_number)
        (set! settings (append settings (list port-number: port_number))))
    (set! settings (append settings (list backlog: backlog reuse-address: reuse_address)))
    (let ((opt (get-codec-from-transcoder transcoder)))
      (if opt (set! settings (append settings (list char-encoding: (replace-underscores opt))))))
    (let ((opt (get-error-handling-mode-from-transcoder transcoder)))
      (if opt (set! settings (append settings (list char-encoding-errors: opt)))))
    (let ((opt (get-eol-encoding-from-transcoder transcoder)))
      (if opt (set! settings (append settings (list eol-encoding: opt)))))
    (if cbfn (fn settings cbfn)
        (fn settings))))

(define (open_tcp_server_stream addr #!key port_number (backlog 128) (reuse_address #t) transcoder)
  (open-tcp-server-helper open-tcp-server addr port_number backlog reuse_address transcoder))

(define (make-delimited-tokenizer stream delimiters)
  (let ((current-token #f))
    (lambda (msg)
      (case msg
        ((next)
         (if (not current-token)
             (next-delimited-token stream delimiters)
             (let ((tmp current-token))
               (set! current-token #f)
               tmp)))
        ((peek)
         (if (not current-token)
             (set! current-token (next-delimited-token stream delimiters)))
         current-token)
        (else (error "Invalid message received by delimited-tokenizer. " msg))))))

(define (next-delimited-token stream delimiters)
  (if (eof-object? (peek-char stream))
      (read-char stream)
      (let ((cmpr (if (list? delimiters) memv char=?)))
        (let loop ((str '())
                   (c (peek-char stream)))
          (if (or (eof-object? c)
                  (cmpr c delimiters))
              (begin (read-char stream)
                     (list->string (reverse str)))
              (loop (cons (read-char stream) str) (peek-char stream)))))))

(define (stream_tokenizer delimiters #!optional (stream (current-input-port))) 
  (if delimiters (make-delimited-tokenizer stream delimiters)
      (make-tokenizer stream '())))

(define (peek_token tokenizer)
  (tokenizer 'peek))

(define (get_token tokenizer)
  (tokenizer 'next))

(define (show #!key (stream (current-output-port)) #!rest objs)
  (let loop ((objs objs))
    (if (not (null? objs))
	(begin (slgn-display (car objs) display-string: #t port: stream)
	       (loop (cdr objs))))))

(define (showln #!key (stream (current-output-port)) #!rest objs)
  (let loop ((objs objs))
    (if (not (null? objs))
	(begin (slgn-display (car objs) display-string: #t port: stream)
	       (loop (cdr objs)))))
  (newline stream))
