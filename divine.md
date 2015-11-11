In this chapter we describe internal architecture of \divine, with main focus
on implementation of \llvm verification. More details about \divine can be found
for example in Ph.D. thesis of Petr Ročkai, \cite{RockaiPhD}.

For the purposes of this thesis, most of internal architecture of \divine is
irrelevant --- we will focus mostly on \llvm interpreter, which is the only part
directly involved in this work and its architecture is important for
understanding of proposed \llvm-to-\llvm transformations as well as possibility
to use them outside of \divine. We will also describe already employed state
space reduction techniques.

# Overall Architecture

\divine is implemented in C++, with modular architecture. The main modules are
state space generators, exploration algorithms and closed set storages.
Currently, there are multiple implementations of each of these modules,
providing different functionality. For state space generators, there are
versions for different input formalisms such as \llvm, DVE \cite{TODO}, and
\textsc{UppAll} timed automata \cite{TODO}. Each of these generators define
input formalism and is capable of generating state space graph from its input,
that is, for given state in state space it gives its successor and is able to
report state flags --- these are used by exploration algorithm to detect if goal
state was reached (in case of safety properties) or is accepting in case of
\ltl verification using \buchi automata.

The closed set storage defines a way in which closed set is stored, so that for
given state it can be quickly checked if it was already seen and it is possible
to retrieve algorithm data associated with this state. In \divine 3 two modes of
operation are present --- hash table, and hash table with lossless \tc
\cite{RSB15}.

Finally exploration algorithm connects all these parts together in order to
verify given property. The algorithm used depends on verified property, for
safety properties, either standard \bfs based reachability, or
context-switch-directed reachability \cite{SRB14} can be used. For general \ltl
properties OWCTY algorithm \cite{TODO} is used. All of these algorithm support
parallel and distributed verification.

# \llvm{} in \divine

\llvm support is implemented by the means of \llvm state stace generator, also
called \llvm interpreter and bitcode libraries. The interpreter is responsible
for instruction execution, memory allocation and thread handling, as well as
parts of exception handling --- its role is similar to the role of operating
system and hardware. On the other hand the bitcode libraries provide higher
level functionality for users program --- they implement language support by the
means of standard libraries for C and C++, higher-level threading by the means
of `pthread` library, and to some extend a limited UNIX-compatible environment.
The libraries use intrinsic functions provided by the generator to implement low
level functionality --- these functions are akin to system calls in operating
systems.

As a terminology, we will denote all the parts implemented in \llvm bitcode,
that is the bitcode libraries together with user-provided code as the
*userspace*, to distinguish it from the interpreter, which is compiled into
\divine. Unlike the interpreter, the userspace can be easily changed, or even
completely replaced without the need to modify and recompile \divine itself.

## Interpreter

## Userspace

# Reduction Techniques

## $\tau+$ and Heap Reductions

*   \cite{RBB13} $\tau+$

## \Tc

*   \cite{RSB15} tree

# \lart
