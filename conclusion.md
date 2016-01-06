We showed that \llvm transformations are useful preprocessing step for model
checking of real-world programs, namely in verification of C and C++ using
\divine explicit-state model checker. We showed that \llvm transformations are
usable in many ways, both to extend verifier's abilities and to decrease size of
verification problem.

We proposed and implemented an instrumentation which adds under-approximation of
\llvm memory models into a program in such a way that the result can be verified
with \divine. This transformation allows verification of program under \llvm
memory model on an unmodified verifier which assumes sequential consistency.
This transformation extends the one presented in \cite{SRB15} is number of ways,
namely it supports parametrized memory models, including memory models weaker
that total store order, it fully supports \llvm atomic instructions (and
therefore C++11 atomic library), and it is up to several orders of magnitude
more efficient than the version in \cite{SRB15}. Despite the state space
explosion, which is even more pronounced for programs with relaxed memory
models, we were able to verify several benchmarks, including unit tests
of real-world data structures.

We also showed usefulness of \llvm transformations on the case of annotated
atomic functions, and on adaptation of SV-COMP benchmarks to \divine.

In the case of state space reductions, we proposed the use of \llvm
optimizations which do not change behavior of parallel programs and do not
increase state space size. We proposed and implemented a few such optimizations
and evaluated them. We showed that some of these transformations, namely lifting
of local variables into registers, can significantly reduce state space size.

While working on this thesis, we also uncovered bug in implementation of
\divine's $\tau+$ state space reductions and found cases in which these
reductions could be improved. These improvements were implemented and evaluated,
they turned to have significant impact.

The proposed extensions, namely instrumentation for weak memory models, as well
as some of the reductions techniques will be included in the next version of
\divine.

# Future Work

There is a lot of future work in the field of \llvm transformations as a
preprocessing step for verification of real-world code and we would like to
continue to work in this field.

Efficient verification with weak memory models is still somewhat problematic and
we believe that there is still room for improvement of transformation technique.
Namely, static detection of thread-local memory locations, for example using pointer
analysis could prove to be useful in reducing state space size of programs with
weak memory model simulation as accesses to such memory locations need not be
instrumented with memory model. The results also show that difference between
total store order and partial store order simulation is not as big as expected
which suggests that total store order simulation could be improved.

Further extensions of \divine's abilities using \llvm transformations are also
part of future work. One such possibility is use of abstractions which was
proposed in \cite{RockaiPhD}, another is integration of
control-explicit-data-symbolic approach to model checking into \divine with the
help of \llvm transformations.

Finally, more advanced optimization techniques should be evaluated in the field
of state space reductions. One example of such technique is dealing with control
flow loops which do not cause infinite loops in the program. Also, slicing,
static partial order reduction, and symmetry reduction could be useful for state
space reduction.
