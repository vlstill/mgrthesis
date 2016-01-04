# Preprocessing 


# Relaxed Memory Models

The related work for verification of relaxed memory models is described in more
details in \cite{SRB15}. As for memory models, the actual memory models
implemented in hardware differ with CPU vendors, or even particular models of
CPUs and are usually not publicly available. For these reasons it would not be
practical and feasible to verify programs with regard to a particular
implementation of real-world memory model. Theoretical memory models which were
proposed to allow analysis of programs under relaxed memory models, namely
*Total Store Order* (TSO) \cite{SPARC94}, *Partial Store Order* (PSO)
\cite{SPARC94}.  Also, \llvm defines a memory model for atomic instructions
which is described in \autoref{sec:llvm:atomic}.

These memory models are usually described as constraints to allowed reordering
of instructions which manipulate with memory.  In those theoretical models, an
update may be deferred for an infinite amount of time.  Therefore, even a finite
state program that is instrumented with a possibly infinite delay of an update
may exhibit an infinite state space. It has been proven that for such an
instrumented program, the problem of reachability of a particular system
configuration is decidable, but the problem of repeated reachability of a given
system configuration is not \cite{Atig:2010:VPW:1706299.1706303}.
