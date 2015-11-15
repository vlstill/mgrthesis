In this chapter we describe internal architecture of \divine, as of version 3.3,
with main focus on implementation of \llvm verification. More details about
\divine can be found for example in Ph.D. thesis of Petr Ročkai
\cite{RockaiPhD}, or in tool paper introducing \divine 3.0 \cite{DiVinE30}.

For the purposes of this thesis, most of internal architecture of \divine is
irrelevant --- we will focus mostly on \llvm interpreter, which is the only part
directly involved in this work and its architecture is important for
understanding of proposed \llvm-to-\llvm transformations as well as possibility
to use them outside of \divine. We will also describe employed state space
reduction techniques already implemented in \divine.

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
state was reached (in case of safety properties) or the state is accepting in
case of \ltl verification using \buchi automata.

The closed set storage defines a way in which closed set is stored, so that for
given state it can be quickly checked if it was already seen and it is possible
to retrieve algorithm data associated with this state. In \divine two modes of
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
referred to as \llvm interpreter, and bitcode libraries. The interpreter is
responsible for instruction execution, memory allocation and thread handling, as
well as parts of exception handling --- its role is similar to the role of
operating system and hardware. On the other hand, the bitcode libraries provide
higher level functionality for users program --- they implement language support
by the means of standard libraries for C and C++, higher-level threading by the
means of `pthread` library, and to some extend a UNIX-compatible environment,
with simulation of basic filesystem functionality. The libraries use intrinsic
functions provided by the generator to implement low level functionality ---
these functions are akin to system calls in operating systems.

As a terminology, we will denote all the parts implemented in \llvm bitcode,
that is the bitcode libraries together with user-provided code as the
*userspace*, to distinguish it from the interpreter, which is compiled into
\divine. Unlike the interpreter, the userspace can be easily changed, or even
completely replaced without the need to modify and recompile \divine itself and
is closely tied to the language of verified program, while the interpreter is
mostly language agnostic.

## Interpreter

\TODO{...}

### Problem Categories

\label{divine:llvm:problems}


### Intrinsic Functions

Intrinsic functions allow the userspace to communicate with the interpreter, in
order to allocate or free memory, create threads, report errors and so on. These
functions are intended to be used by library writers, not by the user of \divine,
but they are relevant to this work as some of them are used in proposed
transformations. Since these functions are \divine-specific, the transformations
using them would need to be modified, or equivalent functions would have to be
provided should the transformation be used for other tools.


```{.cpp}
int __divine_new_thread( void (*entry)(void *), void *arg );
int __divine_get_tid();
```

The `__divine_new_thread` intrinsic instructs the interpreter to create new
thread, this thread will use `entry` as its entry procedure, which has to accept
singe `void *` argument, the interpreter will pass `arg` to the entry procedure
of new thread. The function returns thread ID used for identification of the new
thread in \divine's interpreter. The `__divine_get_tid` returns \divine thread ID.

When implementing threading primitives, such as those in `pthread` library, in
userspace it required that these are themselves data race free. To facilitate
this, \divine provides way to make atomic section of instructions, and
interpreter takes care that this block of instructions is indeed executed
atomically --- there is only one edge in state space corresponding to
the entire block of instructions, which might include any number of
instructions or even function calls. It is, however, responsibility of the
library writer to use these atomic sections correctly, namely each of these
sections must always terminate, that is, there must be no (possibly) infinite
cycles, such as busy-waiting for variable to be set.

```{.cpp}
void __divine_interrupt_mask();
void __divine_interrupt_unmask();
```

The `__divine_interrupt_mask` function marks start of atomic section, all
actions performed until the atomic section is ends will happen atomically. The
atomic section can end in two ways --- either by explicit call to
`__divine_interrupt_unmask`, or implicitly when function which called
`__divine_interrupt_mask` exits.

When atomic sections are nested (that is, `__divine_interrupt_mask` is called
before the end of previous atomic section), the behavior can be explained by the
means of *mask flag* associated with each call frame --- when
`__divine_interrupt_mask` is called the frame of its caller is marked with mask
flag, which can be reset by call to `__divine_interrupt_unmask`. The instruction
is then part of atomic section if it is executed inside masked frame. If the
executed function is function call, the frame of the callee inherits the mask
flag of the caller. However, when `__divine_interrupt_unmask` is called it
resets mask flag of its caller, leaving mask flags of functions lower in stack
frame unmodified --- that is the current atomic section ends, but if the caller
of `__divine_interrupt_unmask` was not the caller of `__divine_interrupt_mask`,
then a new atomic section will be entered after the caller of
`__divine_interrupt_unmask` exits.

```{.cpp}
void __divine_assert( int value );
void __divine_problem( int type, const char *data );
```
These functions are used for error reporting from the userspace.
`__divine_assert` behaves much like the standard C macro `assert`, if it is
called with nonzero value current state is marked as goal and the problem (see
\autoref{divine:llvm:problems}) is set so that it indicated assertion violation
on the line which called `__divine_assert`. `__divine_problem` unconditionally
reports problem of given category to the interpreter, the report can be
accompanied by error message passed in `data` value.

```{.cpp}
void __divine_ap( int id );
```

`__divine_ap` indicate that atomic proposition represented by `id` holds in
current state, this is always an observable actions. For more details on \ltl in
\divine see \autoref{sec:divine:llvm:ltl}.

```{.cpp}
int __divine_choice( int n, ... );
```

`__divine_choice` is nondeterministic choice, when it is encountered, the
state of the program splits into `n` copies; ecach copy of the state
will see a different return value from `__divine_choice` starting from $0$ up to
$n - 1$. When more than one parameter is given, the choice becomes probabilistic
and the remainting parameters (there must be exactly `n` additional parameters)
give probability distribution of the choices. This can be used for probabilistic
C++ verification \cite{TODO:MUSEPAT}.

```{.cpp}
void *__divine_malloc( unsigned long size );
void __divine_free( void *ptr );
int __divine_heap_object_size( void *ptr );
int __divine_is_private( void *ptr );
```

These are low level heap access functions, `__divine_malloc` allocates new block
of memory of given size, without any alignment. This function does not fail.
`__divine_free` frees a block of memory previously allocated with
`__divine_malloc`. If the block was already freed, problem is reported. If null
pointer is passed to `__divine_free`, nothing is done.

`__divine_heap_object_size` returns allocation size of given object, and
`__divine_is_private` return nonzero if the pointer passed to it is private to
the thread calling this function.

```{.cpp}
void *__divine_memcpy( void *dest, void *src, size_t count );
```

The behavior of `__divine_memcpy` is similar to `memmove` function in standard C
library, that is, it copies `count` bytes from `src` to `dest`, the memory areas
are allowed to overlap. This intrinsic is required due to pointer tracking used
for heap canonization (see \autoref{sec:divine:llvm:heap} for more details).

```{.cpp}
void *__divine_va_start();
```
Variable argument handling. Calling `__divine_va_start` gives a pointer to
a monolithic block of memory that contains all the variadic arguments, successively
assigned higher addresses going from left to right. All the rest of variadic
argument support is implemented in the userspace.

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

These functions and types relate to exception handling. `__divine_unwind`
unwinds all frames between current frame and frame denoted by `frameid`. No
landing pads are triggered in intermediate frames, if there is a landing pads
for active call in the frame in which unwinding ends and any arguments other
then `frameid` were passed to `__divine_unwind`, this landing pad returns
arguments passed to `__divine_unwind`. The `frameid` is $0$ for caller of
`__divine_unwind`, $-1$ for its caller and so on.

`__divine_landingpad` gives information about landing pad of active call in
frame denoted by `frameid`. It returns \TODO{TODO}.


\iffalse
```
/*
 * Exception handling and stack unwinding.
 *
 * To unwind some frames (in the current execution stack, i.e. the current
 * thread), call __divine_unwind. The argument "frameid" gives the id of the
 * frame to unwind to (see also __divine_landingpad). If more than 1 frame is
 * unwound, the intervening frames will NOT run their landing pads.
 *
 * If a landing pad exists for the active call in the frame that we unwind
 * into, the landing pad personality routine gets exactly the arguments passed
 * as varargs to __divine_unwind.
 */
void __divine_unwind( int frameid, ... );

struct _DivineLP_Clause {
    int32_t type_id; // -1 for a filter
    void *tag; /* either a pointer to an array constant for a filter, or a
                  typeinfo pointer for catch */
} __attribute__((packed));

struct _DivineLP_Info {
    int32_t cleanup; /* whether the cleanup flag is present on the landingpad */
    int32_t clause_count;
    void *personality;
    struct _DivineLP_Clause clause[];
} __attribute__((packed));

/*
 * The LPInfo data will be garbage-collected when it is no longer
 * referenced. The info returned reflects the landingpad LLVM instruction: each
 * LPClause is either a "catch" or a "filter". The frameid is either an
 * absolute frame number counted from 1 upwards through the call stack, or a
 * relative frame number counted from 0 downwards (0 being the caller of
 * __divine_landingpad, -1 its caller, etc.). Returns NULL if the active call
 * in the given frame has no landing pad.
 */
struct _DivineLP_Info *__divine_landingpad( int frameid );
```
\fi

## Userspace

# Reduction Techniques

## $\tau+$ and Heap Reductions

*   \cite{RBB13} $\tau+$

## \Tc

*   \cite{RSB15} tree

## \ltl

\label{sec:divine:llvm:ltl}

# \lart
