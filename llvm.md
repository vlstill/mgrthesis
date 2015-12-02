\llvm\cite{llvm:web} was originally introduced in \cite{Lattner02} as an
infrastructure for optimization. Today \llvm is presented as compiler
infrastructure, it provides programming language and platform independent tools
for optimization and support for code generation for many platforms. It also
defines intermediate representation --- \llvm IR --- a Single Static Assignment
based low level language, and a library for manipulation with this intermediate
representation.

# \llvm{} Intermediate Representation

\begin{quote}
``\llvm is a Static Single Assignment (SSA) based representation that provides
type safety, low-level operations, flexibility, and the capability of
representing ‘all’ high-level languages cleanly. It is the common code
representation used throughout all phases of the \llvm compilation strategy.''

\hfill --- \llvm Language Reference Manual \cite{llvm:langref}
\end{quote}

\llvm IR can be represented in three ways --- a human readable assembly (`.ll`
file), a compact serialized bitcode (`.bc` file), or as in-memory C++ objects.

* Local Variable representation

## Exception Handling

\label{sec:llvm:eh}

*   stack unwinding without EH: exit,…
*   landingpad block = bb beginning with `landingpad`
*   \cite{RBB13}

## Atomic Instructions

\label{sec:llvm:atomic}

\llvm has support for atomic instructions with well-defined behavior in
multi-threaded programs \cite{llvm:atomics}. \llvm's atomic instructions are
build so that they can provide functionality required by C++11 atomic operation
library, as well as Java volatile. Apart from atomic versions of `load` and
`store` instruction \llvm supports three atomic instructions --- `atomicrmw`
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
*happens-before* partial order of operations of concurrent program.
Happens-before is least partial order that is superset of single-thread
execution order, and when *a* *synchronizes-with* *b* it includes edge from *a*
to *b*. Synchronizes-with edges are introduces by platform-specific ways,[^sync]
and by atomic instructions.

[^memmodel]: Chapter *Memory Model for Concurrent Operation* of
\cite{llvm:langref}.

[^sync]: For example by thread creation or joining, mutex locking and unlocking.

Unordered

~   can be used only for `load` and `store` instructions and does not guarantee
    any synchronization but it guarantees that the load or store itself will be
    atomic, that is it cannot be split into two or more instructions or
    otherwise changed in a way that load would result in value different from
    all written previously to the same memory location. This memory ordering is
    used for non-atomic loads and stores in Java and other programming languages
    in which data races are not allowed to have undefined behaviour.[^cpprace]

Monontonic

~   corresponds to `memory_order_relaxed` in C++11 standard, in addition to
    guarantees given by unordered, it guarantees that a total ordering consistent
    with happens-before partial order exists between all monotonic operations
    affecting same memory location.

Acquire

~   corresponds to `memory_order_acquire` in C++11, in addition to guarantess of
    monotonic, a read operation flagged as acquire creates synchronizes-with
    edge with a write operation which created the value if this write operation
    was flagged as release. Acquire is memory ordering strong enought to
    implement lock acquire.

Release

~   corresponds to `memory_order_release` in C++11, in addition to guarantess of
    monotonic, it can create synchronizes-with edge with corresponding acquire
    operation. Release is memory ordering storng enoght to implement lock
    release.

Acquire-Release

~   corresponds to `memory_order_acq_rel` in C++11, acts as both acquire and
    release on given memory location.

Sequentially Consistent

~   corresponds to `memory_order_seq_cst` which is default for `atomic`
    operations in C++. In addition to guarantees given by acquire-release it
    guaratees that there is a global total order of all sequentially-consistent
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

Unlike aforementioned atomic instructions the `fence` instruction is not bound
to a specific memory location. \TODO{semantika fence}

# \llvm{} Library

Apart from the intermediate representation \llvm also provides a C++ library
which provides wide range of tools for optimization and manipulation of \llvm
IR.

