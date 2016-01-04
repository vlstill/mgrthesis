With modern multi-core CPUs, multi-threaded programs are increasingly common and
therefore the need to show their correctness, or at least find bugs in then is
increasing.  The problem is that testing of multi-threaded programs lacks well
established deterministic procedure. While common techniques, such as unit
testing, can be applied to parallel programs, they are unable to reliably find
bugs caused by data races. The reason is that such bugs occur only if threads
are interleaved in an order which exposes this data race, a condition which
might happen only rarely.

Explicit-state model checking using automata-base approach \cite{Clarke2000MC}
is a standard technique which can help in this regard as it allows us to
explore all possible interleavings of parallel programs. While pure
explicit-state model checking requires programs to be closed (not have any
inputs) it is still very helpful as it can be applied for example to unit tests
and this combination yields deterministic testing procedure for parallel unit
tests. Furthermore, there are techniques, such as control-explicit-data-symbolic
model checking \cite{BBH14}, which allow application of model checking to
parallel programs with inputs.

For a verification tool to be useful to software developers it is important to
minimize any extra effort the developers have to put into usage of such tool.
Historically this effort was large as older generations of verifiers such as
SPIN \cite{Hol97SPIN} and LTSmin \cite{ltsmin}, required manual translation of
the verified program into a modeling language such as ProMeLa. With the new
generation of verifiers, such as \divine 3 \cite{DiVinE30}, CBMC \cite{CBMC},
and LLBMC \cite{LLBMC}, special-purpose languages for verification are no longer
required as these tools support direct verification of widely used programming
languages such as C and C++ either directly or using \llvm intermediate
representation (an intermediate language which can be used in translation of
many programming languages, including C and C++).

\llvm IR in particular is becoming input language of choice for many verification
tools. This assembly-like language is simpler to work with than higher level
languages, yet it maintains platform independence, compact instruction set, and
useful abstractions such as type information and unbounded number of registers
which make it easier to analyze than machine code. Furthermore, \llvm IR
comes with large library for manipulations and optimizations.

\bigskip

In this work we demonstrate that \llvm transformations are useful technique
which can aid verification of real-world programs, more specifically, we focus
on model checking of parallel C and C++ using \divine \cite{DiVinE30}, a well
established explicit-state model checker, which aims primarily at verification
of unmodified C and C++ code using \llvm intermediate representation as its
input.  \divine aims to have full support of language features for C++ including
for example exception handling.  Furthermore \divine provides near complete
implementation of C and C++ standard library including features of newest C++14
standard and `pthread` threading library. In this way, \divine can often be
directly applied to verification of real-world code, provided it does not use
inputs or platform specific features such as calls into the kernel of the
operating system.

\divine uses the standard automata based approach to explicit state model
checking \cite{Clarke2000MC}, that is, it builds state space graph and explores
it. Either it looks for states violating given safety property (such as
assertion violation or memory usage error), or for accepting cycles in product
with \buchi automaton for liveness properties.

We will present two areas of use of \llvm transformations to aid model checking.
One is extending verifiers capabilities, most importantly enriching input
programs with weak memory models such that these can be verified using
unmodified model checker which assumes sequential consistency; this is
continuation of the work presented in \cite{SRB15}. We also show that \llvm
transformations can be used to wider range of extensions, for example to allow
verification of SV-COMP benchmarks with \divine \cite{SRB16svc}.  The other area
aims at decreasing size of the verification problem without changing the
semantics of the input program.

While the techniques presented here are designed primarily for \divine, their
nature as \llvm transformation allows their application for other model
checkers, or even verifiers using different principles, provided they use \llvm
as an input language and they have support for features required by these
transformations.

In \autoref{chap:llvm} we present \llvm intermediate representation and \llvm
memory model, in \autoref{chap:divine} we present architecture of \divine, and
in \autoref{chap:related} we present other related work. \autoref{chap:trans}
demonstrates how \llvm transformations can be used to extend capabilities of
model checker, in particular by adding weak memory support into \divine as \llvm
transformation, and explores the usage of \llvm transformation for state space
reductions.  In \autoref{chap:results} experimental evaluation of proposed
techniques is given and finally chapter \autoref{chap:conclusion} concludes this
work.
