;
; sort.asm - qsort_asm, a recursive quicksort callable from C.
;
; Module 1 of renlib. It is assembled on its own into sort.obj and linked
; with bench.o, search.obj and util.obj.
;
; The contract, from bench.c:
;
;       void qsort_asm(int *arr, int n)
;       int n                     [ebp+12]
;       int *arr                  [ebp+8]
;
; Sort n 32-bit signed integers in place, ascending. qsort_asm is the only
; C-facing routine here, so it must obey cdecl:
;   * arguments at [ebp+8] upward (the caller pushed them right to left)
;   * the return value (none here) would go in eax
;   * ebx, esi, edi and ebp are handed back unchanged (callee-saved)
;   * the caller removes the arguments after every call it makes
;
; The two internal routines, qsort_recursive and partition, use our own
; documented convention. It happens to match cdecl's layout: three dword
; arguments (arr, lo, hi) pushed right to left, cleaned up by the caller,
; and the result (partition's p) in eax.
;
; Call structure:
;
;   qsort_asm(arr, n)                          <- C calls this
;     -> qsort_recursive(arr, 0, n-1)
;          -> partition(arr, lo, hi)          returns p
;          -> qsort_recursive(arr, lo, p-1)   left part  (recursion)
;          -> qsort_recursive(arr, p+1, hi)   right part (recursion)
;
; The manual's pseudocode:
;
;   qsort(arr, lo, hi):
;       if lo >= hi: return
;       p = partition(arr, lo, hi)
;       qsort(arr, lo, p - 1)
;       qsort(arr, p + 1, hi)
;
;   partition(arr, lo, hi):          (Lomuto, last element as pivot)
;       pivot = arr[hi]
;       i = lo - 1
;       for j = lo to hi - 1:
;           if arr[j] <= pivot:
;               i = i + 1
;               swap arr[i], arr[j]
;       swap arr[i + 1], arr[hi]
;       return i + 1
;
; Array indexing: elements are 4 bytes, so arr[k] is the memory at
; arr + k*4, written [base + index*4] with x86's scaled-index addressing.
;

; Windows C puts a leading underscore on every exported name. Linux C does
; not. The Makefile passes -d ELF_TYPE on Linux. This block then respells
; the names below to match. asm_io.inc does the same for _asm_main in the
; bootcamp blocks. Leave this block alone.
%ifdef ELF_TYPE
  %define _qsort_asm qsort_asm
  section .note.GNU-stack noalloc noexec nowrite progbits
%endif

; ---------------------------------------------------------------------------
; Optional stand-alone test harness. It is built only with `nasm -d TEST`,
; never by the Makefile. It sorts a small array and exits through a Linux
; syscall without libc, so the result can be inspected in a debugger.
; ---------------------------------------------------------------------------
%ifdef TEST
segment .data
test_arr:   dd  5, -3, 9, 0, 2, 2, -7, 100, 1, 4   ; the input array
TEST_N      equ ($ - test_arr) / 4                   ; n = number of elements (10)

segment .text
        global  _start
_start:
        push    dword TEST_N        ; n    -> [ebp+12]
        push    dword test_arr      ; arr  -> [ebp+8]
        call    _qsort_asm
        add     esp, 8              ; caller cleanup: 2 args x 4 bytes

        mov     eax, 1              ; exit(0) via syscall, no libc needed
        xor     ebx, ebx
        int     0x80
%endif

segment .text
        global  _qsort_asm              ; export: C calls qsort_asm

; ===========================================================================
; void qsort_asm(int *arr, int n)                               [C-facing]
;
; Frame after `enter 0,0` and `push ebx`:
;       [ebp+12] = n
;       [ebp+8]  = arr
;       [ebp+4]  = return address into C
;       [ebp+0]  = C's saved ebp
;       [ebp-4]  = C's saved ebx            <- esp
;
; It turns (arr, n) into the inclusive bounds (arr, 0, n-1) that the
; recursive routine expects. It also handles n <= 1 (empty or one element),
; which is already sorted.
; ===========================================================================
_qsort_asm:
        enter   0,0                     ; push ebp ; mov ebp, esp  (open frame)
        push    ebx                     ; save callee-saved ebx for C.
                                        ; Popped below before leave.

        mov     ecx, [ebp + 12]         ; ecx = n

        cmp     ecx, 1                  ; signed compare n with 1
        jle     .done                   ; n <= 1: nothing to sort (covers
                                        ; tiny0.txt and tiny1.txt)

        ; Call qsort_recursive(arr, lo = 0, hi = n - 1).
        ; Arguments are pushed right to left: hi, then lo, then arr.
        mov     eax, ecx                ; eax = n
        sub     eax, 1                  ; eax = n - 1 (index of the last element)
        push    eax                     ; 3rd arg: hi = n - 1

        mov     eax, 0
        push    eax                     ; 2nd arg: lo = 0

        mov     eax, [ebp + 8]          ; eax = arr (base address)
        push    eax                     ; 1st arg: arr

        call    qsort_recursive         ; sort arr[0..n-1] in place
        add     esp, 12                 ; caller cleanup: 3 args x 4 bytes.
                                        ; Without this, `pop ebx` below would
                                        ; load arr instead of C's ebx.
        jmp     .done

.done:
        pop     ebx                     ; restore C's ebx (reverse order of saves)
        leave                           ; mov esp, ebp ; pop ebp  (close frame)
        ret                             ; back to C (void: eax is not used)


; ---------------------------------------------------------------------------
; qsort_recursive(arr, lo, hi)                       [internal, recursive]
;
; Sorts arr[lo..hi] (inclusive) in place.
;
; Frame after the prologue (push ebp; mov ebp, esp; sub esp, 4):
;       [ebp+16] = hi
;       [ebp+12] = lo
;       [ebp+8]  = arr
;       [ebp+4]  = return address (into qsort_asm or a parent level)
;       [ebp+0]  = caller's saved ebp
;       [ebp-4]  = p, the pivot's final index (local)      <- esp
;
; Each call has its own copy of arr, lo, hi and p in its own frame, which is
; why the recursion works: a child call cannot overwrite the parent's values.
; No ebx, esi or edi is used, so none is saved. Only eax is clobbered.
; ---------------------------------------------------------------------------
qsort_recursive:
        ; 1. Set up the stack frame.
        push    ebp                     ; save caller's frame pointer
        mov     ebp, esp                ; ebp = base of this frame
        sub     esp, 4                  ; reserve 4 bytes for local p at [ebp-4]

        ; 2. Base case: if lo >= hi, the range has 0 or 1 elements. Return.
        mov     eax, [ebp + 12]         ; eax = lo
        cmp     eax, [ebp + 16]         ; compare lo with hi
        jge     .base_case_qsort_recursive   ; SIGNED: hi can be -1 or lo-1

        ; 3. p = partition(arr, lo, hi). Arguments pushed right to left.
        push    dword [ebp + 16]        ; 3rd arg: hi
        push    dword [ebp + 12]        ; 2nd arg: lo
        push    dword [ebp + 8]         ; 1st arg: arr
        call    partition               ; eax = p
        add     esp, 12                 ; caller cleanup: 3 args x 4 bytes
        mov     [ebp - 4], eax          ; save p in our frame. eax will be
                                        ; overwritten by the calls below.

        ; 4. qsort_recursive(arr, lo, p - 1): sort the left part.
        ;    arr[p] is already in its final place, so it is excluded.
        mov     eax, [ebp - 4]          ; eax = p
        sub     eax, 1                  ; eax = p - 1
        push    eax                     ; 3rd arg: hi = p - 1
        push    dword [ebp + 12]        ; 2nd arg: lo
        push    dword [ebp + 8]         ; 1st arg: arr
        call    qsort_recursive         ; recursion
        add     esp, 12                 ; caller cleanup: 3 args x 4 bytes

        ; 5. qsort_recursive(arr, p + 1, hi): sort the right part.
        ;    p is re-read from [ebp-4]. The left call could not touch it,
        ;    because it lives in our frame, not in a register.
        push    dword [ebp+16]          ; 3rd arg: hi
        mov     eax, [ebp-4]            ; eax = p
        add     eax, 1                  ; eax = p + 1
        push    eax                     ; 2nd arg: lo = p + 1
        push    dword [ebp+8]           ; 1st arg: arr
        call    qsort_recursive         ; recursion
        add     esp, 12                 ; caller cleanup: 3 args x 4 bytes

        mov     esp, ebp                ; free local p (and anything below)
        pop     ebp                     ; restore caller's frame pointer
        ret                             ; back to the parent level

.base_case_qsort_recursive:
        mov     esp, ebp                ; free local p
        pop     ebp                     ; restore caller's frame pointer
        ret                             ; nothing to sort


; ---------------------------------------------------------------------------
; partition(arr, lo, hi)                       [internal, Lomuto scheme]
;
; Uses arr[hi] as the pivot. Rearranges arr[lo..hi] so that every element
; <= pivot comes before it and every element > pivot comes after it.
; Returns the pivot's final index p in eax.
;
; Frame after the prologue (push ebp; mov ebp, esp; sub esp, 12):
;       [ebp+16] = hi
;       [ebp+12] = lo
;       [ebp+8]  = arr
;       [ebp+4]  = return address (into qsort_recursive)
;       [ebp+0]  = caller's saved ebp
;       [ebp-4]  = pivot   value of arr[hi]
;       [ebp-8]  = i       end of the "<= pivot" region (starts at lo - 1)
;       [ebp-12] = j       loop index (its live copy is kept in ecx)
;
; Registers: ecx = j during the loop, edx = arr for the compare.
; ebx and esi are used only inside the pusha/popa pairs around each swap.
; pusha saves all eight general registers and popa restores them, so the
; callee-saved ebx/esi come back unchanged and ecx (= j) survives the swap.
; ---------------------------------------------------------------------------
partition:
        push    ebp                     ; save caller's frame pointer
        mov     ebp, esp                ; ebp = base of this frame
        sub     esp, 12                 ; reserve 3 locals:
                                        ;   pivot = [ebp - 4]
                                        ;   i     = [ebp - 8]
                                        ;   j     = [ebp - 12]

        ; 1. pivot = arr[hi]
        mov     eax, [ebp + 8]          ; eax = arr
        mov     ecx, [ebp+16]           ; ecx = hi
        mov     eax, [eax + ecx*4]      ; eax = arr[hi] (base + index*4)
        mov     [ebp - 4], eax          ; pivot = arr[hi]

        ; 2. i = lo - 1  (the "<= pivot" region is empty at the start)
        mov     eax, [ebp+12]           ; eax = lo
        sub     eax, 1                  ; eax = lo - 1
        mov     [ebp - 8], eax          ; i = lo - 1

        ; j = lo
        mov     eax, [ebp+12]           ; eax = lo
        mov     [ebp - 12], eax         ; j = lo

        mov     ecx, [ebp - 12]         ; ecx = j (the loop works on ecx)

; 3. Loop j from lo to hi - 1.
.loop:
        ; Continue while j <= hi - 1. Stop when j > hi - 1.
        mov     eax, [ebp+16]           ; eax = hi
        sub     eax, 1                  ; eax = hi - 1
        cmp     ecx, eax                ; compare j with hi - 1
        jg      .done                   ; SIGNED: j > hi - 1 -> loop finished

        ; 4. If arr[j] <= pivot, grow the left region and swap arr[j] into it.
        mov     eax, [ebp-4]            ; eax = pivot
        mov     edx, [ebp + 8]          ; edx = arr
        cmp     [edx + 4*ecx], eax      ; compare arr[j] with pivot
        jg      .nothing                ; SIGNED: arr[j] > pivot -> skip.
                                        ; (ja would break on negative values)

        add     dword [ebp - 8], 1      ; i = i + 1

        ; swap arr[i], arr[j]. There is no memory-to-memory mov, so both
        ; values pass through registers.
        pusha                           ; save all 8 GPRs (incl. ebx, esi, ecx=j)

        mov     ebx, [ebp+8]            ; ebx = arr
        mov     eax, [ebp-8]            ; eax = i
        mov     edx, ecx                ; edx = j  (ecx still holds j here)

        mov     ecx, [ebx + 4*eax]      ; ecx = arr[i]
        mov     esi, [ebx + 4*edx]      ; esi = arr[j]
        mov     [ebx + 4*eax], esi      ; arr[i] = arr[j]
        mov     [ebx + 4*edx], ecx      ; arr[j] = old arr[i]

        popa                            ; restore all 8: ebx/esi for the
                                        ; caller, ecx = j for the loop

        add     ecx, 1                  ; j = j + 1
        jmp     .loop                   ; next iteration

.done:
        ; 5. Put the pivot in its final position:
        ;       swap arr[i + 1], arr[hi]
        pusha                           ; save all 8 GPRs (ebx is clobbered)

        mov     eax, [ebp+16]           ; eax = hi
        mov     ebx, [ebp + 8]          ; ebx = arr

        mov     ecx, [ebx + 4*eax]      ; ecx = arr[hi] (the pivot)

        mov     eax, [ebp-8]            ; eax = i
        add     eax, 1                  ; eax = i + 1
        mov     edx, [ebx+ 4*eax]       ; edx = arr[i+1]

        mov     [ebx + 4*eax], ecx      ; arr[i+1] = arr[hi]
        mov     eax, [ebp+16]           ; eax = hi
        mov     [ebx + 4*eax], edx      ; arr[hi] = old arr[i+1]

        popa                            ; restore all 8 GPRs

        ; 6. Return p = i + 1 in eax. This must come after popa, because
        ;    popa would overwrite eax.
        mov     eax, [ebp-8]            ; eax = i
        add     eax, 1                  ; eax = i + 1 = p

        mov     esp, ebp                ; free the 3 locals
        pop     ebp                     ; restore caller's frame pointer
        ret                             ; return p to qsort_recursive


.nothing:
        ; arr[j] > pivot: leave it where it is, it belongs on the right.
        add     ecx, 1                  ; j = j + 1
        jmp     .loop                   ; next iteration
