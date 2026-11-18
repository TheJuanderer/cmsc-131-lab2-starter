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

#### Stack frame of one recursive `qsort_recursive` call

The stack grows toward lower addresses. This is the view from inside a call
`qsort_recursive(arr, lo, p - 1)` made by its parent, once its prologue
(`push ebp; mov ebp, esp; sub esp, 4`) has run:

```text
higher addresses
        |  ...parent's frame (its own p, saved ebp, args)...  |
        +-----------------------------------------------------+
EBP+16  |  hi   = p - 1          pushed first by the parent   |  arguments,
EBP+12  |  lo                                                 |  pushed right
EBP+8   |  arr  (base address)   pushed last                  |  to left
        +-----------------------------------------------------+
EBP+4   |  return address        pushed by `call`             |
EBP+0   |  saved EBP (parent's frame pointer)  <-- EBP        |  prologue
EBP-4   |  p    (partition result, local)      <-- ESP        |  sub esp, 4
        +-----------------------------------------------------+
        |  args for the next call: hi, lo, arr, then its      |
        |  return address, saved EBP, p ... (child frame)     |
lower addresses
```

Saved registers: `qsort_recursive` saves none because it keeps nothing in
`ebx`, `esi` or `edi`. Its only values that must survive a call (`arr`, `lo`,
`hi`, `p`) live at fixed `ebp` offsets in its own frame, so a child call
cannot clobber them. `partition` saves and restores registers around each
swap with `pusha`/`popa`. The C-facing `qsort_asm` pushes `ebx` just below
its saved `ebp`, at `[ebp-4]`, and pops it before `leave`. After every call,
the caller removes the arguments with `add esp, 12`.

#### Registers we preserve, and why

| Register | Status under cdecl | What our code does |
|---|---|---|
| `eax`, `ecx`, `edx` | caller-saved (scratch) | Used freely. `eax` carries every return value. Nothing that must survive a `call` is kept in them. Values are reloaded from the frame instead. |
| `ebx`, `esi`, `edi` | callee-saved | `qsort_asm` saves `ebx`. `partition` uses `ebx`/`esi` only between `pusha` and `popa`. `bsearch_recursive` pushes and pops `ebx` around the division. `gcd_asm` and `sum_range_asm` never touch them. |
| `ebp` | callee-saved | Every routine opens with `enter 0,0` or `push ebp; mov ebp, esp` and closes with `leave` or `mov esp, ebp; pop ebp`. |
| `esp` | must be balanced | Each `call` is followed by `add esp, 4*nargs`, and locals are released by `mov esp, ebp` or `leave`. |

The reason is that C (and our own recursion) keeps live values in the
callee-saved registers across calls. A recursive routine is its own caller,
so a clobbered register would corrupt the outer invocation of the same
routine. `./bench --hostile` loads sentinels into `ebx`/`esi`/`edi`, checks
that they and `esp` come back unchanged, and passes for all four routines.

#### Why `sum_range_asm` is reentrant

`sum_range_asm` and its helper `sum_range_recursive` keep **no mutable state
outside their own stack frames**. There is no `.data` or `.bss` variable in
the routine. `lo` and `hi` sit in each call's argument slots. The partial
sum is returned in `eax` and added to `[ebp+8]` (this frame's own `lo`) after
the child returns. When `bench_callback` starts a nested
`sum_range_asm(1, 100)`, the nested call builds its frames *below* the outer
call's frame and returns before the outer one continues. The outer call then
reads `lo`/`hi` from its own untouched slots.

A non-reentrant version would keep an accumulator in `.bss`
(`acc resd 1`): zero it on entry, call the callback, then add `lo..hi` into
`acc`. The nested call made from inside the callback would also zero `acc` and
leave 5050 in it. The outer call would resume and add 1..1000 on top of
5050, giving 505550, not 500500. A global loop counter would fail the same
way. `gcd_depth` is the only global in `util.asm`. It belongs to `gcd_asm` and
is diagnostic. Because of it, `gcd_asm` itself is *not* reentrant (see
Quirks).

### Measurements

The ratio `bench` reports on `random1000.txt`, `sorted1000.txt`,
`reverse1000.txt`, `duplicates.txt`, and `identical.txt`. Your worst case
and its cause. One improvement and its estimated effect.

Measured on Linux (WSL2, gcc -m32). Each figure is the range over three
runs of `./bench --sort <file>`. bench already averages 200 sorts per run.

| File | `qsort_asm` (ms) | C `qsort` (ms) | Ratio |
|---|---|---|---|
| `random1000.txt` | 0.089 – 0.093 | 0.138 – 0.142 | 0.65x |
| `sorted1000.txt` | 4.21 – 4.33 | 0.062 – 0.071 | 60 – 70x |
| `reverse1000.txt` | 2.38 – 2.43 | 0.070 – 0.074 | 32 – 34x |
| `duplicates.txt` | 0.275 – 0.288 | 0.038 – 0.042 | 6.6 – 7.5x |
| `identical.txt` | 0.043 | 0.004 – 0.005 | 9 – 10.5x |

**Random input.** We beat C's `qsort`. As the manual warns, this says more
about C than about us: C calls `cmp_int` through a function pointer for
every comparison, while we compare in a register.

**Worst case: `sorted1000.txt`.** Lomuto with the last element as pivot
picks the *maximum* of every subarray on sorted input. Every element is
`<= pivot`, so each partition leaves `n-1` elements on the left and none on
the right. The recursion is `n` levels deep instead of about `log2 n`, and
the total work is about n²/2 = 500,000 comparisons, against about
n log2 n ≈ 10,000 on random input. Sorted input is worse than reversed input
because every comparison is followed by a swap (`arr[i]` with itself), and
our swap runs `pusha`/`popa` (16 extra stack operations) each time. On
reversed input the pivot is the minimum, so almost no swaps happen. The
recursion is still quadratic, which is why `reverse1000.txt` sits at about
half the cost. `identical.txt` and `duplicates.txt` hit the same quadratic
pattern within each run of equal keys, because `<=` sends every equal key to
one side.

**One improvement: median-of-three pivot.** Before partitioning, order
`arr[lo]`, `arr[mid]`, `arr[hi]` and swap the median into `arr[hi]`. Lomuto
then runs unchanged. On sorted and reversed input the median is the true
middle, so the recursion becomes balanced, about n log n. We estimate
`sorted1000.txt` would fall from about 4.3 ms to about 0.1 ms, roughly
40×–50× faster, which takes its ratio from about 65x to around 1x. Separately,
replacing the `pusha`/`popa` around each swap with two scratch registers
(`eax`/`edx`, as in the manual's swap snippet) should cut the per-swap cost.
We estimate 20–30% off every file. Median-of-three does not help
`identical.txt`. That needs three-way (Dutch-flag) partitioning.

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

- **Quadratic time and linear recursion depth on sorted input.** `qsort_asm`
  takes about 65x as long as C on `sorted1000.txt`. Cause: Lomuto with the last
  element as pivot always picks the extreme value on sorted or reversed input
  (see Measurements). Each level also costs a 24-byte frame, so a sorted
  array of a few hundred thousand elements could overflow a 1 MB Windows
  stack. What we did: documented it and measured it. Median-of-three is the
  planned fix. The manual does not require it.
- **`sum_range_asm` recursion depth is `hi - lo + 1`.** Each level uses a
  16-byte frame. `bench` only asks for 1..1000 and 1..100. A range that still
  fits in 32 bits, such as -46340..46340, needs about 93,000 frames (about
  1.5 MB). That fits Linux's 8 MB default stack but not Windows' 1 MB. What
  we did: kept the recursive form the manual specifies and documented the
  limit. A closed form, `(lo + hi) * (hi - lo + 1) / 2`, would avoid it.

### Quirks

- **`gcd_asm` is recursive but not reentrant.** It writes the global
  `gcd_depth`, which bench requires. Two overlapping `gcd_asm` calls would
  overwrite each other's depth. The gcd *result* would still be correct,
  because the level is passed on the stack. This is the manual's
  "recursion is not reentrancy" point in practice.
- **`gcd_depth` counts calls, including the final `b == 0` call.**
  `gcd(1071, 462)` reports 4: (1071,462) → (462,147) → (147,21) → (21,0).
  `gcd(42, 0)` reports 1 and `gcd(0, 42)` reports 2.
- **`bsearch_asm` returns *an* index of the key, not necessarily the
  first.** On `duplicates.txt` and `identical.txt` any matching index
  is correct, and bench accepts it.
- **`bsearch_recursive` halves with unsigned `div`.** That is safe only
  because the base case `lo > hi` runs first, so `hi - lo >= 0`. `shr eax, 1`
  would be equivalent and cheaper.
- **Added test:** `tests/tiny_ordered.txt` is the already-ordered pair the
  manual leaves to the group. `make check` therefore reports 38 checks
  instead of 36.
