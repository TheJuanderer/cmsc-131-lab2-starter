;
; util.asm - gcd_asm and sum_range_asm, both recursive, callable from C.
;
; Module 3 of renlib. It is assembled on its own into util.obj and linked
; with bench.o, sort.obj and search.obj.
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
; Both are C-facing and must obey cdecl:
;   * The caller pushes the arguments right to left, so the first argument
;     ends up nearest the return address, at [ebp+8].
;   * `call` pushes the return address, which sits at [ebp+4].
;   * The callee returns its result in eax.
;   * The callee must hand back ebx, esi, edi, ebp and esp unchanged. It
;     may destroy eax, ecx and edx (the caller-saved scratch registers).
;   * The CALLER removes the arguments after the call (add esp, 4*nargs).
;
; gcd_asm also sets the global `gcd_depth` to the recursion depth of its
; most recent call: the number of gcd calls on the stack at the deepest
; point, the first call counted as 1. gcd(1071, 462) makes four calls,
; (1071,462) -> (462,147) -> (147,21) -> (21,0), so it reaches 4.
;
; sum_range_asm must be reentrant: correct even when a second call starts
; before the first has finished. bench_callback (a C function) starts that
; second call. That is why sum_range_asm keeps NO state in .data or .bss.
;
; Euclid:                                 sum_range:
;
;   gcd(a, b):                              sum_range(lo, hi):
;       if b == 0: return a                     if lo > hi: return 0
;       return gcd(b, a % b)                    return lo + sum_range(lo + 1, hi)
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

; ---------------------------------------------------------------------------
; Data. .bss holds uninitialised storage (zeroed when the program loads).
; ---------------------------------------------------------------------------
segment .bss
        global  _gcd_depth              ; export it so bench.c can read it
_gcd_depth      resd    1               ; reserve 1 dword (4 bytes) for the depth

segment .text
        global  _gcd_asm                ; export: C calls gcd_asm
        extern  _bench_callback         ; import: defined in bench.c

; ===========================================================================
; int gcd_asm(int a, int b)                                     [C-facing]
;
; Frame after `enter 0,0`:
;       [ebp+12] = b
;       [ebp+8]  = a
;       [ebp+4]  = return address into C
;       [ebp+0]  = C's saved ebp
;
; It resets gcd_depth, then calls the recursive helper with level = 1.
; Registers: it uses only eax (via the helper), so it saves nothing.
; ===========================================================================
_gcd_asm:
        enter   0,0                     ; push ebp ; mov ebp, esp  (open frame)

        ; Reset the diagnostic global so it reflects only this call.
        ; `dword` tells NASM the memory operand is 4 bytes wide.
        mov     dword [_gcd_depth], 0

        ; Call gcd_recursive(a, b, level). Internal convention (ours):
        ;       [ebp+16] = level   current depth, the first call is 1
        ;       [ebp+12] = b
        ;       [ebp+8]  = a
        ; The caller pushes right to left and removes the 12 bytes after.
        ; The result comes back in eax. The helper touches only eax, ecx and
        ; edx, so it needs to save nothing. The level travels on the stack,
        ; so each frame owns its own copy.
        push    dword 1                 ; 3rd arg: level = 1
        push    dword [ebp + 12]        ; 2nd arg: b
        push    dword [ebp + 8]         ; 1st arg: a (pushed last, sits lowest)
        call    .gcd_asm_recursive      ; pushes return address, jumps
        add     esp, 12                 ; caller cleanup: 3 args x 4 bytes

        leave                           ; mov esp, ebp ; pop ebp  (close frame)
        ret                             ; pop return address -> back to C.
                                        ; eax still holds the gcd.


; ---------------------------------------------------------------------------
; gcd_recursive(a, b, level)                         [internal, recursive]
;
; Frame after the prologue:
;       [ebp+16] = level
;       [ebp+12] = b
;       [ebp+8]  = a
;       [ebp+4]  = return address (into gcd_asm or into a parent level)
;       [ebp+0]  = caller's saved ebp
;
; Returns gcd(a, b) in eax. It clobbers only eax, ecx and edx.
; ---------------------------------------------------------------------------
.gcd_asm_recursive:
        push    ebp                     ; save caller's frame pointer
        mov     ebp, esp                ; ebp = base of this frame

        ; Record the peak: if level > gcd_depth, gcd_depth = level.
        ; Only the maximum is stored, so the value survives the unwind.
        ; (A counter that is incremented on entry and decremented on exit
        ; would be back at 0 when bench.c reads it.)
        mov     eax, [ebp+16]           ; eax = level
        cmp     eax, [_gcd_depth]       ; signed compare level vs. stored peak
        jle     .depth_ok               ; level <= peak: nothing to record
        mov     [_gcd_depth], eax       ; new peak
.depth_ok:

        ; Base case: if b == 0, return a.
        mov     eax, [ebp+12]           ; eax = b
        cmp     eax, 0
        je      .return                 ; b == 0 -> answer is a

        ; a % b using idiv. idiv divides the 64-bit edx:eax by its operand:
        ; quotient -> eax, remainder -> edx. cdq sign-extends eax into edx
        ; first. (`mov edx, 0` would be wrong for a negative dividend.)
        mov     eax, [ebp+8]            ; eax = a (the dividend)
        cdq                             ; edx:eax = sign-extended a
        mov     ecx, [ebp+12]           ; ecx = b (the divisor, never 0 here)
        idiv    ecx                     ; eax = a / b, edx = a % b

        ; Recurse: gcd_recursive(b, a % b, level + 1), args pushed right to left.
        mov     eax, [ebp+16]           ; eax = level
        inc     eax                     ; level + 1: the child is one deeper
        push    eax                     ; 3rd arg: level + 1

        mov     eax, edx                ; eax = a % b
        push    eax                     ; 2nd arg: a % b

        mov     eax, [ebp+12]           ; eax = b
        push    eax                     ; 1st arg: b

        call    .gcd_asm_recursive      ; eax = gcd(b, a % b)
        add     esp, 12                 ; caller cleanup: 3 args x 4 bytes

        jmp    .done                    ; eax already holds the answer


.return:
        mov     eax, [ebp+8]            ; base case result: a
        jmp     .done


.done:
        mov     esp, ebp                ; drop anything below the frame
        pop     ebp                     ; restore caller's frame pointer
        ret                             ; return to the parent level


        global  _sum_range_asm          ; export: C calls sum_range_asm
; ===========================================================================
; int sum_range_asm(int lo, int hi)                             [C-facing]
;
; Frame after `enter 0,0`:
;       [ebp+12] = hi
;       [ebp+8]  = lo
;       [ebp+4]  = return address into C
;       [ebp+0]  = C's saved ebp
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
; ===========================================================================
_sum_range_asm:
        enter   0,0                     ; push ebp ; mov ebp, esp

        ; Exactly once per call from C. The recursion below does not call it,
        ; otherwise bench would count more than 2 callbacks. bench_callback
        ; takes no arguments, so there is nothing to push or clean up. This is
        ; the moment bench starts the nested sum_range_asm(1, 100).
        call    _bench_callback

        ; sum_range_recursive(lo, hi), args pushed right to left.
        push    dword [ebp + 12]        ; 2nd arg: hi (from our own frame)
        push    dword [ebp + 8]         ; 1st arg: lo
        call    sum_range_recursive     ; eax = lo + ... + hi
        add     esp, 8                  ; caller cleanup: 2 args x 4 bytes

        leave                           ; mov esp, ebp ; pop ebp
        ret                             ; result already in eax


; ---------------------------------------------------------------------------
; sum_range_recursive(lo, hi)                         [internal, recursive]
;
; Frame after the prologue (same layout as cdecl):
;       [ebp+12] = hi
;       [ebp+8]  = lo
;       [ebp+4]  = return address
;       [ebp+0]  = caller's saved ebp
;
; Returns lo + (lo+1) + ... + hi in eax, or 0 when lo > hi. The caller
; removes the arguments. It uses only eax, so every other register is
; preserved. The depth is hi - lo + 2 frames of 16 bytes each.
;
;   sum_range(lo, hi):
;       if lo > hi: return 0
;       return lo + sum_range(lo + 1, hi)
; ---------------------------------------------------------------------------
sum_range_recursive:
        push    ebp                     ; save caller's frame pointer
        mov     ebp, esp                ; ebp = base of this frame

        mov     eax, [ebp + 8]          ; eax = lo
        cmp     eax, [ebp + 12]         ; compare lo with hi
        jg      .empty                  ; SIGNED jump: lo > hi -> 0.
                                        ; (ja would treat -5 as huge)

        ; sum_range(lo + 1, hi). lo + 1 cannot overflow here: lo <= hi
        ; means lo < INT_MAX.
        push    dword [ebp + 12]        ; 2nd arg: hi (unchanged)
        inc     eax                     ; eax = lo + 1
        push    eax                     ; 1st arg: lo + 1
        call    sum_range_recursive     ; eax = (lo+1) + ... + hi
        add     esp, 8                  ; caller cleanup: 2 args x 4 bytes

        ; Add this level's lo, re-read from THIS frame's own slot. Nothing
        ; was kept in a register across the call, and no global is used.
        add     eax, [ebp + 8]          ; eax = lo + sum_range(lo + 1, hi)
        jmp     .done

.empty:
        xor     eax, eax                ; eax = 0 (shorter than mov eax, 0)
.done:
        mov     esp, ebp                ; discard the frame
        pop     ebp                     ; restore caller's frame pointer
        ret                             ; back to the parent level / wrapper
