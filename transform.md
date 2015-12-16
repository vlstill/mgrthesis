In this chapter we will propose \llvm transformations which aim at improving
model checking capabilities. All the proposed transformations were
implemented in \lart and will be release together with the next release of
\divine.

# Analyses and Transformation Building Blocks

Many tasks done in \llvm transformations are common and therefore should be
provided as separate and reusable analyses or transformation building blocks, so
that they can be ready to use when required and it is not necessary to implement
them ad-hoc every time. In some cases (for example dominator tree and domination
relation) analyses are provided in \llvm library, and \llvm also provides
useful utilities for instruction and basic block manipulation, such as basic
block splitting and instruction insertion. In other cases it is useful to add
to this set of primitives, for this reason \lart was extended to include several
such utilities.

## Fast Instruction Reachability \label{sec:trans:b:reach}

While \llvm has support to check whether value of one instruction might reach
other instruction (using `isPotentiallyReachable` function) this function is
slow if many-to-many reachability is to be calculated (this function's time
complexity is linear with respect to the number of basic blocks in control flow
graph of the function).  For this reason we introduce analysis which
pre-calculates reachability relation between all instructions and allows fast
querying, this analysis can be found in `lart/analysis/bbreach.h`.

To calculate instruction reachability fast and store it compactly, we store
transitive closure of basic block reachability instead, transitive closure of
instruction reachability can be easily retrieved from this information.
Instruction $i$ other than `invoke` reaches instruction $j$ in at least one step
if and only if the basic block $b(i)$ of instruction $i$ reaches in at least one
step basic block $b(j)$ of instruction $j$, or $b(i) = b(j)$ and $i$ is earlier
in $b(i)$ than $j$. For `invoke` instruction the situation is more complicated
as it is the only terminator instruction which returns value, and its value is
available only in its normal destination block and not in its unwind destination
block (the landing block which is used when the function called by the `invoke`
throws an exception). For this reason value of `invoke` instruction $i$ reaches
instruction $j$ if and only if $b(j)$ is reachable (in any number of steps,
including zero) from normal destination basic block of $i$.

Basic block reachability is calculated in two phases, first basic block graph
of the function is split into strongly connected components using Tarjan's
algorithm with results into directed acyclic graph of strongly connected
components, then this SCC collapse is recursively traversed and transitive
closure of SCC reachability is calculated \TODO{algorithm?}.

The theoretical time complexity of this algorithm is linear in the size of the
control flow graph of the function (which is in the worst case
$\mathcal{O}(n^2)$ where $n$ is number of basic blocks). In practice associative
maps are used in several parts of the algorithm resulting in worst case
time complexity in $\mathcal{O}(n^2 \cdot \log n)$ for transitive closure
calculation and $\mathcal{O}(\log n)$ for retrieval of the information whether
one block reaches another. However, since in practice control flow graphs 
are sparse,[^sparsecfg] the expected time complexity is $\mathcal{O}(n \log n)$
for transitive closure.

[^sparsecfg]: The argumentation is that all terminator instructions other that
`switch` have at most two successors and `switch` is rare, for this reason the
average number of edges in control flow graph with $n$ vertices is expected to
be less then $2n$.


## Exception Visibility \label{sec:trans:b:vex}

Often \llvm is transformed in a way which requires that certain cleanup action
is performed right before a function exits, one such example would be unlocking
atomic section, used in \autoref{sec:trans:atomic}. Implementing this for
languages without non-local control flow transfer other then with `call` and
`ret` instructions, for example standard C, would be fairly straight-forward ---
it is sufficient to run the cleanup just before the function returns. However,
while pure standard-compliant C has no non-local control transfer, in POSIX
there are `setjmp` and `longjmp` functions which allow non-local jumps and, even
more importantly, C++ has exceptions already in its standard. Since `longjmp`
and `setjmp` are not supported in \divine we will assume they will not be used
in the transformed program. On the other hand, exceptions are supported by
\divine and therefore should be taken into account.

In the presence of exceptions (but without `longjmp`) function can be exited in
the following ways:

*   by `ret` instruction;
*   by `resume` instruction which resumes propagation of exception which was
    earlier intercepted by `landingpad`;
*   when exception causes unwinding, but the active instruction through which
    the exception is propagating is `call` and not `invoke`, or it is `invoke`
    but the associated `landingpad` does not catch exception of given type ---
    in this case the frame of the function is unwound and the exception is not
    intercepted.

The latest case happens often in C++ functions which do not require any
destructors to be run at function, in those cases Clang usually generates `call`
instead of `invoke` even if the callee can throw an exception as it is not
necessary to intercept the exception in the caller. Also, if the function
contains `try` block Clang will generate `invoke` but since there is not need to
run destructors the corresponding `landingpad` will not intercept exceptions
which are not catched by `catch` block.  The problem with the latest case is
that the function exit is implicit, at any `call` instruction which can throw or
at `invoke` with `landingpad` without `cleanup` flag.

In order to make it possible to add code at the end of function it is therefore
necessary to eliminate this implicit way of exiting function without
intercepting the exception and the transformation must be performed in such a
way that it does not interfere with exception handling which was already present
in the transformed function.

Therefore we need to transform any call in such a way that if the called
function can throw an exception it is always called by `invoke`, and all the
`langingpad` instruction have `cleanup` flag. Furthermore, this transformation
must not change observable behaviour of the program --- if the exception would
fall through without being intercepted in the original program, it needs to be
intercepted and immediately resumed, and if the exception was intercepted by the
original program, its processing must be left unchanged (while the fact that the
exception is intercepted by `langingpad` and immediately resumed makes the run
different from the run in the original program, this change is not
distinguishable by any safety or stuttering-free \ltl property, and therefore
the transformed program can be considered equivalent to the original).

After this transformation every exception is visible in every function it can
propagate through. Now if we need to add cleanup code to the function it is
sufficient to add it before every `ret` and `resume` instruction, as there is no
other way the function can be exited.

### Implementation

The idea outlined above is implemented in `lart/support/cleanup.h` by the
function `makeExceptionsVisible`. Any `call` instruction for which we cannot
show that the callee cannot throw an exception is transformed into `invoke`
instruction, which allows as to branch out into a landing block if an exception
is thrown by the callee. The `landingpad` in the landing block need to be set up
in a way in can caught any exception (this can be done using `cleanup` flag for
`landingpad`). The instrumentation can be done as follows:

*   for a call site, if it is a `call`:

    1.  given a `call` instruction to be converted, split its parent basic block
        into two just after this instruction (we will call these blocks *invoke
        block* and *invoke-ok block*),
    2.  add a new basic block for cleanup, this block will contain a `landingpad`
        instruction with `cleanup` flag and a `resume` instruction (we will call
        this block *invoke-unwind block*),
    3.  replace the `call` instruction with `invoke` with the same function and
        parameters, its normal destination is set to invoke-ok block and its
        unwind destionation is set to invoke-unwind block,

*   otherwise, if it is an `invoke` and its unwind block does not contain
    `cleanup` flag in `landingpad`:
    1.  create new basic block containing just resume instruction (*resume
        block*)
    2.  add `cleanup` flag into `landingpad` of the unwind block of the `invoke`
        and branch into *resume block* if landing block is triggered due to
        `cleanup`,
*   otherwise leave the instruction unmodified.

Any calls using `call` instruction with known destination which is a function
marked with `nounwind` attribute will not be modified. Functions marked with
`nounwind` need to be checked for exceptions as \llvm states that these
functions should never throw an exception and therefore we assume that throwing
and exception from such a function will be reported as an error by the verifier.

\begFigure[tp]
```{.cpp}
void foo() { throw 0; }
void bar() { foo(); }
int main() {
    try { bar(); }
    catch ( int & ) { }
}
```

An example of simple C++ program which demonstrates use of exceptions, the
exception is thrown by `foo`, goes through `bar` and is catched in `main`.

```{.llvm}
define void @_Z3barv() #0 {
entry:
  call void @_Z3foov()
  unreachable
}
```

\llvm IR for function `bar` of the previous example (the names of functions are
mangled by C++ compiler). It can be seen that while `foo` can throw an exception
and this exception can propagate through `bar`, `bar` does not intercept this
exception in any way.

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

A transformed version of `bar` function in which the exception is intercepted
and therefore visible in this function, but it is immediately resumed. A cleanup
code would be inserted just before line 8. The original basic block `entry` was
split into `entry` and `fin` and the `call` instruction was replaced with
`invoke` which transfers control to the `lpad` label if any exception is thrown
by `foo`.  The function header is now extended with personality function, this
personality function calculates the value returned by `landingpad` for given
exception.

\caption{An example of transformation of a \llvm to make exceptions visible.}
\label{fig:transform:b:vex:example}
\endFigure

After the call instrumentation the following holds: every time the function is
entered by stack unwinding due to active exception, the control is transfered to
a landing block and, if before this transformation the exception would not be
intercepted by `landingpad` in this function, after the transformation 
the same exception would be rethrown by `resume`.

Furthermore, if the transformation adds `landingpad` into a function which did
not contain `landingpad` before, it is necessary to set personality function for
this function. For this reason, personality function which is used by the
program is a parameter of the transformation.

An example of the transformation can be seen in
\autoref{fig:transform:b:vex:example}.

\bigskip
Furthermore, to simplify transformations which add cleanups at function exits, a
function `atExits` is available in the same header file.


## Local Variable Cleanup \label{sec:trans:b:lvc}

When enriching \llvm bitcode in a way which modifies local variables it is
often necessary to perform cleaning operation at the end of the scope of these
variables. One of these cases is mentioned in \autoref{sec:extend:wm:invstore},
another can arise from compiled-in abstractions proposed in \cite{RockaiPhD}.
These variable cleanups are essentially akin to C++ destructors in a sense that
they get executed at the end of scope of the variable, no matter how this
happens, with only exception of thread termination.

The local variable cleanup builds on top of function cleanups described in
\autoref{sec:trans:b:vex}. Unlike the previous case it is not necessary to
transform all calls which can throw an exception, it is sufficient to transform
calls which can happen after some local variable declaration (that is value of
`alloca` instruction can reach the `call` or `invoke` instruction). After this
transformation a cleanup code is added before every exit from the function.
However, in order for the cleanup code to work, it needs to be able to access all local
variables which can be defined before the associated function exit, that is results of all
`alloca` instructions from which this exit can be reached. This might
not be always true, for example if local variable is allocated in only one
branch:[^allocabranch]

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

[^allocabranch]: While Clang usually moves all `alloca` instructions into the
first block of the function, the example is still a valid \llvm bitcode, and
therefore should be handled properly.

In this example, `%y` is defined in `if.then` basic block, but it needs to be
cleared just before the `return` instruction at the end of `if.end` basic block,
and the definition of `%y` does not dominate the cleaning point. The cleanup
cannot be, in general, inserted after the last use of given local variable as
the variable's address can escape scope of the function and even the thread in
which it was created and therefore it is not decidable when its scope ends.
Nevertheless it is safe to insert cleanup just before the function exits as the
variable will cease to exists when the function exits, that is immediately after
the cleanup.

To make all local variables which can reach exit point of a function accessible
at this exit point we will first insert $\varphi$-nodes in such a way that any
`alloca` is represented in any block which it can reach --- either by its value
if the control did pass the `alloca` instruction (the local variable is defined
at this point), or by `null` constant if the control did not pass it. For our
example the result of the modification would be the following (just last basic
block is modified):

```{.llvm}
if.end:  ; preds = %if.then, %entry
  %y.phi = phi i32* [ null, %entry ], [ %y, %if.then ];
  ; cleanup will be inserted here, it will access %y.phi
  ret i32 0
```

In this example, `%y.phi` represents `%y` at the cleanup point --- it can be
either equal to `%y` if control passed through definition of `%y`, or `null`
otherwise.

While this transformation changes the set of runs of the program all the runs in
the original program have equivalent (from the point of safety and stuttering-free
\ltl properties) runs transformed programs --- the only difference is that there
can be some intermediate states in the transformed program's runs.

### Implementation

To calculate which `alloca` instructions can reach given function exit point a
version of standard reaching definitions analysis is used. Using this analysis
we compute which `alloca` instruction values reach end of each basic block of
the function, and for every such value which does not dominate the end of the
basic block a $\varphi$-node is inserted. For each basic block the algorithm
also keeps track of which value represents the particular `alloca` instruction
in this basic block (it can be either the `alloca` itself, or a `phi`
instruction) The transformation is done by function `addAllocaCleanups` which is
defined in `lart/support/cleanup.h`.

# New Interface for Atomic Sections \label{sec:trans:atomic}

The interface for declaring atomic sections in verified code (described in
\autoref{sec:divine:llvm:mask}) is hard to use, the main reason being that while
the mask set by `__divine_interrupt_mask` is inherited by called functions,
these have no way of knowing if they are inside atomic section, and more
importantly, they can end the atomic section by calling
`__divine_interrupt_unmask`. This is especially bad for composition of atomic
functions, see \autoref{fig:ex:atomic:bad} for example. For this reason, the
only compositionally safe way to use \divine's original atomic sections is to
never call `__divine_interrupt_unmask` and let \divine end the atomic section
when the caller of `__divine_interrupt_mask` ends.

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

\begCaption
Example of composition problem with original \divine atomic sections
--- the atomic section begins on line 10 and is inherited to
\texttt{doSomething}, but the atomic section ends by the unmask call at line 4
and the rest of \texttt{doSomething} and \texttt{foo} are not executed
atomically. The atomic section is then re-entered when \texttt{doSomething}
returns.
\endCaption
\label{fig:ex:atomic:bad}
\endFigure

To alleviate aforementioned problems we reimplemented atomic sections in
\divine. The new design uses only one *mask flag* to indicate that current
thread of execution is in atomic section, this flag is internal to the
interpreter and need not be saved in the state --- indeed it would be always set
to false in the state emitted by the generator because the state can never be
emitted in the middle of atomic section. Furthermore, we modified
`__divine_interrupt_mask` to return `int` value corresponding to value of
mask flag before it was set by this call to `__divine_interrupt_mask`.

To make using new atomic sections easier we provide higher level interface for
atomic sections by the means of a C++ library and annotations. The C++ interface
is intended to be used mostly by developers of language support for \divine,
while the annotations are designed to be usable by users of \divine.

The C++ interface is RAII-based[^raii], it works similar to C++11 `unique_lock`
with recursive mutexes --- an atomic section begins by construction of an object
of type `divine::InterruptMask` and is left either by call of `release` method
on this object, or by the destructor of the `InterruptMask` object. If atomic
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
}
```

\caption{An example of use of C++ interface for the new atomic sections in
\divine.}
\label{fig:ex:atomic:cpp}
\endFigure

[^raii]: Resource Acquisition Is Initialization, a common pattern in C++ in
which a resource is allocated inside object and safely deallocated when that
object exits scope, usually at the end of function. \TODO{odkaz, citace?}

The annotation interface is based on \lart transformation pass and annotations
which can be used to mark entire functions atomic. This way, the function can
be marked atomic by adding `__lart_atomic_function` to their header, see
\autoref{fig:ex:atomic:lart} for an example. While this is safer way to use
atomic sections than explicitly using `__divine_interrupt_mask`, it is still
necessary that the atomic function always terminates (e.g. does not contain
infinite cycle).

\begFigure[tp]
```{.cpp}
#include <lart/atomic.h>

int atomicInc( int *ptr, int val ) __lart_atomic_function {
    int prev = *ptr;
    *ptr += val;
    return prev;
}
```
\begCaption
An example of usage of annotation interface for atomic functions in \divine ---
the function `atomicInc` is aways executed atomically and is safe to be executed
inside another function annotated as atomic.
\endCaption
\label{fig:ex:atomic:lart}
\endFigure

### Implementation of Annotation Interface

Atomic sections using annotations are implemented in two phases --- first the
function is annotated with `__lart_atomic_function` which is in fact macro
which expands to GCC/Clang attributes `annotate("lart.interrupt.masked")` and
`noinline`; the first one is used so that the annotated function can be
identified in \llvm, the second makes sure the function will not be inlined (if
it would be inlined it would not be possible to identify it in the bitcode).

Second phase is \lart pass which actually adds atomic sections into annotated
functions, this pass is implemented by class `Mask` in
`lart/reduction/interrupt.cpp`.  For each function which is annotated with
`lart.interrupt.masked` it adds call to `__divine_interrupt_mask` at the
beginning of the function, and call to `__divine_interrupt_unmask` before any
exit point of the function (exit point is either `ret` or `resume` instruction,
that is either normal exit, or exception propagation). The call to
`__divine_interrupt_unmask` is conditional, it is only called if
`__divine_interrupt_mask` returned 0 (that is, atomic section begun by this
call).

However, since the transformed program can use exceptions, and it is desirable
that mask is exited every time the annotated function is left (not just during
normal execution), it is necessary to first make all exceptions visible, and
then perform the aforementioned transformation. To make exceptions visible we
use the transformation outlined in \autoref{sec:trans:b:vex}, which
makes sure any exception which would otherwise propagate through the transformed
function without stopping will be intercepted by landing block and immediately
resumed. After this transformation it is sufficient to end atomic section before
any exit from the function, since no exception can fall through without being
intercepted.

This \lart pass was integrated into build of program using `divine compile`
command and therefore it is not necessary to run \lart manually to make atomic
sections work.



# Weak Memory Models

In modern CPUs, a write to memory location need not be immediately visible in
other threads, for example due to caches or out-of-order execution. However most
of the verification tools, including \divine, do not directly support
verification with these relaxed memory models, instead they assume *sequential
consistency*, that is immediate visibility of any write to memory.

In \cite{SRB15} it was proposed to add weak memory model simulation using
\llvm-to-\llvm transformation. In this section we will extended version of this
transformation which allows verification of full range of properties supported
by \divine (the original version was not usable for verification of memory
safety). Furthermore this extended version supports wider range of memory models
and the memory model to be used can be specified by user of the transformation.
We also show how to decrease state space size of compared to the original
version and evaluate the final transformation on several models.

## Theoretical Memory Models

Since the memory models implemented in hardware differ with CPU vendors, or even
particular models of CPUs, it would not be practical and feasible to verify
programs with regard to a particular implementation of real-world memory model.
For this reason several theoretical memory models were proposed, namely *Total
Store Order* (TSO) \cite{SPARC94}, *Partial Store Order* (PSO) \cite{SPARC94}.
These memory models are usually described as constraints to allowed reordering
of instructions which manipulate with memory.  In those theoretical models, an
update may be deferred for an infinite amount of time. Therefore, even a finite
state program that is instrumented with a possibly infinite delay of an update
may exhibit an infinite state space. It has been proven that for such an
instrumented program, the problem of reachability of a particular system
configuration is decidable, but the problem of repeated reachability of a given
system configuration is not \cite{Atig:2010:VPW:1706299.1706303}.

In Total Store Order memory model (which was used as basis for \cite{SRB15}),
any write can be delayed infinitely but the order in which writes done by one
thread become visible in other threads must match the order of writes in the
thread which executed them. This memory model can be simulated by store buffer
--- any write is first done into a thread-private buffer so it is invisible for
other threads, this buffer keeps writes in FIFO order. The buffer can later be
nondeterministically flushed, that is oldest entry from the buffer can be
written to memory. Furthermore, any reads have to first look into store buffer
of their thread for newer value of memory location, only if there is none they
can look into memory. See \autoref{fig:trans:wm:sb} for an example of store
buffer working.

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

\begin{center}
\begin{tikzpicture}[ ->, >=stealth', shorten >=1pt, auto, node distance=3cm
                   , semithick
                   , scale=0.7
                   ]
  \draw [-] (-10,0) -- (-6,0) -- (-6,-2) -- (-10,-2) -- (-10,0);
  \draw [-] (-10,-1) -- (-6,-1);
  \draw [-] (-8,0) -- (-8,-2);
  \node () [anchor=west] at (-10,0.5) {main memory};
  \node () [anchor=west] at (-10,-0.5)  {\texttt{0x04}};
  \node () [anchor=west] at (-8,-0.5)  {\texttt{0x08}};
  \node () [anchor=west] at (-10,-1.5)  {\texttt{x = 0}};
  \node () [anchor=west] at (-8,-1.5)  {\texttt{y = 0}};

  \node () [anchor=west] at (-10,-3.5) {store buffer for thread 0};
  \node () [anchor=west] at (0,-3.5) {store buffer for thread 1};

  \draw [-] (-10,-4) -- (-4, -4) -- (-4,-5) -- (-10,-5) -- (-10,-4);
  \draw [-] (0,-4) -- (6, -4) -- (6,-5) -- (0,-5) -- (0,-4);
  \draw [-] (-8,-4) -- (-8,-5);
  \draw [-] (-6,-4) -- (-6,-5);
  \draw [-] (2,-4) -- (2,-5);
  \draw [-] (4,-4) -- (4,-5);

  \node () [anchor=west] at (-10,-4.5)  {\texttt{0x08}};
  \node () [anchor=west] at (-8,-4.5)  {\texttt{1}};
  \node () [anchor=west] at (-6,-4.5)  {\texttt{32}};

  \node () [anchor=west] at (0,-4.5)  {\texttt{0x04}};
  \node () [anchor=west] at (2,-4.5)  {\texttt{1}};
  \node () [anchor=west] at (4,-4.5)  {\texttt{32}};

  \node () [] at (-4, 0.5) {thread 0};
  \draw [->] (-4,0) -- (-4,-2);
  \node () [anchor=west] at (-3.5, -0.5) {\texttt{store y 1;}};
  \node () [anchor=west] at (-3.5, -1.5) {\texttt{load x;}};

  \node () [] at (2, 0.5) {thread 1};
  \draw [->] (2,0) -- (2,-2);
  \node () [anchor=west] at (2.5, -0.5) {\texttt{store x 1;}};
  \node () [anchor=west] at (2.5, -1.5) {\texttt{load y;}};

  \draw [->, dashed] (-0.5,-0.5) to[in=0, out=0] (-4,-4.5);
  \draw [->, dashed] (-9,-2) to[in=0, out=-90, out looseness=0.7] (-1.3,-1.5);
  \draw [->, dashed] (5.5,-0.5) to[in=0, out=0] (6,-4.5);
  \draw [->, dashed] (-7,-2) to[in=0, out=-90, out looseness=0.5] (4.7,-1.5);

\end{tikzpicture}
\end{center}

\caption{In this example, each of the threads first writes into a global variable
  and later reads the variable written by the other thread. Under sequential
  consistency, the possible outcomes would be $x = 1, y = 1$; $x = 1, y = 0$; and $x
  = 0, y = 1$, since at least one write must proceed before the first read
  proceeds. However, under TSO $x = 0, y = 0$ is also possible: this corresponds
  to the reordering of the load on line 3 before the independent store on line
  2, and can be simulated by performing the store on line 2 into a store
  buffer. The diagram shows (shortened) execution of the listed code. Dashed
  lines represent where given value is read from/stored to.}
\label{fig:trans:wm:sb}
\endFigure

The transformation presented in \cite{SRB15} implements under-approximation of
TSO using bounded store buffer. In this case the buffer size is limited and if
an entry is to be written into full store buffer, the oldest entry from the
buffer is flushed into memory. With this limited store buffer the
transformation can be reasonably implemented, and the resulting state space is
finite if the state space of the original program was finite, therefore this
transformation is suitable for explicit state model checking.

The main limitation of the version proposed in \cite{SRB15} is that it does not
fully support \llvm atomic instructions with other that sequential consistency
ordering and it supports only TSO ordering. On the other hand the extended
version proposed in this work does support all atomic ordering supported by
\llvm and it does not implement TSO, instead it simulates memory model of \llvm
and allows specification of which guarantees should be added to this memory
model. In this way the transformation can be parametrized to approximate larger
range of memory models. Please refer to \autoref{sec:llvm:atomic} for details
about \llvm memory model.

## Representation of \llvm Memory Model Using Store Buffers



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

# Code Optimization in Formal Verification

When real-world code is being verified 

# Atomic Blocks

# Nondeterminism Tracking
