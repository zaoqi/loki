; string2tokens
; this pass converts a stream of characters (via an input port) into a list of scheme tokens.
; if the stream of characters is not a valid list of scheme tokens an error will be raised

; each token stores the original string from the input, the representative scheme value, 
; and the original location in the source file

; TODO: implement string escapes and multi-line strings

(define-library 
    (p00_string2tokens)
    (import (scheme base))
    (import (scheme char))
    (import (scheme complex))
    (import (scheme write))
    (import (srfi 115))
    (import (srfi 159))
    (import (util))
    (import (shared))
    (export p00_string2tokens)
(begin

(define *whitespace* '(#\tab #\return #\newline #\space))
(define (whitespace? c) (member c *whitespace*))

(define *left-paren* (car (string->list "(")))
(define *right-paren* (car (string->list ")")))
(define (left-paren? c) (equal? c *left-paren*))
(define (right-paren? c) (equal? c *right-paren*))

(define *left-vector* "#(")
(define *left-bytevector* "#u8(")
(define (left-vector? s) (equal? s *left-vector*))
(define (left-bytevector? s) (equal? s *left-bytevector*))

(define (newline? c) (equal? c #\newline))
(define (return? c) (equal? c #\return))
(define (semicolon? c) (equal? c #\;))
(define (doublequote? c) (equal? c #\"))
(define (hash? c) (equal? c #\#))
(define (quote? c) (equal? c #\'))
(define (quasiquote? c) (equal? c #\`))
(define (unquote? c) (equal? c #\,))
(define (unquote-splicing? s) (equal? s ",@"))
(define (dot? c) (equal? c #\.))
(define (vertical? c) (equal? c #\|))
(define (delimiter? c)
    (or
        (eof-object? c)
        (left-paren? c)
        (right-paren? c)
        (whitespace? c)
        (doublequote? c)
        (semicolon? c)))

(define *char-literal-regexp* (rx (: bos #\# #\\ any eos)))
(define *char-name-regexp* (rx (: bos #\# #\\ 
    (or "alarm" "backspace" "delete" "escape" "newline" "null" "return" "space" "tab") eos)))
(define *char-scalar-regexp* (rx (: bos #\# #\\ #\x (+ hex-digit) eos)))
(define (char-literal? str) (regexp-search *char-literal-regexp* str))
(define (char-name? str) (regexp-search *char-name-regexp* str))
(define (char-scalar? str) (regexp-search *char-scalar-regexp* str))

(define (char-literal->char str) 
    (car (string->list (string-copy str 2 3))))
(define (char-name->char str)
    (cond
        ((equal? str "#\\alarm") #\alarm)
        ((equal? str "#\\backspace") #\backspace)
        ((equal? str "#\\delete") #\delete)
        ((equal? str "#\\escape") #\escape)
        ((equal? str "#\\newline") #\newline)
        ((equal? str "#\\null") #\null)
        ((equal? str "#\\return") #\return)
        ((equal? str "#\\space") #\space)
        ((equal? str "#\\tab") #\tab)
        (else (raise "unknown character name"))))
(define (char-scalar->char str)
    (let ((scalar (string-copy str 3 (string-length str))))
        (integer->char (real-string->number scalar 16 #t))))

(define *num-infnan-sre* '(or "+inf.0" "-inf.0" "+nan.0" "-nan.0"))
(define *num-sign-sre* '(or #\+ #\-))
(define *num-exactness-sre* '(? (or "#i" "#e")))

(define *num-radix-02-sre* "#b")
(define *num-radix-08-sre* "#o")
(define *num-radix-10-sre* '(? "#d"))
(define *num-radix-16-sre* "#x")

(define *num-digit-02-sre* '(or #\0 #\1))
(define *num-digit-08-sre* '(or #\0 #\1 #\2 #\3 #\4 #\5 #\6 #\7))
(define *num-digit-10-sre* 'num)
(define *num-digit-16-sre* 'hex-digit)

(define (define-num-sre digit-sre radix-sre)
    (define num-uinteger-sre `(+ ,digit-sre))
    (define num-ureal-sre
        `(or 
            ,num-uinteger-sre
            (: ,num-uinteger-sre #\/ ,num-uinteger-sre)))
    (define num-real-sre
        `(or
            (: (? ,*num-sign-sre*) ,num-ureal-sre)
            ,*num-infnan-sre*))
    (define num-complex-sre
        `(or
            (-> real ,num-real-sre)
            (: (-> real ,num-real-sre) (-> imag (: ,*num-sign-sre* (? ,num-ureal-sre))) #\i)
            (: (-> real ,num-real-sre) (-> imag ,*num-infnan-sre*) #\i)
            (: (-> x ,num-real-sre) #\@ (-> y ,num-real-sre))
            (: (-> imag ,*num-sign-sre* ,num-ureal-sre) #\i)
            (: (-> imag ,*num-infnan-sre*) #\i)
            (: (-> imag ,*num-sign-sre*) #\i)))
    (define num-prefix-sre
        `(or
            (: (-> radix ,radix-sre) (-> exact ,*num-exactness-sre*))
            (: (-> exact ,*num-exactness-sre*) (-> radix ,radix-sre))))
    `(: ,num-prefix-sre ,num-complex-sre))

(define *num-02-sre* (define-num-sre *num-digit-02-sre* *num-radix-02-sre*))
(define *num-08-sre* (define-num-sre *num-digit-08-sre* *num-radix-08-sre*))
(define *num-10-sre* (define-num-sre *num-digit-10-sre* *num-radix-10-sre*))
(define *num-16-sre* (define-num-sre *num-digit-16-sre* *num-radix-16-sre*))

(define *num-02-regexp* (regexp *num-02-sre*))
(define *num-08-regexp* (regexp *num-08-sre*))
(define *num-10-regexp* (regexp *num-10-sre*))
(define *num-16-regexp* (regexp *num-16-sre*))
(define *num-regexp* (regexp 
    `(or 
        ,*num-10-sre*
        ,*num-02-sre*
        ,*num-08-sre*
        ,*num-16-sre*
        )))
(define (parse-num str) 
    (or
        (regexp-matches *num-10-regexp* str)
        (regexp-matches *num-16-regexp* str)
        (regexp-matches *num-02-regexp* str)
        (regexp-matches *num-08-regexp* str)))

(define (char-hex-letter? char)
    (let ((int (char->integer char)))
        (or
            (and (>= int 65) (<= int 70))
            (and (>= int 97) (<= int 102)))))
(define (char-hex-letter->number char)
    (let ((int (char->integer char)))
        (+ (if (and (>= int 65) (<= int 70))
            (- int 65)
            (- int 97)) 10)))
(define (radix->base radix)
    (cond
        ((equal? radix "#b") 2)
        ((equal? radix "#o") 8)
        ((equal? radix "#d") 10)
        ((equal? radix "") 10)
        ((equal? radix "#x") 16)
        (else (raise "unknown radix"))))
(define (real-string->number str base is-exact)
    (if str
        (cond
            ((equal? str "+inf.0") +inf.0)
            ((equal? str "-inf.0") -inf.0)
            ((equal? str "+nan.0") +nan.0)
            ((equal? str "-nan.0") -nan.0)
            (else
                (let* ((chars (string->list str))
                    (sign 1)
                    (num (fold-left (lambda (char num)
                        (cond 
                            ((char-numeric? char) (+ (* num base) (digit-value char)))
                            ((char-hex-letter? char) (+ (* num base) (char-hex-letter->number char)))
                            ((equal? char #\-) (set! sign -1) num)
                            ((equal? char #\+) num)
                            ((equal? char #\/) (raise "rational literals unimplemented"))
                            (else (raise "unhandled character in real number string")))) 0 chars)))
                    (* sign (if is-exact (exact num) (inexact num))))))
                0))
(define (imag-string->number str base is-exact)
    (cond
        ((equal? str "-") (if is-exact (exact -1) (inexact -1)))
        ((equal? str "+") (if is-exact (exact 1) (inexact 1)))
        ((equal? str "") (if is-exact (exact 1) (inexact 1)))
        (else (real-string->number str base is-exact))))

(define (lexed-num->num str matches)
    (let* ((real (regexp-match-submatch matches 'real))
          (imag (regexp-match-submatch matches 'imag))
          (x (regexp-match-submatch matches 'x))
          (y (regexp-match-submatch matches 'y))
          (radix (regexp-match-submatch matches 'radix))
          (exactness (regexp-match-submatch matches 'exact))
          (exact (if (equal? exactness "#i") #f #t))
          (base (radix->base radix))
          (realnum (real-string->number real base exact))
          (imagnum (imag-string->number imag base exact))
          (xnum (real-string->number x base exact))
          (ynum (imag-string->number y base exact)))
        (if (or x y)
            (make-polar xnum ynum)
            (make-rectangular realnum imagnum))))

(define *initial-id-sre* '(or alpha #\! #\$ #\% #\& #\* #\/ #\: #\< #\=
    #\> #\? #\^ #\_ #\~))
(define *explicit-sign-sre* '(or #\+ #\-))
(define *special-subsequent-sre* `(or ,*explicit-sign-sre* #\. #\@))
(define *subsequent-id-sre* `(or ,*initial-id-sre* num ,*special-subsequent-sre*))
(define *sign-subsequent-id-sre* `(or ,*initial-id-sre* ,*explicit-sign-sre* #\@))
(define *dot-subsequent-id-sre* `(or ,*sign-subsequent-id-sre* #\.))
(define *symbol-element-id-sre* 
    '(or
        (difference any ("|\\"))
        (: #\\ #\x (+ hex-digit))
        (or "\\a" "\\b" "\\t" "\\n" "\\r")
        "\\|"))
(define *id-sre* `(: bos (or 
    (-> id (: ,*initial-id-sre* (* ,*subsequent-id-sre*)))
    (: #\| (-> id (* ,*symbol-element-id-sre*)) #\|)
    (-> id ,*explicit-sign-sre*)
    (-> id (: ,*explicit-sign-sre* ,*sign-subsequent-id-sre* (* ,*subsequent-id-sre*)))
    (-> id (: ,*explicit-sign-sre* #\. ,*dot-subsequent-id-sre* (* ,*subsequent-id-sre*)))
    (-> id (: #\. ,*dot-subsequent-id-sre* (* ,*subsequent-id-sre*))) eos)))
(define *id-regexp* (regexp *id-sre*))

(define (parse-id string) (regexp-matches *id-regexp* string))
(define (lexed-id->symbol matches) (regexp-match-submatch matches 'id))

(define-record-type <tchar>
    (make-tchar char location)
    tchar?
    (char tchar->char)
    (location tchar->location))

(define (tchar->token tchar type value)
    (make-token 
        (list->string (list (tchar->char tchar)))
        type
        value
        (tchar->location tchar)))
(define (tchars->string tchars) (list->string (map tchar->char tchars)))
(define (tchars->token tchars type value)
    (let ((chars (map tchar->char tchars)))
        (make-token
            (list->string chars)
            type
            value
            (tchar->location (car tchars)))))

(define-record-type <reader>
    (make-reader port saves line col offset)
    reader?
    (port reader->port)
    (saves reader->saves set-reader-saves)
    (line reader->line set-reader-line)
    (col reader->col set-reader-col)
    (offset reader->offset set-reader-offset))

(define (port->reader port)
    (make-reader port '() 1 1 0))

(define (read-reader reader)
    (let ((port (reader->port reader))
          (saves (reader->saves reader)) 
          (line (reader->line reader)) 
          (col (reader->col reader))
          (offset (reader->offset reader)))
        (if (null? saves)
            (let* ((char (read-char port)) 
                   (next (peek-char port))
                   (tchar (make-tchar char (make-source-location line col offset))))
                (if (return? char)
                    (if (newline? next)
                        (begin
                            ; will be crlf, but currently on cr, only increment col
                            (set-reader-col reader (+ col 1))
                            (set-reader-offset reader (+ offset 1))
                            tchar)
                        (begin
                            ; only cr, increment as cr line ending
                            (set-reader-line reader (+ line 1))
                            (set-reader-col reader 1)
                            (set-reader-offset reader (+ offset 1))
                            tchar))
                    (if (newline? char)
                        (begin
                            ; only lf, increment as lf line ending
                            (set-reader-line reader (+ line 1))
                            (set-reader-col reader 1)
                            (set-reader-offset reader (+ offset 1))
                            tchar)
                        (begin
                            ; no line endings
                            (set-reader-col reader (+ col 1))
                            (set-reader-offset reader (+ offset 1))
                            tchar))))
            (let ((save (car saves)))
                (set-reader-saves reader (cdr saves))
                save))))

(define (peek-reader reader)
    (let ((tchar (read-reader reader)))
        (roll-back-reader reader tchar)
        tchar))
            
(define (roll-back-reader reader tchar)
    (set-reader-saves reader (cons tchar (reader->saves reader))))
                
(define (add-token token tokens) (cons token tokens))

(define (p00_string2tokens port)
    (let* ((raw-reader (port->reader port))
           (tokens '())
           (buffer '())
           (should-roll-back #f))
        (define (emit-tchar tchar type value)
            (set! tokens (cons (tchar->token tchar type value) tokens)))
        (define (emit-buffer type value)
            (set! tokens (cons (tchars->token (reverse buffer) type value) tokens))
            (set! buffer '()))
        (define (push-buffer tchar)
            (set! buffer (cons tchar buffer)))
        (define (reader) (read-reader raw-reader))
        (define (peek) (peek-reader raw-reader))
        (define (roll-back tchar)
            (roll-back-reader raw-reader tchar))
        (define (buffer->string)
            (tchars->string (reverse buffer)))
        (define (error-with-value msg value)
            (error (string-append 
                "error! "
                msg
                ": "
                value)))

        (define (lex-ready)
            (let* ((tchar (reader)) (char (tchar->char tchar)))
                (cond
                    ((eof-object? char) #f)
                    ((whitespace? char) (lex-ready))
                    ((dot? char) (emit-tchar tchar 'dot #f) (lex-ready))
                    ((quote? char) (emit-tchar tchar 'quote #f) (lex-ready))
                    ((quasiquote? char) (emit-tchar tchar 'quasiquote #f) (lex-ready))
                    ((unquote? char) 
                        (let* ((next (peek)) (next-char (tchar->char next)))
                                (if (equal? next-char #\@)
                                    (begin
                                        (push-buffer tchar)
                                        (push-buffer (reader))
                                        (emit-buffer 'unquote-splicing #f))
                                    (emit-tchar tchar 'unquote #f))
                                (lex-ready)))
                    ((doublequote? char) 
                        (push-buffer tchar)
                        (lex-string))
                    ((left-paren? char)
                        (emit-tchar tchar 'lparen #f)
                        (lex-ready))
                    ((right-paren? char)
                        (emit-tchar tchar 'rparen #f)
                        (lex-ready))
                    (else 
                        (push-buffer tchar)
                        (lex-reading)))))

        (define (lex-reading)
            (let* ((tchar (reader)) (char (tchar->char tchar)))
                (if (delimiter? char)
                    (let* ((string (buffer->string)))
                        (cond 
                            ((and (left-paren? char) (equal? string "#")) 
                                (push-buffer tchar)
                                (emit-buffer 'lvector #f))
                            ((and (left-paren? char) (equal? string "#u8")) 
                                (push-buffer tchar)
                                (emit-buffer 'lbytevector #f))
                            (else
                                (roll-back tchar)
                                (cond
                                    ((equal? string "#t") (emit-buffer 'boolean #t))
                                    ((equal? string "#true") (emit-buffer 'boolean #t))
                                    ((equal? string "#f") (emit-buffer 'boolean #f))
                                    ((equal? string "#false") (emit-buffer 'boolean #f))
                                    ((parse-num string) => (lambda (matches) (emit-buffer 'number (lexed-num->num string matches))))
                                    ((parse-id string) => (lambda (matches) (emit-buffer 'id (string->symbol (lexed-id->symbol matches)))))
                                    ((char-literal? string) (emit-buffer 'char (char-literal->char string)))
                                    ((char-name? string) (emit-buffer 'char (char-name->char string)))
                                    ((char-scalar? string) (emit-buffer 'char (char-scalar->char string)))
                                    (else (error-with-value "unknown value" string)))))
                            (lex-ready))
                    (begin
                        (push-buffer tchar)
                        (lex-reading)))))

        ; escapes need to be re-handled
        ; as well as multi line strings with \
        (define (lex-string)
            (let* ((tchar (reader)) (char (tchar->char tchar)))
                (cond
                    ((eof-object? char) (error "unterminated string!!!"))
                    ((doublequote? char) 
                        (push-buffer tchar)
                        (let ((str (buffer->string)))
                            (emit-buffer 'string (string-copy str 1 (- (string-length str) 1)))
                            (lex-ready)))
                    (else 
                        (push-buffer tchar)
                        (lex-string)))))

        (lex-ready)
        (reverse tokens)))

))