(define-library 
(p06_closes2funcs)
(import (scheme base))
(import (util))
(import (shared))
(export p06_closes2funcs)
(begin

(define funcid (make-anon-id "$$f"))

(define (close? x) (and (list? x) (eq? (car x) 'close)))
(define (close->bindings x) (cadr x))
(define (close->body x) (caddr x))
(define (close->frees x) 
    (let* ((body (close->body x))
           (bounds (close->bindings x))
           (frees (insts->frees body))
           (without-bounds (filter 
                (lambda (f) (not (member f bounds))) frees)))
        (append without-bounds)))

(define (refer->var x) (cadr x))
(define (refer->frees x)
    (let ((var (cadr x)))
        (if (eq? (variable->binding var) 'free)
            (list (refer->var x))
            #f)))

(define (test->frees x)
    (let ((consequent (cadr x))
          (alternate (caddr x)))
        (append (insts->frees consequent)
                (insts->frees alternate))))

(define (inst->frees x)
    (let ((op (car x)))
        (cond
            ((eq? op 'close) (close->frees x))
            ((eq? op 'refer) (refer->frees x))
            ((eq? op 'test) (test->frees x))
            (else '()))))
(define (insts->frees is)
    (unique (apply append (map inst->frees is))))

(define (mark-close x) 
    (let* ((body (close->body x)) (frees (close->frees x)))
        `(close ,(funcid) ,(close->bindings x) ,frees ,body)))
(define (mark-closes x)
    (let* ((mark-inst (lambda (inst) 
            (if (close? inst) (mark-close inst) inst))))
        (map mark-inst x)))

(define (mclose->mapped x) (cadr x))
(define (mclose->bounds x) (caddr x))
(define (mclose->frees x) (cadddr x))
(define (mclose->body x) (cadddr (cdr x)))

(define (map-close x) `(makeclosure ,(mclose->mapped x) ,(mclose->frees x)))
(define (map-inst x) (if (close? x) (map-close x) x))
(define (map-insts x) (map map-inst x))

(define (close->func x)
    (let* ((lifted (lift-closures (mclose->body x) #f))
           (body (car lifted))
           (funcs (cdr lifted)))
    (cons `(func close ,(mclose->mapped x) ,(mclose->bounds x) ,(mclose->frees x) ,@body) funcs))) ; add frees from outer
(define (closes->funcs x) (apply append (map close->func x)))
(define (entry->func x) `(func open $$fentry () () ,@x))

(define (lift-closures x emit-outer-func)
    (let* ((marked   (mark-closes x))
           (closes   (filter close? marked))
           (mapped   (map-insts marked))
           (funcs    (closes->funcs closes))
           (entry    (entry->func mapped))
           (outer    `(,entry ,@(if (null? funcs) '() funcs))))
        (if emit-outer-func outer (cons mapped funcs))))

(define (p06_closes2funcs x)
        (lift-closures x #t))))
