# New Interface for Atomic Sections

The interface for declaring atomic sections in verified code (described in
\autoref{sec:divine:interp}) is hard to use, the main reason being that while
the mask set by `__divine_interrupt_mask` is inherited by called functions,
these have no way of knowing if they are inside atomic section, and more
importantly, they can end the atomic section by calling
`__divine_interrupt_unmask`. This is especially bad for composition of atomic
functions, see \autoref{fig:ex:atomic:bad} for example. For this reason, the only
compositionally safe way to use \divine's original atomic sections is to never
call `__divine_interrupt_unmask` and let \divine end the atomic section when the
caller of `__divine_interrupt_mask` ends.

#@FIG:tp

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
\caption{Example of composition problem with original \divine atomic sections
--- the atomic section begins on line 10 and is inherited to
\texttt{doSomething}, but the atomic section ends by the unmask call at line 4
and the rest of \texttt{doSomething} and \texttt{foo} are not executed
atomically. The atomic section is then re-entered when \texttt{doSomething}
returns.}
\label{fig:ex:atomic:bad}
#@eFIG

To alleviate aforementioned problems we reimplemented atomic sections in
\divine. The new design uses only one *interrup flag* to indicate that current
thread of execution is in atomic section, this flag is internal to the
interpreter and need not be saved in the state --- indeed it would be always set
to false in the state emitted by the generator because the state can never be
emitted in the middle of atomic section. Furthermore, we modified
`__divine_interrupt_mask` to return `int` value corresponding to value of
interrupt flag before it was set by this call to `__divine_interrupt_mask`.

To make using new atomic sections easier we provide higher level interface for
atomic sections by the means of a C++ library and annotations. The C++ interface
is intended to be used mostly by developers of language bindings for \divine,
while the annotations are designed to be usable by end-users of \divine.

The C++ interface is RAII-based[^raii], it works similar to C++11 `unique_lock`
with recursive mutexes --- an atomic section begins by construction of object of
type `divine::InterruptMask` and is left either by call of `release` method on
this object, or by in the destructor of `InterruptMask` object. If atomic
sections are nested, only the outermost `release` actually ends the atomic
section. See \autoref{fig:ex:atomic:cpp} for an example.

#@FIG:tp
```{.cpp}
#include <divine/interrupt.h>

void doSomething( int *ptr, int val ) {
    divine::InterruptMask mask;
    *ptr += val;
    // relea the mask only if no mask higher on stack:
    mask.release();
    // masked only if caller of doSomething was masked:
    foo( ptr );
}

int main() {
    int x = 0;                    // not masked
    divine::InterruptMask mask;
    doSomething( &x );            // maksed
    // mask ends automatically at the end of main
}
```

\caption{An example of use of C++ interface for the new atomic sections in
\divine.}
\label{fig:ex:atomic:cpp}
#@eFIG

[^raii]: Resource Acquisition Is Initialization, a common pattern in C++ in
which a resource is allocated inside object and safely deallocated when that
object exits scope, usually at the end of function. \TODO{odkaz, citace?}

The annotation interface is based on \lart transformation pass and annotations
which can be used to mark functions atomic. This way, entire functions can
be marked atomic by adding `__lart_atomic_function` to their header, see
\autoref{fig:ex:atomic:lart} for an example.

#@FIG:tp
```{.cpp}
#include <lart/atomic>

int atomicInc( int *ptr, int val ) __lart_atomic_function {
    int prev = *ptr;
    *ptr += val;
    return prev;
}
```
\caption{An example of usage of annotation interface for atomic functions in
\divine{} --- the function \texttt{atomicInc} is aways executed atomically and is
safe to be executed inside another function annotated as atomic.}
\label{fig:ex:atomic:lart}
#@eFIG

\TODO{implementation}


# Local Variable Cleanup

When enriching \llvm bitcode in a way which modifies local variables it is
often necessary to perform cleaning operation at the end of the scope of these
variables. One of these cases is mentioned in \autoref{sec:extend:wm:invstore},
another can arise from compiled-in abstractions proposed in \cite{RockaiPhD}.
These variable cleanups are essentially akin to C++ destructors in a sense that
they get executed at the end of scope of the variable, no matter how this
happens, with only exception of thread termination.

Implementing variable cleanups for languages without non-local control flow
transfer other then with `call` and `return` instructions, for example standard
C, would be fairly straight-forward --- it is sufficient to run cleanup just
before function returns and clean-up any local variables from which this
particular return point is reachable. However, while pure standard-compliant C
has no non-local control transfer, in POSIX there are `setjmp` and `longjmp`
functions which allow non-local jumps and, even more importantly, C++ has
exceptions already in its standard.

In presence of exception handling, the situation is more complicated. Since we
target C++ and allow programs with exception we will now focus on this case,
through the lens of \llvm representation of exception handling (for details on
\llvm exception handling see \autoref{sec:llvm:eh}.

Here we need to make sure that cleanup runs not only in the case of normal exit
from a function by the means of return instruction, but also when the function
is exited by stack unwinding, that is while exception is being propagated.
Furthermore, we need to make sure our cleanup handling does not interfere with
already present exception handling in the function, should there be any. This
can be done in two phases --- it is necessary to convert any calls of functions
which can throw an exception so that any exception can be caught (and re-thrown
if it was not handled originally), and then a cleanup code needs to be added
into appropriate location in the exception handling path and normal function
exit path.

## Call Instrumentation

For the first phase it is sufficient to convert any `call` instruction for which
we cannot show that the callee cannot throw an exception into `invoke`
instruction, which allows as to branch out into a landing block if an
exception is thrown by the callee. The `landingpad` in the landing block need to
be set up in a way in can caught any exception (this can be done using `cleanup`
flag for `landingpad`). The instrumentation can be done as follows:

*   for a call site, if it is a `call`:

    1.  given a `call` instruction to be converted, split its parent basic block
        into two just after this instruction (we will call these blocks *invoke
        block* and *invoke-ok* block),
    2.  add a new basic block for cleanup, this block will contain a `landingpad`
        instruction with `cleanup` flag and a `resume` instruction (we will call
        this block *invoke-unwind block*),
    3.  replace the `call` instruction with `invoke` with the same function and
        parameters, its normal destination is set to *invoke-ok block* and its
        unwind destionation is set to *invoke-unwind block*,

*   otherwise, if it is an `invoke` and its unwind block does not contain `cleanup`
    flag in `landingpad`:
    1.  create new basic block containing just resume instruction (*resume
        block*)
    2.  add `cleanup` flag into `landingpad` of the unwind block of the `invoke` and
        branch into *resume block* if landing block is triggered due to
        `cleanup`.
*   \TODO{otherwise nothing is done}

Any calls using `call` instruction with known destination which is a function
marked with `nounwind` attribute will not be modified. Functions marked with
`nounwind` need to be checked for exceptions as \llvm states that these
functions should never throw an exception and therefore we assume that throwing
and exception from such a function will be reported as an error by the verifier
\TODO{specifikovat někde, že je to požadavek na verifikátor}.

```{.llvm}
TODO: příklad
%1 = call
```

\TODO{popis příkladu}

After the call instrumentation the following holds: every time the function is
entered by stack unwinding due to active exception, the control is transfered to
a landing block and, if before this transformation the exception would not be
intercepted by `landingpad` in this function, after the transformation 
the same exception would be rethrown by `resume`.

\TODO{pozorvonání z jiného vlákna -> přidává běhy, ale o žádné nepříjde}

## Adding Exception Handling Cleanup

The exception handling, which begins in the landing block, can perform two
types of action --- it can either perform cleanup and re-throw the exception
(using `resume` instruction), or catch the exception (using language-dependent
mechanism), and resume normal operation. It can also do combination of these
actions based on the type of the exception. However, it is not necessary to
analyze the exception handling mechanism in the function, instead it is
sufficient to add cleanup code just before any `resume` and `return`
instruction, such that this code will clean all local variables which can reach
this function termination.

In order for the cleanup code to work, it needs to be able to access all local
variables define before the associated function exit, that is results of all
`alloca` instructions from which this exit can be reached. However, this might
not be always true:

```
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

In this example, `%y` is defined in `if.then` basic block, but it needs to be
cleared just before the `return` instruction at the end of `if.end` basic block,
and the definition of `%y` does not dominate the cleaning point. The cleanup
cannot be, in general, safely inserted after last use \TODO{zdůvodnit --
nerozhodnutelné}. For this reason we will first insert $\varphi$-nodes in such a
way that any `alloca` is represented in any block which it can reach --- either
by its value if the control did pass the `alloca` instruction, or by `null`
constant if the control did not pass it. For our example the result of the
modification would be the following (just last basic block is modified):

```
if.end:  ; preds = %if.then, %entry
  %y.phi = phi i32* [ null, %entry ], [ %y, %if.then ];
  ; cleanup will be inserted here
  ret i32 0
```

In this example, `%y.phi` represents `%y` at the cleanup point --- it can be
either equal to `%y` if control passed through definition of `%y`, or `null`
otherwise.

\TODO{Those phi nodes can be added by simple algorithm which traverses BBs in
DFS order…}

# Weak Memory Models

In modern CPUs, the write to memory location need not be immediately visible in
other threads, for example due to caches or out-of-order execution. However most
of the verification tools, including \divine, do not directly support
verification with these relaxed memory models, instead they assume *sequential
consistency*, that is immediate visibility of any write to memory.

In \cite{SRB15}, adding weak memory model simulation using \llvm-to-\llvm
transformation was proposed. In this section we will describe details of the
implementation of this transformation, as well as its extension which allows
verification of full range of properties supported by \divine, most notably
memory safety, which was not possible in original version of the transformation.
We also show that, while the extension for $\tau+$ reduction proposed in
\cite{SRB15} is indeed correct for TSO, it is not correct for PSO, and we
propose alternative method which can partially resolve this problem.

## Total Store Order

Since the memory models implemented in hardware differ with CPU vendors, or
even particular models of CPUs, it would not be practical and feasible to verify
programs with regard to particular implementation of real-world memory model. For this reason
several theoretical memory models were proposed, namely *Total Store Order*
(TSO) \cite{SPARC94}, *Partial Store Order* (PSO) \cite{SPARC94}. 
\TODO{přepsat konec odstavce:} In those theoretical models, an
update may be deferred for an infinite amount of time. Therefore, even a finite
state program that is instrumented with a possibly infinite delay of an update
may exhibit an infinite state space. It has been proven that for such an
instrumented program, the problem of reachability of a particular system
configuration is decidable, but the problem of repeated reachability of a
given system configuration is not \cite{Atig:2010:VPW:1706299.1706303}.

In Total Store Order memory model, any write can be delayed infinitely but the
order in which writes done by one thread become visible in other threads must
match the order of writes in the thread which executed them. This memory model
can be simulated by store buffer --- any write is first done into a
thread-private buffer so it is invisible for other threads, this buffer keeps
writes in FIFO order. The buffer can later be nondeterministically flushed,
that is oldest entry from the buffer can be written to memory. Furthermore, any
reads have to first look into store buffer of their thread for newer value of
memory location, only if there is none they can look into memory. See
\autoref{fig:extend:wm:sb} for an example of store buffer working.

The transformation presented in \cite{SRB15} implements under-approximation of
TSO using bounded store buffer. In this case the buffer size is limited and if
an entry is to be written into full store buffer, the oldest entry from the
buffer is flushed into memory. With this limited store buffer the
transformation can be reasonably implemented, and the resulting state space is
finite if the state space of the original program was finite, therefore this
transformation is suitable for explicit state model checking.

## Implementation

The transformation implementation consists of two passes over \llvm bitcode, the
first one (written by Petr Ročkai) is used to split loads and stores larger than
64 bits into smaller loads and stores. In the second phase (written by me),
bitcode is instrumented with store buffers using functions which perform stores
and loads into store buffer. These functions are implemented in C++ and are part
of the bitcode libraries provided by \divine.

More specifically we distinguish three kind of functions in our transformation:
*TSO*, *SC*, and *bypass* --- TSO functions will be instrumented to use Total
Store Order memory model, SC functions will be instrumented to use Sequential
Consistency \TODO{co to znamená -> ono to neznamená, že by ta funkce viděla
efekty okamžitě, ale že JEJÍ efekty jsou vidět okamžtě),
and bypass functions will be left unchanged --- these are used to
implement the store buffer simulation. These kinds can be assigned to functions
either by the means of annotation attributes[^annot], or by specifying default
function kind, which will be used for all functions without annotation (this can
be either TSO, or SC).

[^annot]: For example `__attribute__((annotate("lart.weakmem.tso")))` should be
added to function header for TSO function.

The transformation of SC functions is the following: there is a memory barrier
at the beginning of the function and after any call to function which is not
known to be SC. No load or store transformation is necessary. For TSO functions,
any load and store must be instrumented. This is done by replacing `load` and
`store` instructions with calls to `__lart_weakmem_load_tso` and
`__lart_weakmem_store_tso` --- these functions perform actual load or store
using store buffer. Furthermore memory can be manipulated by the means of atomic
instructions, that is `atomicrmw` (atomic read-modify-write) and `cmpxchg`
(compare-and-swap), these are implemented by first flushing store buffer, and
then executing the instruction without any modification --- this ensures
sequential consistency required by these instructions \TODO{ne-SC varianty}.
Finally memory barriers done by `fence` instruction are replaced by flushing
store buffer and \llvm memory manipulating intrinsics[^llvmmmi] are replaced by
functions which implement their functionality using store buffers.

[^llvmmmi]: These are `llvm.memcpy`, `llvm.memmove`, and `llvm.memset`.

## Nondeterministic Flushing

## Integration with $\tau+$ Reduction

As described in \autoref{sec:divine:tau} one of important reduction techniques
in \divine is $\tau+$ reduction which allows execution of multiple consecutive
instructions in one atomic block if there is no more then one action observable
by other threads in this block. For example, a `load` instruction is observable
if and only if it loads from memory block to which some other thread holds
a pointer.

This in particular means that any load from or store into store buffer will be
considered visible action because the store buffer has to be visible both from
the thread executing the load or store and from the thread which flushes store
buffer to memory.

To partially mitigate this issue it was proposed in \cite{SRB15} to bypass store
buffer when storing to addresses which are thread local from the point of
\divine's $\tau+$ reduction. To do this `__divine_is_private` intrinsic function
is used in `__lart_weakmem_store_tso`, and if the address to which store is
performed is indeed private, the store is executed directly, bypassing store
buffer.

This reduction is indeed correct for TSO stores. It is easy to see that the
reduction is correct if a memory location is always private, or always public
for the entire run of the program --- the first case means it is never accessed
from more then one thread and therefore no store buffer is needed, the second
case means the store buffer will be always uses. If the memory location (say
`x`) becomes public during the run of the program it is again correct (the
publication can happen only by writing an address of memory location from which
`x` can be reached following pointers into some already public location):

*   if `x` is first written and then published then, were the store
    buffers used, the value of `x` would need to be flushed from store buffer
    before `x` could be reached from other thread (because the stores cannot be
    reordered), and therefore the observable values are the same in with and
    without the reduction;

*   if `x` is first made private and then written, then the "making private"
    must happen by changing some pointer in public location, an action which
    will be delayed by the store buffer. However, this action must be flushed
    before the store to `x` in which it is considered private --- otherwise `x`
    would not be private, and therefore also before any other modifications to
    `x` which precede making `x` private;

*   the remaining possibilities (`x` written after publication, and `x` written
    before making it private) are not changed by the reduction.

Furthermore, considering that all store buffers are reachable from all threads,
and therefore any memory location which has entry in store buffer is considered
public, we can extend this reduction proposed in \cite{SRB15} to `load`
instructions as well. That is we can bypass looking for value in store buffer if
its memory location is considered private by \divine, because no memory location
which is private can have entry in store buffer. This means that loads of
private memory locations are no longer considered as visible actions by $\tau+$
which leads to further state space reduction for programs with weak memory
simulation.

As a final optimization, any load from or store into local variable which never
escapes scope of the function which allocated it need not be instrumented, that
is the `load` or `store` instruction need not be replaced with appropriate weak
memory simulating version. To detect these cases, we currently use
\llvm's `PointerMayBeCaptured` function to check if the memory location of the
local variable was ever written to some other memory location. A more precise
approximation could use pointer analysis to detect which memory locations can
only be accessed from one thread.

The evaluation of the original method proposed in \cite{SRB15}, as well as the
optimizations proposed here can be found in \autoref{sec:res:wm:tau}.

## Invalidated Variable Store Problem

\label{sec:extend:wm:invstore}

## Atomic Instructions in Weak Memory

The original proposal presented on MEMICS 2015 \cite{SRB15} did not include
support for atomic instructions with atomic ordering other than sequentially
consistent (for description about atomic instructions and atomic orderings in
\llvm see \autoref{sec:llvm:atomic}). In this section we present extension of
the original proposal which allows simulation of weaker versions of atomic
functions.

# Atomic Functions and Instructions
