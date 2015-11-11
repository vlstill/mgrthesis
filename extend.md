# Weak Memory Models

\cite{SRB15}

## Invalidated Variable Store Problem

\label{sec:extend:wm:invstore}

# Local Variable Cleanup

It is often necessary to perform cleaning operation at the end of the scope of
a local variable, one of these cases is mentioned in
\autoref{sec:extend:wm:invstore}, another can arise from compiled-in
abstractions proposed in \cite{RockaiPhD}. These variable cleanups are
essentially akin to C++ destructors in a sense that they get executed at the end
of scope of the variable, no matter how this happens, with only exception of
thread termination.

Implementing variable cleanups for languages without exception handling, such as
C, would be fairly straight-forward --- it is sufficient to run cleanup just
before function returns and clean-up any local variables from which this
particular return point is reachable. In presence of exception handling, such as
in case of C++, the situation is more complicated. Since we target C++ and allow
programs with exception we will now focus on this case, through the lens of
\llvm representation of exception handling (for details on \llvm exception
handling see \autoref{sec:llvm:eh}.

Here we need to make sure that cleanup runs not only in the case of normal exit
from a function by the means of return instruction, but also when the function
is exited by stack unwinding, that is while exception is being propagated.
Furthermore, we need to make sure our cleanup handling does not interfere with
already present exception handling in the function, should there be any. This
can be done in two phases --- it is necessary to convert any calls of functions
which can throw an exception so that any exception can be caught (and re-thrown
if it was not handled originally), and then a cleanup code needs to be added
into appropriate location in the exception handling path and normal function
exit path.

## Call Instrumentation

For the first phase it is sufficient to convert any `call` instruction for which
we cannot show that the callee cannot throw an exception into `invoke`
instruction, which allows as to branch out into a landing block if an
exception is thrown by the callee. The `landingpad` in the landing block need to
be set up in a way in can caught any exception (this can be done using `cleanup`
flag for `landingpad`). The instrumentation can be done as follows:

*   for a call site, if it is a `call`:

    1.  given a `call` instruction to be converted, split its parent basic block
        into two just after this instruction (we will call these blocks *invoke
        block* and *invoke-ok* block),
    2.  add a new basic block for cleanup, this block will contain a `landingpad`
        instruction with `cleanup` flag and a `resume` instruction (we will call
        this block *invoke-unwind block*),
    3.  replace the `call` instruction with `invoke` with the same function and
        parameters, its normal destination is set to *invoke-ok block* and its
        unwind destionation is set to *invoke-unwind block*,

*   otherwise, if it is an `invoke` and its unwind block does not contain `cleanup`
    flag in `landingpad`:
    1.  create new basic block containing just resume instruction (*resume
        block*)
    2.  add `cleanup` flag into `landingpad` of the unwind block of the `invoke` and
        branch into *resume block* if landing block is triggered due to
        `cleanup`.

Any calls using `call` instruction with known destination which is a function
marked with `nounwind` attribute will not be modified. Functions marked with
`nounwind` need to be checked for exceptions as \llvm states that these
functions should never throw an exception and therefore we assume that throwing
and exception from such a function will be reported as an error by the verifier
\TODO{specifikovat někde, že je to požadavek na verifikátor}.

```{.llvm}
TODO: příklad
%1 = call
```

\TODO{popis příkladu}

After the call instrumentation the following holds: every time the function is
entered by stack unwinding due to active exception, the control is transfered to
a landing block and, if before this transformation the exception would not be
intercepted by `landingpad` in this function, after the transformation 
the same exception would be rethrown by `resume`.

## Adding Exception Handling Cleanup

The exception handling, which begins in the landing block, can perform two
types of action --- it can either perform cleanup and re-throw the exception
(using `resume` instruction), or catch the exception (using language-dependent
mechanism), and resume normal operation. It can also do combination of these
actions based on the type of the exception. However, it is not necessary to
analyze the exception handling mechanism in the function, instead it is
sufficient to add cleanup code just before any `resume` and `return`
instruction, such that this code will clean all local variables which can reach
this function termination.

In order for the cleanup code to work, it needs to be able to access all local
variables define before the associated function exit, that is results of all
`alloca` instructions from which this exit can be reached. However, this might
not be always true:

```
entry:
  %x = alloca i32, align 4
  store i32 1, i32* %x, align 4
  %0 = load i32, i32* %x, align 4
  %cmp = icmp eq i32 %0, 0
  br i1 %cmp, label %if.then, label %if.end

if.then: ; preds = %entry
  %y = alloca i32, align 4
  store i32 1, i32* %y, align 4
  br label %if.end

if.end:  ; preds = %if.then, %entry
  ; cleanup will be inserted here
  ret i32 0
```

In this example, `%y` is defined in `if.then` basic block, but it needs to be
cleared just before the `return` instruction at the end of `if.end` basic block,
and the definition of `%y` does not dominate the cleaning point. The cleanup
cannot be, in general, safely inserted after last use \TODO{zdůvodnit --
nerozhodnutelné}. For this reason we will first insert $\phi$-nodes in such a
way that any `alloca` is represented in any block which it can reach --- either
by its value if the control did pass the `alloca` instruction, or by `null`
constant if the control did not pass it. For our example the result of the
modification would be the following (just last basic block is modified):

```
if.end:  ; preds = %if.then, %entry
  %y.phi = phi i32* [ null, %entry ], [ %y, %if.then ];
  ; cleanup will be inserted here
  ret i32 0
```

In this example, `%y.phi` represents `%y` at the cleanup point --- it can be
either equal to `%y` if control passed through definition of `%y`, or `null`
otherwise.

\TODO{Those phi nodes can be added by simple algorithm which traverses BBs in
DFS order…}

# Atomic Functions and Instructions
