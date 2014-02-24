;; Copyright (c) 2013-2014 by Vijay Mathew Pandyalakal, All Rights Reserved.

(define is_number number?)
(define is_integer integer?)
(define is_real real?)
(define is_rational rational?)
(define is_complex complex?)
(define is_zero zero?)
(define is_even even?)
(define is_odd odd?)
(define is_positive positive?)
(define is_negative negative?)
(define is_nan nan?)
(define is_fixnum fixnum?)
(define is_flonum flonum?)
(define is_fx_negative fxnegative?)
(define is_fx_positive fxpositive?)
(define is_fx_zero fxzero?)
(define is_fx_even fxeven?)
(define is_fx_odd fxodd?)
(define is_fl_finite flfinite?)
(define is_fl_infinite flinfinite?)
(define is_fl_even fleven?)
(define is_fl_odd flodd?)
(define is_fl_integer flinteger?)
(define is_fl_nan flnan?)
(define is_fl_zero flzero?)
(define is_fl_negative flnegative?)
(define is_fl_positive flpositive?)

(define (is_positive_infinity n)
  (if (not (real? n))
      (##fail-check-real 1 is_positive_infinity n))
  (eq? *pos-inf-sym* (string->symbol (number->string n))))

(define (is_negative_infinity n)
  (if (not (real? n))
      (##fail-check-real 1 is_negative_infinity n))
  (eq? *neg-inf-sym* (string->symbol (number->string n))))

(define integer_to_char integer->char)
(define exact_to_inexact exact->inexact)
(define inexact_to_exact inexact->exact)
(define number_to_string number->string)

(define (real_to_integer n)
  (inexact->exact (round n)))

(define (integer_to_real n)
  (exact->inexact n))

(define fixnum_to_flonum fixnum->flonum)

(define rectangular make-rectangular)
(define polar make-polar)
(define real_part real-part)
(define imag_part imag-part)

(define add +)
(define sub -)
(define mult *)
(define div /)

(define fxadd fx+)
(define fxsub fx-)
(define fxmult fx*)
(define fxwrap_add fxwrap+)
(define fxwrap_sub fxwrap-)
(define fxwrap_mult fxwrap*)

(define fladd fl+)
(define flsub fl-)
(define flmult fl*)
(define fldiv fl/)

(define arithmetic_shift arithmetic-shift)
(define bitwise_merge bitwise-merge)
(define bitwise_and bitwise-and)
(define bitwise_ior bitwise-ior)
(define bitwise_xor bitwise-xor)
(define bitwise_not bitwise-not)
(define bit_count bit-count)
(define integer_length integer-length)
(define is_bit_set bit-set?)
(define is_any_bits_set any-bits-set?)
(define is_all_bits_set all-bits-set?)
(define first_bit_set first-bit-set)
(define extract_bit_field extract-bit-field)
(define is_bit_field_set test-bit-field?)
(define clear_bit_field clear-bit-field)
(define replace_bit_field replace-bit-field)
(define copy_bit_field copy-bit-field)

(define is_fx_bit_set fxbit-set?)
(define fxarithmetic_shift fxarithmetic-shift)
(define fxarithmetic_shift_left fxarithmetic-shift-left)
(define fxarithmetic_shift_right fxarithmetic-shift-right)
(define fxbit_count)
(define fxfirst_bit_set fxfirst-bit-set)
(define fxwrap_arithmetic_shift fxwraparithmetic-shift)
(define fxwrap_arithmetic_shift_left fxwraparithmetic-shift-left)
(define fxwrap_arithmetic_shift_right fxwraplogical-shift-right)

(define is_number_eq =)
(define is_number_lt <)
(define is_number_gt >)
(define is_number_lteq <=)
(define is_number_gteq >=)

(define is_fx_eq fx=)
(define is_fx_lt fx<)
(define is_fx_gt fx>)
(define is_fx_lteq fx<=)
(define is_fx_gteq fx>=)

(define is_fl_eq fl=)
(define is_fl_lt fl<)
(define is_fl_gt fl>)
(define is_fl_lteq fl<=)
(define is_fl_gteq fl>=)

(define integer_sqrt integer-sqrt)
(define integer_nth_root integer-nth-root)

(define random_integer random-integer)
(define random_real random-real)
(define random_byte_array random-u8vector)
(define random_source make-random-source)
(define random_source_state random-source-state-ref)
(define random_source_set_state random-source-state-set!)
(define random_source_randomize random-source-randomize!)
(define random_source_pseudo_randomize random-source-pseudo-randomize!)
(define random_source_for_integers random-source-make-integers)
(define random_source_for_reals random-source-make-reals)
(define random_source_for_byte_arrays random-source-make-u8vectors)

