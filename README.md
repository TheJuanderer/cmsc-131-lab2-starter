<!--no-pdf-->
# CMSC 131 Lab 2 Starter

[![lab2-checks](https://github.com/WhiteLicorice/cmsc-131-lab2-starter/actions/workflows/test.yml/badge.svg)](https://github.com/WhiteLicorice/cmsc-131-lab2-starter/actions/workflows/test.yml)

A C-callable library of sort, search, and utility routines in assembly. The manual is the assignment. This file is the repository's own notes.

## Layout

```text
Makefile       platform preamble and build rules
bench.c        provided: file I/O, timing, the C-side comparison, the hostile caller
cdecl.h        provided: the calling-convention macros
LICENSE        provided
sort.asm       yours
search.asm     yours
util.asm       yours
run_tests.sh   provided: the correctness gate
tests/         provided: the test corpus
```

## What to Run

On Windows, run these commands in Git Bash, the shell from Block 1. In that
shell, `make` is your alias for `mingw32-make`. On Linux, use your terminal.

```bash
make
make check
```

`make` builds `bench`. `make check` builds, then runs `./run_tests.sh`,
which reports each check and exits nonzero when any of them fail. Each run
is captured first. Its exit status is read before its text is examined,
so a program that prints the right line and then crashes still fails.

## Reading a First Run

The assembly files ship as stubs that assemble and link as-is, so the build
works before you write any code. Right now they do nothing useful, and 19
of the 36 checks fail. The seventeen that pass prove little. Four are files
that arrive empty, single-element, or already sorted. `gcd(0, 0)` expects 0.
The hostile caller cannot be upset by a stub that touches no register. The
rest are argument and file refusals that the harness performs before any
assembly runs. That red run is the correct starting state for a starter. The
badge stays red until you implement the routines.

The provided files are fixtures. The grader compares your fork against the
starter. An edit to `bench.c`, `Makefile`, `run_tests.sh`, or a `tests/`
file appears as a diff in the open.

## Documentation

The three sections at the end of this file are yours. Complete Design Notes
and Subsystem Ownership before the Week 1 progress report. Complete Quirks
and Issues before the Week 3 progress report. Each section says what it
needs. Leave the rest of this file as it is.

---

## Design Notes

Complete this section before the Week 1 progress report and finish it by
Week 3. The syllabus asks for problem analysis, a solution architecture,
and an estimated timeline. The manual's Deliverables section lists what
this activity adds. Keep each part short. Update it when the plan changes.

### Problem analysis

The activity requires implementing four assembly routines that can be called from C. The routines must produce correct results and follow the 32-bit x86 cdecl calling convention.

`qsort_asm(int *arr, int n)` — Sorts an array of n integers in ascending order. It does not return a value.

`bsearch_asm(int *arr, int n, int key)` — Searches for key in a sorted array and returns its index if found, or -1 if absent.

`gcd_asm(int a, int b)` — Computes and returns the greatest common divisor (GCD) of two nonnegative integers. It also records the recursion depth in gcd_depth.

`sum_range_asm(int lo, int hi)` — Computes and returns the sum of integers from lo to hi, inclusive. It must support nested calls without interfering with an earlier invocation.

All routines must follow the cdecl calling convention. The callee must preserve the EBX, ESI, and EDI registers because they are callee-saved registers. It must also preserve EBP and leave stack cleanup to the caller. Return values are placed in EAX for routines that return an integer. These requirements are necessary for compatibility with C and are tested by the provided hostile caller.

**Note**
- qsort_asm returns void since the returned value is in one of the input itself, while the other three routines return integers. Also, the gcd_depth global is specifically required for reporting recursion depth; it is not the GCD result itself.

### Solution architecture

A stack frame diagram for one recursive call of `qsort_asm`, showing where
the arguments, the return address, saved `ebp`, and the saved registers
sit. Why `sum_range_asm` is reentrant.

`_qsort_asm`
Purpose: C-facing function that starts QuickSort.

Stack frame:
[EBP + 12] = n       (number of elements)
[EBP + 8]  = arr     (array pointer)
[EBP + 4]  = return address
[EBP]      = saved EBP


`qsort_recursive`
Purpose: Recursively sort the array sections.

Arguments:
[EBP + 8]  = arr
[EBP + 12] = lo
[EBP + 16] = hi

Stack frame:
[EBP + 16] = hi
[EBP + 12] = lo
[EBP + 8]  = arr
[EBP + 4]  = return address
[EBP]      = saved EBP

Local variables:
[EBP - 4] = p (pivot's final index)


`partition`
Purpose: Place the pivot in its correct position.

Arguments:
[EBP + 8]  = arr
[EBP + 12] = lo
[EBP + 16] = hi

Stack frame:
[EBP + 16] = hi
[EBP + 12] = lo
[EBP + 8]  = arr
[EBP + 4]  = return address
[EBP]      = saved EBP

Local variables:
[EBP - 4]  = pivot (arr[hi])
[EBP - 8]  = i (boundary index)
[EBP - 12] = j (loop index)







### Measurements

The ratio `bench` reports on `random1000.txt`, `sorted1000.txt`,
`reverse1000.txt`, `duplicates.txt`, and `identical.txt`. Your worst case
and its cause. One improvement and its estimated effect.

| File | Ratio |
|---|---|
| `random1000.txt` | |
| `sorted1000.txt` | |
| `reverse1000.txt` | |
| `duplicates.txt` | |
| `identical.txt` | |

### Timeline

One line per week. Name the subsystem each week finishes and the member
who owns it.

| Week | Goal | Owner |
|---|---|---|
| 1 |Problem Analysis and Ownership |Brent|
| 2 |qsort & bsearch|Chua|
| 3 |gcd & sum_range|JM|
| 4 | Defense | |

## Subsystem Ownership

Complete this section before the Week 1 progress report. The manual lists
the three subsystems. Each member owns one. In a group of four, two members
share one. The commit history must agree with this table.

| Subsystem | Owner |
|---|---|
| Sorting (`qsort_asm` and its partition) |Brent |
| Searching (`bsearch_asm`, `gcd_asm`) |Chua|
| Convention and measurement (`sum_range_asm`, the benchmarks) |JM|

## Quirks and Issues

Complete this section before the Week 3 progress report. The syllabus asks
for documentation of quirks and issues with the complete implementation.
One entry per item. State what happens, what causes it, and what the group
did about it.

### Known issues

- 

### Quirks

- 
