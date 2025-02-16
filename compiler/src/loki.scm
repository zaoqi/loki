(import (scheme base))
(import (scheme write))
(import (scheme read))
(import (scheme file))
(import (scheme repl))
(import (scheme process-context))
(import (util))
(import (shared))

(import (p00_string2tokens))
(import (p01_tokens2syntax))
(import (p02_attrs))
(import (p03_syntax2scheme))
(import (p04_scheme2cps))
(import (p05_liftlambda))
(import (p06_reduce))
(import (p07_lift_rodatas))
(import (p08_funcs2wat))

(import (srfi 159))
(import (chibi show pretty))

(define (print-help-and-exit) 
        (display "arguments: loki.scm [input.scm] [out.wat]")
        (exit))

(if (not (eq? (length (command-line)) 3))
    (print-help-and-exit))

(define input-file (list-ref (command-line) 1))
(define output-file (list-ref (command-line) 2))

(define (program->wat program)
    (show #f (pretty program)))

(define (write-program program file)
    (if (file-exists? file) (delete-file file))
    (let ((p (open-output-file file)))
        (show p (program->wat program))
        (close-output-port p)))

(define (handle-compile-error e)
    (let ((location (compile-error->location e))
          (message (compile-error->message e)))
        (display "compile error at ")
        (display (source-location->string location))
        (display ": ")
        (display message)
        (display "\n")
        (display "\n")
        (exit 1)))

(define (handle-unexpected-error e)
    (display "unexpected error in compiler: ")
    (display (show #f (pretty e)))
    (raise e)
    (exit 1))

(define (handle-error e)
    (if (compile-error? e)
        (handle-compile-error e)
        (handle-unexpected-error e)))

(define (compile prog)
    (call/cc (lambda (k)
        (with-exception-handler
            (lambda (e) 
                (handle-error e))
            (lambda ()
                (let ((p00 (p00_string2tokens prog)))
                (let ((p01 (p01_tokens2syntax p00)))
                (let ((p02 (p02_attrs p01)))
                (let ((p03 (p03_syntax2scheme p02)))
                (let ((p04 (p04_scheme2cps p03)))
                (let ((p05 (p05_liftlambda p04)))
                (let ((p06 (p06_reduce p05)))
                (let ((p07 (p07_lift_rodatas p06)))
                (let ((p08 (p08_funcs2wat p07)))
                (display (show #f (pretty p08)))
                    p08))))))))))))))

(define (main)
    (let* ((program (compile (open-input-file input-file))))
            (write-program program output-file)))

(main)
