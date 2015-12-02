With modern multi-core CPUs, multi-threaded programs are increasingly common and
therefore their correctness, or at least bug finding in such programs is common
concern. However testing of multi-threaded programs lacks well established
deterministic procedure --- which common techniques, such as unit testing, are
applicable to parallel programs, they are unable to reliably find bugs caused by
data races. The reason is that such bugs occur only if certain conditions are
met, namely threads are interleaved in order which exposes this data race.

Explicit-state model checking[^esmc] is a technique which can help in this regard ---
it allows us to explore all possible interleavings of parallel programs. While
pure explicit-state model checking requires programs to be closed (not have any
inputs) it is still very helpful --- it can be applied for example to unit
tests and this combination yields deterministic testing procedure for parallel
programs. Furthermore, there are techniques, such as
control-explicit-data-symbolic model checking \cite{BBH14}, which allow
application of model checking to parallel programs with inputs.

[^esmc]: Introduction to explicit-state model checking and automata based
approach to \ltl verification can be found in \cite{Clarke2000MC}.

For model checking to be useful to software developer it is important to
minimize any extra effort the developer has to put into usage of such tool.
Historically this effort was large --- older generations of verifiers such as
\TODO{doplnit: SPIN, LTSmin,…} required translation of the verified program into
a modelling language such as \TODO{promela,…}. With new generation of verifiers,
such as \divine, CBMC, \TODO{…} special-purpose language for verification is no
longer required --- these tools support direct verification of widely used
programming languages such as C, C++, and Java, either directly or using \llvm
intermediate representation (an intermediate language used in translation of
many programming languages, including C and C++).

\llvm IR in particular is becoming input language of choice for many verification
tools --- this assembly-like language is simpler to work with than higher level
languages, yet it maintains platform independence, compact instruction set, and
useful abstractions such as type information and unbounded number of registers
which make it easier to analyze than machine code. Furthermore \llvm IR
comes with large library for manipulation and optimization.

In this work we demonstrate that \llvm transformations are useful technique
which can aid verification of real-world programs, more specifically, we focus
on model checking of C and C++ using \divine \cite{DiVinE30} --- a well
established explicit-state model checker, aiming primarily at verification of
unmodified C and C++ code using \llvm intermediate representation as its input.
\divine aims to have full support of language features for C++ including for
example exception handling --- a feature often omitted by other C++ verifiers.
Furthermore \divine provides near complete implementation of C and C++ standard
library including features of newest C++14 standard and `pthread` threading
library. In this way, \divine can often be directly applied to verification of
real-world code provided it does not use inputs or platform specific features
such as calls into the kernel of operating system.

We will present two case studies of using \llvm transformations to aid model
checking --- one is enriching input programs with weak memory models such that
these can be verified using model checker which assumes sequential consistency.
The other case study aims at decreasing size of the verification problem without
changing the semantics of the input program.

While the techniques presented here are aimed primarily for \divine, their
nature as \llvm transformation allows their application for other model
checkers, or even verifiers using different principles, provided they use \llvm
as an input language and they have support for features required by these
transformations.

In \autoref{chap:llvm} we present \llvm intermediate representation, in
\autoref{chap:divine} we present architecture of the \divine model checker, in
\autoref{chap:related} we \TODO{…}, \autoref{chap:extend} demonstrates how \llvm
transformations can be used to extend capabilities of model checker, in
particular by adding weak memory support into \divine as \llvm transformation,
\autoref{chap:reduce} explores usage of \llvm transformation for state space
reductions, and finally chapter \autoref{chap:conclusion} concludes this work.
