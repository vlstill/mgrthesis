In this chapter, we describe internal architecture of \divine [^dvers] with the
main focus on the implementation of \llvm verification. More details about
\divine can be found for example in \cite{RockaiPhD, DiVinE30, DiVinE:web}.

[^dvers]: More precisely version 3.3 which is the latest released version at the
time of writing of this thesis.

For the purposes of this thesis, most of the internal architecture of \divine is
irrelevant and we will focus mostly on the \llvm interpreter, which is the only part
directly involved in this work, and its interaction with the verified program is
important for the understanding of the proposed \llvm transformations as well as
possibility to use them outside of \divine. We will also describe state space
reduction techniques implemented in \divine.

# Overall Architecture

\divine is implemented in C++, with a modular architecture. The main modules are
state space generators, exploration algorithms, and closed set stores.
Currently, there are multiple implementations of each of these modules,
providing different functionality. For state space generators, there are
versions for different input formalisms such as \llvm, DVE \cite{Simecek2006},
and UPPAAL timed automata \cite{UppAll}. Each of these generators
define an input formalism and can be used to generate a state space graph from its
input, that is, for a given state in the state space, it yields its successors and
is able to report state flags. State flags are used by the exploration algorithm
to detect if a goal state was reached (in the case of safety properties) or the
state is accepting (in the case of \ltl verification using \buchi automata).

The closed set store defines a way in which the closed set is stored, so that for
a given state, it can be quickly checked if it was already seen and it is possible
to retrieve algorithm data associated with this state. In \divine, two versions
of closed set stores are present: a hash table and a hash table with lossless
tree compression \cite{RSB15}.

Finally, the exploration algorithm connects all these parts together in order to
verify a given property. Which algorithm is used depends on the verified property, for
safety properties, either standard \bfs{}-based reachability or
context-switch-directed reachability \cite{SRB14} can be used. For general \ltl
properties, the OWCTY algorithm \cite{OWCTY} is used. All of these algorithms support
parallel and distributed verification.

# \llvm{} in \divine

\llvm support is implemented by the means of an \llvm state space generator,
also referred to as an \llvm interpreter, and libraries. The interpreter is
responsible for instruction execution, memory allocation and thread handling, as
well as parts of exception handling. The role of the interpreter is similar to
the role of the operating system and hardware for natively compiled programs. On
the other hand, the libraries provide higher level functionality for user's
programs, as they implement language support by the means of standard libraries
for C and C++, higher-level threading by the means of the `pthread` library, and
to some extent a POSIX-compatible environment, with a simulation of basic
filesystem functionality. The libraries use intrinsic functions provided by the
interpreter to implement low-level functionality; these functions are akin to
system calls in operating systems.

We will denote all the parts implemented in \llvm bitcode, that is the libraries
together with the user-provided code as the *userspace*, to distinguish it from
the interpreter, which is compiled into \divine. Unlike the interpreter, the
userspace can be easily changed, or even completely replaced without the need to
modify and recompile \divine itself, and is closely tied to the language of the
verified program, while the interpreter is mostly language-agnostic.

In order to verify programs in C or C++ in \divine, they are first compiled into
\llvm using Clang together with libraries, the overall workflow of verification
of C/C++ code is illustrated in \autoref{fig:divine:llvm:workflow}.

\begin{figure}[t]
    \center\small

    \begin{tikzpicture}[ ->, >=stealth', shorten >=1pt, auto, node distance=3cm
                       , semithick
                       , scale=0.7
                       , state/.style={ rectangle, draw=black, very thick,
                         minimum height=2em, minimum width = 4em, inner
                         sep=2pt, text centered, node distance = 2em }
                       ]
      \node[state, minimum width = 5em] (lib) {Libraries};

      \node[state, below = of lib.south west, anchor = north west] (cpp) {C++};
      \node[state, right = of cpp, rounded corners] (clang) {Clang};
      \node[state, right = of clang] (llvm) {\llvm IR};
      \node[state, right = of llvm, rounded corners] (lart) {\lart};
      \node[state, right = of lart] (llvm2) {\llvm IR};
      \node[state, right = of llvm2, rounded corners] (divine) {\divine};

      \node[state, above = of divine.north east, anchor = south east, minimum width = 11em] (ltl) {\ltl or safety property};
      \node[state, below = of divine] (valid) {Valid};
      \node[state, left = of valid, minimum width = 8em] (ce) {Counterexample};

      \path (ltl.south) edge[out=270, in=90] (divine.north)
            (cpp) edge (clang)
            (clang) edge (llvm)
            (lib) edge [out=0, in=90, looseness = 1] (clang)
            (llvm) edge (lart)
            (lart) edge (llvm2)
            (llvm2) edge (divine)
            (divine.south) edge (valid) edge[out=270, in=90] (ce.north)
            ;
    \end{tikzpicture}

  \caption{Workflow of verification of C++ programs with \divine. \lart is
  optional. Boxes with rounded corners represent executables.}
  \label{fig:divine:llvm:workflow}
\end{figure}

## Interpreter

\label{sec:divine:interpreter}

The \llvm interpreter is responsible for the execution of \llvm instructions and
intrinsic functions (built-in operations which are represented in \llvm as calls
to certain functions with a `__divine` or `llvm` prefix and are executed
similarly to instructions in the interpreter). It also performs state space
reductions (described in \autoref{sec:divine:reduction}) and recognizes which
states violate the verified property.

### Problem Categories

\label{divine:divine:problems}

\divine has several safety properties which can be verified in \llvm models;
these properties are specified in term of problem categories. Each category is a
group of related problems which should be reported as property violations.
Problem categories can be reported either directly by the \llvm interpreter, or
from the userspace using the `__divine_problem` intrinsic. When a problem is
reported, it is indicated in the state together with the position in the program
at which it was detected. Problem names are defined in the `divine/problem.h`
header file, which is available to the program when it is compiled using
\divine.

Assert
~   corresponds to a call of `assert` function with arguments which evaluated to
    false.

Invalid dereference
~   is reported by the interpreter if a load is performed from an invalid
    address.

Invalid argument
~   is reported by the interpreter when a function is called with unexpected
    arguments, for example, non-variadic function called with more (or fewer)
    arguments that it expected, or an intrinsic called with wrong argument values.

Out of bounds
~   is reported by the interpreter when an access out of the bounds of a memory
    object is attempted.

Division by zero
~   is reported when integral division by zero is attempted.

Unreachable executed
~   is reported if an `unreachable` instruction is executed. This instruction
    usually occurs at the end of a non-void function which lacks a return statement.

Memory leak
~   is reported when the last pointer to a given heap memory object is destroyed
    before the object is freed.

Not implemented
~   is intended to be reported by the userspace in function stubs (a function
    which is provided only so that bitcode does not contain undefined functions,
    but is not implemented, for example because it is not expected to be used).

Uninitialized
~   is reported by the interpreter if the control flow depends on an
    uninitialized value.

Deadlock
~   is reported by the userspace deadlock detection mechanisms, for example
    when a circular wait in `pthread` mutexes is detected.

Other
~   is used by the userspace to report other types of problems.


### Intrinsic Functions

Intrinsic functions allow the userspace to communicate with the interpreter, in
order to allocate or free memory, create threads, report errors and so on. These
functions are intended to be used by library writers, not by the users of
\divine. Nevertheless, they are relevant to this work as some of them are used in
proposed transformations. Since these functions are \divine-specific, the
transformations using them would need to be modified, or equivalent functions
would have to be provided should the transformation be used for other tools.

```{.cpp}
int __divine_new_thread( void (*entry)(void *), void *arg );
int __divine_get_tid();
```

The `__divine_new_thread` intrinsic instructs the interpreter to create a new
thread, this thread will use `entry` as its entry procedure. `entry` has to accept
a single `void*` argument, the interpreter will pass `arg` to the entry procedure
of new thread. The function returns a thread ID used for identification of the new
thread in \divine's interpreter. `__divine_get_tid` returns \divine thread
ID of the thread which executed it.

\bigskip When implementing threading primitives (such as those in the `pthread`
library) in userspace, it is required that these are themselves free of data
races.  To facilitate this, \divine provides a way to make a section of
instructs atomic; the interpreter ensures that this block of instructions is
indeed executed atomically, that there is only one edge in the state space
(which corresponds to the entire block of instructions, and may include any
number of instructions or even function calls. It is, however, a responsibility
of the library writer to use these atomic sections correctly, namely, each of
these sections must always terminate; that is, there must be no (possibly)
infinite cycles or recursion, such as busy-waiting for a variable to be set by
another thread.

```{.cpp}
void __divine_interrupt_mask();
void __divine_interrupt_unmask();
```

\label{sec:divine:llvm:mask}

The `__divine_interrupt_mask` function starts an atomic section; all actions
performed until the atomic section ends will happen atomically. The atomic
section can end in two ways, either by an explicit call to unmask function, or
implicitly when function which called the mask function exits.

The behaviour of atomic sections can be more precisely explained by the means of
a *mask flag* associated with each frame of the call stack. When
`__divine_interrupt_mask` is called, the frame of its caller is marked with a
mask flag, which can be reset by a call to `__divine_interrupt_unmask`. An
instruction is part of an atomic section if the frame it corresponds to has the
mask flag set. If the executed function is a function call, the frame of the
callee inherits the mask flag of the caller.  However, when
`__divine_interrupt_unmask` is called, it resets the mask flag of its caller,
leaving mask flags of functions lower in the stack unmodified. If the current
function which calls `__divine_interrupt_unmask` is not the same as the caller
of `__divine_interrupt_mask`, the atomic section ends and a new atomic section
will be entered when the current function returns (the caller of the current
function still has the masked flag set).


```{.cpp}
void __divine_assert( int value );
void __divine_problem( int type, const char *data );
```

These functions can be used to report problems from the userspace.
`__divine_assert` behaves much like the standard C macro `assert`: if it is
called with a nonzero value, the assertion violated problem is added to the
current state's problems.  `__divine_problem` unconditionally reports a problem
of a given category to the interpreter; the report can be accompanied by an
error message passed in the `data` value.

```{.cpp}
void __divine_ap( int id );
```

`__divine_ap` indicates that atomic proposition represented by `id` holds in
the current state. For more details on \ltl in \divine, see
\autoref{sec:divine:ltl}.

```{.cpp}
int __divine_choice( int n, ... );
```

`__divine_choice` is a nondeterministic choice operator. When it is encountered, the
state of the program splits into `n` copies; each copy of the state will see a
different return value from `__divine_choice`, starting from $0$ and up to
$\texttt{n} - 1$. When more than one parameter is given, the choice becomes
probabilistic and the remaining parameters give the probability distribution of the
choices (there must be exactly `n` additional parameters). This can be used for
probabilistic C++ verification, see \cite{BCRSZ16} for more details.

```{.cpp}
void *__divine_malloc( unsigned long size );
void __divine_free( void *ptr );
int __divine_heap_object_size( void *ptr );
int __divine_is_private( void *ptr );
```

These are low-level heap access functions. `__divine_malloc` allocates a new block
of memory of a given size; it never fails.  `__divine_free` frees a block of
memory previously allocated with `__divine_malloc`. If the block was already
freed, a problem is reported. If a null pointer is passed to `__divine_free`,
nothing is done.

`__divine_heap_object_size` returns the allocation size of a given object, and
`__divine_is_private` returns nonzero if the pointer passed to it is private to
the thread calling this function.

```{.cpp}
void *__divine_memcpy( void *dest, void *src, size_t count );
```

The behaviour of `__divine_memcpy` is similar to the `memmove` function in the
standard C library, that is, it copies `count` bytes from `src` to `dest`; the
memory areas are allowed to overlap. This intrinsic is required due to pointer
tracking used for heap canonization (see \cite{RBB13} for details on heap
canonization).

```{.cpp}
void *__divine_va_start();
```

This function is used to implement C macros for functions with variable number
of arguments.  The call to `__divine_va_start` returns a pointer to a block of
memory that contains all the variadic arguments, successively assigned higher
addresses going from left to right.

```{.cpp}
void __divine_unwind( int frameid, ... );
struct _DivineLP_Info *__divine_landingpad( int frameid );
```

These functions relate to exception handling. `__divine_unwind` unwinds all
frames between the current frame and the frame denoted by `frameid`.
`__divine_landingpad` gives information about the `landingpad` instruction
associated with the active call in a given frame.

## Exception Handling

\label{sec:divine:llvm:eh}

In order to allow verification of unmodified programs in any programing
language, it is desirable that all the language features can be handled by the
verifier. When \llvm is used as an intermediate representation by the verifier,
most of the language features are supported automatically by the use of a pre-existing
compiler. Nevertheless, there might still be some features that require support
from the verifier. C++ exceptions are such a feature and they are often omitted
by verifiers for this reason.

In \divine, C++ exceptions are supported and the mechanisms used should allow
implementation of exceptions in other programming languages entirely in the
userspace, provided that they use \llvm exception handling as described in
\autoref{sec:llvm:eh} and they use similar mechanisms as C++ to determine which
`landingpad` clause matches the exception. The full description of \divine's
exceptions can be found in \cite{RBB14}.

From the point of view of a C++ program, \divine acts as an unwinder library, as
it allows control to be transfered from the currently executing function into a
landing block corresponding to an active `invoke` instruction in some stack
frame deeper in the stack. The interface for this functionality is quite simple
and it consists of the following functions and data types:

```{.cpp}
void __divine_unwind( int frameid, ... );

struct _DivineLP_Clause {
    int32_t type_id;
    void *tag;
};

struct _DivineLP_Info {
    int32_t cleanup;
    int32_t clause_count;
    void *personality;
    struct _DivineLP_Clause clause[];
};

struct _DivineLP_Info *__divine_landingpad( int frameid );
```

`__divine_unwind` unwinds all frames between the current frame and the frame
denoted by `frameid`. No landing pads are triggered in the intermediate frames,
if there is a `landingpad` for the active call in the frame in which the
unwinding ends and any arguments other than `frameid` were passed to
`__divine_unwind`, this landing pad returns arguments passed to
`__divine_unwind` (if the active call instruction in the destination frame is
`call` and not `invoke`, the extra arguments are returned as the result of the
function). The `frameid` is $0$ for the caller of `__divine_unwind`, $-1$ for
its caller and so on.

`__divine_landingpad` gives information about `landingpad` associated with the
active `invoke` in the frame denoted by `frameid`, if there is some. It returns
a pointer to a `_DivineLP_Info` object which corresponds to the landing pad, or
a null pointer if the frame does not exist. If the active instruction in the
target frame is a `call` instead of an `invoke`, the returned `_DivineLP_Info`
object will contain no clauses. The returned structure encodes information about
the `landingpad` it corresponds to and about the personality function used by
its enclosing function.  There is a flag which indicates whether the landing
block is a cleanup block (it should be entered even if the exception does not
match any of the clauses), and an array of `_DivineLP_Clause` structures which
encodes the clauses of the `landingpad`. For each of these clauses, there is an
identifier which should be returned as a selector from the `landingpad` if this
clause is matched, and a pointer to a language-specific `tag` (which is a type
information object in C++).

Using these functions, a function which throws an exception can be implemented:
it goes through the stack asking for `_DivineLP_Info` in each frame beginning
with its caller, and for each of them checks if the exception type matches any
of the clauses in the `landingpad`. When a matching clause is found, the
corresponding type id is set in the exception object, which is then passed into
a `personality` function. The personality function returns a value which should
be returned from the `landingpad` instruction, so this value is passed, together
with the frame id of the target frame, into `__divine_unwind` to perform the
unwinding.

The `resume` instruction implementation is in the interpreter. It finds the
nearest `invoke` in the call stack and transfers control to its `landingpad`
which will return the value passed to the `resume`.

Apart from the aforementioned exception handling `__divine_unwind` is also
usable for the implementation of functions such as `pthread_exit`. In this case,
the stack is fully unwound, which causes the thread to terminate. Furthermore,
\cite{RBB14} presents a minor extension of the exception handling mechanism
which would allow an implementation of the `setjmp`/`longjmp` POSIX functions;
this extension is not implemented in \divine.

## \ltl

\label{sec:divine:ltl}

\ltl support in \divine is implemented using an explicit set of atomic
propositions defined as `enum APs` in the verified program. These atomic
propositions are activated explicitly using a macro named `AP` (which uses
`__divine_ap` internally), and they are active in the state where `AP` is
called. As a result of this explicit activation of atomic propositions, it is
not possible for more than one atomic proposition to be true in any state, and
it is not possible to express certain formulas, namely $G(a)$ for $a \in
\texttt{APs}$. The \ltl properties which should be verified are encoded in the
program using a macro named `LTL`. See \autoref{fig:divine:ltl} for an example
of a program with \ltl in \divine.

\begFigure[tp]

```{.cpp}
#include <divine.h>

enum APs { c1in, c1out, c2in, c2out };
LTL(exclusion,
    G((c1in -> (!c2in W c1out)) && (c2in -> (!c1in W c2out))));

void critical1() {
    AP( c1in );
    AP( c1out );
}

void critical2() {
    AP( c2in );
    AP( c2out );
}
```

\antispaceatend
\begCaption
A fragment of C program which uses \ltl property `exclusion` to verify that
functions `critical1` and `critical2` cannot be executed in parallel.
\endCaption

\label{fig:divine:ltl}
\endFigure

## Userspace

\divine has userspace support for C and C++ standard libraries using PDCLib
and libc++. This support is mostly complete, the most notable missing parts are
locale support (which is missing in PDCLib) and limited support for filesystem
primitives (there is support for the creation of directory snapshots which can be
accessed and processed using standard C, C++, or POSIX functions).

Apart from standard libraries, \divine provides the `pthread` threading library,
which provides thread support for C and older versions of C++ which do not
include thread support in the standard library and is also used as the underlying
implementation of C++11 threads. Furthermore, there is rudimentary support for
POSIX-compatible filesystem functions, including certain types of UNIX domain
sockets; however, this library is still under development at the time of writing
of this thesis.

From the point of view of this thesis, all the userspace is considered to be
part of the verified program; that is, any \llvm transformation runs on the
entire userspace, not just the parts provided by the user of \divine.

## Reduction Techniques

\label{sec:divine:reduction}

In order to make verification of real-world \llvm programs tractable, it is
necessary to employ state space reductions. \divine uses $\tau+$ reduction to
eliminate unnecessary intermediate states and heap symmetry reduction when
verifying \llvm \cite{RBB13}. These reductions preserve all safety and \ltl
properties which can be expressed in \divine. Furthermore, \divine uses
lossless, modeling-language-agnostic tree compression of the entire state space
\cite{RSB15}.

### $\tau+$ Reduction

\label{sec:divine:tau}

In \llvm, many instructions have no effect which could be observed by threads
other than the one which executes the instruction. This is true for all
instructions which do not manipulate memory (they might still use registers,
which are always private to the function in which they are declared), or which
manipulate memory which is thread private.

\divine uses this observation to reduce the state space. It is possible to
execute more than one instruction on a single edge in the state space, provided
that only one of them has an effect visible to other threads (is *observable*).
To do this, the interpreter tracks if it has executed any observable instruction
and emits a state just before another observable instruction is executed (this,
of course, is suppressed in atomic sections, where only tracking takes place; a
state can be emitted only after the end of the atomic section). To decide which
instructions are observable, \divine uses the following heuristics:

*   any instruction which does not manipulate memory is not observable (that is,
    all instructions apart from `load`, `store`, `atomicrmw`, `cmpxchg` and the
    built-in function `__divine_memcpy`[^memcpy]);
*   for the memory-manipulating instructions, it is checked whether the
    concerned memory location can be visible by other threads; if it can, the
    instruction is observable.

To detect which memory can be accessed from particular threads, \divine checks
the reachability of a given memory object in the memory graph (memory objects
are nodes, pointers are edges of this graph). In order to check if thread *a*
has access to a memory object *x*, it has to check that *x* is reachable either
from global variables or from registers in any stack frames which belong to *a*.
To build the memory graph, \divine remembers which memory locations contain heap
pointers (this is required as it is valid to cast a pointer to and from a number
in both \llvm and C++).

[^memcpy]: In fact \divine 3.3 does not consider `__divine_memcpy` observable,
this is a bug discovered and fixed during the writing of this thesis.

However, in order to ensure that successor generation terminates, it is
necessary to avoid execution of infinite loops (or recursion) on a single edge
in the state space (this could happen, for example, due to an infinite cycle of
unobservable instructions). For this reason, \divine also tracks which program
counter values were encountered during successor generation, and if any of them
is to be encountered for a second time, a state is emitted before the second
execution of given instruction.


# \lart

\lart is a tool for \llvm transformation and optimization developed together
with \divine; it was first introduced in \cite{RockaiPhD} as a platform for
implementation of static abstraction and refinement of \llvm programs. It is
intended to integrate \llvm transformations and analyses in such a way that
would make it easy to implement new and reuse existing analyses.

Before the time of writing of this thesis, \lart was never released and it
contained few mostly incomplete analyses and a proof-of-concept version of
an \llvm transformation which adds weak memory model verification support to
existing \llvm program (this part was presented in \cite{SRB15}). Most of the
work presented in this thesis is implemented in \lart.
