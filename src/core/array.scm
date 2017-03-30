;; Copyright (c) 2013-2017 by Vijay Mathew Pandyalakal, All Rights Reserved.

(define (make-array dim fill constructor)
  (cond ((integer? dim)
         (if (procedure? fill)
             (let loop ((a (constructor dim))
                        (i 0))
               (cond ((< i dim)
                      (vector-set! a i (fill))
                      (loop a (+ i 1)))
                     (else a)))
             (constructor dim fill)))
        ((list? dim)
         (if (null? (scm-cdr dim))
             (make-array (scm-car dim) fill constructor)
             (make-array (scm-car dim) (lambda () (make-array (scm-cdr dim) fill constructor)) constructor)))
        (else (scm-error "invalid array dimension" dim))))

(define array scm-vector)
(define (make_array dim #!optional fill) (make-array dim fill make-vector))

(define is_array vector?)

(define (vectors-ref vectors i)
  (scm-map (lambda (v) (array_at v i)) vectors))

(define array_at vector-ref)
(define array_set vector-set!)

(define (array_ref arr dim)
  (if (list? dim)
      (if (null? dim) arr
          (array_ref (vector-ref arr (scm-car dim)) (scm-cdr dim)))
      (vector-ref arr dim)))

(define (array_ref_set arr dim obj)
  (if (list? dim)
      (cond ((null? dim) 
             (scm-error "array dimension cannot be empty"))
            ((= 1 (scm-length dim))
             (vector-set! arr (scm-car dim) obj)
             *void*)
            (else (array_ref_set (vector-ref arr (scm-car dim)) (scm-cdr dim) obj)))
      (begin (vector-set! arr dim obj)
             *void*)))      

(define array_length vector-length)
(define arrays_at vectors-ref)
(define array_to_list vector->list)
(define array_copy vector-copy)
(define subarray subvector)
(define array_append vector-append)
(define array_fill vector-fill!)
(define subarray_fill subvector-fill!)
(define subarray_move subvector-move!)
(define array_shrink vector-shrink!)

(define (vector-map f vec . vectors)
  (if (scm-not (null? vectors))
      (assert-equal-lengths vec vectors vector-length))
  (let ((len (vector-length vec)))
    (if (null? vectors)
        (generic-map1! f (make-vector len) vec len vector-ref vector-set!)
        (generic-map2+! f (make-vector len) (scm-cons vec vectors) len vectors-ref vector-set!))))

(define (vector-for-each f vec . vectors)
  (if (scm-not (null? vectors))
      (assert-equal-lengths vec vectors vector-length))
  (let ((len (vector-length vec)))
    (if (null? vectors)
        (generic-map1! f #f vec len vector-ref vector-set!)
        (generic-map2+! f #f (scm-cons vec vectors) len vectors-ref vector-set!))))

(define array_map vector-map)
(define array_for_each vector-for-each)

(define (array_index_of arr obj #!key (test *default-eq*))
  (let ((len (vector-length arr)))
    (let loop ((i 0))
      (cond ((>= i len) -1)
            ((test (vector-ref arr i) obj) i)
            (else (loop (+ i 1)))))))

;; byte arrays.

(define u8array scm-u8vector)
(define (make_u8array dim #!optional (fill 0)) (make-u8vector dim fill))
(define is_u8array u8vector?)
(define u8array_length u8vector-length)
(define u8array_at u8vector-ref)
(define u8array_set u8vector-set!)
(define u8array_to_list u8vector->list)
(define list_to_u8array list->u8vector)
(define u8array_fill u8vector-fill!)
(define object_to_u8array object->u8vector)
(define u8array_to_object u8vector->object)
(define subu8array_fill subu8vector-fill!)
(define u8array_append u8vector-append)
(define u8array_copy u8vector-copy)
(define subu8array subu8vector)
(define subu8array_move subu8vector-move!)
(define u8array_shrink u8vector-shrink!)

(define (u8array_to_string u8)
  (let ((len (u8vector-length u8))
        (out (open-output-string)))
    (let loop ((i 0))
      (if (>= i len)
          (get-output-string out)
          (begin (write-char (integer->char (u8vector-ref u8 i)) out)
                 (loop (+ i 1)))))))

(define s8array scm-s8vector)
(define (make_s8array dim #!optional (fill 0)) (make-s8vector dim fill))
(define is_s8array s8vector?)
(define s8array_length s8vector-length)
(define s8array_at s8vector-ref)
(define s8array_set s8vector-set!)
(define s8array_to_list s8vector->list)
(define list_to_s8array list->s8vector)
(define s8array_fill s8vector-fill!)
(define subs8array_fill subs8vector-fill!)
(define s8array_append s8vector-append)
(define s8array_copy s8vector-copy)
(define subs8array subs8vector)
(define subs8array_move subs8vector-move!)
(define s8array_shrink s8vector-shrink!)

(define s16array scm-s16vector)
(define (make_s16array dim #!optional (fill 0)) (make-s16vector dim fill))
(define is_s16array s16vector?)
(define s16array_length s16vector-length)
(define s16array_at s16vector-ref)
(define s16array_set s16vector-set!)
(define s16array_to_list s16vector->list)
(define list_to_s16array list->s16vector)
(define s16array_fill s16vector-fill!)
(define subs16array_fill subs16vector-fill!)
(define s16array_append s16vector-append)
(define s16array_copy s16vector-copy)
(define subs16array subs16vector)
(define subs16array_move subs16vector-move!)
(define s16array_shrink s16vector-shrink!)

(define u16array scm-u16vector)
(define (make_u16array dim #!optional (fill 0)) (make-u16vector dim fill))
(define is_u16array u16vector?)
(define u16array_length u16vector-length)
(define u16array_at u16vector-ref)
(define u16array_set u16vector-set!)
(define u16array_to_list u16vector->list)
(define list_to_u16array list->u16vector)
(define u16array_fill u16vector-fill!)
(define subu16array_fill subu16vector-fill!)
(define u16array_append u16vector-append)
(define u16array_copy u16vector-copy)
(define subu16array subu16vector)
(define subu16array_move subu16vector-move!)
(define u16array_shrink u16vector-shrink!)

(define s32array scm-s32vector)
(define (make_s32array dim #!optional (fill 0)) (make-s32vector dim fill))
(define is_s32array s32vector?)
(define s32array_length s32vector-length)
(define s32array_at s32vector-ref)
(define s32array_set s32vector-set!)
(define s32array_to_list s32vector->list)
(define list_to_s32array list->s32vector)
(define s32array_fill s32vector-fill!)
(define subs32array_fill subs32vector-fill!)
(define s32array_append s32vector-append)
(define s32array_copy s32vector-copy)
(define subs32array subs32vector)
(define subs32array_move subs32vector-move!)
(define s32array_shrink s32vector-shrink!)

(define u32array scm-u32vector)
(define (make_u32array dim #!optional (fill 0)) (make-u32vector dim fill))
(define is_u32array u32vector?)
(define u32array_length u32vector-length)
(define u32array_at u32vector-ref)
(define u32array_set u32vector-set!)
(define u32array_to_list u32vector->list)
(define list_to_u32array list->u32vector)
(define u32array_fill u32vector-fill!)
(define subu32array_fill subu32vector-fill!)
(define u32array_append u32vector-append)
(define u32array_copy u32vector-copy)
(define subu32array subu32vector)
(define subu32array_move subu32vector-move!)
(define u32array_shrink u32vector-shrink!)

(define s64array scm-s64vector)
(define (make_s64array dim #!optional (fill 0)) (make-s64vector dim fill))
(define is_s64array s64vector?)
(define s64array_length s64vector-length)
(define s64array_at s64vector-ref)
(define s64array_set s64vector-set!)
(define s64array_to_list s64vector->list)
(define list_to_s64array list->s64vector)
(define s64array_fill s64vector-fill!)
(define subs64array_fill subs64vector-fill!)
(define s64array_append s64vector-append)
(define s64array_copy s64vector-copy)
(define subs64array subs64vector)
(define subs64array_move subs64vector-move!)
(define s64array_shrink s64vector-shrink!)

(define u64array scm-u64vector)
(define (make_u64array dim #!optional (fill 0)) (make-u64vector dim fill))
(define is_u64array u64vector?)
(define u64array_length u64vector-length)
(define u64array_at u64vector-ref)
(define u64array_set u64vector-set!)
(define u64array_to_list u64vector->list)
(define list_to_u64array list->u64vector)
(define u64array_fill u64vector-fill!)
(define subu64array_fill subu64vector-fill!)
(define u64array_append u64vector-append)
(define u64array_copy u64vector-copy)
(define subu64array subu64vector)
(define subu64array_move subu64vector-move!)
(define u64array_shrink u64vector-shrink!)

(define f64array scm-f64vector)
(define (make_f64array dim #!optional (fill 0.0)) (make-f64vector dim fill))
(define is_f64array f64vector?)
(define f64array_length f64vector-length)
(define f64array_at f64vector-ref)
(define f64array_set f64vector-set!)
(define f64array_to_list f64vector->list)
(define list_to_f64array list->f64vector)
(define f64array_fill f64vector-fill!)
(define subf64array_fill subf64vector-fill!)
(define f64array_append f64vector-append)
(define f64array_copy f64vector-copy)
(define subf64array subf64vector)
(define subf64array_move subf64vector-move!)
(define f64array_shrink f64vector-shrink!)

(define f32array scm-f32vector)
(define (make_f32array dim #!optional (fill 0.0)) (make-f32vector dim fill))
(define is_f32array f32vector?)
(define f32array_length f32vector-length)
(define f32array_at f32vector-ref)
(define f32array_set f32vector-set!)
(define f32array_to_list f32vector->list)
(define list_to_f32array list->f32vector)
(define f32array_fill f32vector-fill!)
(define subf32array_fill subf32vector-fill!)
(define f32array_append f32vector-append)
(define f32array_copy f32vector-copy)
(define subf32array subf32vector)
(define subf32array_move subf32vector-move!)
(define f32array_shrink f32vector-shrink!)

(define (generic-array-length tab)
  (cond
   ((string? tab) (string-length tab))
   ((vector? tab) (vector-length tab))
   ((list? tab) (scm-length tab))
   ((%bitvector? tab) (%bitvector-size tab))
   ((u8vector? tab) (u8vector-length tab))
   ((s8vector? tab) (s8vector-length tab))
   ((u16vector? tab) (u16vector-length tab))
   ((s16vector? tab) (s16vector-length tab))
   ((u32vector? tab) (u32vector-length tab))
   ((s32vector? tab) (s32vector-length tab))
   ((u64vector? tab) (u64vector-length tab))
   ((s64vector? tab) (s64vector-length tab))
   ((f32vector? tab) (f32vector-length tab))
   ((f64vector? tab) (f64vector-length tab))
   (else (scm-error !not_indexed tab))))

(define scm-subvector subvector)
(define scm-subu8vector subu8vector)
(define scm-subs8vector subs8vector)
(define scm-subu16vector subu16vector)
(define scm-subs16vector subs16vector)
(define scm-subu32vector subu32vector)
(define scm-subs32vector subs32vector)
(define scm-subu64vector subu64vector)
(define scm-subs64vector subs64vector)
(define scm-subf32vector subf32vector)
(define scm-subf64vector subf64vector)

(define (safe-generic-array-rest a)
  (with-exception-catcher
   (lambda (e) #f)
   (lambda ()
     (cond
      ((string? a) (scm-substring a 1 (string-length a)))
      ((vector? a) (scm-subvector a 1 (vector-length a)))
      ((%bitvector? a) (scm-subbitarray a 1 (%bitvector-size a)))
      ((u8vector? a) (scm-subu8vector a 1 (u8vector-length a)))
      ((s8vector? a) (scm-subs8vector a 1 (s8vector-length a)))
      ((u16vector? a) (scm-subu16vector a 1 (u16vector-length a)))
      ((s16vector? a) (scm-subs16vector a 1 (s16vector-length a)))
      ((u32vector? a) (scm-subu32vector a 1 (u32vector-length a)))
      ((s32vector? a) (scm-subs32vector a 1 (s32vector-length a)))
      ((u64vector? a) (scm-subu64vector a 1 (u64vector-length a)))
      ((s64vector? a) (scm-subs64vector a 1 (s64vector-length a)))
      ((f32vector? a) (scm-subf32vector a 1 (f32vector-length a)))
      ((f64vector? a) (scm-subf64vector a 1 (f64vector-length a)))
      (else #f)))))

(define (safe-generic-array-first tab)
  (with-exception-catcher
   (lambda (e) #f)
   (lambda ()
     (let ((key 0))
       (cond
        ((vector? tab)
         (vector-ref tab key))
        ((string? tab)
         (string-ref tab key))
        ((list? tab)
         (list-ref tab key))
        ((%bitvector? tab)
         (bitvector-set? tab key))
        ((u8vector? tab)
         (u8vector-ref tab key))
        ((s8vector? tab)
         (s8vector-ref tab key))
        ((u16vector? tab)
         (u16vector-ref tab key))
        ((s16vector? tab)
         (s16vector-ref tab key))
        ((u32vector? tab)
         (u32vector-ref tab key))
        ((s32vector? tab)
         (s32vector-ref tab key))
        ((u64vector? tab)
         (u64vector-ref tab key))
        ((s64vector? tab)
         (s64vector-ref tab key))
        ((f32vector? tab)
         (f32vector-ref tab key))
        ((f64vector? tab)
         (f64vector-ref tab key))
        (else #f))))))
