;
; sort.asm - qsort_asm, a recursive quicksort callable from C.
;
; This is your starting point: it assembles and links as-is, so the build
; works before you write any code. Right now it does nothing, which makes
; the benchmark print "NOT SORTED" and "Match: NO". Your job is to replace
; that with the sort described below.
;
; The contract, from bench.c:
;
;       int n                     [ebp+12]
;       int *arr                  [ebp+8]
;
; Sort n 32-bit signed integers in place, ascending. This is the C-facing
; routine. It must obey cdecl (prologue, args at [ebp+8]+, return in eax,
; preserve ebx/esi/edi/ebp, clean arguments after every call it makes). The
; manual lets you use any convention you document for the internal recursive
; routine, but the outer one is fixed.
;
; Requirements from the manual:
;
;   * Recursive. An iterative sort with an explicit stack array does not
;     satisfy the activity.
;   * Lomuto partition with the last element as pivot (the manual's scheme).
;   * No calls into the C standard library.
;   * Clean the arguments off the stack after each call. The next pop
;     otherwise loads an argument into a register you promised to
;     preserve, and the outer call's array base is gone.
;
; The manual's pseudocode:
;
;   qsort(arr, lo, hi):
;       if lo >= hi: return
;       p = partition(arr, lo, hi)
;       qsort(arr, lo, p - 1)
;       qsort(arr, p + 1, hi)
;
;   partition(arr, lo, hi):
;       pivot = arr[hi]
;       i = lo - 1
;       for j = lo to hi - 1:
;           if arr[j] <= pivot:
;               i = i + 1
;               swap arr[i], arr[j]
;       swap arr[i + 1], arr[hi]
;       return i + 1
;

; Windows C puts a leading underscore on every exported name. Linux C does
; not. The Makefile passes -d ELF_TYPE on Linux. This block then respells
; the names below to match. asm_io.inc does the same for _asm_main in the
; bootcamp blocks. Leave this block alone.
%ifdef ELF_TYPE
  %define _qsort_asm qsort_asm
  section .note.GNU-stack noalloc noexec nowrite progbits
%endif

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
        add     esp, 8

        mov     eax, 1              ; exit(0) via syscall, no libc needed
        xor     ebx, ebx
        int     0x80
%endif

segment .text
        global  _qsort_asm
_qsort_asm:
        enter   0,0
        push    ebx
        

        ;
        ; TODO: sort.
        ;
        ; Remember the array elements are four bytes, so index with a *4
        ; scale. The first thing to handle is the empty and single-element
        ; arrays: n <= 1 sorts itself.
        ;

        mov     ecx, [ebp + 12] ; n elements
        

        cmp     ecx, 1
        jle     .done ; do sort



        ; entry to recursive qsort, initial bounds
        ; compute and push the hi variable
        mov     eax, ecx
        sub     eax, 1
        push    eax

        ; lo variable
        mov     eax, 0
        push    eax

        ; array
        mov     eax, [ebp + 8]
        push    eax
        
        ; call qsort recursive(arr, lo, hi)
        call    qsort_recursive
        add     esp, 12
        jmp     .done

.done:  
        pop     ebx
        leave
        ret        
        
        
       


qsort_recursive: 
        ; 1. Set up stack frame
        push    ebp
        mov     ebp, esp
        sub     esp, 4 ; for p

        ; 2. Base case: if lo >= hi, return
        mov     eax, [ebp + 12]    ; lo
        cmp     eax, [ebp + 16]    ; compare lo with hi
        jge     .base_case_qsort_recursive


        

        ; 3. Call partition(arr, lo, hi)
        push    dword [ebp + 16]
        push    dword [ebp + 12]
        push    dword [ebp + 8]
        call    partition
        add     esp, 12
        mov     [ebp - 4], eax


        ; 4. Save p, then call qsort_recursive(arr, lo, p-1)
        mov     eax, [ebp - 4]   ; p
        sub     eax, 1           ; p - 1
        push    eax              ; hi = p - 1
        push    dword [ebp + 12]
        push    dword [ebp + 8]
        call    qsort_recursive
        add     esp, 12

        ; 5. Call qsort_recursive(arr, p+1, hi)

        push    dword [ebp+16]
        mov     eax, [ebp-4]
        add     eax, 1
        push    eax
        push    dword [ebp+8]
        call    qsort_recursive
        add     esp, 12

        mov     esp, ebp
        pop     ebp
        ret

.base_case_qsort_recursive:
        mov     esp, ebp        ; return back to the previous function stack frame
        pop     ebp
        ret



partition:
        ; Arguments:
        ; [ebp+8]  = arr
        ; [ebp+12] = lo
        ; [ebp+16] = hi

        push    ebp
        mov     ebp, esp
        sub     esp, 12 ; for pivot =  [ebp - 4]
                        ; for i = [ebp - 8]
                        ; for j = [ebp - 12]


        ; 1. pivot = arr[hi]
        mov     eax, [ebp + 8]
        mov     ecx, [ebp+16]
        mov     eax, [eax + ecx*4]
        mov     [ebp - 4], eax

        ; 2. i = lo - 1
        mov     eax, [ebp+12]
        sub     eax, 1
        mov     [ebp - 8], eax

        ; j = lo
        mov     eax, [ebp+12]
        mov     [ebp - 12], eax

        mov     ecx, [ebp - 12] ; ecx = j

; 3. Loop j from lo to hi-1
.loop:
        ; if j <= hi-1
        mov     eax, [ebp+16]
        sub     eax, 1
        cmp     ecx, eax
        jg      .done

        ; 4. Swap elements when arr[j] <= pivot
        mov     eax, [ebp-4]
        mov     edx, [ebp + 8]  ;edx = arr
        cmp     [edx + 4*ecx], eax
        jg      .nothing       ; do nothing
        
        add     dword [ebp - 8], 1    ; i = i + 1


        
        ; swap arr[i], arr[j]
        pusha

        mov     ebx, [ebp+8]    ; ebx = arr
        mov     eax, [ebp-8]    ; eax = i
        mov     edx, ecx        ; edx = j  (ecx still holds j here)

        mov     ecx, [ebx + 4*eax]      ; ecx = arr[i]
        mov     esi, [ebx + 4*edx]      ; esi = arr[j]
        mov     [ebx + 4*eax], esi      ; arr[i] = arr[j]
        mov     [ebx + 4*edx], ecx      ; arr[j] = old arr[i]

        popa




        add     ecx, 1
        jmp     .loop

.done:
        
        
        ; 5. Swap pivot into its final position
        pusha

        ;       swap arr[i + 1], arr[hi]
        mov     eax, [ebp+16]   ; hi
        mov     ebx, [ebp + 8]  ; arr

        mov     ecx, [ebx + 4*eax]      ; ecx = arr[hi]
        
        mov     eax, [ebp-8]            ; i
        add     eax, 1                  ; i + 1
        mov     edx, [ebx+ 4*eax]       ; edx = arr[i+1]

        mov     [ebx + 4*eax], ecx      ; arr[i+1] = arr[hi]
        mov     eax, [ebp+16]           ; hi
        mov     [ebx + 4*eax], edx          ; arr[hi] = arr [i+1]        
                
        popa
        

        ; 6. Return p in eax
        ;       return i + 1
        mov     eax, [ebp-8]
        add     eax, 1

        
        mov     esp, ebp
        pop     ebp
        ret


.nothing:
        add     ecx, 1
        jmp     .loop