With modern multi-core CPUs, multi-threaded programs are increasingly common and
therefore the need to show their correctness, or at least find bugs in then is
increasing.  The problem is that testing of multi-threaded programs lacks well
established deterministic procedure. While common techniques, such as unit
testing, can be applied to parallel programs, they are unable to reliably find
bugs caused by data races.

The underlying reason is that data races occur when actions performed by threads
in parallel are executed in unexpected order which exposes the problem. This
interleaving might be, however, quite rare and therefore it is often hard to
trigger this bug by testing. Furthermore, even if the bug can be triggered by
testing, it is often hard to reproduce and debug it, as common debugging
approaches, including debuggers and logging often interfere in a way which can
hide the particular erroneous run.

# Explicit-state Model Checking

Formal methods, explicit-state model checking using automata-base approach
\cite{Clarke2000MC} in particular, can help in this regard. Explicit-state model
checking allows us to explore all possible interleavings of parallel programs
and therefore uncover even extremely rare data races. While pure explicit-state
model checking requires programs to be closed (not have any inputs) it is still
very helpful as it can be applied for example to unit tests and this combination
yields deterministic testing procedure for parallel unit tests. Furthermore,
there are techniques, such as control-explicit-data-symbolic model checking
\cite{BBH14}, which allow application of model checking to parallel programs
with inputs.

On the other hand, formal methods come with a new set of issues, such as their
computational complexity and their usability for software developer.  For a
verification tool to be useful to software developers it is important to
minimize any extra effort the developers have to put into usage of such tool.
Historically this effort was large as older generations of verifiers such as
SPIN \cite{Hol97SPIN} and LTSmin \cite{ltsmin}, required manual translation of
the verified program into a modeling language such as ProMeLa. With the new
generation of verifiers, such as \divine 3 \cite{DiVinE30}, CBMC \cite{CBMC},
and LLBMC \cite{LLBMC}, special-purpose languages for verification are no longer
required. These tools support direct verification of widely used programming
languages such as C and C++, either directly or using \llvm intermediate
representation \cite{llvm:web} (an intermediate language which can be used in
translation of many programming languages, including C and C++).

\llvm IR in particular is becoming input language of choice for many verification
tools. This assembly-like language is simpler to work with than higher level
languages, yet it maintains platform independence, compact instruction set, and
useful abstractions such as type information and unbounded number of registers
which make it easier to analyze than machine code. Furthermore, \llvm IR
comes with large library for manipulations and optimizations.

With this approach, real-world code can be verified, and the ultimate goal is to
be able to verify a program without any modifications to it. This is also the
goal for \divine \cite{DiVinE30}, a well established explicit-state model
checker, which aims primarily at verification of unmodified C and C++ programs
with parallelism using \llvm as an intermediate representation. \divine aims to
have full support of language features for C++ including for example exception
handling.  Furthermore \divine provides near complete implementation of C and
C++ standard library including features of newest C++14 standard and `pthread`
threading library. In this way, \divine can often be directly applied to
verification of real-world code, provided it does not use inputs or platform
specific features such as calls into the kernel of the operating system. \divine
is able to verify wide range of properties, such as memory and assertion safety,
absence of memory leaks, and liveness properties defined by linear temporal
logic specification.

The other problem for practical model checking is state space explosion. The
state space of all runs of a parallel program can be large, and therefore, the
resources to explore it can be vastly larger than resources needed to execute
the program directly. This problem is even more pronounced with verification of
real-world programs, as the tedious detains often abstracted away in translation
to modelling languages are still present in them. To make verification of
real-world programs feasible in more cases, \divine employs advanced state space
reductions, including $\tau+$ and heap symmetry reductions which eliminate large
number of unnecessary interleavings \cite{RBB13} and tree compression to achieve
memory-efficient storage of state space \cite{RSB15}. \divine also supports
parallel and distributed verification \cite{BRSW15, BBCR10}.

# Relaxed Memory Models

One common source of bugs in parallel programs is the fact that modern CPUs use
relaxed memory models. With relaxed memory models, the visibility of an update
to a shared memory location need not be visible immediately by other threads and
it might be reordered with other updates to different memory locations. This
adds yet another level of difficulty to already difficult programming of
parallel programs: memory models are hard to reason about and it is often hard
to specify the desired behaviour in the programming language in question. While
hardware commonly has support to ensure particular ordering of memory
operations, this is often not supported by programming languages, such as older
versions of C and C++. With newer programming languages, such as C11/C++11, it
is possible to specify the behavior of the program precisely, but this is still
a difficult problem, especially for high-performance tasks when it is desirable
to use weakest synchronization which is sufficient for correctness. For these
reasons it is important to be able to verify programs under relaxed memory
models. This is, however, not the case for many verifiers, even if they aim at
verification of real-world programs.

To further complicate the matter of relaxed memory models, the actual memory
models implemented in hardware differ with CPU architectures, vendors, or even
particular models of CPUs and detailed descriptions are usually not publicly
available. For these reasons it would not be practical and feasible to verify
programs with regard to a particular implementation of real-world memory model.
Theoretical memory models which were proposed to allow analysis of programs
under relaxed memory models, namely *Total Store Order* (TSO) \cite{SPARC94},
*Partial Store Order* (PSO) \cite{SPARC94}. Also, programming language
standards, such as C++11, and \llvm define memory models for programs written in
the particular language \cite{llvm:atomics}. These theoretical memory models are
usually described as constraints to allowed reordering of instructions which
manipulate with memory. 

In those theoretical models, an update may be deferred for an infinite amount of
time. Therefore, even a finite state program that is instrumented with a
possibly infinite delay of an update may exhibit an infinite state space. It has
been proven that for such an instrumented program, the problem of reachability
of a particular system configuration is decidable, but the problem of repeated
reachability of a given system configuration is not
\cite{Atig:2010:VPW:1706299.1706303}.

A variety of ways to verify programs under relaxed memory models were proposed.
The idea of using model checking was first discussed in the context of
Mur$\varphi$ model checker which was used to generate all possible outcomes of
small, assembly language, multiprocessor program for a given memory models
\cite{Murphi, ParkDill99}. A technique which represents TSO store buffers with
finite automata to represent possibly infinite set of its contents was
introduced in \cite{TSO+} and later extended in \cite{Linden-mfence}.
In the context of \divine, relaxed memory models were first discussed in the
context of DVE modelling language \cite{BBH13LTL}.

More recently, an proof-of-concept support for under-approximation of  Total
Store Order relaxed memory model for C and C++ programs was introduced in
\cite{SRB15}. This support is based on \llvm transformation which automatically
instruments the program-to-be-verified with store buffers, and this enriched
program is verified with \divine. The main limitation of the transformation
proposed in \cite{SRB15} is that it does not fully support \llvm atomic
instructions with other that sequential consistency ordering and it supports
only TSO memory model.

# Aims and Contributions of This Work

This work focuses on use of \llvm transformations as a preprocessing step for
verification of real-world parallel C and C++ programs using \divine model
checker. We demonstrate that this technique is both viable and useful as it can
aid verification of these programs. More specifically, we focus into two areas,
the first one is extension of verifiers capabilities, most importantly enriching
input programs with weak memory models such that these can be verified using
unmodified model checker which assumes sequential consistency. This is
continuation of the work presented in \cite{SRB15} which is significantly
extended. The new memory model instrumentations has full support of \llvm memory
model with atomic instructions, it supports verification under more relaxed
memory models than total store order, and it supports full range of properties
supported by \divine. We also show a use of \llvm transformations on the case of
verification of SV-COMP \cite{SVCOMP} benchmarks with \divine \cite{SRB16svc}.

The other area is state space size reduction aided by \llvm transformations
which do not change the semantics of the input program. In this field we propose
a few transformations which can be used with \divine.

While the techniques presented here are designed primarily for \divine, their
nature as \llvm transformation allows their application for other model
checkers, or even verifiers using different principles, provided they use \llvm
as an input language and they have support for features required by these
transformations.

The structure of the thesis is the following: first, in \autoref{chap:llvm} we
present \llvm intermediate representation and \llvm memory model and in
\autoref{chap:divine} we present architecture of \divine. \autoref{chap:trans}
demonstrates how \llvm transformations can be used to extend capabilities of
model checker, in particular by adding weak memory support into \divine as \llvm
transformation, and explores the usage of \llvm transformation for state space
reductions. \autoref{chap:results} presents experimental evaluation of proposed
techniques and finally chapter \autoref{chap:conclusion} concludes this work.
