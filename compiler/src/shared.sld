(define-library 
    (shared)
    (import (scheme base))
    (import (scheme write))
    (import (srfi 69))
    (import (srfi 159))
    (import (util))
    (import (chibi ast)) ; TODO, remove this!
    (export 
        make-source-location
        source-location->line
        source-location->col
        source-location->string

        make-token
        token?
        token->string
        token->type
        token->value
        token->location
        
        make-cons-syntax
        cons-syntax?
        cons-syntax->start
        cons-syntax->car
        cons-syntax->cdr
        cons-syntax->attrs

        make-atom-syntax
        atom-syntax?
        atom-syntax->type
        atom-syntax->token
        atom-syntax->value
        atom-syntax->attrs

        make-variable
        variable?
        variable->value

        make-intrinsic
        intrinsic?
        intrinsic->name
        intrinsic-names
        intrinsic-name?

        make-comment
        comment?
        comment->text

        make-compile-error
        compile-error?
        compile-error->location
        compile-error->message
        raise-syntax-error
        
        syntax->attrs
        syntax-get-attr
        syntax-set-attr
        
        safe-car-syntax
        safe-cdr-syntax
        safe-cadr-syntax
        safe-cddr-syntax
        safe-caddr-syntax
        safe-cdddr-syntax
        safe-cadddr-syntax
        safe-cddddr-syntax
        
        scheme->mock-syntax)
(begin

(define-record-type <source-location>
    (make-source-location line col offset)
    source-location?
    (line source-location->line)
    (col  source-location->col)
    (offset source-location->offset))
(define (source-location->string l)
    (string-append 
        "["
        (number->string (source-location->line l))
        ":"
        (number->string (source-location->col l))
        "]"))

(define-record-type <token>
    (make-token string type value location)
    token?
    (string token->string)
    (type token->type)
    (value token->value)
    (location token->location))

(define (make-attrs) (make-hash-table))

(define-record-type <cons-syntax>
    (make-cons-syntax-record start car cdr attrs)
    cons-syntax?
    (start cons-syntax->start)
    (car cons-syntax->car)
    (cdr cons-syntax->cdr)
    (attrs cons-syntax->attrs))
(define (make-cons-syntax start car cdr)
    (make-cons-syntax-record start car cdr (make-attrs)))
(type-printer-set! <cons-syntax> 
    (lambda (x writer out) 
        (display (string-append 
            "("
            (show #f (cons-syntax->car x))
            " . "
            (show #f (cons-syntax->cdr x))
            ")"
            ) out)))

(define-record-type <atom-syntax>
    (make-atom-syntax-record type token value attrs)
    atom-syntax?
    (type atom-syntax->type)
    (token atom-syntax->token)
    (value atom-syntax->value)
    (attrs atom-syntax->attrs))
(define (make-atom-syntax type token value)
    (make-atom-syntax-record type token value (make-attrs)))
(type-printer-set! <atom-syntax> 
    (lambda (x writer out) 
        (display (show #f (atom-syntax->value x)) out)))

(define-record-type <variable>
    (make-variable value)
    variable?
    (value variable->value))
(type-printer-set! <variable> 
    (lambda (x writer out) 
        (display (symbol->string (variable->value x)) out)))

(define-record-type <intrinsic>
    (make-intrinsic name)
    intrinsic?
    (name intrinsic->name))
(define intrinsic-names '($$prim$add
                          $$prim$sub
                          $$prim$car
                          $$prim$cdr
                          $$prim$cons
                          $$prim$concat-string

                          $$prim$le_s))
(define (intrinsic-name? name)
    (contains? intrinsic-names name))
(type-printer-set! <intrinsic> 
    (lambda (x writer out) 
        (display (string-append 
            "i:" (symbol->string (intrinsic->name x))) out)))


(define-record-type <comment>
    (make-comment text)
    comment?
    (text comment->text))
(type-printer-set! <comment> 
    (lambda (x writer out) 
        (display (string-append "(;" (comment->text x) ";)") out)))

(define-record-type <compile-error>
    (make-compile-error location message)
    compile-error?
    (location compile-error->location)
    (message compile-error->message))

(define (syntax->location syntax)
    (cond
        ((cons-syntax? syntax) (cons-syntax->start syntax))
        ((atom-syntax? syntax) 
            (token->location (atom-syntax->token syntax)))
        (else (raise "unknown syntax type when getting token"))))
(define (raise-syntax-error syntax message)
    (let ((location (syntax->location syntax)))
        (raise (make-compile-error location message))))

(define (syntax->attrs syntax)
    (cond
        ((cons-syntax? syntax) (cons-syntax->attrs syntax))
        ((atom-syntax? syntax) (atom-syntax->attrs syntax))
        (else (raise "unknown syntax type when getting attrs"))))
(define (syntax-set-attr syntax attr value)
    (let ((attrs (syntax->attrs syntax)))
        (hash-table-set! attrs attr value)))
(define (syntax-get-attr syntax attr)
    (let ((attrs (syntax->attrs syntax)))
        (hash-table-ref/default attrs attr #f)))

(define (safe-car-syntax syntax) (if (cons-syntax? syntax) (cons-syntax->car syntax) #f))
(define (safe-cdr-syntax syntax) (if (cons-syntax? syntax) (cons-syntax->cdr syntax) #f))
(define (safe-cadr-syntax syntax) (safe-car-syntax (safe-cdr-syntax syntax)))
(define (safe-cddr-syntax syntax) (safe-cdr-syntax (safe-cdr-syntax syntax)))
(define (safe-caddr-syntax syntax) (safe-car-syntax (safe-cdr-syntax (safe-cdr-syntax syntax))))
(define (safe-cdddr-syntax syntax) (safe-cdr-syntax (safe-cdr-syntax (safe-cdr-syntax syntax))))
(define (safe-cadddr-syntax syntax) (safe-car-syntax (safe-cdr-syntax (safe-cdr-syntax (safe-cdr-syntax syntax)))))
(define (safe-cddddr-syntax syntax) (safe-cdr-syntax (safe-cdr-syntax (safe-cdr-syntax (safe-cdr-syntax syntax)))))

(define (scheme->mock-syntax scheme)
    (cond
        ((pair? scheme)
            (make-cons-syntax #f (scheme->mock-syntax (car scheme)) 
                                    (scheme->mock-syntax (cdr scheme))))
        ((string? scheme) (make-atom-syntax 'string #f scheme))
        ((boolean? scheme) (make-atom-syntax 'boolean #f scheme))
        ((char? scheme) (make-atom-syntax 'char #f scheme))
        ((number? scheme) (make-atom-syntax 'number #f scheme))
        ((symbol? scheme) (make-atom-syntax 'symbol #f scheme))
        ((null? scheme) (make-atom-syntax 'null #f scheme))
        (else (raise (string-append
            "unknown scheme, can't convert value "
            (show #f scheme)
            "to syntax")))))
))
