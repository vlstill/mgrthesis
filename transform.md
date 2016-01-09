In this chapter, we will propose \llvm transformations which aim at improving
model checking capabilities and reduce state-space size. Most of the proposed
transformations were implemented in \lart and will be released together with the
next release of \divine.

# Extensions to \divine

In order to implement some of the proposed transformations, it was necessary to
perform minor changes to the \llvm interpreter in \divine. All these changes are
implemented in the version of \divine submitted with this thesis and are
described in this section.

## Simplified Atomic Masks

The original semantics of `__divine_interrupt_mask` were not well suited for
composition of functions which use it. For this reason, we reimplemented this
feature so that it behaves as if `__divine_interrupt_mask` locks a global lock
and `__divine_interrupt_unmask` unlocks it, and we devised a higher-level
interface for this feature. This interface is described in
\autoref{sec:trans:atomic}.

## Assume Intrinsic

```{.cpp}
void __divine_assume( int value );
```

We extended \divine with a new intrinsic function which implements the
well-known assume statement. If `__divine_assume` is executed with a zero
`value` it, stops the interpreter and causes it to ignore the current state.
`__divine_assume` is useful for implementation of synchronization primitives,
for example in weak memory model simulation (see \autoref{sec:trans:wm}). This
function should be used primarily by \divine developers; it combines well with
atomic masks to create conditional transitions in the state space.

## Extended State Space Reductions

\label{sec:trans:tauextend}

When evaluating which transformations are useful for state space reductions, we
identified several cases in which a runtime solution by extension of the $\tau+$
reduction was more efficient. For this reason, the existing reduction technique
was improved, and these improvements are implemented in the version of \divine
submitted with this thesis. Please refer to \autoref{sec:divine:tau} for details
about $\tau+$ reduction. The evaluation of the impact of the proposed changes to
$\tau+$ reduction can be found in \autoref{sec:res:tau}.

### Control Flow Cycle Detection

First we improved upon the overly pessimistic control flow cycle detection
heuristic. This detection is used to make sure successor generation terminates
and it is based on detection of repeating program counter values. However, the
set of encountered program counter values was originally reset only at the
beginning of state generation. For this reason, it was not possible to execute
one function more that once on one edge in the state space as program counter of
this function was already in the set of seen program counters on the second
invocation. Therefore, a new state was generated before the function could be
executed for a second time, which resulted in unnecessary states.

To alleviate this limitation, all program counter values of a function are
deleted from the set of seen program counter values every time the function
exits. This way, two consecutive calls to the same function need not generate a
new state, while a call in the loop will generate a new state before the second
invocation (since the `call` instruction repeats), and recursion will also
generate a new state at the second entry into the recursive function.

This improved reduction is now enabled by default. The original behaviour can be
obtained by option `--reduce=tau+,taustores` to `divine verify` (the extended
reduction can be explicitly enabled by `tau++` key in the `--reduce` option if
necessary).

### Independent Loads

Another case of overly strict reduction heuristic are independent loads from
shared memory locations. Consider two shared memory locations (for example
shared variables) $a$ and $b$ such that $a \neq b$. The proposition is that we
can extend $\tau+$ reduction in such a way that load from $a$ and load from $b$
can be performed without an intermediate state (that is, on a single edge in
the state space). We will now show correctness of this proposition.

Suppose thread $t1$ performs load of $a$ and then load of $b$ (and there are no
actions which would be considered observable by $\tau+$ in-between).

*   If any other thread performs a load of $a$ or $b$, this clearly does not
    interfere with $t1$.
*   If some other thread $t2$ writes[^store] into $a$, this write is always
    an observable action and it can happen either

    a)  before the load of $a$ by $t1$ or after the load of $b$ by $t1$; in
        these cases the proposed change has no effect;
    b)  after the load of $a$, but before the load of $b$ by $t1$; this case is
        not possible with the extended reduction, but equivalent result can be
        obtained if $a$ is written after the load of $b$, as this load is
        independent and therefore its result does not depend on the value of
        $a$.

*   If some other thread $t2$ writes into $b$, this write is always an observable
    action and it can happen either

    a)  before the load of $a$ by $t1$ or after the load of $b$ by $t1$; in
        these cases the proposed change has no effect;
    b)  after the load of $a$, but before the load of $b$ by $t1$; again, this
        case is not possible with the extended reduction but an equivalent
        result can be obtained if $b$ is written before the load of $a$ (it does
        not change its result as $a \neq b$).

*   There can be no synchronization which would disallow any of the
    aforementioned interleavings as thread $t2$ cannot detect where in the
    sequence of instructions between load $a$ and load $b$ thread $t1$ is
    (there are no visible actions between the loads).

*   On the other hand, if there are any other visible actions between these
    loads, or if $a = b$, the conditions are not met and the loads are not
    performed atomically.

The same argument can be applied to more than two independent loads from a
single thread; this way, any sequence of independent loads and unobservable
actions can execute atomically.

Furthermore, the reduction can be extended to a sequence of independent loads
followed by a write into a memory location distinct from all the memory locations
of the loads. The argument is similar to the argumentation for the case of
a sequence of loads. If a write $w$ from another thread happens between the loads
and the write $w'$ in the sequence, a write with the same effect can happen in
the reduced state space too: if $w$ and $w'$ write to different memory locations
than $w$ can happen after the sequence which ends with $w'$; otherwise, all the
loads in the sequence are independent of $w$ and therefore $w$ can happen before
the sequence.

\bigskip To implement this reduction, \divine now tracks which memory objects
were loaded while it generates a state. If a memory object is loaded for the
first time, its address is saved and this load is not considered to be
observable. If the same object is to be accessed for the second time during
generation of the state, the state is emitted just before this access. If a
non-private object is to be loaded after a new value was stored into it, a state
is emitted before this load too. This reduction is now enabled by default; the
original behaviour can be obtained by using the option
`--reduce=tau++,taustores` to `divine verify` (the extended reduction can be
explicitly enabled by the `tauloads` key in the `--reduce` option).

[^store]: Write  can be implemented using `store`, `atomicrmw`, or `cmpxchg`
instructions, or by `__divine_memcpy` intrinsic.

# Analyses and Transformation Building Blocks

Many tasks done in \llvm transformations are common and, therefore, should be
provided as separate and reusable analyses or transformation building blocks, so
that they can be readily used when required and it is not necessary to implement
them ad-hoc every time. In some cases (for example dominator tree and domination
relation), analyses are provided in the \llvm library, and \llvm also provides
useful utilities for instruction and basic block manipulation, such as basic
block splitting and instruction insertion. In other cases, it is useful to add
to this set of primitives, and, for this reason, \lart was extended to include
several such utilities.

## Fast Instruction Reachability

\label{sec:trans:b:reach}

While \llvm has support for checking whether the value of one instruction might
reach some other instruction (using the `isPotentiallyReachable` function), this
function is slow if many-to-many reachability is to be calculated (this
function's time complexity is linear with respect to the number of basic blocks
in the control flow graph of the function).  For this reason, we introduce an
analysis which pre-calculates the reachability relation between all instructions
and allows fast querying; this analysis can be found in
`lart/analysis/bbreach.h`.

To calculate instruction reachability quickly and store it compactly, we store
the transitive closure of basic block reachability instead; the transitive
closure of instruction reachability can be easily retrieved from this
information.  Instruction $i$ other than `invoke` reaches instruction $j$ in at
least one step if and only if the basic block $b(i)$ of instruction $i$ reaches
in at least one step the basic block $b(j)$ of instruction $j$ or if $b(i) =
b(j)$ and $i$ is earlier in $b(i)$ than $j$. For the `invoke` instruction, the
situation is more complicated as it is the only terminator instruction which
returns a value, and its value is available only in its normal destination block
and not in its unwind destination block (the landing block which is used when
the function called by the `invoke` throws an exception). For this reason, the
value of `invoke` instruction $i$ reaches instruction $j$ if and only if $b(j)$
is reachable (in any number of steps, including zero) from the normal
destination basic block of $i$.

Basic block reachability is calculated in two phases, first the basic block
graph of the function is split into strongly connected components using Tarjan's
algorithm. This results in a directed acyclic graph of strongly connected
components. This SCC collapse is recursively traversed and the transitive
closure of SCC reachability is calculated.

The theoretical time complexity of this algorithm is linear in the size of the
control flow graph of the function (which is in the worst case
$\mathcal{O}(n^2)$ where $n$ is the number of basic blocks). In practice, associative
maps are used in several parts of the algorithm, resulting in the worst case
time complexity in $\mathcal{O}(n^2 \cdot \log n)$ for transitive closure
calculation and $\mathcal{O}(\log n)$ for retrieval of the information whether
one block reaches another. However, since in practice control flow graphs
are sparse,[^sparsecfg] the expected time complexity is $\mathcal{O}(n \log n)$
for transitive closure calculation.

[^sparsecfg]: The argument is that all terminator instructions other that
`switch` have at most two successors and `switch` is rare, for this reason, the
average number of edges in control flow graph with $n$ basic blocks is expected
to be less than $2n$.


## Exception Visibility

\label{sec:trans:b:vex}

Often, \llvm is transformed in a way which requires that certain cleanup action
is performed right before a function exits; one such example would be unlocking
atomic sections, used in \autoref{sec:trans:atomic}. Implementing this for
languages without non-local control flow transfer other than with `call` and
`ret` instructions, for example standard C, would be fairly straightforward.  In
this case, it is sufficient to run the cleanup just before the function returns.
However, while pure standard-compliant C has no non-local control transfer, in
POSIX there are `setjmp` and `longjmp` functions which allow non-local jumps
and, even more importantly, C++ has exceptions in its standard. Since `longjmp`
and `setjmp` are not supported in \divine, we will assume they will not be used
in the transformed program. On the other hand, exceptions are supported by
\divine and, therefore, should be taken into account.

In the presence of exceptions (but without `longjmp`); a function can be exited
in the following ways:

*   by a `ret` instruction;
*   by a `resume` instruction which resumes propagation of an exception which was
    earlier intercepted by a `landingpad`;
*   by an explicit call to `__divine_unwind`;
*   when an exception causes unwinding, and the active instruction through which
    the exception is propagating is a `call` and not an `invoke`, or it is an `invoke`
    and the associated `landingpad` does not catch exceptions of given type;
    in this case, the frame of the function is unwound and the exception is not
    intercepted.

The latest case happens often in C++ functions which do not require any
destructors to be run at the end of the function. In those cases, Clang usually
generates a `call` instead of an `invoke` even if the callee can throw an
exception, as it is not necessary to intercept the exception in the caller. Also,
if the function contains a `try` block, Clang will generate an `invoke` without
a `cleanup` flag in the `landingpad` as there is no need to run any destructors.
The problem with the last case is that the function exit is implicit: it is
possible at any `call` instruction which can throw, or at an `invoke` with a
`landingpad` without a `cleanup` flag.

In order to make it possible to add code at the end of the function, it is
therefore necessary to eliminate this implicit exit without interception of the
exception. The transformation must be performed in such a way that it does not
interfere with exception handling which was already present in the transformed
function.

Therefore, we need to transform any call in such a way that if the called
function can throw an exception, it is always called by `invoke`, and all the
`langingpad` instructions have a `cleanup` flag. Furthermore, this transformation
must not change the observable behaviour of the program. If an exception would
fall through without being intercepted in the original program, it needs to be
intercepted and immediately resumed, and if the exception was intercepted by the
original program, its processing must be left unchanged (while the fact that the
exception is intercepted by a `langingpad` and immediately resumed makes the run
different from the run in the original program, this change is not
distinguishable by any safety or \ltl property supported by \divine, and
therefore the transformed program can be considered equivalent to the original).

After this transformation, every exception is visible in every function it can
propagate through. Now if we need to add cleanup code to the function, it is
sufficient to add it before every `ret` and `resume` instruction and before
calls to `__divine_unwind`, as there is no other way the function can be exited.

If `setjmp`/`longjmp` were implemented as an extension of exception handling
support as described in \cite{RBB14}, it would require minor modification of this
transformation. It would be necessary to run transformation cleanups, but not
cleanups done by higher level language (such as C++ destructors) when unwinding
is caused by `longjmp` (`longjmp` is not required to trigger destructors in C++;
in fact, it is undefined behaviour to cause unwinding of any function with
nontrivial destructors by `longjmp`). To achieve this, a fresh selector ID for
`longjmp` would be assigned and a `catch` clause corresponding to this ID would
be added to each `langingpad`. If this clause is triggered, only transformation
cleanups would be run before the unwinding would be resumed.

### Implementation

The idea outlined above is implemented in `lart/support/cleanup.h` by the
function `makeExceptionsVisible`. Any `call` instruction for which we cannot
show that the callee cannot throw an exception is transformed into an `invoke`
instruction, which allows us to branch out into a landing block if an exception
is thrown by the callee. The `landingpad` in the landing block needs to be set
up so that it can catch any exception (this can be done using the `cleanup` flag
for `landingpad`). The instrumentation can be done as follows:

*   for a call site, if it is a `call`:

    1.  given a `call` instruction to be converted, split its basic block into
        two just after this instruction (we will call these blocks *invoke
        block* and *invoke-ok block*);
    2.  add a new basic block for cleanup; this block will contain a
        `landingpad` instruction with a `cleanup` flag and no `catch` clauses and
        a `resume` instruction (we will call this block *invoke-unwind block*);
    3.  replace the `call` instruction with an `invoke` of the same function
        and with the same parameters, its normal destination is set to the
        invoke-ok block and its unwind destination is set to invoke-unwind
        block;

*   otherwise, if it is an `invoke` and its unwind block does not contain
    the `cleanup` flag in the `landingpad`:

    1.  create a new basic block which contains just a resume instruction
        (*resume block*)
    2.  add `cleanup` flag into the `landingpad` of the unwind block of the
        `invoke` and branch into the *resume block* if the landing block is
        triggered due to `cleanup` (selector value is $0$),

*   otherwise leave the instruction unmodified.

Any calls using the `call` instruction with a known destination which is a function
marked with `nounwind` will not be modified. Functions marked with
`nounwind` need not be checked for exceptions since \llvm states that these
functions should never throw an exception and therefore we assume that throwing
an exception from such a function will be reported as an error by the verifier.

\begFigure[tp]

```{.cpp}
void foo() { throw 0; }
void bar() { foo(); }
int main() {
    try { bar(); }
    catch ( int & ) { }
}
```

An example of a simple C++ program which demonstrates use of exceptions, the
exception is thrown by `foo`, goes through `bar` and is caught in `main`.

```{.llvm}
define void @_Z3barv() #0 {
entry:
  call void @_Z3foov()
  unreachable
}
```

\llvm IR for function `bar` of the previous example (the names of functions are
mangled by the C++ compiler). It can be seen that while `foo` throws an
exception and this exception propagates through `bar`, `bar` does not intercept
this exception in any way.

```{.llvm .numberLines}
define void @_Z3barv() #0 personality
    i8* bitcast (i32 (...)* @__gxx_personality_v0 to i8*) {
entry:
  invoke void @_Z3foov()
      to label %fin unwind label %lpad
lpad:
  %0 = landingpad { i8*, i32 } cleanup
  resume { i8*, i32 } %0 ; rethrow the exception
fin:
  unreachable
}
```

A transformed version of `bar` in which the exception is intercepted and,
therefore, visible in this function, and it is immediately resumed. Cleanup code
would be inserted just before line 8. The original basic block `entry` was split
into `entry` and `fin` and the `call` instruction was replaced with an `invoke`
which transfers control to the `lpad` label if any exception is thrown by `foo`.
The function header is now extended with a personality function and this
personality function calculates the value returned by `landingpad` for a given
exception.

\caption{An example of the transformation of a function which makes exceptions
visible.}
\label{fig:transform:b:vex:example}
\endFigure

After the call instrumentation, the following holds: every time a function is
entered during stack unwinding due to an active exception, the control is
transfered to a landing block. Moreover, if before this transformation the
exception would not have been intercepted by `landingpad` in this function,
after the transformation the exception will be rethrown by `resume`.

Furthermore, if the transformation adds a `landingpad` into a function which did
not contain any `landingpad` before, it is necessary to set a personality
function for this function. For this reason, the personality function which is
used by the program is a parameter of the transformation.

An example of the transformation can be seen in
\autoref{fig:transform:b:vex:example}.

\bigskip
Finally, to simplify transformations which add cleanups at function exits, a
function `atExits` is available in the same header file.

## Local Variable Cleanup

\label{sec:trans:b:lvc}

A special case of a cleanup code ran before a function exits is local variable
cleanup, a cleanup code which needs to access local variables (results of
`alloca` instruction). One of transformations which requires this kind of
cleanup  is the transformation to enable weak memory model verification
(\autoref{sec:trans:wm:cleanup}), another case can arise from compiled-in abstractions
proposed in \cite{RockaiPhD}. Variable cleanups are essentially akin to
C++ destructors, in a sense that they get executed at the end of the scope of the
variable, no matter how this happens (with the possible exception of thread
termination).

The local variable cleanup builds on top of the function cleanups described in
\autoref{sec:trans:b:vex}. Unlike the previous case, it is not necessary to
transform all calls which can throw an exception, it is sufficient to transform
calls which can happen after some local variable declaration (that is a value of
an `alloca` instruction can reach a `call` or an `invoke` instruction). After
this transformation a cleanup code is added before every exit from the function.
However, in order for the cleanup code to work, it needs to be able to access
all local variables which can be defined before the associated function exit
(results of all `alloca` instructions from which this exit can be reached). This
might not be always be the case in the original program, see
\autoref{fig:trans:b:lvc:phi} for an example.  In this example, `%y` is defined
in `if.then` basic block and it needs to be cleared just before the `return`
instruction at the end of `if.end` basic block, and the definition of `%y` does
not dominate the cleaning point.

\begFigure[tbp]

```{.llvm}
entry:
  %x = alloca i32, align 4
  store i32 1, i32* %x, align 4
  %0 = load i32, i32* %x, align 4
  %cmp = icmp eq i32 %0, 0
  br i1 %cmp, label %if.then, label %if.end

if.then: ; preds = %entry
  %y = alloca i32, align 4
  store i32 1, i32* %y, align 4
  br label %if.end

if.end:  ; preds = %if.then, %entry
  ; cleanup will be inserted here
  ret i32 0
```

\antispaceatend
\begCaption
An example of \llvm code in which a local variable is allocated in only one
branch and therefore does not dominate the function exit. While Clang usually
moves all `alloca` instructions into the first block of the function, the
example is still a valid \llvm bitcode, and therefore should be handled
properly.
\endCaption
\label{fig:trans:b:lvc:phi}
\endFigure

The cleanup cannot be, in general, inserted after the last use of a local
variable as the variable's address can escape the scope of the function and even
the thread in which it was created and, therefore, it is not decidable when its
scope ends.  Nevertheless, it is safe to insert the cleanup just before the
function exits as the variable will cease to exists when the function exits,
that is immediately after the cleanup.

To make all local variables which can reach an exit point of a function
accessible at this exit point, we will first insert $\varphi$-nodes in such a
way that any `alloca` is represented in any block which it can reach, either by
its value if the control did pass the `alloca` instruction (the local variable
is defined at this point), or by the `null` constant if the control did not pass
the `alloca`. For our example, the result of the modification is shown in
\autoref{fig:trans:b:lvc:phi:post}. In this code, `%y.phi` represents `%y` at
the cleanup point. It can either be equal to `%y` if the control passed through
the definition of `%y`, or `null` otherwise.

\begFigure[tbp]

```{.llvm}
if.end:  ; preds = %if.then, %entry
  %y.phi = phi i32* [ null, %entry ], [ %y, %if.then ]
  ; cleanup will be inserted here, it will access %y.phi
  ret i32 0
```

\antispaceatend
\begCaption
Transformation of the last basic block from \autoref{fig:trans:b:lvc:phi} to
allow cleanup of `%y`.
\endCaption
\label{fig:trans:b:lvc:phi:post}
\endFigure

While this transformation changes the set of runs of a program all the runs in
the original program have equivalent (from the point of safety and \ltl
properties supported by \divine) runs transformed programs. The only difference
is that there can be some intermediate states (which correspond to the cleanup)
in the transformed program's runs. This is, however, not distinguishable in
\divine unless the cleanup code signals a problem or sets an atomic proposition.

### Implementation

To calculate which `alloca` instructions can reach a function exit a version of
the standard reaching definitions analysis is used. Using this analysis, we
compute which `alloca` instruction values reach the end of each basic block of
the function and for every such value which does not dominate the end of the
basic block a $\varphi$-node is added. For each basic block the algorithm also
keeps track of the value which represents a particular `alloca` instruction in
this basic block (it can be either the `alloca` itself, or a `phi` instruction).
These values are passed to the cleanup code. The transformation is done by the
`addAllocaCleanups` function which is defined in `lart/support/cleanup.h`.

# New Interface for Atomic Sections

\label{sec:trans:atomic}

The interface for atomic sections in the verified code (described in
\autoref{sec:divine:llvm:mask}) is hard to use, the main reason being that while
the mask set by `__divine_interrupt_mask` is inherited by called functions,
these functions have no way of knowing if an instruction executes inside an
atomic section, and therefore, a callee can accidentally end the atomic section
by calling `__divine_interrupt_unmask`. This is especially bad for composition
of atomic functions, see \autoref{fig:ex:atomic:bad} for an example. For this
reason, the only compositionally safe way to use the \divine's original atomic
sections is to never call `__divine_interrupt_unmask` and let \divine end the
atomic section when the caller of `__divine_interrupt_mask` ends.

\begFigure[tp]

```{.cpp .numberLines}
void doSomething( int *ptr, int val ) {
    __divine_interrupt_mask();
    *ptr += val;
    __divine_interrupt_unmask();
    foo( ptr );
}

int main() {
    int x = 0;
    __divine_interrupt_mask();
    doSomething( &x );
    __divine_interrupt_unmask();
}
```

\antispaceatend
\begCaption
An example of composition problem with the original version of \divine's atomic
sections.  The atomic section begins on line 10 and is inherited to
`doSomething`. The atomic section ends by the unmask call at line 4 and the rest
of `doSomething` and `foo` are not executed atomically. The atomic section is
then re-entered when `doSomething` returns.
\endCaption
\label{fig:ex:atomic:bad}
\endFigure

To alleviate the aforementioned problems we reimplemented atomic sections in
\divine. The new design uses only one *mask flag* to indicate that the current
thread of execution is in an atomic section; this flag is internal to the
interpreter and need not be saved in the state (indeed, it would be always set
to false in the state emitted by the generator, because the state can never be
emitted in the middle of an atomic section). Furthermore, we modified
`__divine_interrupt_mask` to return an `int` value corresponding to the value of
mask flag before it was set by this call.

To make the new atomic sections easier to use we provide higher level interfaces
for atomic sections by the means of a C++ library and annotations. The C++
interface is intended to be used primarily by developers of the language support
and libraries for \divine, while the annotations are designed to be used by
users of \divine.

The C++ interface is RAII-based,[^raii] it works similarly to C++11
`unique_lock` with recursive mutexes. An atomic section begins by construction
of an object of type `divine::InterruptMask` and it is left either by a call of
`release` method on this object or by the destructor of the object. When atomic
sections are nested, only the `release` on the object which started the atomic
section actually ends the atomic section. See \autoref{fig:ex:atomic:cpp} for an
example.

\begFigure[tp]

```{.cpp}
#include <divine/interrupt.h>

void doSomething( int *ptr, int val ) {
    divine::InterruptMask mask;
    *ptr += val;
    // release the mask only if 'mask' object owns it:
    mask.release();
    // masked only if caller of doSomething was masked:
    foo( ptr );
}

int main() {
    int x = 0;                    // not masked
    divine::InterruptMask mask;
    doSomething( &x );            // maksed
    x = 1;                        // still masked
    // mask ends automatically at the end of main
    // (if it began here)
}
```

\antispaceatend
\caption{An example use of the C++ interface for the new version of atomic sections in
\divine.}
\label{fig:ex:atomic:cpp}
\endFigure

[^raii]: Resource Acquisition Is Initialization, a common pattern in C++.  A
resource is allocated inside an object and safely deallocated when that object's
scope ends, usually at the end of a function in which the object was declared
\cite{cppref:RAII}.

The annotation interface is based on a \lart transformation pass and annotations
which can be used to mark an entire functions as atomic. A function can be
marked atomic by adding `__lart_atomic_function` to the function header, see
\autoref{fig:ex:atomic:lart} for an example. While this is a safer way to use
atomic sections than explicitly using `__divine_interrupt_mask`, it is still
necessary that the atomic function always terminates (e.g. does not contain
infinite cycle).

\begFigure[tp]

```{.cpp}
#include <lart/atomic.h> // defines the annotation
// this function executes atomically
int atomicInc( int *ptr, int val ) __lart_atomic_function {
    int prev = *ptr;
    *ptr += val;
    return prev;
}
```

\antispaceatend
\begCaption
An example of a use of the annotation interface for atomic functions in \divine.
The function `atomicInc` is aways executed atomically and it is safe execute it
inside another atomic section.
\endCaption
\label{fig:ex:atomic:lart}
\endFigure

### Implementation of Annotation Interface

Atomic sections using annotations are implemented in two phases. First the
function is annotated with `__lart_atomic_function` which is a macro which
expands to GCC/Clang attributes `annotate("lart.interrupt.masked")` and
`noinline`; the first attribute is used so that the annotated function can be
identified in \llvm IR, the second to make sure the function will not be
inlined.

The second phase is the \lart pass which adds atomic sections into annotated
functions. This pass is implemented in `lart/reduction/interrupt.cpp` by class
`Mask`.  For each function which is annotated, it adds a call to
`__divine_interrupt_mask` at the beginning of the function, and a call to
`__divine_interrupt_unmask` before any exit point of the function (using the
cleanup transformation introduced in \autoref{sec:trans:b:vex}). The unmask call
is conditional, it is only called if the mask call returned 0 (that is, the
current atomic section begun by this call).

This \lart pass was integrated into the program build with the `divine compile`
command and, therefore, it is not necessary to run \lart manually to make atomic
sections work.


# Weak Memory Models

\label{sec:trans:wm}

In \cite{SRB15} it was proposed to add a weak memory model simulation using
\llvm transformation. In this section we will present an extended version of
this transformation. The new version supports the \llvm memory model fully,
including support atomic instructions, support for more relaxed memory models
than total store order, and specification of memory model as a parameter of the
transformation. It also allows for verification of the full range of properties
supported by \divine (the original version was not usable for verification of
memory safety). Furthermore, we propose ways to reduce the state space size
compared to the original version. The evaluation of the proposed transformation
can be found in \autoref{sec:res:wm}.

## Representation of the \llvm Memory Model Using Store Buffers

\label{sec:trans:wm:rep}

Relaxed memory models can be simulated using store buffers. Any write is first
done into a thread-private buffer and therefore it is invisible for other
threads. This buffer keeps the writes in FIFO order and it can be flushed
nondeterministically into the memory, the order of flushing depends on
particular memory model. For total store order, only the oldest entry can be
flushed, for partial store order any entry can be flushed, provided that there
is no older entry for the same memory location. Furthermore, any load has to
first look into the store buffer of its thread for newer values of the loaded
memory location, only if there is no such value, it can look into the memory.
See \autoref{fig:trans:wm:sb} for an example of a store buffer instrumentation.

\begFigure[tp]

```{.cpp}
int x = 0, y = 0;
```
\begSplit

```{.cpp}
void thread0() {
  y = 1;
  cout << "x = " << x << endl;
}
```

\Split

```{.cpp}
void thread1() {
  x = 1;
  cout << "y = " << y << endl;
}
```

\endSplit

\bigskip In this example, each of the threads first writes into a global
variable and later it reads the variable written by the other thread. Under
sequential consistency, the possible outcomes would be $x = 1, y = 1$; $x = 1, y
= 0$; and $x = 0, y = 1$ as at least one write must proceed before the first
read can proceed. However, under total store order $x = 0, y = 0$ is also
possible: this corresponds to the reordering of the load on line 3 before the
independent store on line 2. This behaviour can be simulated using store buffer,
in this case the store on line 2 is not immediately visible, it is done into
store buffer.  The following diagram shows (shortened) execution of the listed
code. Dashed lines represent where the given value is read from/stored to.

\begin{center}
\begin{tikzpicture}[ ->, >=stealth', shorten >=1pt, auto, node distance=3cm
                   , semithick
                   , scale=0.7
                   ]
  \draw [-] (-10,0) -- (-6,0) -- (-6,-2) -- (-10,-2) -- (-10,0);
  \draw [-] (-10,-1) -- (-6,-1);
  \draw [-] (-8,0) -- (-8,-2);
  \node () [anchor=west] at (-10,0.5) {main memory};
  \node () [anchor=west] at (-10,-0.5)  {\texttt{@x}};
  \node () [anchor=west] at (-8,-0.5)  {\texttt{@x}};
  \node () [anchor=west] at (-10,-1.5)  {\texttt{0}};
  \node () [anchor=west] at (-8,-1.5)  {\texttt{0}};

  \node () [anchor=west] at (-10,-3.5) {store buffer for thread 0};
  \node () [anchor=west] at (0,-3.5) {store buffer for thread 1};

  \draw [-] (-10,-4) -- (-4, -4) -- (-4,-5) -- (-10,-5) -- (-10,-4);
  \draw [-] (0,-4) -- (6, -4) -- (6,-5) -- (0,-5) -- (0,-4);
  \draw [-] (-8,-4) -- (-8,-5);
  \draw [-] (-6,-4) -- (-6,-5);
  \draw [-] (2,-4) -- (2,-5);
  \draw [-] (4,-4) -- (4,-5);

  \node () [anchor=west] at (-10,-4.5)  {\texttt{@y}};
  \node () [anchor=west] at (-8,-4.5)  {\texttt{1}};
  \node () [anchor=west] at (-6,-4.5)  {\texttt{32}};

  \node () [anchor=west] at (0,-4.5)  {\texttt{@x}};
  \node () [anchor=west] at (2,-4.5)  {\texttt{1}};
  \node () [anchor=west] at (4,-4.5)  {\texttt{32}};

  \node () [] at (-4, 0.5) {thread 0};
  \draw [->] (-4,0) -- (-4,-2);
  \node () [anchor=west] at (-3.5, -0.5) {\texttt{store @y 1;}};
  \node () [anchor=west] at (-3.5, -1.5) {\texttt{load @x;}};

  \node () [] at (2, 0.5) {thread 1};
  \draw [->] (2,0) -- (2,-2);
  \node () [anchor=west] at (2.5, -0.5) {\texttt{store @x 1;}};
  \node () [anchor=west] at (2.5, -1.5) {\texttt{load @y;}};

  \draw [->, dashed] (0,-0.5) to[in=0, out=0] (-4,-4.5);
  \draw [->, dashed] (-9,-2) to[in=0, out=-90, out looseness=0.7] (-1, -1.5);
  \draw [->, dashed] (6,-0.5) to[in=0, out=0] (6,-4.5);
  \draw [->, dashed] (-7,-2) to[in=0, out=-90, out looseness=0.5] (5,-1.5);

\end{tikzpicture}
\end{center}

\antispaceatend
\caption{An illustration of a behaviour which is not possible with sequential
consistency. It is, however, possible with total store order or any more relaxed
memory model.}
\label{fig:trans:wm:sb}
\endFigure

The basic idea behind the proposed \llvm memory model simulation is that a store
buffer can be flushed nondeterministically in any order, however, not all orders
result in valid runs of the program. The store buffer entries are enriched with
an information about the instruction which created them and therefore the
validity of a particular run can be checked when load, read fence, or atomic
instruction is performed, and the invalid runs are discarded (using
`__divine_assume`).

The approximation uses store buffers to delay `store` and `fence` instructions.
There is a bounded store buffer associated with each thread of the program, this
buffer is filled by `store` and `fence` instructions and flushed
nondeterministically. The store buffer contains *store entries*, each of them is
created by a single `store` instruction and contains the following fields:

*   the **address** of the memory location of the store,
*   the **value** of the store,
*   the **bit width** of the stored value (the value size is limited to 64 bits),
*   the **atomic ordering** used by the store,
*   a bit which indicates if the value **was already flushed** (*flushed flag*),
*   a bit set of **threads which observed the store** (*observed set*).

\noindent
Apart from store entries, a store buffer can contain *fence entries* which
correspond to `fence` instructions with at least release ordering (write fence).
Fence entries have following fields:

*   the **atomic ordering** of the fence,
*   a bit set of **threads which observed the fence**.

\noindent
Store buffer entries are saved in the order of execution of their corresponding
instructions.

Atomic instructions are not directly represented in store buffers; instead, they
are split into their non-atomic equivalents using `load` and `store`
instructions which are performed atomically in a \divine's atomic section and
transformed using weak memory model. Finally, `load` instructions and read
fences have constraints on the state of store buffers in which they can execute.
These constraints ensure that the guarantees given by the atomic ordering of the
instruction are met.

\bigskip

The aim of the proposed transformation is to approximate the \llvm memory model
as closely as possible (except for the limitations given by the bound on store
buffer size). For this reason, we support all atomic orderings apart from *not
atomic*, which is modelled as *unordered*.[^unord] The store buffer is organized in
FIFO manner, it is flushed nondeterministically in any order which satisfies the
condition that no entry can be flushed into the memory if there is an older
*matching entry*.  Entry $A$ matches entry $B$ (or depends on $B$) if both $A$
and $B$ change the same memory location (this does not imply that the address in
$A$ is the same as the address in $B$, as it can happen that $B$ changes only a
part of the value written by $A$ or vice versa).

[^unord]: The difference between *not atomic* and *unordered* is that both a
compiler and hardware is allowed to split *not atomic* operations and the value
of concurrently written *not atomic* location is undefined while for *unordered*
operation it is guaranteed to be one of the previously written values; however,
on most modern hardware, there is no difference between *unordered* and *not
atomic* for objects of size less or equal to 64 bits. *Not atomic* instructions
also permit large variety of optimizations. However, this is not a problem as
\divine should be applied on the bitcode after any desired optimizations.

Furthermore, the entry can be set as flushed using the flushed flag or deleted
from the store buffer when it is flushed. The flushed flag is used only for
*monotonic* (or stronger) entries which follow any *release* (or stronger)
entries; all other entries are deleted immediately. These flushed entries are
used to check validity of the run.

The description of the realization of atomic instructions follows. We will denote
*local store buffer* to be the store buffer of the thread which performs the
instruction in question; the store buffers of all other threads will be denoted
as *foreign store buffers*.

All stores
~   are performed into the local store buffer. The address, the value, and the
    bitwidth of the value is saved, the atomic ordering of the entry is set
    according to the atomic ordering of the corresponding `store` instruction,
    the flushed flag is set to false and the observed set is set to empty
    set.

*Unordered* loads
~   can be executed at any time. All loads load value from the local store
    buffer if it contains a newer value then the memory.

*Monotonic* load
~   can be executed at any time too. Furthermore, if there is a flushed, at least
    *monotonic* entry $E$ in any foreign store buffer, the observed flag is set to
    any entry which:

    *   is in the same store buffer as $E$ and is older, or $E$ itself,
    *   and it has at least *release* ordering.

    All these entries are set to be observed by the thread which performs the
    load.

*Monotonic* atomic compound instruction
~   (`cmpxchg` or `atomicrmw`) can be performed if a *monotonic* load can be
    performed and there is no not-flushed *monotonic* entry for the same memory
    location in any foreign store buffer. It also sets observed flags in the
    same way as monotinc loads.

*Acquire* fence
~   can be performed if there are no entries in foreign store buffers with at
    least *release* ordering which were observed by the current thread. This way a
    *release* store or fence synchronizes with an *acquire* fence if the conditions of
    fence synchronization are met.

*Acquire* load
~   can be performed if

    *   a *monotonic* load from the same memory location can be performed,
    *   and an *acquire* fence can be performed,
    *   and there are no flushed *release* (or stronger) store entries for the
        same memory location in any foreign store buffer.
    
    This way an *acquire* load synchronizes with the latest *release* store to
    the same memory location if the value of the store can be already read (the
    only way to remove a *release* entry from a store buffer is to first remove
    all the entries which precede it).

*Acquire* atomic compound operations
~   can be performed if

    *   an *acquire* load from the same memory location can be performed,
    *   and there are no (at least) *release* entries for the same memory location
        in any foreign store buffer.

*Release* and *acquire-release* loads
~   are not allowed by \llvm.

*Release* fences
~   add fence entry into the local store buffer. The memory ordering of the
    entry is set according to the ordering of the fence and the observed set is
    set to an empty set.

*Acquire-release* fence
~   behaves as both *release* and *acquire* fence.

*Sequentially consistent* fence
~   can be performed if an *acquire* fence can be performed and there are no
    *sequentially consistent* entries in any foreign store buffer. This way a
    *sequentially consistent* fence synchronizes with any *sequentially
    consistent* operation performed earlier.

*Sequentially consistent* loads and atomic compound operations
~   can be performed if

    *   the same operation with *acquire-release* ordering and on the same memory
        location can be performed,
    *   and a *sequentially consistent* fence can be performed.

While there is no explicit synchronization between multiple *sequentially
consistent* stores/loads/fences there is still a total order of all the
*sequentially consistent* operations which respects the program order of each of
the threads and the synchronizes-with edges. For operations within a single
thread their relative position in this total order is given by the order in
which they are executed.  For two stores executed in different threads which are
not ordered as a result of an explicit synchronization, their relative order can
be arbitrary as they are not dependent. Loads and atomic compound operations are
explicitly synchronized as described above.

The case of *monotonic* operations is similar, not-otherwise-synchronized stores
and loads from different threads can be flushed in arbitrary order. The total
order of *monotonic* operations over a memory location can be derived from their
order of execution:

*   the total order of `store` instructions is given by the order in which the
    corresponding store entries are flushed (which is a total order as \divine
    executes instructions interleaved and not in parallel);
*   the total order of `load` instructions is given by the order they are
    executed in;
*   every `store` is ordered before any `load` which loads the value written by
    this or any later stores;
*   this total order is consistent with order of execution of threads; for
    `load` instructions this is obvious, for `store` it follows from the fact
    that stores to the same memory location from the same thread cannot be
    reordered.

In the case of `atomicrmw` and `cmpxchg` instructions a stronger synchronization
is needed; representing them as an atomically-executed `load` followed by a
`store` could break the total order. Suppose thread $0$ performs an atomic
increment of a memory location `@x` and later thread $1$ increments the same
location; now, if the store buffer entry corresponding to the `store` in thread
$0$ is not flushed before the `load` in thread $1$ the old value will be read in
thread $1$ and the result will be same as if only one increment executed. The
corresponding ordering is: `load` in thread $0$, `load` in thread $1$, `store`
in thread $0$, and `store` in thread $1$. This ordering is possible even though
both of the `load`--`store` combinations are executed atomically, due to the
fact that the position of `store` in the total order is determined by the moment
in which this store is flushed. To resolve this, these atomic operations can
only be performed if there are no atomic store entries for the given memory
location in any foreign store buffer. This way, a total ordering of these
operations is guaranteed.

\bigskip
Figures \ref{fig:trans:wm:simple1}, \ref{fig:trans:wm:simple2}, and
\ref{fig:trans:wm:simple3} demonstrate the store buffer approximation of the
\llvm memory model for the case of simple shared variables, one of which is
accessed atomically. Figures \ref{fig:trans:wm:fence1},
\ref{fig:trans:wm:fence2}, and \ref{fig:trans:wm:fence3} show an illustration
with a `fence` instruction.

\begFigure[p]

```{.cpp .numberLines}
int x;
std::atomic< bool > a;

void thread0() {
    x = 42;
    a.store( true, std::memory_order_release );
}

void thread1() {
    while ( !a.load( std::memory_order_acquire ) { }
    std::cout << x << std::endl; // always prints 42
}
```

This is an example of two threads which communicate using a shared global
variable `x` which is guarded by an atomic global variable `a`. Following is a
simplified execution of this programs (only `load` and `store` instructions are
shown).

\bigskip
\begin{tikzpicture}[ ->, >=stealth', shorten >=1pt, auto, node distance=3cm
                   , semithick
                   , scale=0.7
                   ]
  \draw [-] (-10,0) -- (-6,0) -- (-6,-2) -- (-10,-2) -- (-10,0);
  \draw [-] (-10,-1) -- (-6,-1);
  \draw [-] (-8,0) -- (-8,-2);
  \node () [anchor=west] at (-10,0.5) {main memory};
  \node () [anchor=west] at (-10,-0.5)  {\texttt{@x}};
  \node () [anchor=west] at (-8,-0.5)  {\texttt{@a}};
  \node () [anchor=west] at (-10,-1.5)  {\texttt{0}};
  \node () [anchor=west] at (-8,-1.5)  {\texttt{false}};

  \node () [anchor=west] at (-10,-3.5) {store buffer for thread 0};
  \node () [anchor=west] at (0,-3.5) {store buffer for thread 1};

  \draw [-] (-10,-4) -- (-1,-4);
  \draw [-] (0,-4) -- (8,-4);

  \node () [] at (-4.5, 0.5) {thread 0};
  \draw [->, dashed] (-4.5,0) -- (-4.5,-2);
  \node () [anchor=west] at (-4, -0.5) {\texttt{store @x 42}};
  \draw [->] (-4.5,-0.25) -- (-4, -0.25);
  \node () [anchor=west] at (-4, -1.5) {\texttt{store @a true release}};

  \node () [] at (3, 0.5) {thread 1};
  \draw [->, dashed] (3,0) -- (3,-2);
  \node () [anchor=west] at (3.5, -0.5) {\texttt{load @a acquire}};
  \draw [->] (3, -0.25) -- (3.5, -0.25);
  \node () [anchor=west] at (3.5, -1.5) {\texttt{load @x}};

\end{tikzpicture}

1.  Before the first instruction is executed, `@x` is initiated to 0 and `@a` to
    `false`. Store buffers are empty. When thread 0 executes the first
    instruction, the store will be performed into store buffer.

\begin{tikzpicture}[ ->, >=stealth', shorten >=1pt, auto, node distance=3cm
                   , semithick
                   , scale=0.7
                   ]
  \draw [-] (-10,0) -- (-6,0) -- (-6,-2) -- (-10,-2) -- (-10,0);
  \draw [-] (-10,-1) -- (-6,-1);
  \draw [-] (-8,0) -- (-8,-2);
  \node () [anchor=west] at (-10,0.5) {main memory};
  \node () [anchor=west] at (-10,-0.5)  {\texttt{@x}};
  \node () [anchor=west] at (-8,-0.5)  {\texttt{@a}};
  \node () [anchor=west] at (-10,-1.5)  {\texttt{0}};
  \node () [anchor=west] at (-8,-1.5)  {\texttt{false}};

  \node () [anchor=west] at (-10,-3.5) {store buffer for thread 0};
  \node () [anchor=west] at (0,-3.5) {store buffer for thread 1};

  \draw [-] (-10,-4) rectangle (-1,-5);
  \draw [-] (0,-4) -- (8,-4);
  \draw [-] (-9,-4) -- (-9,-5);
  \draw [-] (-7,-4) -- (-7,-5);
  \draw [-] (-6,-4) -- (-6,-5);

  \node () [anchor=west] at (-10,-4.5)  {\texttt{@x}};
  \node () [anchor=west] at (-9,-4.5)  {\texttt{42}};
  \node () [anchor=west] at (-7,-4.5)  {\texttt{32}};
  \node () [anchor=west] at (-6,-4.5)  {\texttt{Unordered}};

  \node () [] at (-4.5, 0.5) {thread 0};
  \draw [->, dashed] (-4.5,0) -- (-4.5,-2);
  \node () [anchor=west] at (-4, -0.5) {\texttt{store @x 42}};
  \draw [->] (-4.5,-0.75) -- (-4, -0.75);
  \node () [anchor=west] at (-4, -1.5) {\texttt{store @a true release}};

  \node () [] at (3, 0.5) {thread 1};
  \draw [->, dashed] (3,0) -- (3,-2);
  \node () [anchor=west] at (3.5, -0.5) {\texttt{load @a acquire}};
  \draw [->] (3, -0.25) -- (3.5, -0.25);
  \node () [anchor=west] at (3.5, -1.5) {\texttt{load @x}};

\end{tikzpicture}

2.  After the first instruction of thread 0, its store buffer contains an entry
    with the address of the stored memory location, the stored value, its
    bitwidth, and the memory ordering used for the store.

\antispaceatend
\caption{Example of the weak memory model simulation with store buffers, part I.}
\label{fig:trans:wm:simple1}
\endFigure

\begFigure[p]

\begin{tikzpicture}[ ->, >=stealth', shorten >=1pt, auto, node distance=3cm
                   , semithick
                   , scale=0.7
                   ]
  \draw [-] (-10,0) -- (-6,0) -- (-6,-2) -- (-10,-2) -- (-10,0);
  \draw [-] (-10,-1) -- (-6,-1);
  \draw [-] (-8,0) -- (-8,-2);
  \node () [anchor=west] at (-10,0.5) {main memory};
  \node () [anchor=west] at (-10,-0.5)  {\texttt{@x}};
  \node () [anchor=west] at (-8,-0.5)  {\texttt{@a}};
  \node () [anchor=west] at (-10,-1.5)  {\texttt{0}};
  \node () [anchor=west] at (-8,-1.5)  {\texttt{false}};

  \node () [anchor=west] at (-10,-3.5) {store buffer for thread 0};
  \node () [anchor=west] at (0,-3.5) {store buffer for thread 1};

  \draw [-] (-10,-4) rectangle (-1,-6);
  \draw [-] (-10,-5) -- (-1,-5);
  \draw [-] (0,-4) -- (8,-4);
  \draw [-] (-9,-4) -- (-9,-6);
  \draw [-] (-7,-4) -- (-7,-6);
  \draw [-] (-6,-4) -- (-6,-6);

  \node () [anchor=west] at (-10,-4.5)  {\texttt{@x}};
  \node () [anchor=west] at (-9,-4.5)  {\texttt{42}};
  \node () [anchor=west] at (-7,-4.5)  {\texttt{32}};
  \node () [anchor=west] at (-6,-4.5)  {\texttt{Unordered}};
  \node () [anchor=west] at (-10,-5.5)  {\texttt{@a}};
  \node () [anchor=west] at (-9,-5.5)  {\texttt{true}};
  \node () [anchor=west] at (-7,-5.5)  {\texttt{8}};
  \node () [anchor=west] at (-6,-5.5)  {\texttt{Release}};

  \node () [] at (-4.5, 0.5) {thread 0};
  \draw [->, dashed] (-4.5,0) -- (-4.5,-2);
  \node () [anchor=west] at (-4, -0.5) {\texttt{store @x 42}};
  \draw [->] (-4.5,-1.75) -- (-4, -1.75);
  \node () [anchor=west] at (-4, -1.5) {\texttt{store @a true release}};

  \node () [] at (3, 0.5) {thread 1};
  \draw [->, dashed] (3,0) -- (3,-2);
  \node () [anchor=west] at (3.5, -0.5) {\texttt{load @a acquire}};
  \draw [->] (3, -0.25) -- (3.5, -0.25);
  \node () [anchor=west] at (3.5, -1.5) {\texttt{load @x}};

\end{tikzpicture}

3.  Second entry is appended to the store buffer. If the first instruction of
    thread 1 executed now, it would read `false` from the memory and the cycle
    would be repeated.

\begin{tikzpicture}[ ->, >=stealth', shorten >=1pt, auto, node distance=3cm
                   , semithick
                   , scale=0.7
                   ]
  \draw [-] (-10,0) -- (-6,0) -- (-6,-2) -- (-10,-2) -- (-10,0);
  \draw [-] (-10,-1) -- (-6,-1);
  \draw [-] (-8,0) -- (-8,-2);
  \node () [anchor=west] at (-10,0.5) {main memory};
  \node () [anchor=west] at (-10,-0.5)  {\texttt{@x}};
  \node () [anchor=west] at (-8,-0.5)  {\texttt{@a}};
  \node () [anchor=west] at (-10,-1.5)  {\texttt{0}};
  \node () [anchor=west] at (-8,-1.5)  {\texttt{true}};

  \node () [anchor=west] at (-10,-3.5) {store buffer for thread 0};
  \node () [anchor=west] at (0,-3.5) {store buffer for thread 1};

  \draw [-] (-10,-4) rectangle (-1,-6);
  \draw [-] (-10,-5) -- (-1,-5);
  \draw [-] (0,-4) -- (8,-4);
  \draw [-] (-9,-4) -- (-9,-6);
  \draw [-] (-7,-4) -- (-7,-6);
  \draw [-] (-6,-4) -- (-6,-6);

  \node () [anchor=west] at (-10,-4.5)  {\texttt{@x}};
  \node () [anchor=west] at (-9,-4.5)  {\texttt{42}};
  \node () [anchor=west] at (-7,-4.5)  {\texttt{32}};
  \node () [anchor=west] at (-6,-4.5)  {\texttt{Unordered}};
  \node () [anchor=west] at (-10,-5.5)  {\texttt{@a}};
  \node () [anchor=west] at (-9,-5.5)  {\texttt{true}};
  \node () [anchor=west] at (-7,-5.5)  {\texttt{8}};
  \node () [anchor=west] at (-6,-5.5)  {\texttt{Release, flushed}};

  \node () [] at (-4.5, 0.5) {thread 0};
  \draw [->, dashed] (-4.5,0) -- (-4.5,-2);
  \node () [anchor=west] at (-4, -0.5) {\texttt{store @x 42}};
  \draw [->] (-4.5,-1.75) -- (-4, -1.75);
  \node () [anchor=west] at (-4, -1.5) {\texttt{store @a true release}};

  \node () [] at (3, 0.5) {thread 1};
  \draw [->, dashed] (3,0) -- (3,-2);
  \node () [anchor=west] at (3.5, -0.5) {\texttt{load @a acquire}};
  \draw [->] (3, -0.25) -- (3.5, -0.25);
  \node () [anchor=west] at (3.5, -1.5) {\texttt{load @x}};
\end{tikzpicture}

4.  The entry for `@a` in the store buffer of thread 0 is flushed into the memory, but
    the entry is still remembered in the store buffer as it is a release entry and
    future loads (it they have at least acquire ordering) will have to
    synchronize with it. It would be also possible to first flush the entry for
    `@x`, in this case it would be removed from the store buffer as it is the
    oldest entry, and therefore no explicit synchronization is necessary.

\antispaceatend
\caption{Example of the weak memory model simulation with store buffers, part II.}
\label{fig:trans:wm:simple2}
\endFigure

\begFigure[p]

\begin{tikzpicture}[ ->, >=stealth', shorten >=1pt, auto, node distance=3cm
                   , semithick
                   , scale=0.7
                   ]
  \draw [-] (-10,0) -- (-6,0) -- (-6,-2) -- (-10,-2) -- (-10,0);
  \draw [-] (-10,-1) -- (-6,-1);
  \draw [-] (-8,0) -- (-8,-2);
  \node () [anchor=west] at (-10,0.5) {main memory};
  \node () [anchor=west] at (-10,-0.5)  {\texttt{@x}};
  \node () [anchor=west] at (-8,-0.5)  {\texttt{@a}};
  \node () [anchor=west] at (-10,-1.5)  {\texttt{0}};
  \node () [anchor=west] at (-8,-1.5)  {\texttt{true}};

  \node () [anchor=west] at (-10,-3.5) {store buffer for thread 0};
  \node () [anchor=west] at (0,-3.5) {store buffer for thread 1};

  \draw [-] (-10,-4) rectangle (-1,-6);
  \draw [-] (-10,-5) -- (-1,-5);
  \draw [-] (0,-4) -- (8,-4);
  \draw [-] (-9,-4) -- (-9,-6);
  \draw [-] (-7,-4) -- (-7,-6);
  \draw [-] (-6,-4) -- (-6,-6);

  \node () [anchor=west] at (-10,-4.5)  {\texttt{@x}};
  \node () [anchor=west] at (-9,-4.5)  {\texttt{42}};
  \node () [anchor=west] at (-7,-4.5)  {\texttt{32}};
  \node () [anchor=west] at (-6,-4.5)  {\texttt{Unordered}};
  \node () [anchor=west] at (-10,-5.5)  {\color{red}\texttt{@a}};
  \node () [anchor=west] at (-9,-5.5)  {\texttt{true}};
  \node () [anchor=west] at (-7,-5.5)  {\texttt{8}};
  \node () [anchor=west] at (-6,-5.5)  {\color{red}\texttt{Release, flushed}};

  \node () [] at (-4.5, 0.5) {thread 0};
  \draw [->, dashed] (-4.5,0) -- (-4.5,-2);
  \node () [anchor=west] at (-4, -0.5) {\texttt{store @x 42}};
  \draw [->] (-4.5,-1.75) -- (-4, -1.75);
  \node () [anchor=west] at (-4, -1.5) {\texttt{store @a true release}};

  \node () [] at (3, 0.5) {thread 1};
  \draw [->, dashed] (3,0) -- (3,-2);
  \node () [anchor=west] at (3.5, -0.5) {\texttt{load {\color{red}@a acquire}}};
  \draw [->] (3, -0.5) -- (3.5, -0.5);
  \node () [anchor=west] at (3.5, -1.5) {\texttt{load @x}};
\end{tikzpicture}

5.  When the first instruction of thread 1 is executed, a synchronization takes
    place. The acquire load on `@a` forces the matching, flushed entry in the
    store buffer of thread 0 to be evicted; however, this is a *release* entry
    so all the entries which precede it will have to be flushed and evicted too.

\begin{tikzpicture}[ ->, >=stealth', shorten >=1pt, auto, node distance=3cm
                   , semithick
                   , scale=0.7
                   ]
  \draw [-] (-10,0) -- (-6,0) -- (-6,-2) -- (-10,-2) -- (-10,0);
  \draw [-] (-10,-1) -- (-6,-1);
  \draw [-] (-8,0) -- (-8,-2);
  \node () [anchor=west] at (-10,0.5) {main memory};
  \node () [anchor=west] at (-10,-0.5)  {\texttt{@x}};
  \node () [anchor=west] at (-8,-0.5)  {\texttt{@a}};
  \node () [anchor=west] at (-10,-1.5)  {\texttt{42}};
  \node () [anchor=west] at (-8,-1.5)  {\texttt{true}};

  \node () [anchor=west] at (-10,-3.5) {store buffer for thread 0};
  \node () [anchor=west] at (0,-3.5) {store buffer for thread 1};

  \draw [-] (-10,-4) -- (-1,-4);
  \draw [-] (0,-4) -- (8,-4);

  \node () [] at (-4.5, 0.5) {thread 0};
  \draw [->, dashed] (-4.5,0) -- (-4.5,-2);
  \node () [anchor=west] at (-4, -0.5) {\texttt{store @x 42}};
  \draw [->] (-4.5,-1.75) -- (-4, -1.75);
  \node () [anchor=west] at (-4, -1.5) {\texttt{store @a true release}};

  \node () [] at (3, 0.5) {thread 1};
  \draw [->, dashed] (3,0) -- (3,-2);
  \node () [anchor=west] at (3.5, -0.5) {\texttt{load @a acquire}};
  \draw [->] (3, -0.75) -- (3.5, -0.75);
  \node () [anchor=west] at (3.5, -1.5) {\texttt{load @x}};
\end{tikzpicture}

6.  The load of `@a` in thread 1 now proceeds, the load of `@x` will always
    return `42` as there is a synchronizes-with edge between the *release* store
    and the *acquire* load of `@a` and therefore all action of thread 0 before
    the store of `@a` are visible after the load of `@a` returns the stored
    value.

\antispaceatend
\caption{Example of the weak memory model simulation with store buffers, part III.}
\label{fig:trans:wm:simple3}
\endFigure

\begFigure[p]

```{.cpp .numberLines}
int x;
std::atomic< true > a;

void thread0() {
    x = 42;
    std::atomic_thread_fence( std::memory_order_release );
    a.store( true, std::memory_order_monotonic );
}

void thread1() {
    while ( !a.load( std::memory_order_relaxed ) { }
    std::cout << x << std::endl; // can print 0 or 42
    std::atomic_thread_fence( std::memory_order_acquire );
    std::cout << x << std::endl; // always prints 42
}
```

This example is similar to the one in \autoref{fig:trans:wm:simple1}; however,
it uses explicit fences to synchronize the access to the global variable `x`.

\bigskip
\begin{tikzpicture}[ ->, >=stealth', shorten >=1pt, auto, node distance=3cm
                   , semithick
                   , scale=0.7
                   ]
  \draw [-] (-10,0) -- (-6,0) -- (-6,-2) -- (-10,-2) -- (-10,0);
  \draw [-] (-10,-1) -- (-6,-1);
  \draw [-] (-8,0) -- (-8,-2);
  \node () [anchor=west] at (-10,0.5) {main memory};
  \node () [anchor=west] at (-10,-0.5)  {\texttt{@x}};
  \node () [anchor=west] at (-8,-0.5)  {\texttt{@a}};
  \node () [anchor=west] at (-10,-1.5)  {\texttt{0}};
  \node () [anchor=west] at (-8,-1.5)  {\texttt{false}};

  \node () [anchor=west] at (-10,-4.5) {store buffer for thread 0};
  \node () [anchor=west] at (0,-4.5) {store buffer for thread 1};

  \draw [-] (-10,-5) rectangle (-0.4,-8);
  \draw [-] (-10,-6) -- (-0.4,-6) (-10,-7) -- (-0.4,-7);
  \draw [-] (-9,-5) -- (-9,-6) (-9,-7) -- (-9,-8);
  \draw [-] (-7,-5) -- (-7,-6) (-7,-7) -- (-7,-8);
  \draw [-] (-6,-5) -- (-6,-6) (-6,-7) -- (-6,-8);

  \draw [-] (0,-5) -- (8,-5);

  \node () [anchor=west] at (-10,-5.5)  {\texttt{@x}};
  \node () [anchor=west] at (-9,-5.5)  {\texttt{42}};
  \node () [anchor=west] at (-7,-5.5)  {\texttt{32}};
  \node () [anchor=west] at (-6,-5.5)  {\texttt{Unordered}};

  \node () [anchor=west] at (-10,-6.5)  {\texttt{Fence: Release}};

  \node () [anchor=west] at (-10,-7.5)  {\texttt{@a}};
  \node () [anchor=west] at (-9,-7.5)  {\texttt{true}};
  \node () [anchor=west] at (-7,-7.5)  {\texttt{8}};
  \node () [anchor=west] at (-6,-7.5)  {\texttt{Monotonic, flushed}};

  \node () [] at (-4.5, 0.5) {thread 0};
  \draw [->, dashed] (-5,0) -- (-5,-3.25);
  \node () [anchor=west] at (-4.5, -0.5) {\texttt{store @x 42}};
  \node () [anchor=west] at (-4.5, -1.5) {\texttt{fence release}};
  \node () [anchor=west] at (-4.5, -2.5) {\texttt{store @a true monotonic}};
  \draw [->] (-5,-2.75) -- (-4.5, -2.75);

  \node () [] at (3.5, 0.5) {thread 1};
  \draw [->, dashed] (3,0) -- (3,-3.25);
  \draw [->] (3, -0.25) -- (3.5, -0.25);
  \node () [anchor=west] at (3.5, -0.5) {\texttt{load @a monotonic}};
  \node () [anchor=west] at (3.5, -1.5) {\texttt{fence acquire}};
  \node () [anchor=west] at (3.5, -2.5) {\texttt{load @x}};

\end{tikzpicture}

1.  After all the instructions of thread 0 executed the store buffer contains
    two store entries and one fence entry which corresponds to the fence on line 6.

\antispaceatend
\caption{Example of the weak memory model simulation with fences, part I.}
\label{fig:trans:wm:fence1}
\endFigure

\begFigure[p]

\begin{tikzpicture}[ ->, >=stealth', shorten >=1pt, auto, node distance=3cm
                   , semithick
                   , scale=0.7
                   ]
  \draw [-] (-10,0) -- (-6,0) -- (-6,-2) -- (-10,-2) -- (-10,0);
  \draw [-] (-10,-1) -- (-6,-1);
  \draw [-] (-8,0) -- (-8,-2);
  \node () [anchor=west] at (-10,0.5) {main memory};
  \node () [anchor=west] at (-10,-0.5)  {\texttt{@x}};
  \node () [anchor=west] at (-8,-0.5)  {\texttt{@a}};
  \node () [anchor=west] at (-10,-1.5)  {\texttt{0}};
  \node () [anchor=west] at (-8,-1.5)  {\texttt{true}};

  \node () [anchor=west] at (-10,-4.5) {store buffer for thread 0};
  \node () [anchor=west] at (0,-4.5) {store buffer for thread 1};

  \draw [-] (-10,-5) rectangle (-0.4,-8);
  \draw [-] (-10,-6) -- (-0.4,-6) (-10,-7) -- (-0.4,-7);
  \draw [-] (-9,-5) -- (-9,-6) (-9,-7) -- (-9,-8);
  \draw [-] (-7,-5) -- (-7,-6) (-7,-7) -- (-7,-8);
  \draw [-] (-6,-5) -- (-6,-6) (-6,-7) -- (-6,-8);

  \draw [-] (0,-5) -- (8,-5);

  \node () [anchor=west] at (-10,-5.5)  {\texttt{@x}};
  \node () [anchor=west] at (-9,-5.5)  {\texttt{42}};
  \node () [anchor=west] at (-7,-5.5)  {\texttt{32}};
  \node () [anchor=west] at (-6,-5.5)  {\texttt{Unordered}};

  \node () [anchor=west] at (-10,-6.5)  {\texttt{Fence: Release}};

  \node () [anchor=west] at (-10,-7.5)  {\texttt{@a}};
  \node () [anchor=west] at (-9,-7.5)  {\texttt{true}};
  \node () [anchor=west] at (-7,-7.5)  {\texttt{8}};
  \node () [anchor=west] at (-6,-7.5)  {\texttt{Monotonic, flushed}};

  \node () [] at (-4.5, 0.5) {thread 0};
  \draw [->, dashed] (-5,0) -- (-5,-3.25);
  \node () [anchor=west] at (-4.5, -0.5) {\texttt{store @x 42}};
  \node () [anchor=west] at (-4.5, -1.5) {\texttt{fence release}};
  \node () [anchor=west] at (-4.5, -2.5) {\texttt{store @a true monotonic}};
  \draw [->] (-5,-2.75) -- (-4.5, -2.75);

  \node () [] at (3.5, 0.5) {thread 1};
  \draw [->, dashed] (3,0) -- (3,-3.25);
  \draw [->] (3, -0.25) -- (3.5, -0.25);
  \node () [anchor=west] at (3.5, -0.5) {\texttt{load @a monotonic}};
  \node () [anchor=west] at (3.5, -1.5) {\texttt{fence acquire}};
  \node () [anchor=west] at (3.5, -2.5) {\texttt{load @x}};

\end{tikzpicture}


2.  The last entry from the store buffer is flushed, the entry remains in the
    store buffer as it is preceded by a *release* entry.

\begin{tikzpicture}[ ->, >=stealth', shorten >=1pt, auto, node distance=3cm
                   , semithick
                   , scale=0.7
                   ]
  \draw [-] (-10,0) -- (-6,0) -- (-6,-2) -- (-10,-2) -- (-10,0);
  \draw [-] (-10,-1) -- (-6,-1);
  \draw [-] (-8,0) -- (-8,-2);
  \node () [anchor=west] at (-10,0.5) {main memory};
  \node () [anchor=west] at (-10,-0.5)  {\texttt{@x}};
  \node () [anchor=west] at (-8,-0.5)  {\texttt{@a}};
  \node () [anchor=west] at (-10,-1.5)  {\texttt{0}};
  \node () [anchor=west] at (-8,-1.5)  {\texttt{true}};

  \node () [anchor=west] at (-10,-4.5) {store buffer for thread 0};
  \node () [anchor=west] at (0,-4.5) {store buffer for thread 1};

  \draw [-] (-10,-5) rectangle (-0.4,-8);
  \draw [-] (-10,-6) -- (-0.4,-6) (-10,-7) -- (-0.4,-7);
  \draw [-] (-9,-5) -- (-9,-6) (-9,-7) -- (-9,-8);
  \draw [-] (-7,-5) -- (-7,-6) (-7,-7) -- (-7,-8);
  \draw [-] (-6,-5) -- (-6,-6) (-6,-7) -- (-6,-8);

  \draw [-] (0,-5) -- (8,-5);

  \node () [anchor=west] at (-10,-5.5)  {\texttt{@x}};
  \node () [anchor=west] at (-9,-5.5)  {\texttt{42}};
  \node () [anchor=west] at (-7,-5.5)  {\texttt{32}};
  \node () [anchor=west] at (-6,-5.5)  {\texttt{Unordered}};

  \node () [anchor=west] at (-10,-6.5)  {\texttt{Fence: Release, observed by 1}};

  \node () [anchor=west] at (-10,-7.5)  {\texttt{@a}};
  \node () [anchor=west] at (-9,-7.5)  {\texttt{true}};
  \node () [anchor=west] at (-7,-7.5)  {\texttt{8}};
  \node () [anchor=west] at (-6,-7.5)  {\texttt{Monotonic, flushed}};

  \node () [] at (-4.5, 0.5) {thread 0};
  \draw [->, dashed] (-5,0) -- (-5,-3.25);
  \node () [anchor=west] at (-4.5, -0.5) {\texttt{store @x 42}};
  \node () [anchor=west] at (-4.5, -1.5) {\texttt{fence release}};
  \node () [anchor=west] at (-4.5, -2.5) {\texttt{store @a true monotonic}};
  \draw [->] (-5,-2.75) -- (-4.5, -2.75);

  \node () [] at (3.5, 0.5) {thread 1};
  \draw [->, dashed] (3,0) -- (3,-3.25);
  \node () [anchor=west] at (3.5, -0.5) {\texttt{load @a monotonic}};
  \draw [->] (3, -1.25) -- (3.5, -1.25);
  \node () [anchor=west] at (3.5, -1.5) {\texttt{fence acquire}};
  \node () [anchor=west] at (3.5, -2.5) {\texttt{load @x}};

\end{tikzpicture}

3.  The *monotonic* load of `@a` executes, the value is already flushed into the
    memory and the load does not cause any synchronization. It does, however,
    add observed flag with thread ID of the thread which performed the load to
    any at least *release* barrier which precedes the store buffer entry for
    `@a`. The observed flag would be also added to any *release* (or stronger)
    store entries which precede the store entry for `@a` and to the entry for
    `@a` if it was *release* or stronger.

\antispaceatend
\caption{Example of the weak memory model simulation with fences, part II.}
\label{fig:trans:wm:fence2}
\endFigure

\begFigure[tp]
\begin{tikzpicture}[ ->, >=stealth', shorten >=1pt, auto, node distance=3cm
                   , semithick
                   , scale=0.7
                   ]
  \draw [-] (-10,0) -- (-6,0) -- (-6,-2) -- (-10,-2) -- (-10,0);
  \draw [-] (-10,-1) -- (-6,-1);
  \draw [-] (-8,0) -- (-8,-2);
  \node () [anchor=west] at (-10,0.5) {main memory};
  \node () [anchor=west] at (-10,-0.5)  {\texttt{@x}};
  \node () [anchor=west] at (-8,-0.5)  {\texttt{@a}};
  \node () [anchor=west] at (-10,-1.5)  {\texttt{42}};
  \node () [anchor=west] at (-8,-1.5)  {\texttt{true}};

  \node () [anchor=west] at (-10,-4.5) {store buffer for thread 0};
  \node () [anchor=west] at (0,-4.5) {store buffer for thread 1};

  \draw [-] (-10,-5) -- (-0.4,-5);

  \draw [-] (0,-5) -- (8,-5);

  \node () [] at (-4.5, 0.5) {thread 0};
  \draw [->, dashed] (-5,0) -- (-5,-3.25);
  \node () [anchor=west] at (-4.5, -0.5) {\texttt{store @x 42}};
  \node () [anchor=west] at (-4.5, -1.5) {\texttt{fence release}};
  \node () [anchor=west] at (-4.5, -2.5) {\texttt{store @a true monotonic}};
  \draw [->] (-5,-2.75) -- (-4.5, -2.75);

  \node () [] at (3.5, 0.5) {thread 1};
  \draw [->, dashed] (3,0) -- (3,-3.25);
  \node () [anchor=west] at (3.5, -0.5) {\texttt{load @a monotonic}};
  \node () [anchor=west] at (3.5, -1.5) {\texttt{fence acquire}};
  \draw [->] (3, -2.25) -- (3.5, -2.25);
  \node () [anchor=west] at (3.5, -2.5) {\texttt{load @x}};

\end{tikzpicture}

4.  The fence executes. It is an *acquire* fence so it synchronizes with any (at
    least) *release* fence which was observed by the thread which executed the
    *release* fence (thread 1). This means that all the entries before all the
    observed *release* fences has to be flushed and evicted and the fence is
    flushed and evicted too. Finally, as the store entry for `@a` was already
    flushed and it would be first entry in the store buffer after the fence is
    evicted, it is also evicted.  The load of `@x` will always return `42`.

\antispaceatend
\caption{Example of the weak memory model simulation with fences, part III.}
\label{fig:trans:wm:fence3}
\endFigure

## Nondeterministic Flushing

\label{sec:trans:wm:flush}

When a write is performed into a store buffer it can be flushed into the memory
at any later time. To simulate this nondeterminism, we introduce a thread which
is responsible for store buffer flushing. There will be one such *flusher*
thread for each store buffer. The interleaving of this thread with the other
threads will result in all the possible ways in which flushing can be done.

The flusher threads runs an infinite loop, an iteration of this loop is enabled
if there are any entries in the store buffer associated with this flusher
thread. In each iteration of the loop, the flusher thread nondeterministically
selects an entry in the store buffer and flushes if it is possible (if there is
no older entry for matching location).

## Atomic Instruction Representation

\label{sec:trans:wm:atomic}

Atomic instructions (`cmpxchg` and `atomicrmw`) are not transformed to the \llvm
memory model directly. Instead, they are first split into a sequence of
instructions which performs the same action (but not atomically) and this
sequence is executed under \divine's mask. This sequence of instructions
contains loads and stores with atomic ordering derived from the atomic ordering
of the original atomic instruction and these instructions are later transformed
to the \llvm memory model. The sequence also contains an explicit additional
synchronization required to ensure a total ordering of all the atomic
instructions over the same memory location.

```{.llvm}
%res = atomicrmw op ty* %pointer, ty %value ordering
```

\noindent The atomic read-modify-write instruction atomically performs a load
from `pointer` with the given atomic ordering, then it performs a given
operation with the result of the load and `value`, and finally it stores the
result into the `pointer` again, using the given atomic ordering. It yields the
original value loaded from `pointer`. The operation `op` can be one of
`exchange`, `add`, `sub`, `and`, `or`, `nand`, `xor`, `max`, `min`, `umax`,
`umin` (the last two are unsigned minimum and maximum, while the previous two
perform signed versions). An example of the transformation of this instruction
can be seen in \autoref{fig:trans:wm:atomicrmw}.

\begFigure[tp]

```{.llvm}
; some instructions before
%res = atomicrmw op ty* %pointer, ty %value ordering
; some instructions after
```

\noindent This will be transformed into:

```{.llvm}
; some instructions before
%0 = call i32 @__divine_interrupt_mask()
%atomicrmw.shouldunlock = icmp eq i32 %3, 0
%atomicrmw.orig = load atomic ty, ty* %ptr ordering
; explicit synchronization
%1 = bitcast ty * %ptr to i8*
call void @__lart_weakmem_sync(i8* %1, i32 width, i32 ordering)
; the instruction used here depends on op:
%opval = op %atomicrmw.orig %value
store atomic ty %opval, ty* %ptr seq_cst
br i1 %atomicrmw.shouldunlock,
    label %atomicrmw.unmask,
    label %atomicrmw.continue

atomicrmw.unmask:
call void @__divine_interrupt_unmask()
br label %atomicrmw.continue

atomicrmw.continue:
; some other instructions after, %res is replaced with
; %atomicrmw.orig
```

The implementation of `op` depends on its value, for example for `exchange`
there will be no instruction corresponding to `op` and the `store` will store
`%value` instead of `%opval`. On the other hand, `max` will be implemented using
two instructions (first the values are compared, then the bigger of them is
selected using the `select` instruction):

```{.llvm}
%1 = icmp sgt %atomicrmw.orig %value
%opval = select %1 %atomicrmw.orig %value
```

\antispaceatend
\begCaption
An example of the transformation of `atomicrmw` instruction into an equivalent
sequence of instructions which is executed atomically using
`__divine_interrupt_mask` and synchronized strongly with the other operations
using `__lart_weakmem_sync`.
\endCaption
\label{fig:trans:wm:atomicrmw}
\endFigure

```{.llvm}
%res = cmpxchg ty* %pointer, ty %cmp, ty %new
    success_ordering failure_ordering ; yields  { ty, i1 }
```

The atomic compare-and-exchange instruction atomically loads a value from
`pointer`, compares it with `cmp` and, if they match, stores `new` into
`pointer`. It returns a tuple which contains the original value loaded from
`pointer` and a boolean flag which indicates if the comparison succeeded. Unlike
the other atomic instructions, `cmpxchg` take two atomic ordering arguments; one
which gives ordering in the case of success and the other for ordering in the
case of failure. This instruction can be replaced by a code which performs
`load` with `failure_ordering`, comparison of the loaded value and `cmp` and, if
the comparison succeeds, an additional synchronization with `succeeds_ordering`
and `store` with `succeeds_ordering`. The reason to use `failure_ordering` in
the load is that failed `cmpxchg` should be equivalent to a load with
`failure_ordering`. The additional synchronization in the case of success is
needed to strengthen ordering to `success_ordering` and to ensure total store
order of the all operations which affect the given memory location. An example
of such transformation can be seen in \autoref{fig:trans:wm:atomic:cmpxchg}.

\begFigure[tp]

```{.llvm}
; some instructions before
%res = cmpxchg ty* %pointer, ty %cmp, ty %new
    success_ordering failure_ordering
; some instructions after
```

\noindent This will be transformed into:

```{.llvm}
; some instructions before
%0 = call i32 @__divine_interrupt_mask()
%cmpxchg.shouldunlock = icmp eq i32 %6, 0
%cmpxchg.orig = load atomic ty, ty* %ptr failure_ordering
%1 = bitcast ty * %ptr to i8*
call void @__lart_weakmem_sync(i8* %1, i32 bitwidth,
                               i32 failure_ordering)
%cmpxchg.eq = icmp eq i64 %cmpxchg.orig, %cmp
br i1 %cmpxchg.eq,
    label %cmpxchg.ifeq,
    label %cmpxchg.end

cmpxchg.ifeq:
call void @__lart_weakmem_sync(i8* %1, i32 bitwidth,
                               i32 success_ordering)
store atomic ty %new, ty* %ptr success_ordering
br label %cmpxchg.end

cmpxchg.end:
%2 = insertvalue { ty, i1 } undef, ty %cmpxchg.orig, 0
%res = insertvalue { ty, i1 } %2, i1 %cmpxchg.eq, 1
br i1 %cmpxchg.shouldunlock,
    label %cmpxchg.unmask,
    label %cmpxchg.continue

cmpxchg.unmask:
call void @__divine_interrupt_unmask()
br label %cmpxchg.continue

cmpxchg.continue:
; some instructions after
```

\antispaceatend
\begCaption
An example of the transformation of the `cmpxchg` instruction into an equivalent
sequence of instructions which is executed atomically using
`__divine_interrupt_mask` and synchronized strongly with the other operations
using `__lart_weakmem_sync`.
\endCaption
\label{fig:trans:wm:atomic:cmpxchg}
\endFigure

## Memory Order Specification

\label{sec:trans:wm:spec}

It is not always desirable to verify a program with the weakest possible memory
model. For this reason, the transformation can be parametrized with a minimal
ordering it guarantees for a given memory operation (each of `load`, `store`,
`fence`, `atomicrmw`, `cmpxchg` success ordering, and `cmpxchg` failure ordering
can be specified).

This way, memory models stronger than the \llvm memory model can be simulated,
for example total store order is equivalent to setting all of the minimal
orderings to *release-acquire*, the memory model of `x86` (which is basically TSO
with *sequentially consistent* atomic compare and swap, atomic
read-modify-write, and fence) can be approximated by setting `load` to *acquire*,
`store` to *release*, and the remaining instructions to *sequentially consistent
ordering*.

## Memory Cleanup

\label{sec:trans:wm:cleanup}

When a write to a certain memory location is delayed, it can happen that this
memory location becomes invalid before the delayed write is actually performed.
This can happen both for local variables and for dynamically allocated memory.
For local variables, the value might be written after the function exits, while
for the dynamic memory, value might be stored after the memory is freed.

To solve this problem, entries corresponding to invalidated memory need to be
removed from local store buffer. The reason to leave the entries in foreign
store buffers is that the existence of such entries suggests that the write to
the (soon-to-be invalidated) memory location did not synchronize properly with
the end of the scope of the memory location.

For dynamic memory, it is sufficient to remove all entries corresponding to the
object just before the call to `__divine_free` which performs the deallocation.
For local variables, it is necessary to remove the entries just before the
function exits, to do this we employ the local variable cleanups described in
\autoref{sec:trans:b:lvc}.

## Integration with $\tau+$ Reduction

\label{sec:trans:wm:tau}

As described in \autoref{sec:divine:tau} one of the important reduction
techniques in \divine is the $\tau+$ reduction, which allows execution of
multiple consecutive instructions in one atomic block if there is no more then
one action observable by other threads in this block. For example, a `store`
instruction is observable if and only if it stores to a memory block to which
some other thread holds a pointer.

This means that any load from or store into store buffer will be considered to
be a visible action, because the store buffer has to be visible both from the
thread executing the load or store and from the thread which flushes store
buffer to the memory.

\bigskip

To partially mitigate this issue, it was proposed in \cite{SRB15} to
bypass store buffer when storing to addresses which are considered thread
private by \divine's $\tau+$ reduction. To do this, `__divine_is_private`
intrinsic function is used in the function which implements weak memory store,
and, if the address to which store is performed is indeed private, the store is
executed directly, bypassing store buffer.

This reduction is indeed correct for TSO stores which were simulated in
\cite{SRB15}. It is easy to see that the reduction is correct if a memory
location is always private or always public for the entire run of the program.
The first case means that it is never accessed from more then one thread and
therefore no store buffer is needed, the second case means the store buffer will
be used always. If the memory location (say `x`) becomes public during the run
of the program, it is again correct (the publication can happen only by writing
an address of memory location from which `x` can be reached following pointers
into some already public location):

*   if `x` is first written and then published then, were the store buffers
    used, the value of `x` would need to be flushed from store buffer before `x`
    could be reached from the other thread (because the stores cannot be
    reordered under TSO), and therefore the observed values are the same with
    and without the reduction;

*   if `x` is first made private and then written, then the "making private"
    must happen by changing some pointer in public location, an action which
    will be delayed by the store buffer. However, this action must be flushed
    before the store to `x` in which it is considered private, as otherwise `x`
    would not be private, and therefore also before any other modifications to
    `x` which precede making `x` private;

*   the remaining possibilities (`x` written after the publication, and `x`
    written before making it private) are not changed by the reduction.

In our case of the general \llvm memory model with presence of explicit atomic
instructions, this reduction cannot be used: suppose a memory location `x` is
written while it is thread private and later the address of `x` is written into
visible location `y`. Now it might be possible, provided that `y` has
weaker than *release* ordering, that the old value of `x` is accessed through `y`
(if `y` is flushed before `x`). For this reason, stores to all memory locations
have to go through the store buffer (unless it is possible to prove that they
can never be visible by more than one thread).

\bigskip

Furthermore, considering that all store buffers are reachable from all threads,
and therefore any memory location which has entry in store buffer is considered
public, we can bypass store buffers for `load` instructions, even under \llvm
memory model. That is, the store buffer lookup can be bypassed for a memory
location if it is considered private by \divine, because no memory location
which is private can have entry in any store buffer. This means that loads of
private memory locations are no longer considered as visible actions by $\tau+$,
which leads to a state space reduction.

As a final optimization, any load from or store into local variable which never
escapes scope of the function which allocated it need not be instrumented, that
is the `load` or `store` instruction need not be replaced with appropriate weak
memory simulating version. To detect these cases, we currently use \llvm's
`PointerMayBeCaptured` function to check if the memory location of a local
variable was ever written to some other memory location. A more precise
approximation could use pointer analysis to detect which memory locations can
only be accessed from one thread.

The evaluation of the proposed optimizations can be found in
\autoref{sec:res:wm:tau}.

## Interaction With Atomic Sections

An important consequence of the \llvm memory model transformation is that effects of
instructions which are executed inside \divine's atomic sections (using
`__divine_interrupt_mask`) need not happen as part of the atomic section. For
example, a `store` executed in an atomic section can be flushed much later after
the atomic sections ends. This creates additional requirements to the implementation of
libraries for \divine, namely the `pthread` threading library. For this reason,
any `pthread` function which uses atomic sections now includes a *sequentially
consistent* fence after the atomic section is entered and before it is exited.

## Implementation

The transformation implementation consists of two passes over \llvm bitcode, the
first one is used to split loads and stores larger than 64 bits into smaller
loads and stores. In the second phase, the bitcode is instrumented with the
\llvm memory model using functions which implement stores, loads, and fences
using store buffer and atomic functions are rewritten as described in
\autoref{sec:trans:wm:atomic}. The userspace functions simulating the memory
model are implemented in C++ and compiled together with the verified program by
`divine compile`. The userspace functions can be found in
`lart/userspace/weakmem.h` and `lart/userspace/weakmem.cpp`, the transformation
pass can be found in `lart/weakmem/pass.cpp`. The transformation can be run
using `lart` binary, see \autoref{sec:ap:lart} for detains on how to compile and
run \lart.

### Userspace Functions

The userspace interface is described by `lart/userspace/weakmem.h`, which
defines types and functions necessary for the transformation.

```{.c}
volatile extern int __lart_weakmem_buffer_size;
```

\noindent
The store buffer size limit is saved in this variable so that it can be set by the
weak memory transformation.

```{.c}
enum __lart_weakmem_order {
    __lart_weakmem_order_unordered,
    __lart_weakmem_order_monotonic,
    __lart_weakmem_order_acquire,
    __lart_weakmem_order_release,
    __lart_weakmem_order_acq_rel,
    __lart_weakmem_order_seq_cst
};
```

\noindent
An enumeration type which corresponds to the \llvm atomic orderings.

```{.c}
void __lart_weakmem_store( char *addr, uint64_t value,
            uint32_t bitwidth, __lart_weakmem_order ord );
uint64_t __lart_weakmem_load( char *addr, uint32_t bitwidth,
            __lart_weakmem_order ord );
void __lart_weakmem_fence( __lart_weakmem_order ord );
```

\noindent These functions replace `store`, `load`, and `fence` instructions. The
transformation is expected to fill-in `bitwidth` parameter according to the
actual bit width of the loaded/stored type and to perform any necessary casts.
Each of these functions is performed atomically using \divine atomic mask. Load
function must be able to reconstruct loaded value from several entries in the
store buffer as it is possible that some entry corresponds to only a part of the
requested value. While these functions are primarily intended to be used by the
\lart transformation, their careful manual usage can be used to manually
simulate weak memory model for a subset of operations.

```{.c}
void __lart_weakmem_sync( char *addr, uint32_t bitwidth,
                            __lart_weakmem_order ord );
```

\noindent This function is used for explicit synchronization of atomic
instructions (`atomicrmw`, `cmpxchg`) to ensure a total order of all atomic
modifications.  The memory order must be at least *monotonic*, this function
ensures that there is no (at least) *monotonic* entry for a matching address in
any foreign store buffer.

```{.c}
void __lart_weakmem_cleanup( int cnt, ... );
```

\noindent This function is used to implement memory cleanups
(\autoref{sec:trans:wm:cleanup}). Its variadic arguments are memory addresses
which should be evicted from local store buffer, `cnt` should be set to the
number of these addresses.

```{.c}
void __lart_weakmem_memmove( char *dest, const char *src,
                                          size_t n );
void __lart_weakmem_memcpy( char *dest, const char *src,
                                          size_t n );
void __lart_weakmem_memset( char *dest, int c, size_t n );
```

\noindent These functions are used as replacements for `llvm.memcpy`,
`llvm.memset`, and `llvm.memmove` intrinsics. The transformation pass will
derive two versions of these functions, one to be used by the weak memory model
implementation (this version must not use store buffers) and the other to
implement these intrinsics in weak memory model.

\bigskip

All of these functions have following attributes (using GCC syntax
`__attribute__` which is understood by Clang):

`noinline`
~   to prevent inlining of these functions into their callers;

`flatten`
~   to inline all function calls these functions contain into their body (this
    is used to make sure these functions do not call any function which could
    use store buffer);

`annotate("lart.weakmem.bypass")`
~   which indicates to the transformation pass that these functions should not be
    transformed to use store buffers;

`annotate("lart.weakmem.propagate")`
~   which indicates to the transformation pass that any function called from
    these functions should not be transformed to use store buffers (this is done
    to handle cases in which compiler refuses to inline all calls into these
    functions, the transformation pass will output a warning if this happens).

### \lart Transformation Pass

The transformation pass processes all the functions in the module one by one.
For the weak memory implementation functions it only transforms calls to
`llvm.memmove`, `llvm.memcpy`, and `llvm.memset` intrinsics to calls to their
implementations which do not use store buffer simulation.

For other functions the transformation is done in the following three phases.

1.  Atomic compound instructions (`atomicrmw` and `cmpxchg`) are replaced by
    their equivalents as described in \autoref{sec:trans:wm:atomic}.

2.  Loads and stores are replaced by calls to the appropriate userspace
    functions.  This includes casting of the addresses to the `i8*` \llvm type
    and values need to be truncated from respectively extended to the `i64`
    type. For non-integral types this also includes `bitcast` from (to) integral
    types (a cast which does not change bit pattern of the value, it changes
    only its type).

    The atomic ordering used in the \llvm memory model simulation is derived
    from the atomic ordering of the original instruction and from the default
    atomic ordering for given instruction type which is determined by
    transformation configuration (\autoref{sec:trans:wm:spec}).

3.  Memory intrinsics (`llvm.memmove`, `llvm.memcpy`, and `llvm.memset`) are
    translated to the appropriate userspace functions which implement these
    operations using store buffers.

The transformation is not applied to instructions which manipulate local
variables which do not escape scope of the function which defines them.

The transformation is configurable. It can be specified what minimal atomic
ordering is guaranteed for each instruction type and what should be the size
bound for store buffers. The specification is given when \lart is invoked (see
\autoref{sec:ap:lart}), for atomic orderings it can be one of:

`std`
~   for the unconstrained \llvm memory model;

`tso`
~   for Total Store Order simulation, this guarantees that all loads have at
    least *acquire* ordering, all stores have at least *release* ordering, and all
    the other operations have at least *acquire-release* ordering.

`x86`
~   for simulation of a memory model similar to the one in `x86` CPUs. In this
    case, loads have at least *acquire* ordering, stores have at least *release*
    ordering and all other transformed operations have *sequentially consistent*
    ordering.

custom specification
~   is a comma separated list of `kind=ordering` pairs, where `kind` is an
    instruction type (one of `all`, `load`, `store`, `cas`, `casfail`, `casok`,
    `armw`, and `fence`) and `ordering` is atomic ordering specification (one of
    `unordered`, `relaxed`,[^rel] `acquire`, `release`, `acq_rel`, and
    `seq_cst`). The list of these pairs is processed left to right, the latter
    entries override the former.

    For example, TSO can be specified as `all=acq_rel`, equivalent of `x86` can
    be specified as `all=seq_cst,load=acquire,store=release`.

[^rel]: In this case `relaxed` is used to denote the \llvm's monotonic ordering
to match the name used for this ordering in the C++11/C11 standard.



# Code Optimization in Formal Verification

\label{sec:trans:opt}

\divine aims at verification of real-world code written in C and C++. Both \llvm
IR and assembly produced from such a code is often heavily optimized during the
compilation to increase its speed. To verify the code as precisely as possible,
it is desirable to verify \llvm IR with all the optimizations which will be used
in the binary version of the program and the binary should be compiled by the
same compiler as the \llvm IR used in \divine. Ideally, it would be possible to
use the same \llvm IR for verification and to build the binary. This is,
however, not currently possible as \divine needs to re-implement library
features (namely `pthreads` and C++ exception handling) and this implementation
might not be compatible with the implementation used on given platform.
Nevertheless, \divine should use the optimization levels requested by its user
for the program compilation.

On the other hand, it is desirable to utilize \llvm optimizations in such a way
that model checking can benefit from it. This, however, requires special purpose
optimizations designed for the verification, as the general purpose
optimizations do not meet two critical requirements for verification.

*   **They can change satisfiability of the verified property.** This is usually
    caused by the fact that compiler optimizations are not required to preserve
    behaviour of parallel programs, and that many programs written in C/C++
    contain undefined behaviour as they access non-atomic non-volatile variables
    from multiple threads. See \autoref{fig:trans:opt:undef} for an example of
    such property-changing optimization.

*   **They might increase state space size.** Not all optimizations which lead
    to faster execution lead to faster verification as they might change program
    behaviour in such a way that model checker generates more states. An example
    of such a transformation can be any transformation which increases the
    number of registers in a function. This might cause states which were
    originally considered to be the same to become distinct after the
    optimization.  More specifically, examples of such transformation are
    promotion of variables into registers, loop unrolling, and loop rotation
    which can be seen in \autoref{fig:trans:opt:looprot}.

\begFigure[tp]

```{.cpp}
int x;
void foo() {
    x = 1;
    assert( x == 1 );
}
int main() {
    std::thread t( &foo );
    x = 2;
    t.join();
}
```

This code is an example of an undefined behaviour, the global non-atomic
variable `x` is written concurrently from two threads. For this program
assertion safety does not hold. The assertion can be violated if the assignment
`x = 2` executes between `x = 1` and `assert( x == 1 )`.


```{.llvm}
store i32 1, i32* @x, align 4
%0 = load i32, i32* @x, align 4
%tobool = icmp ne i32 %0, 0
%conv = zext i1 %tobool to i32
call void @__divine_assert(i32 %conv)
ret void
```

The body of `foo` emitted by Clang without any optimization is a straightforward
translation of the C++ code. It stores into global `@x`, then loads it and
compares the loaded value to `0`. In this case, \divine will report assertion
violation.

```{.llvm}
store i32 1, i32* @x, align 4
tail call void @__divine_assert(i32 1)
ret void
```

This is optimized (`-O2`) version of `foo`. `store` is still present, but the
compiler assumes that the `load` which should follow it will return the save
value as written immediately before it (this is a valid assumption for
non-atomic, non-volatile shared variable). For this reason, the assertion is
optimized into `assert( true )` and no assertion violation is possible.

\begCaption
An example of program in which optimizations change property satisfiability.
\endCaption
\label{fig:trans:opt:undef}
\endFigure

\begFigure[tp]

Suppose a program with global atomic boolean variable `turn` and a code snipped
which waits for this value to be set to true:

```{.cpp}
while ( !turn ) { }
// rest of the code
```

\noindent
This program might generate following \llvm:

```{.llvm}
loop:
%0 = load atomic i8, i8* @turn seq_cst
%1 = icmp eq i8 %0, 0
br %1, label %loop, label %end

end:
; rest of the code
```

\noindent
With optimization, this \llvm can be changed to:

```{.llvm}
pre:
%0 = load atomic i8, i8* @turn seq_cst
%1 = icmp eq i8 %0, 0
br %1, label %loop, label %end

loop:
%2 = load atomic i8, i8* @turn seq_cst
%3 = icmp eq i8 %2, 0
br %3, label %loop, label %end

end:
; rest of the code
```

\noindent
Basically the loop is rotated to a loop equivalent to the following code:

```{.cpp}
if ( !trun ) {
    do { } while ( !turn ) { }
}
```

While this code might be faster in practice due to branch prediction, for model
checking this is an adverse change as the model checker can now distinguish the
state after one and two executions of the original loop based on the register
values.

\begCaption
An example of optimization with an adverse effect on model checking.
\endCaption
\label{fig:trans:opt:looprot}
\endFigure

For these reasons, we suggest some optimization techniques which would allow
optimization of \llvm IR and not change verification outcome or increase state
space size. On the other hand, these techniques can use a specific knowledge
about the verification environment they will be used in. Some of these
techniques were already implemented as part of this thesis and are evaluated in
\autoref{sec:res:opt}, some of them are proposals for a future work.

## Constant Local Variable Elimination

\label{sec:trans:opt:local}

Especially with optimizations disabled, compilers often create `alloca`
instructions (which correspond to stack-allocated local variables) even for
local variables which need not have address and perform loads and stores into
those memory locations instead of keeping the value in registers. To eliminate
unnecessary `alloca` instructions, \llvm provides a register promotion pass.
Nevertheless, this pass is not well suited for the model checking as it can add
registers into the function and in this way increase the state space size. For this
reason, we introduce a pass which eliminates *constant* local variables, as these
can be eliminated without adding registers (actually, some registers can be
removed in this case).

With this reduction, an `alloca` instruction can be eliminated if the following
conditions are met:

*   the address of the memory is never accessed outside of the function;
*   it is written only once;
*   the `store` into the `alloca` dominates all `loads` from it.

\noindent The first condition ensures that the `alloca` can be deleted, while
the other two conditions ensure that the value which is loaded from it is always
the same, and therefore can be replaced with the value which was stored into the
`alloca`.

In the current implementation of this pass, each function is searched for
`alloca` instructions which meet these criteria (ignoring uses of address in
`llvm.dbg.declare` intrinsic[^dbg]), all uses of results of loads from these
memory locations are replaced with the value which was originally stored into
it, and finally the `alloca` and all its uses are eliminated from the function.
Please note that the conditions ensure that the only uses of the `alloca` are
the single store into it, the loads which read it, and `llvm.dbg.declare`
intrinsics.

[^dbg]: This intrinsic is used to bind a debugging information such as variable
name with the variable's \llvm IR representation. It does not affect the
behaviour of the program in any way.

## Constant Global Variable Annotation

\label{sec:trans:opt:global}

In \divine, any non-constant global variable is considered to be visible by all
threads and is saved in each state in the state space. However, it can happen
that this variable cannot be changed during any run of the program. If such a
condition can be detected statically, it is possible to set this variable to be
constant which removes it from all states (it is stored in constants, which are
part of the interpreter state) and it also causes the loads of this variable to
be considered to be invisible actions by $\tau+$ reduction.

For a global variable to be made constant in this way, it must meet the following
conditions:

*   it must be never written to, neither directly nor through any pointer;
*   it must have constant initializer.

While the second condition can be checked from the definition of the global
variable, the first one cannot be exactly efficiently determined. It can be
approximated using pointer analysis.

Currently, \lart lacks working pointer analysis, so we used a simple heuristic
for the initial implementation: the address of the global variable must not
be stored into any memory location and any value derived from the address must
not be used in instructions which can store into it (`store`, `atomicrmw`,
`cmpxchg`). This is implemented by recursively tracking all uses of the values
derived from the global variable's address. The implementation is available in
`lart/reduction/globals.cpp`.

## Local Variable and Register Zeroing

\label{sec:trans:opt:lzero}

\llvm registers are immutable and therefore they retain their value even after
it is no longer useful. This means that there can be states in the state space
which differ only in a value of a register which does not change the execution
of the program as it will be never used again. This situation can be eliminated
by setting the no-longer-used registers to 0. However, this is not possible in
the \llvm as it is in a static single assignment form.

Nevertheless, with addition of one intrinsic function into the \divine's \llvm
interpreter, it is possible to zero registers in \divine at the place determined
by the call to this intrinsic. Since \llvm is type safe, this intrinsic is
actually implemented as a family of functions with `__divine_drop_register.`
prefix, one for each type of register which needs to be zeroed. Signatures for
these functions are generated automatically by the \lart pass which perform
register zeroing. Any call to a function with this prefix is implemented as an
intrinsic which zeroes the register and sets it as uninitialized.

The \lart pass (which is implemented in `lart/reduce/register.cpp`) processes
each function with the following algorithm.

1.  For each instruction $i$, it searches for last uses:
    *   this is either a use $u$ such that no other use of $i$ is reachable from
        $u$;
    *   or a use $u$ which is part of a loop and all the uses of $i$ reachable
        from it are in the same loop.

2.  Insertion points for `__divine_drop_register` calls are determined:
    *   for the uses which are not in a loop, the insertion point is set to be
        immediately after the use;
    *   for the uses which are in a loop, the insertion point is at the
        beginning of any basic block which follows the loop.

    Strongly connected components of the control flow graph of the function are
    used to determine if an instruction is in a loop and successors of a loop.

3.  If an instruction $i$ dominates an insertion point, `__divine_drop_register`
    call for $i$ is inserted at this point.

Furthermore, if the instruction in question is an `alloca`, it is treated
specially. `alloca` cannot be zeroed until the local variable it represents is
released. A simple heuristics is used to determine if the local variable might
be aliased, and if not, it is dropped immediately before the register which
corresponds to its `alloca` is zeroed. Otherwise the register is not zeroed and
the `alloca` will be released automatically by \divine.

## Terminating Loop Optimization

\label{sec:trans:opt:loop}

In \divine a loop will generate a state at least once an iteration. This is
caused by the heuristics which makes sure the state generation terminates.
However, if the loop performs no visible action and always terminates, it is
possible to run it atomically. This way, the entire loop is merged into one
action, which leads to further reduction of the state space size.

This reduction is not implemented yet, however, to implement it, it would be
necessary to have the following components:

1.  loop detection, this is possible using \llvm's `LoopAnalysis`;
2.  termination analysis for \llvm loops, which requires recovering of loop
    condition from \llvm IR and should employ some existing termination
    detection heuristic;
3.  pointer analysis to detect if loop accesses any variable which is (or might
    be) accessible from other threads; it is also possible to use
    `__divine_is_private` to detect visibility dynamically, or combine these
    approaches.

## Nondeterminism Tracking

\label{sec:trans:opt:nondet}

\divine is an explicit state model checker and it does not handle data
nondeterminism well. Nevertheless, data nondeterminism is often useful, for
example to simulate input or random number generation by a variable which can
have arbitrary value from some range. The only way to simulate such
nondeterminism in \divine is to enumerate all the possibilities explicitly,
using `__divine_choice`. This, of course, can lead to large state space, as it
causes branching of the size of the argument of `__divine_choice`.

Nevertheless, for small domains, this handling of nondeterminism is quite
efficient, as it does not require any symbolic data representation. This way,
`__divine_choice` is used for example to simulate failure of `malloc`: `malloc`
can return a null pointer if the allocation is not possible and \divine
simulates this in such a way that any call to `malloc` nondeterministically
branches into two possibilities; either the `malloc` succeeds and returns
memory, or it fails. Similarly, weak memory model simulation
(\autoref{sec:trans:wm}) uses nondeterministic choice to determine which entry
of store buffer should be flushed.

For the verification of real-world programs it is useful to be able to constrain
nondeterminism which can occur in them, for example as a result of a call of the
`rand` function, which returns a random number from some interval, usually from
$0$ to $2^{31} - 1$. Such a nondeterminism is too large to be handled
explicitly. Nevertheless, it often occurs in patterns like `rand() % N` for some
fixed and usually small number `N`. In these cases it is sufficient to replace
`rand() % N` with `__divine_choice( N )` which might be tractable for
sufficiently small values of `N`.

To automate this replacement at least in some cases a \llvm pass which tracks
nondeterministic value and constraints the nondeterministic choice to smallest
possible interval can be created. A very simple implementation of such pass
which tracks nondeterminism only inside one function and recognizes two
patterns, cast to `bool` and modulo constant number, can be found in
`lart/svcomp/svcomp.cpp`, class `NondetTracking`. For a more complete
implementation, a limited symbolic execution of part of the program which uses
the nondeterministic value could be used. This version is not implemented yet.

# Transformations for SV-COMP 2016

SV-COMP is a competition of software verifiers associated with TACAS conference
\cite{SVCOMP}. It provides a set of benchmarks in several categories, benchmarks
are written in C. \divine is participating in SV-COMP 2016 in the concurrency
category which contains several hundred of short parallel C programs. Some of
these programs have infinite state space (usually infinite number of threads),
or use nondeterministic data heavily an therefore are not tractable by \divine.
There are, however, many programs which can be verified by \divine, with some
minor tweaks.

In order to make it possible to verify the SV-COMP programs with \divine, they
have to be pre-processed, as they use some SV-COMP-specific functions and rely
on certain assumptions about the semantics of C which is not always met when C
is compiled into \llvm.

1.  The benchmark is compiled using `divine compile`.

2.  Using \lart, atomic sections used in SV-COMP are replaced with \divine's
    atomic sections which use `__divine_interrupt_mask`.

3.  Using \lart, all reads and writes to global variables defined in the
    benchmark are set to be volatile. This is done because SV-COMP models often
    contain undefined behaviour, such as concurrent access to non-volatile,
    non-atomic variable which could be optimized improperly for SV-COMP. This
    pass actually hides errors in SV-COMP benchmarks; nevertheless, it is
    necessary, since SV-COMP benchmarks assume any use of shared variable will
    cause a load from it, which is not required by the C standard.

4.  \llvm optimizations are run, using \llvm `opt` with `-Oz` (optimizations for
    binary size).

5.  Nondeterminism tracking (\autoref{sec:trans:opt:nondet}) is used.

6.  \lart is used to disable `malloc` nondeterministic failure as SV-COMP
    assumes that `malloc` never fails.

7.  Finally, \divine is run on the program with Context-Switch-Directed
    Reachability \cite{SRB14} and assertion violations are reported if
    there are any. Other errors are not reported.

With these transformations, \divine is expected to score more than 900 points
out of 1222 total in the concurrency category. A report which describes our approach
is to appear in TACAS proceedings \cite{SRB16svc}. The implementation of these
transformations can be found in the `lart/svmcomp/` directory.
