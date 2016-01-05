

# Preprocessing 


# Relaxed Memory Models

In modern CPUs, a write to memory location need not be immediately visible in
other threads, for example due to caches or out-of-order execution. However most
of the verification tools, including \divine, do not directly support
verification with these relaxed memory models, instead they assume *sequential
consistency*, that is immediate visibility of any write to memory.

In Total Store Order memory model (which was used as basis for \cite{SRB15}),
any write can be delayed infinitely but the order in which writes done by one
thread become visible in other threads must match their execution order. This
memory model can be simulated by store buffer. 

The transformation presented in \cite{SRB15} implements under-approximation of
TSO using bounded store buffer. In this case the buffer size is limited and if
an entry is to be written into full store buffer, the oldest entry from the
buffer is flushed into memory. With this limited store buffer the transformation
can be reasonably implemented, and the resulting state space is finite if the
state space of the original program was finite, therefore this transformation is
suitable for explicit state model checking.

The main limitation of the transformation proposed in \cite{SRB15} is that it
does not fully support \llvm atomic instructions with other that sequential
consistency ordering and it supports only TSO ordering. On the other hand the
extended version proposed in this work does support all atomic ordering
supported by \llvm and it does not implement TSO, instead it simulates memory
model of \llvm and allows specification of which guarantees should be added to
this memory model.


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
