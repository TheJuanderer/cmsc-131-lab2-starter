;
; search.asm - bsearch_asm, a recursive binary search callable from C.
;
; This is your starting point: it assembles and links as-is, so the build
; works before you write any code. Right now it always returns 0, which
; makes the benchmark report a match at index 0 for any key. Your job is to
; replace that with the search described below.
;
; The contract, from bench.c:
;
;       int key                    [ebp+16]
;       int n                      [ebp+12]
;       int *arr                   [ebp+8]
;
; Return the index of key in the sorted array, or -1 if it is absent.
; Preserve ebx/esi/edi/ebp, return in eax, and obey cdecl for the outer
; routine (the internal recursive one may use any convention you document).
;
; Requirements from the manual:
;
;   * Recursive.
;   * Compute the midpoint as lo + (hi - lo) / 2, never (lo + hi) / 2.
;     The sum can overflow 32 bits on large arrays. The difference cannot.
;     This exact bug lived in the Java standard library for nine years.
;   * An absent key returns -1.
;   * An empty array and a single-element array must behave.
;   * No calls into the C standard library.
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
        global  _bsearch_asm
_bsearch_asm:
        enter   0,0


        ;
        ; TODO: search.
        ;
        ; n is a count, so the search range is lo=0, hi=n-1. An empty array
        ; has n=0, which makes hi=-1 before the first comparison. That case
        ; must return -1 immediately.
        ;
        ; For the midpoint, compute hi - lo first, halve it, then add lo.
        ; The base case runs before the midpoint, so hi - lo is never
        ; negative there and a shift halves it. If you reach for idiv
        ; instead, sign-extend with cdq. mov edx, 0 is right only for a
        ; dividend that cannot be negative.
        ;


        
        ; push (arr, lo, hi, key) from right to left
        ; push key
        mov     eax, [ebp+16]
        push    eax

        ; push hi
        mov     eax, [ebp+12]
        sub     eax, 1
        push    eax

        ; push lo
        mov     eax, 0
        push    eax

        ; push arr
        mov     eax, [ebp+8]
        push    eax

        call    bsearch_recursive
        add    esp, 16

        jmp     _bsearch_asm_done

_bsearch_asm_done:
        leave
        ret



bsearch_recursive:
        ; 1. Set up stack frame
        push    ebp
        mov     ebp, esp
        sub     esp, 4 ; [ebp - 4] = mid (lo + (hi - lo) / 2)



        mov     eax, [ebp + 16] ; hi
        cmp     [ebp + 12], eax
        jg      .bsearch_recursive_absent_key
        

        
        push    ebx

        ;  mid = lo + (hi - lo) / 2
        ; eax = mid
        
        ; (hi - lo)
        mov     eax, [ebp + 16]
        sub     eax, [ebp + 12]

        mov     ebx, 2

        ; eax / 2
        xor     edx, edx    ; Clear EDX
        div     ebx         ; EDX:EAX / EBX

        ; lo + eax
        add     eax, [ebp + 12] 
        mov     [ebp - 4], eax          ; mid local variable

        ;       if arr[mid] == key: return mid
        mov     ecx, [ebp - 4]  ; [mid]
        mov     eax, [ebp + 8]  ; arr
        mov     ebx, [ebp + 20] ; key

        mov     eax, [eax + 4*ecx]
        mov     ecx, ebx        ; key

        pop     ebx





        cmp     eax, ecx
        je      .bsearch_recursive_mid




        ; if arr[mid] < key:  return bsearch(arr, mid + 1, hi, key)
        cmp     eax, ecx
        jl      .bsearch_recursive_less_than_key


        ; else:               return bsearch(arr, lo, mid - 1, key)
        jmp     .else


.bsearch_recursive_done:
        mov     esp, ebp
        pop     ebp
        ret



.bsearch_recursive_absent_key:
        mov     eax, -1
        jmp     .bsearch_recursive_done


.bsearch_recursive_mid:
        mov     eax, [EBP - 4]
        jmp     .bsearch_recursive_done



; if arr[mid] < key
.bsearch_recursive_less_than_key:
        ; push (arr, mid + 1, hi, key) from right to left
        mov     eax, [ebp + 20]
        push    eax

        mov     eax, [ebp + 16]
        push    eax

        mov     eax, [ebp - 4]
        add     eax, 1
        push    eax

        mov     eax, [ebp + 8]
        push    eax

        call    bsearch_recursive
        add    esp, 16

        jmp     .bsearch_recursive_done




.else:
        ; push (arr, lo, mid - 1, key) from right to left
        mov     eax, [ebp + 20]
        push    eax

        mov     eax, [ebp - 4]
        sub     eax, 1
        push    eax

        mov     eax, [ebp + 12]
        push    eax

        mov     eax, [ebp + 8]
        push    eax

        call    bsearch_recursive
        add    esp, 16

        jmp     .bsearch_recursive_done