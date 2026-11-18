;
; search.asm - bsearch_asm, a recursive binary search callable from C.
;
; Module 2 of renlib. It is assembled on its own into search.obj and linked
; with bench.o, sort.obj and util.obj.
;
; The contract, from bench.c:
;
;       int bsearch_asm(int *arr, int n, int key)
;       int key                    [ebp+16]
;       int n                      [ebp+12]
;       int *arr                   [ebp+8]
;
; Returns the index of key in the sorted (ascending) array, or -1 if it is
; absent. bsearch_asm is C-facing and obeys cdecl: arguments at [ebp+8]
; upward, result in eax, ebx/esi/edi/ebp preserved, and the caller removes
; the arguments after each call.
;
; The internal routine bsearch_recursive uses our own documented
; convention. It matches cdecl's layout: four dword arguments
; (arr, lo, hi, key) pushed right to left, cleaned up by the caller, and the
; result in eax.
;
; Midpoint: computed as lo + (hi - lo) / 2, never (lo + hi) / 2.
; lo + hi can exceed 2^31 - 1 and wrap to a negative number once hi
; reaches 2^30, putting mid outside the array. hi - lo is never larger than
; the array length, so it cannot overflow, and adding its half back to lo
; stays between lo and hi. (This exact bug lived in Java's
; Arrays.binarySearch for nine years.) No test can catch it: overflow needs
; a 4 GB array, which is the entire 32-bit address space.
;
; The manual's pseudocode:
;
;   bsearch(arr, lo, hi, key):
;       if lo > hi: return -1
;       mid = lo + (hi - lo) / 2
;       if arr[mid] == key: return mid
;       if arr[mid] < key:  return bsearch(arr, mid + 1, hi, key)
;       else:               return bsearch(arr, lo, mid - 1, key)
;

; Windows C puts a leading underscore on every exported name. Linux C does
; not. The Makefile passes -d ELF_TYPE on Linux. This block then respells
; the names below to match. asm_io.inc does the same for _asm_main in the
; bootcamp blocks. Leave this block alone.
%ifdef ELF_TYPE
  %define _bsearch_asm bsearch_asm
  section .note.GNU-stack noalloc noexec nowrite progbits
%endif

segment .text
        global  _bsearch_asm            ; export: C calls bsearch_asm

; ===========================================================================
; int bsearch_asm(int *arr, int n, int key)                     [C-facing]
;
; Frame after `enter 0,0`:
;       [ebp+16] = key
;       [ebp+12] = n
;       [ebp+8]  = arr
;       [ebp+4]  = return address into C
;       [ebp+0]  = C's saved ebp
;
; It converts the count n into inclusive bounds lo = 0, hi = n - 1. An empty
; array (n = 0) gives hi = -1, so the recursive routine's lo > hi base case
; returns -1 immediately, with no special case needed here.
; Registers: it uses only eax, so it saves nothing.
; ===========================================================================
_bsearch_asm:
        enter   0,0                     ; push ebp ; mov ebp, esp  (open frame)

        ; Call bsearch_recursive(arr, lo, hi, key), pushed right to left.
        mov     eax, [ebp+16]           ; eax = key
        push    eax                     ; 4th arg: key

        mov     eax, [ebp+12]           ; eax = n
        sub     eax, 1                  ; eax = n - 1 (last valid index)
        push    eax                     ; 3rd arg: hi = n - 1

        mov     eax, 0
        push    eax                     ; 2nd arg: lo = 0

        mov     eax, [ebp+8]            ; eax = arr (base address)
        push    eax                     ; 1st arg: arr

        call    bsearch_recursive       ; eax = index or -1
        add    esp, 16                  ; caller cleanup: 4 args x 4 bytes

        jmp     _bsearch_asm_done

_bsearch_asm_done:
        leave                           ; mov esp, ebp ; pop ebp  (close frame)
        ret                             ; back to C, result in eax


; ---------------------------------------------------------------------------
; bsearch_recursive(arr, lo, hi, key)                [internal, recursive]
;
; Searches arr[lo..hi] (inclusive). Returns the index of key or -1.
;
; Frame after the prologue (push ebp; mov ebp, esp; sub esp, 4):
;       [ebp+20] = key
;       [ebp+16] = hi
;       [ebp+12] = lo
;       [ebp+8]  = arr
;       [ebp+4]  = return address (into bsearch_asm or a parent level)
;       [ebp+0]  = caller's saved ebp
;       [ebp-4]  = mid (local)
;       [ebp-8]  = saved ebx, only while the midpoint is computed
;
; ebx is callee-saved, so it is pushed before use and popped before any
; branch or call. eax, ecx and edx are scratch. Every recursive call is a
; tail position: its eax result is returned unchanged.
; ---------------------------------------------------------------------------
bsearch_recursive:
        ; 1. Set up the stack frame.
        push    ebp                     ; save caller's frame pointer
        mov     ebp, esp                ; ebp = base of this frame
        sub     esp, 4                  ; [ebp - 4] = mid (lo + (hi - lo) / 2)

        ; 2. Base case: if lo > hi, the range is empty and key is absent.
        mov     eax, [ebp + 16]         ; eax = hi
        cmp     [ebp + 12], eax         ; compare lo with hi
        jg      .bsearch_recursive_absent_key  ; SIGNED: hi may be -1

        push    ebx                     ; save callee-saved ebx (we divide by it)

        ; 3. mid = lo + (hi - lo) / 2  -- the overflow-safe form (see header).
        mov     eax, [ebp + 16]         ; eax = hi
        sub     eax, [ebp + 12]         ; eax = hi - lo. Never negative here,
                                        ; because the base case ran first.

        mov     ebx, 2                  ; divisor = 2

        ; eax / 2 using unsigned div: edx:eax / ebx -> quotient eax.
        ; Zeroing edx (instead of cdq) is correct ONLY because hi - lo >= 0.
        xor     edx, edx                ; edx = 0, high half of the dividend
        div     ebx                     ; eax = (hi - lo) / 2, edx = remainder

        add     eax, [ebp + 12]         ; eax = lo + (hi - lo) / 2
        mov     [ebp - 4], eax          ; mid = eax (kept in our frame)

        ; 4. Load arr[mid] and key so they can be compared.
        mov     ecx, [ebp - 4]          ; ecx = mid
        mov     eax, [ebp + 8]          ; eax = arr
        mov     ebx, [ebp + 20]         ; ebx = key

        mov     eax, [eax + 4*ecx]      ; eax = arr[mid] (base + index*4)
        mov     ecx, ebx                ; ecx = key (moved out of ebx)

        pop     ebx                     ; restore caller's ebx. It is not
                                        ; needed again in this call.

        ; if arr[mid] == key: return mid
        cmp     eax, ecx                ; compare arr[mid] with key
        je      .bsearch_recursive_mid  ; found

        ; if arr[mid] < key: return bsearch(arr, mid + 1, hi, key)
        cmp     eax, ecx
        jl      .bsearch_recursive_less_than_key  ; SIGNED: arrays hold negatives

        ; else (arr[mid] > key): return bsearch(arr, lo, mid - 1, key)
        jmp     .else


; Common exit. eax already holds the result.
.bsearch_recursive_done:
        mov     esp, ebp                ; free local mid
        pop     ebp                     ; restore caller's frame pointer
        ret                             ; back to parent level / bsearch_asm


.bsearch_recursive_absent_key:
        mov     eax, -1                 ; empty range: key not present
        jmp     .bsearch_recursive_done


.bsearch_recursive_mid:
        mov     eax, [EBP - 4]          ; return mid (the index where key is)
        jmp     .bsearch_recursive_done


; arr[mid] < key: the key can only be in the right half, mid+1..hi.
.bsearch_recursive_less_than_key:
        ; push (arr, mid + 1, hi, key) from right to left
        mov     eax, [ebp + 20]         ; eax = key
        push    eax                     ; 4th arg: key

        mov     eax, [ebp + 16]         ; eax = hi
        push    eax                     ; 3rd arg: hi

        mov     eax, [ebp - 4]          ; eax = mid
        add     eax, 1                  ; eax = mid + 1 (mid already checked)
        push    eax                     ; 2nd arg: lo = mid + 1

        mov     eax, [ebp + 8]          ; eax = arr
        push    eax                     ; 1st arg: arr

        call    bsearch_recursive       ; recursion. eax = result
        add    esp, 16                  ; caller cleanup: 4 args x 4 bytes

        jmp     .bsearch_recursive_done ; pass the child's eax straight up


; arr[mid] > key: the key can only be in the left half, lo..mid-1.
.else:
        ; push (arr, lo, mid - 1, key) from right to left
        mov     eax, [ebp + 20]         ; eax = key
        push    eax                     ; 4th arg: key

        mov     eax, [ebp - 4]          ; eax = mid
        sub     eax, 1                  ; eax = mid - 1 (mid already checked)
        push    eax                     ; 3rd arg: hi = mid - 1

        mov     eax, [ebp + 12]         ; eax = lo
        push    eax                     ; 2nd arg: lo

        mov     eax, [ebp + 8]          ; eax = arr
        push    eax                     ; 1st arg: arr

        call    bsearch_recursive       ; recursion. eax = result
        add    esp, 16                  ; caller cleanup: 4 args x 4 bytes

        jmp     .bsearch_recursive_done ; pass the child's eax straight up
