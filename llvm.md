\begin{quote}
``\llvm is a Static Single Assignment (SSA) based representation that provides
type safety, low-level operations, flexibility, and the capability of
representing ‘all’ high-level languages cleanly. It is the common code
representation used throughout all phases of the \llvm compilation strategy.''

\hfill --- \llvm Language Reference Manual \cite{llvm:langref}
\end{quote}

\llvm\cite{llvm:web} was originally introduced in \cite{Lattner02} as an
infrastructure for optimization. Today \llvm is presented as compiler
infrastructure, it provides programming language and platform independent tools
for optimization and support for code generation for many platforms. It also
defines intermediate representation --- \llvm IR --- a
single-static-assignment-based low-level language, and a library for
manipulation with this intermediate representation. The name \llvm itself is
often used both for the complete infrastructure as well as for \llvm IR.

\llvm IR can be represented in three ways --- a human readable assembly (`.ll`
file), a compact serialized bitcode (`.bc` file), or as in-memory C++ objects
which can be manipulated by \llvm libraries and read from and serialized to both
other forms.


# \llvm IR basics

\llvm IR human-readable representation is similar to assembly languages,
but it is typed and more verbose. In this section, we will shortly describe
relevant part of this human-readable \llvm representation as well as a basic
structure of \llvm IR. Through whole work, we will use `typewriter-style font` to
denote a fragment of code in some programming language, notably in \llvm IR or
C++. We will also use the same font for instruction and function names.

\llvm IR has two basic kinds of identifiers: global identifiers, used for global
variables and functions (their name begins with `@`), and local identifiers,
such as register names and types (their name begins with `%`). The identifiers
can be either named or unnamed, unnamed identifiers are represented using
unsigned value.

\llvm programs consist of *modules* --- a module represents compilation unit of
the input program or a result of the \llvm linker. Modules contain functions, global
variables, symbol table entries, and metadata.

A function contains, apart from its header (which defines name, number and type
of parameters and function attributes), a body which consists of *basic blocks*.
Basic block is a continuous sequence of instruction with no branching inside,
terminated by so called *terminator* instruction --- an instruction which
transfers control flow to another basic block (branching instruction) or exits
the function (in the case of `ret` and `resume`). Values in a function are held
in *registers* which are in SSA form (they are assigned only once, at their
declaration) and there is unlimited number of them.

Most \llvm instructions operate on registers, memory manipulation is possible
only using four instructions: `load`, `store`, `atomicrmw`, and `cmpxchg`. The
meaning of `load` and `store` instructions is simple enough, the first one
loads value of given type from memory location given by its pointer argument,
the second one stores value to memory location given by its pointer argument.
`atomicrmw` and `cmpxchg` are atomic instructions, they perform atomic
read-modify-write and compare-and-swap, more about these instructions can be
found in \autoref{sec:llvm:atomic}.

Since \llvm registers are in SSA form and their address cannot be taken they are
not suitable for representation of local variables. To represent these variables
\llvm uses `alloca` instruction --- this instruction takes a size and returns
a pointer to a memory location of given size which will be automatically freed on
function exit. Usually `alloca` is implemented using stack when \llvm is
compiled to runnable binary.

Finally, again as a consequence of SSA form, \llvm IR includes $\varphi$-nodes
represented by `phi` instruction --- these are special instructions which merge
values from different basic blocks. `phi` instructions must be at the beginning
of basic block.

# \llvm Compilation Process

\llvm itself is not a complete compiler --- it lacks support for translation
from a higher-level programming language into \llvm IR. This translation is a role
for *frontend* such as Clang, which is C/C++/Objective-C compiler released
together with \llvm, or DragonEgg which integrates \llvm with GCC parsers and
allows processing of Ada, Fortran, and other.

After the frontend generates \llvm IR, \llvm can be used to run optimizations
on this IR. These optimizations are organized into *passes*, each of the passes
performs single optimization or code analysis task, such as constant
propagation, or inlining. \llvm passes are usually run directly by the
compiler, but they can be also executed on serialized \llvm IR using `opt`
binary which comes with \llvm. Optimization passes are written in C++ using
\llvm libraries.

Finally, the optimized IR has to be translated into a platform-specific
assembler. This is done by a code generator, which is part of \llvm. \llvm comes
with code generator for many platforms, including X86, X86_64, ARM, and
PowerPC. \llvm also comes with infrastructure for writing code generators for
other platforms.


# Exception Handling \label{sec:llvm:eh}

Exception handling in \llvm \cite{llvm:except} is based on Itanium ABI zero-cost
exception handling. This means that exception handling does not incur any
overhead such as checkpoint creation when entering `try` blocks. Instead, all the
work is done at the time exception is thrown, that is exception handling is
zero-cost until the exception is actually used.

The concrete implementation of exception handling is platform dependent and as
such cannot be completely described in \llvm --- it usually consists of
*exception handling tables* compiled in the binary, an *unwinder* library
provided by the operating system, and a language-dependent way of throwing and
catching exceptions. The exception handling tables and most of the unwinder
interface is not exposed into \llvm IR as it is filled in by the backend for
the particular platform. Nevertheless, there must be information in \llvm IR
which allows generation of this backend-specific data. For this reason \llvm
has three exception-handling-related instructions: `invoke`, `landingpad`, and
`resume`.

`landingpad`

~   is used at the beginning of exception handling block (it can be preceded
    only by `phi` instruction). Its return value is platform and language
    specific description of the exception which is being propagated. For C++
    this is a tuple containing a pointer to the exception and a *selector* ---
    an integral value corresponding to the type of the exception which is used
    in the exception catching code. The basic block which contains `landingpad`
    instruction will be referred to as *landing block*.[^lblp]

    The `landingpad` instruction specifies which exception it can catch --- it
    can have multiple *clauses* and each clause is either `catch` clause,
    meaning the `landingpad` should be used for exceptions of type this clause
    specifies, or `filter` clause --- in this case `landingpad` should be
    entered if the type of exception does not match any of the types in the
    clause. The type of the exception is determined dynamically, that is the
    clauses contain runtime type information objects. Furthermore, the
    `landingpad` can be denoted as `cleanup`, meaning it should be entered
    even if no matching clause is found.

    As the matching clause is determined at the runtime the code in landing
    block has to be able to determine which of the possible clauses (or
    `cleanup` flag) fired. For this reason the return value of `landingpad`
    instruction is determined using a *personality function* --- a
    language-specific function which is called when throwing the exception or
    by the stack unwinder. For C++ and Clang, the personality function is
    `__gxx_personality_v0` and it returns pointer to the exception and integral
    selector which uniquely determines which catch block of the original C++
    code should fire.

`invoke`

~   instruction works similar to `call` instruction, it can be used to
    call function in such a way that if it throws an exception this exception
    will be handled by dedicated basic block. Unlike `call`, `invoke` is a
    terminator instruction --- it has to be last in the basic block. Apart from
    function to call and its parameters it also takes two basic block labels,
    one to be used when the function return normally and one to be used on
    exception propagation, the second one must be a label of a landing block.

`resume`

~   is used to resume propagation of exception which was earlier intercepted by
    `invoke`--`landingpad` combination, it takes same arguments as returned by
    the `landingpad`.

[^lblp]: In \llvm documentation this block is referred to as *landing pad*,
however, we will use the naming introduced in \cite{RBB14} to avoid confusion
between `landingpad` as an instruction and landing pad as a basic block which
contains this instruction.

It is important to note that \llvm does not have any instruction for throwing
of exceptions, this is left to the frontend to be done in language-dependent
way. In C++ throwing is done by a call to `__cxa_throw` which will initiate the
stack unwinding in cooperation with the unwinder library. Similarly, allocation
and catching of the exception are left to be provided by the frontend.

# Atomic Instructions

\label{sec:llvm:atomic}

\llvm has support for atomic instructions with well-defined behavior in
multi-threaded programs \cite{llvm:atomics}. \llvm's atomic instructions are
build so that they can provide the functionality required by C++11 atomic operation
library, as well as Java volatile. Apart from atomic versions of `load` and
`store` instructions \llvm supports three atomic instructions --- `atomicrmw`
(atomic read-modify-write) and `cmpxchg` (atomic compare-and-exchange, also
compare-and-swap) which are essentially atomic load immediately followed by
atomic store in such a way that no other memory action can happen between the
load and store, and `fence` instruction which allows synchronization which is
not part of any other operation.

The semantics of these atomic instructions is affected by their *atomic
ordering* --- the strength of atomicity they guarantee. Apart from *not atomic*
which is used to denote `load` and `store` instructions with no atomicity
guarantee, there are six atomic ordering: *unordered*, *monotonic*, *acquire*,
*release*, *acquire-release*, and *sequentially consistent* (given in order of
increasing strength). These atomic ordering are described by memory model of
\llvm{}.[^memmodel]

In order to describe aforementioned atomic orderings, we first need to define
*happens-before* partial order of operations of a concurrent program.
Happens-before is least partial order that is superset of single-thread
execution order, and when *a* *synchronizes-with* *b* it includes edge from *a*
to *b*. Synchronizes-with edges are introduced by platform-specific ways,[^sync]
and by atomic instructions.

[^memmodel]: Chapter *Memory Model for Concurrent Operation* of
\cite{llvm:langref}.

[^sync]: For example by thread creation or joining, mutex locking and unlocking.

Unordered

~   can be used only for `load` and `store` instructions and does not guarantee
    any synchronization but it guarantees that the load or store itself will be
    atomic --- it cannot be splited into two or more instructions or
    otherwise changed in a way that load would result in value different from
    all written previously to the same memory location. This memory ordering is
    used for non-atomic loads and stores in Java and other programming languages
    in which data races are not allowed to have undefined behaviour.[^cpprace]

Monotonic

~   corresponds to `memory_order_relaxed` in C++11 standard. In addition to
    guarantees given by unordered, it guarantees that a total ordering consistent
    with happens-before partial order exists between all monotonic operations
    affecting same memory location.

Acquire

~   corresponds to `memory_order_acquire` in C++11. In addition to the
    guarantees of monotonic ordering, a read operation flagged as acquire
    creates synchronizes-with edge with a write operation which created the
    value if this write operation was flagged as release. Acquire is memory
    ordering strong enough to implement lock acquire.

Release

~   corresponds to `memory_order_release` in C++11. In addition to the
    guarantees of monotonic ordering, it can create synchronizes-with edge with
    corresponding acquire operation. Release is memory ordering strong enough
    to implement lock release.

Acquire-Release

~   corresponds to `memory_order_acq_rel` in C++11, acts as both acquire and
    release on given memory location.

Sequentially Consistent

~   corresponds to `memory_order_seq_cst` which is default for `atomic`
    operations in C++. In addition to guarantees given by acquire-release it
    guarantees that there is a global total order of all sequentially-consistent
    operations on all memory locations which is consistent with happens-before
    partial order and with modification order of all the affected memory
    locations.

[^cpprace]: This is in contrast with standard of C++11/C11 which specify that
concurrent, unsynchronized access of same non-atomic memory location results in
undefined behaviour, for example `load` can return value which was never written
to given memory location.

An example of synchronizes-with edges and happens-before partial order can be
seen in \autoref{fig:llvm:at:happensbefore}.

\begin{figure}[tp]
\begin{tikzpicture}[ >=stealth', shorten >=1pt, auto, node distance=3cm
                   , semithick, scale=0.65 ]

  \draw [dashed] (0,0) -- (0,-7);
  \draw [dashed] (8,0) -- (8,-7);

  \node () [anchor=south] at (0,0) {thread \texttt{t1}};
  \node (s1a) [anchor=west] at (0,-1) {\texttt{store 1, @a release}};
  \node (s1b) [anchor=west] at (0,-2) {\texttt{store 1, @b release}};
  \draw [->, line width = 2pt] (0,-1) -- (0,-2);

  \node () [anchor=south] at (8,0) {thread \texttt{t2}};
  \node (l2b) [anchor=west] at (8,-3) {\texttt{\%1 = load @b acquire}};
  \node (s2c) [anchor=west] at (8,-4) {\texttt{store \%1, @c release}};
  \node (s2d) [anchor=west] at (8,-5) {\texttt{store 1, @d monotinic}};
  \draw [->, line width = 2pt] (8,-3) -- (8,-4);
  \draw [->, line width = 2pt] (8,-4) -- (8,-5);

  \path [color=red, line width=2pt,->] (0,-2) edge[out=270, in=180] (8,-3);

  \node (l1d) [anchor=west] at (0,-6) {\texttt{\%1 = load @d acquire}};
  \draw [->, line width = 2pt] (0,-2) -- (0,-6);

\end{tikzpicture}

\caption{Happens-before partial order and synchronizes-with edges of simple
program with two threads (\texttt{t1} and \texttt{t2}) and global variables
\texttt{a}, \texttt{b}, \texttt{c}, and \texttt{d} for an execution when first
thread \texttt{t1} executes two instructions, then \texttt{t2} executes and
finally \texttt{t1} continues execution. The black arrows denote happens-before
ordering given from the single-thread execution while red arrow denote
synchronizes-with edge (which is part of happens-before partial order). Please
note that there is no synchronizes-with edge between \texttt{store} and
\texttt{load} of \texttt{d} (even in case that the \texttt{load} returns value
written by the \texttt{store}) as the \texttt{store} is not release or stronger.}
\label{fig:llvm:at:happensbefore}
\end{figure}

\bigskip
Unlike aforementioned atomic instructions the `fence` instruction is not bound
to a specific memory location. Instead, it establishes memory synchronization
between non-atomic and monotonic atomic accesses. The synchronization is
established if there exists a pair of `fence` instructions *R* and *A* where *R*
is `release` fence and *A* is `acquire` fence, and an atomic object *M* which is
modified by instruction *S* (with at least `monotonic` ordering) after *R* and
read by instruction *L* (with at least `monotonic` ordering) before *A*. In this
case, there is happens-before edge from *R* to *A*. Now if the read *L* of *M*
observes the value written by write *S* this implies that all (atomic or not)
writes which happen-before the fence *R* also happen-before the fence *A*. An
illustration how this can be used to implement spin-lock can be found in
\autoref{fig:llvm:fence}.

If the fence has sequentially consistent ordering it also participates in
global program order of all sequentially consistent operations. A fence is not
allowed to have monotonic, unordered, or no atomic ordering.

\begFigure[tp]

```{.cpp .numberLines}
int a;
std::atomic< bool > flag;

void foo() {
    a = 42;
    std::atomic_thread_fence( std::memory_order_release );
    flag.store( true, std::memory_order_relaxed );
}

void bar() {
    while ( !flag.load( std::memory_order_relaxed ) ) { }
    std::atomic_thread_fence( std::memory_order_acquire );
    std::cout << a << std::endl; // this will print 42
}
```

```{.llvm .numberLines}
define void @_Z3foov() {
entry:
  store i32 42, i32* @a, align 4
  fence release
  store atomic i8 1, i8* @flag monotonic, align 1
  ret void
}

define void @_Z3barv() {
entry:
  br label %while.cond

while.cond:
  %0 = load atomic i8, i8* @flag monotonic, align 1
  %tobool.i.i = icmp eq i8 %0, 0
  br i1 %tobool.i.i, label %while.cond, label %while.end

while.end:
  fence acquire
  %1 = load i32, i32* @a, align 4
  ; ...
```

\begCaption
An example of a use of `fence` instruction. The `release` fence (line 6 in C++,
4 in \llvm) synchronizes with the `acquire` fence (line 12 in C++, 19 in \llvm)
because there exists an atomic object `flag` and an operation which modifies it
with `monotonic` ordering (lines 7, 5) after the `release` fence, and reads it,
again with `monotonic` ordering (lines 11, 14), before the `acquire` fence.
\endCaption
\label{fig:llvm:fence}
\endFigure

\bigskip
Finally, all atomic instructions can optionally have `singlethreaded` flag
which means they do not synchronize with other threads, and only synchronize
with other atomic instructions within the thread. This is useful for
synchronization with signal handlers.
