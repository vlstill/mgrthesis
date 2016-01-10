\begin{quote}
``\llvm is a Static Single Assignment (SSA) based representation that provides
type safety, low-level operations, flexibility, and the capability of
representing ‘all’ high-level languages cleanly. It is the common code
representation used throughout all phases of the \llvm compilation strategy.''

\hfill --- \llvm Language Reference Manual \cite{llvm:langref}
\end{quote}

\llvm\cite{llvm:web} was originally introduced in \cite{Lattner02} as an
infrastructure for optimization. Today, \llvm is presented as compiler
infrastructure, it provides programming-language-and-platform-independent tools
for optimization and support for code generation for many platforms. It also
defines intermediate representation --- \llvm IR --- a
static-single-assignment-based low-level language, and a library which can be
used to manipulate this intermediate representation. The name \llvm itself
is often used both for the complete infrastructure as well as for \llvm IR.

\llvm IR can be represented in three ways: a human readable assembly (`.ll`
file), a compact serialized bitcode (`.bc` file), or as in-memory C++ objects
which can be manipulated by \llvm libraries and read from and serialized to both
the other forms.

# \llvm IR basics

\llvm IR human-readable representation is similar to assembly languages, but it
is typed and more verbose. In this section, we will shortly describe relevant
part of this human-readable \llvm representation as well as a basic structure of
\llvm IR. Through the whole work, we will use `typewriter-style font` to denote
a fragment of code in some programming language, most often in \llvm IR or C++.
We will also use the same font for instruction and function names.

\llvm IR has two basic kinds of identifiers: global identifiers, used for global
variables and functions (their names begin with `@`), and local identifiers,
such as register names, types and labels (their names begin with `%`). The
identifiers can be either named or unnamed, unnamed identifiers are represented
using unsigned numerical values.

### Modules and Functions

\llvm programs consist of *modules*. A module represents a compilation unit of
the input program or a result of the \llvm linker. Modules contain functions, global
variables, symbol table entries, and metadata.

A function contains a header (which defines a name, the number and type of
parameters and function attributes) and a body which consists of *basic blocks*.
Basic block is a continuous sequence of instructions with no branching inside,
terminated by a so-called *terminator* instruction, which is an instruction
which transfers control flow to another basic block (branching instruction) or
exits the function (in the case of `ret` and `resume`). Each basic block has a
*label* which serves as a name of the basic block. Only labels can be targets of
branch instructions. Values in a function are held in *registers* which are in
SSA form (they are assigned only once, at their declaration) and there is an
unlimited number of them.

Most \llvm instructions operate on registers, memory manipulation is possible
using only four instructions: `load`, `store`, `atomicrmw`, and `cmpxchg`. The
`load` instruction loads a value of a given type from a memory location given by
its pointer argument and the `store` instruction stores a value to a memory
location given by its pointer argument. `atomicrmw` and `cmpxchg` are atomic
instructions, they perform atomic read-modify-write and compare-and-swap. More
information about these instructions can be found in \autoref{sec:llvm:atomic}.

Since \llvm registers are in SSA form and their address cannot be taken, they
are not suitable for representation of local variables. To represent these
variables, \llvm uses `alloca` instruction. `alloca` instruction takes a size and
a type and returns a pointer to a memory location of given size, which will be
automatically freed on function exit. Usually `alloca` is implemented using
a stack when \llvm is compiled to runnable binary.

Finally, again as a consequence of SSA form, \llvm IR includes $\varphi$-nodes
represented by the `phi` instruction, a special instruction which merges values from
different basic blocks. `phi` instructions must be at the beginning of a basic
block.

### Types

\llvm is a typed language; there are primitive types, such as integral types
with different bit widths (for example `i32` is a 32 bit integer, `i1` is a
boolean value), floating point types (`float`, `double`), and pointer types
(denoted in the same way as in C, for example `i32*` is pointer to a 32 bit
integer). Apart from primitive types, \llvm has arrays (for example `[4 x i32]`
is an array of 4 integers), and structures (for example `{ i32, i8* }` is a
tuple of an integer and a pointer). Furthermore, \llvm has named types and
additional types, such as vector types, which are not necessary for the
understanding of this work.

There are no implicit casts in \llvm, instead, a variety of of casting
instructions is provided, namely `bitcast` for casting which preserves
representation, `inttoptr` and `ptrtoint` to cast integers to and from pointers
with same size, and `trunc`, `zext`, and `sext` for integer casts to smaller,
respectively larger data types.

### Metadata

\llvm modules can also contain *metadata*. Metadata are non-essential data which
include additional information, for example for the compiler, optimizer or code
generator. An important example of metadata are debugging informations.
Metadata can be bound to \llvm instructions and functions and their names are
prefixed with `!`.

# \llvm Compilation Process

\llvm itself is not a complete compiler as it lacks support for translation
from a higher-level programming language into \llvm IR. This translation is done
by a *frontend*, such as Clang, which is a C/C++/Objective-C compiler released
together with \llvm, or DragonEgg which integrates \llvm with GCC parsers and
allows processing of Ada, Fortran, and others.

After the frontend generates \llvm IR, \llvm can be used to run optimizations
on this IR. These optimizations are organized into *passes*; each of the passes
performs a single optimization or code analysis task, such as constant
propagation or inlining. \llvm passes are usually run directly by the
compiler, but they can be also executed on serialized \llvm IR using the `opt`
binary which comes with \llvm. Optimization passes are written in C++ using
\llvm libraries.

Finally, the optimized IR has to be translated into a platform-specific
assembler. This is done by a code generator, which is part of \llvm. \llvm comes
with code generators for many platforms, including `x86`, `x86_64`, ARM, and
PowerPC. \llvm also comes with infrastructure for writing code generators for
other platforms.

# Exception Handling

\label{sec:llvm:eh}

Exception handling in \llvm \cite{llvm:except} is based on Itanium ABI zero-cost
exception handling. This means that exception handling does not incur any
overhead (such as checkpoint creation) when entering `try` blocks. Instead, all the
work is done at the time exception is thrown, that is, exception handling is
zero-cost until the exception is actually used.

The concrete implementation of exception handling is platform dependent and as
such cannot be completely described in \llvm. It usually consists of
*exception handling tables* compiled into the binary, an *unwinder* library
provided by the operating system, and a language-dependent way of throwing and
catching exceptions. The exception handling tables and most of the unwinder
interface is not exposed into \llvm IR as it is filled in by the backend for
the particular platform. Nevertheless, there must be information in \llvm IR
which allows generation of this backend-specific data. For this reason, \llvm
has three exception-handling-related instructions: `invoke`, `landingpad`, and
`resume`.

`landingpad`

~   is used at the beginning of an exception handling block (it can be preceded
    only by `phi` instructions). Its return value is a
    platform-and-language-specific description of the exception which is being
    propagated. For C++, this is a tuple containing a pointer to the exception
    and a *selector* which is an integral value corresponding to the type of the
    exception that is used in the exception catching code. The basic block which
    contains the `landingpad` instruction will be referred to as *landing
    block*.[^lblp]

    The `landingpad` instruction specifies which exceptions it can catch. It can
    have multiple *clauses* and each clause is either a `catch` clause, meaning
    the `landingpad` should be used for exceptions of a type this clause
    specifies, or a `filter` clause, meaning the `landingpad` should be entered
    if the type of the exception does not match any of the types in the clause.
    The type of the exception is determined dynamically, and therefore clauses
    contain runtime type information objects. Furthermore, a `landingpad` can be
    denoted as `cleanup`, meaning it should be entered even if no matching
    clause is found.

    As the matching clause is determined at the runtime, the code in a landing
    block has to be able to determine which of the possible clauses (or
    `cleanup` flag) fired. For this reason, the return value of a `landingpad`
    instruction is determined using a *personality function*. Personality
    function is a language-specific function which is called when the exception
    is thrown, or by the stack unwinder. For C++ and Clang, the personality
    function is `__gxx_personality_v0` and it returns a pointer to the exception
    and an integral selector which uniquely determines which catch block of the
    original C++ code should fire.

`invoke`

~   instruction works similarly to the `call` instruction; it can be used to call
    a function in such a way that if the function throws an exception, this
    exception will be handled by a dedicated basic block. Unlike `call`, `invoke`
    is a terminator instruction, it has to be last in a basic block. Apart
    from the function to call and its parameters, `invoke` also takes two basic
    block labels, one to be used when the function returns normally and one to be
    used on exception propagation; the second one must be a label of a landing
    block.

`resume`

~   is used to resume propagation of an exception which was earlier intercepted by
    an `invoke`--`landingpad` combination. The parameters are the same as
    returned by the `landingpad`.

[^lblp]: In \llvm documentation this block is referred to as *landing pad*,
however, we will use the naming introduced in \cite{RBB14} to avoid confusion
between `landingpad` as an instruction and landing pad as a basic block which
contains this instruction.

It is important to note that \llvm does not have any instruction for throwing
of an exceptions, this is left to the frontend to be done in language-dependent
way. In C++ throwing is done by a call to `__cxa_throw` which will initiate the
stack unwinding in cooperation with the unwinder library. Similarly, allocation
and catching of exceptions are left to be provided by the frontend.

# Memory Model and Atomic Instructions

\label{sec:llvm:atomic}

\llvm has support for atomic instructions with well-defined behaviour in
multi-threaded programs \cite{llvm:atomics}. \llvm's atomic instructions are
built so that they can provide the functionality required by the C++11 atomic
operations library, as well as Java's volatile. Apart from atomic versions of
`load` and `store` instructions, \llvm supports two atomic instructions:
`atomicrmw` (atomic read-modify-write) and `cmpxchg` (atomic
compare-and-exchange, also compare-and-swap) which are essentially an atomic load,
immediately followed by an operation and an atomic store in such a way that no
other memory action can happen between the load and the store. \llvm also
contains a `fence` instruction (memory barrier) which allows for synchronization
which is not part of any other operation.

## Atomic Ordering

The semantics of these atomic instructions are affected by their *atomic
ordering* which gives the strength of atomicity they guarantee. Apart from *not
atomic* which is used to denote `load` and `store` instructions with no
atomicity guarantee, there are six atomic orderings: *unordered*, *monotonic*,
*acquire*, *release*, *acquire-release*, and *sequentially consistent* (given in
order of increasing strength). These atomic orderings are defined by the memory
model of \llvm{} (which is described in detail in chapter *Memory Model for
Concurrent Operation* of \cite{llvm:langref}).

In order to describe the aforementioned atomic orderings, we first need to define
the *happens-before* partial order of operations of a concurrent program.
Happens-before is the least partial order that is a superset of a single-thread
execution order, and when *a* *synchronizes-with* *b*, it includes an edge from *a*
to *b*. Synchronizes-with edges are introduced in platform-specific ways,[^sync]
and by atomic instructions.


[^sync]: For example by thread creation or joining, mutex locking, and unlocking.

*Unordered*

~   can be used only for `load` and `store` instructions and does not guarantee
    any synchronization, but it guarantees that the load or store itself will be
    atomic. Such an instruction cannot be split into two or more instructions
    or otherwise changed in a way that a load would result in a value different
    from all written previously to the same memory location. This memory
    ordering is used for non-atomic loads and stores in Java and other
    programming languages in which data races are not allowed to have undefined
    behaviour.[^cpprace]

*Monotonic*

~   corresponds to `memory_order_relaxed` in the C++11 standard. In addition to
    guarantees given by *unordered*, it guarantees that a total ordering consistent
    with the happens-before partial order exists between all *monotonic* operations
    affecting the same memory location.

*Acquire*

~   corresponds to `memory_order_acquire` in C++11. In addition to the
    guarantees of *monotonic* ordering, a read operation flagged as *acquire*
    creates a synchronizes-with edge with a write operation which created the
    value if this write operation was flagged as *release*. *Acquire* is a memory
    ordering strong enough to implement lock acquisition.

*Release*

~   corresponds to `memory_order_release` in C++11. In addition to the
    guarantees of *monotonic* ordering, it can create a synchronizes-with edge with
    corresponding *acquire* operation. *Release* is memory ordering strong enough
    to implement lock release.

*Acquire-release*

~   corresponds to `memory_order_acq_rel` in C++11 and acts as both *acquire* and
    *release* on a given memory location.

*Sequentially Consistent*

~   corresponds to `memory_order_seq_cst` which is the default for operations on
    `atomic` objects in C++. In addition to guarantees given by *acquire-release*,
    it guarantees that there is a global total order of all
    *sequentially-consistent* operations on all memory locations which is
    consistent with happens-before partial order and with modification order of
    all the affected memory locations.

[^cpprace]: This is in contrast with C++11 and C11 standards that specify that a
concurrent, unsynchronized access to the same non-atomic memory location results
in an undefined behaviour, for example `load` can return a value which was never
written to a given memory location.

An example of synchronizes-with edges and a happens-before partial order can be
seen in \autoref{fig:llvm:at:happensbefore}.

\begFigure[tp]
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

\begCaption
Happens-before partial order and synchronizes-with edges of a simple program
with two threads (`t1` and `t2`) and global variables `a`, `b`, `c`, and `d` for
an execution when first the thread `t1` executes two instructions, then `t2`
executes and finally `t1` continues execution. The black arrows denote a
happens-before ordering given from the single-thread execution, while the red
arrow denotes a synchronizes-with edge (which is part of the happens-before
partial order). Please note that there is no synchronizes-with edge between the
`store` and `load` of `d` (even in case that the `load` returns the value
written by the `store`) as the `store` is not *release* or stronger.
\endCaption
\label{fig:llvm:at:happensbefore}
\endFigure

\bigskip
Unlike aforementioned atomic instructions, the `fence` instruction is not bound
to a specific memory location. Instead, it establishes memory synchronization
between *non-atomic* and *monotonic* atomic accesses. The synchronization is
established if there exists a pair of `fence` instructions *R* and *A* where *R*
is a *release* fence and *A* is an *acquire* fence, an atomic object *M* which is
modified by instruction *S* (with at least *monotonic* ordering) after *R* and
read by instruction *L* (with at least *monotonic* ordering) before *A*. In this
case, there is a happens-before edge from *R* to *A*. Now if the read *L* of *M*
observes the value written by write *S*, this implies that all (atomic or not)
writes which happen-before the fence *R* also happen-before the fence *A*. An
illustration how this can be used to implement a spin-lock can be found in
\autoref{fig:llvm:fence}.

If the fence has *sequentially consistent* ordering it also participates in
a global program order of all *sequentially consistent* operations. A fence is not
allowed to have *monotonic*, *unordered*, or *not atomic* ordering.

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

\antispaceatend
\begCaption
An example of a use of `fence` instruction. The *release* fence (line 6 in C++,
4 in \llvm) synchronizes with the *acquire* fence (line 12 in C++, 19 in \llvm)
because there exists an atomic object `flag` and an operation which modifies it
with a *monotonic* ordering (lines 7, 5) after the *release* fence, and reads it,
again with a *monotonic* ordering (lines 11, 14), before the *acquire* fence.
\endCaption
\label{fig:llvm:fence}
\endFigure

\bigskip
Finally, all atomic instructions can optionally have a `singlethreaded` flag
which means they do not synchronize with other threads, and only synchronize
with other atomic instructions within the thread. This is useful for
synchronization with signal handlers.
