;
; util.asm - gcd_asm and sum_range_asm, both recursive, callable from C.
;
; This is your starting point: it assembles and links as-is, so the build
; works before you write any code. Right now gcd_asm returns 0 and
; sum_range_asm returns 0, so the benchmark's --gcd and --reentrancy demos
; fail. Your job is to replace both.
;
; The contracts, from bench.c:
;
;       int b                       [ebp+12]
;       int a                       [ebp+8]
;       int gcd_asm(int a, int b)   returns the greatest common divisor
;
;       int hi                      [ebp+12]
;       int lo                      [ebp+8]
;       int sum_range_asm(lo, hi)   returns the sum of lo..hi inclusive
;
; Both are C-facing and must obey cdecl: prologue, args at [ebp+8]+, return
; in eax, preserve ebx/esi/edi/ebp, clean arguments after every call.
;
; gcd_asm also sets the global `gcd_depth` to the recursion depth of its
; most recent call. The depth is the number of gcd calls on the stack at
; the deepest point, the first call counted as 1. gcd(1071, 462) makes
; four calls, so it reaches 4. bench.c declares the global extern and
; prints it after --gcd:
;
;       int gcd_depth               (in .bss, exported, one int)
;
; The manual's requirements:
;
;   * Both recursive (Euclid's algorithm for gcd).
;   * sum_range_asm must be reentrant. It has to stay correct when a second
;     call begins before the first has finished. That means no .data or
;     .bss storage that changes during execution. Everything lives on the
;     stack and in registers. The static gcd_depth global is gcd's, not
;     sum_range's, and it is diagnostic rather than part of a result.
;   * sum_range_asm calls the C function bench_callback(void) once each
;     time C calls it, which is how bench makes one call overlap another.
;     The recursive calls must not call it again. bench counts the calls.
;     Declare it extern and call it with cdecl. It is not in the manual's
;     pseudocode, but it is what the reentrancy demo runs on.
;   * No calls into the C standard library.
;
; Euclid:
;
;   gcd(a, b):
;       if b == 0: return a
;       return gcd(b, a % b)
;
; sum_range, written so that nothing lives outside the stack:
;
;   sum_range(lo, hi):
;       if lo > hi: return 0
;       return lo + sum_range(lo + 1, hi)
;

; Windows C puts a leading underscore on every exported name. Linux C does
; not. The Makefile passes -d ELF_TYPE on Linux. This block then respells
; the names below to match. asm_io.inc does the same for _asm_main in the
; bootcamp blocks. Leave this block alone.
%ifdef ELF_TYPE
  %define _gcd_asm gcd_asm
  %define _sum_range_asm sum_range_asm
  %define _gcd_depth gcd_depth
  %define _bench_callback bench_callback
  section .note.GNU-stack noalloc noexec nowrite progbits
%endif

segment .bss
        global  _gcd_depth
_gcd_depth      resd    1

segment .text
        global  _gcd_asm
        extern  _bench_callback
_gcd_asm:
        enter   0,0
        
        ;
        ; TODO: gcd. Count the calls. Reset gcd_depth at entry, then keep
        ; the deepest level reached, with the first call as level 1. Carry
        ; the current level in a register or count it in the global, but
        ; leave the peak behind. bench.c reads gcd_depth after the call
        ; returns, so a counter that returns to zero on exit prints 0.
        ;

        ; Reset the diagnostic global so it reflects only this call.
        mov     dword [_gcd_depth], 0

        ; gcd_recursive(a, b, level) - internal convention, documented here:
        ;       [ebp+16] = level   current depth, the first call is 1
        ;       [ebp+12] = b
        ;       [ebp+8]  = a
        ; Caller pushes right to left and removes the 12 bytes afterwards,
        ; result in eax. It touches only eax/ecx/edx, so it needs no saves.
        ; The level travels on the stack, so each frame owns its own copy.
        push    dword 1                 ; level = 1
        push    dword [ebp + 12]        ; b
        push    dword [ebp + 8]         ; a
        call    .gcd_asm_recursive
        add     esp, 12                 ; 3 arguments x 4 bytes

        leave
        ret


.gcd_asm_recursive:
        push    ebp
        mov     ebp, esp

        ; Record the peak: if level > gcd_depth, gcd_depth = level.
        ; Only the maximum is stored, so the value survives the unwind.
        mov     eax, [ebp+16]
        cmp     eax, [_gcd_depth]
        jle     .depth_ok
        mov     [_gcd_depth], eax
.depth_ok:

        mov     eax, [ebp+12]
        cmp     eax, 0
        je      .return

        ; a % b
        mov     eax, [ebp+8]
        cdq
        mov     ecx, [ebp+12]
        idiv    ecx

        ; push level + 1
        mov     eax, [ebp+16]
        inc     eax
        push    eax

        ; get the a % b and push it
        mov     eax, edx
        push    eax

        ; get the b and push it
        mov     eax, [ebp+12]
        push    eax

        call    .gcd_asm_recursive
        add     esp, 12                 ; 3 arguments x 4 bytes

        jmp    .done


.return:
        mov     eax, [ebp+8]
        jmp     .done


.done:
        mov     esp, ebp
        pop     ebp
        ret









        global  _sum_range_asm
;
; sum_range_asm(lo, hi) - C-facing, cdecl.
;       [ebp+12] = hi
;       [ebp+8]  = lo
;
; Reentrancy: this routine and its helper read and write nothing outside
; their own stack frames and eax/ecx/edx. There is no .data or .bss
; variable here. lo and hi are re-read from this frame's argument slots
; after bench_callback returns, so a nested sum_range_asm started inside
; the callback (which builds its own frames lower on the stack) cannot
; change them. A non-reentrant version would keep a running total in a
; global, e.g. `acc resd 1`: the nested call would reset acc to 0 and add
; 1..100 into it, and the outer call would then finish with the wrong sum.
;
; No callee-saved register is used, so none needs saving. bench_callback
; may destroy eax/ecx/edx, which is fine because nothing is held in them
; across the call.
;
_sum_range_asm:
        enter   0,0

        ; Exactly once per call from C. The recursion below does not call it.
        call    _bench_callback

        push    dword [ebp + 12]        ; hi
        push    dword [ebp + 8]         ; lo
        call    sum_range_recursive
        add     esp, 8                  ; 2 arguments x 4 bytes

        leave                           ; result already in eax
        ret


;
; sum_range_recursive(lo, hi) - internal, same layout as cdecl:
;       [ebp+12] = hi
;       [ebp+8]  = lo
; Returns lo + (lo+1) + ... + hi in eax, or 0 when lo > hi. Caller removes
; the arguments. Uses only eax, so it preserves every other register.
;
;   sum_range(lo, hi):
;       if lo > hi: return 0
;       return lo + sum_range(lo + 1, hi)
;
sum_range_recursive:
        push    ebp
        mov     ebp, esp

        mov     eax, [ebp + 8]          ; lo
        cmp     eax, [ebp + 12]         ; signed compare: lo may be negative
        jg      .empty                  ; lo > hi -> 0

        ; sum_range(lo + 1, hi). lo + 1 cannot overflow here: lo <= hi
        ; means lo < INT_MAX.
        push    dword [ebp + 12]        ; hi
        inc     eax
        push    eax                     ; lo + 1
        call    sum_range_recursive
        add     esp, 8                  ; 2 arguments x 4 bytes

        add     eax, [ebp + 8]          ; + lo, from this frame's own slot
        jmp     .done

.empty:
        xor     eax, eax
.done:
        mov     esp, ebp
        pop     ebp
        ret
