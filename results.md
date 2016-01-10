
In this chapter we will evaluate the transformations proposed in
\autoref{chap:trans}. All measurements were done on Linux on `x86_64` machines
with enough memory to run verification of the program in question. All numbers
are taken from \divine's report (`--report` was passed to the `verify` command).
Number of states is `States-Visited` from the report, which is the number of
unique states in the state space of the program; memory usage is `Memory-Used`
from the report, which is the peak of the total memory used during the
verification. All measurements were performed with the lossless tree compression
enabled (`--compression`) \cite{RSB15} and, unless explicitly stated otherwise,
the default setting of $\tau+$ reduction (which includes the changes described
in \autoref{sec:trans:tauextend}).

Please note that the results in cases when the property does not hold depend
on the timing and number of processors used for the evaluation. To make these
results distinguishable, they are set in italics. Programs used in the
evaluation are described in \autoref{tab:res:models}.

\begin{table}
\begin{tabularx}{\textwidth}{|lX|} \hline
\texttt{simple} & A program similar to the one in \autoref{fig:trans:wm:sb}; two
threads, each of them reads a value written by the other one. An assertion violation
can be detected with total store order. Written in C++; does not use C++11 atomics. \\
\hline
\texttt{peterson} & A version of the well-known Peterson's mutual exclusion
algorithm; valid under sequential consistency, not valid under total store order
or any more relaxed model. Written in C++, no C++11 atomics. \\
\hline
\texttt{fifo} & A fast communication queue for producer-consumer use with one
producer and one consumer. This queue is used in \divine when running in a distributed
environment. The queue is designed for \texttt{x86}; it is correct unless stores can be
reordered. Written in C++, the queue itself does not use C++11 atomics, the unit
test does use one relaxed (\textit{monotonic}) atomic variable. \\
\hline
\texttt{fifo-at} & A modification of \texttt{fifo} which uses C++11 atomics to
ensure it works with memory models more relaxed than TSO. \\
\hline
\texttt{fifo-bug} & An older version of \texttt{fifo} which contains a data
race. \\
\hline
\texttt{hs-$T$-$N$-$E$} & A hight-performance, lock-free shared memory memory
hash table used in \divine in shared memory setup~\cite{BRSW15}. Written in C++,
uses C++11 atomics heavily, mostly with the \textit{sequentially consistent} ordering.
This model is parametrized; $T$ is the number of threads, $N$ is the number of
elements inserted by each thread (elements inserted by each thread are
distinct), and $E$ is the number of extra elements which are inserted by two
threads. \\
\hline
\texttt{pt-rwlock} & A test for a reader-writer lock in C. \\
\hline
\texttt{collision} & A collision avoidance protocol written in C++, described in
\cite{Jensen96modellingand}. \\
\hline
\texttt{lead-dkr} & A leader election algorithm written in C++, described in \cite{dolev:an}. \\
\hline
\texttt{elevator2} & This model is a C++ version of the elevator model from the
BEEM database \cite{beem}. It is a simulation of elevator planning. \\
\hline
\end{tabularx}
\caption{Description of programs used in the evaluation.}
\label{tab:res:models}
\end{table}

# Extensions of $\tau+$ Reduction

\label{sec:res:tau}

\autoref{tab:res:tau} shows state space sizes of several models with the
original $\tau+$ reduction and with the extensions described in
\autoref{sec:trans:tauextend}. It also includes state space sizes in \divine
3.3, which is the version before any modification described in this thesis.
While both \divine 3.3 and the new version with the original reduction implement
the same reduction strategy the numbers can differ because of bugs which were
fixed since \divine 3.3. The first bug is that \divine 3.3 never considered
`memcpy` to be visible operation, which could cause some runs to be missed; with
this bug fixed, the state space size can grow. The second bug is that if a
visible instruction is at the beginning of a basic block, \divine 3.3 emitted a
state immediately after this instruction; fixing this bug could cause state
space size to decrease. Finally, there was a bug in the calculation of
visibility of a memory location; this information was improperly cached even
over operations which could change the value.

We can see in the table that in all but one case, the extended $\tau+$ reduction
performs better then \divine 3.3 and in all cases it performs better than the
implementation of the original reduction in the new version of \divine. The one
difference is `lead-dkr`, the reason is that this program uses `memcpy` heavily
and therefore is affected by the bug fix. If we consider the fixed
implementation as the baseline for `lead-dkr`, the new reduction represents a
$2.27\times$ improvement.  Overall, the improvement was $1.05\times$ to
$3.18\times$ for benchmarked models, which is a good improvement on the already
heavy reduction of the original $\tau+$.  We can also see that the independent
loads optimization has a higher impact than the control flow loop detection
optimization, but the latter still provides a measurable improvement (up to
$1.5\times$ reduction).

\begin{table}[tp]
\begin{tabularx}{\textwidth}{|l|C|CCCC|C|} \hline
Name & \divine 3.3 & Old & + Control Flow & + Indep. Load & New & Reduction \\ \hline
\texttt{fifo}      &     \si{1836} &     \si{1793} &     \si{1767} &     \si{793}  &     \bf\si{791}  & \speedup{1836}{791} \\
\texttt{fifo-bug}  &     \textit{\si{6641}} &     \textit{\si{6614}} &     \textit{\si{6454}} &     \textit{\si{2882}} &     \textit{\textbf{\si{2876}}} & \speedup{6641}{2876} \\
\texttt{lead-dkr}  &    \si{29921} &   \si{131715} &   \si{131712} &    \si{58151} &    \bf\si{58148} & \speedup{29921}{58148} \\
\texttt{collision} &  \si{3064791} &  \si{3280980} &  \si{3280978} &  \si{1960480} &  \bf\si{1960478} & \speedup{3064791}{1960478} \\
% \texttt{lead-basic} &  19.3\,k & \\ % OLD = 19341906
% \texttt{lead-peters} &  12.3\,k & \\ % OLD = 12282933
\texttt{pt-rwlock} & \si{14237025} & \si{14237027} &  \si{8661079} &  \si{6542607} &  \bf\si{4476710} & \speedup{14237025}{4476710} \\
\texttt{elevator2} & \si{18567508} & \si{18233787} & \si{18233786} & \si{17720079} & \bf\si{17720078} & \speedup{18567508}{17720078} \\
\texttt{hs-2-1-0}  & \it error     &  \si{1875067} &  \si{1873150} &  \si{1008098} &   \bf\si{890973} & \speedup{1875067}{890973} \\
\texttt{hs-2-1-1}  & \it error     &  \si{2871440} &  \si{2869311} &  \si{1505397} &  \bf\si{1341117} & \speedup{2871440}{1341117} \\
\texttt{hs-2-2-2}  & \it error     &  \si{4990846} &  \si{4988242} &  \si{2622816} &  \bf\si{2328550} & \speedup{4990846}{2328550} \\ \hline
\end{tabularx}

\caption{Evaluation of the improved $\tau+$ reduction. \divine 3.3 is used as a
reference, as it does not include any changes described in this thesis.
\textit{Old} corresponds to the original $\tau+$ reduction with several
bugfixes, \textit{+ Control Flow} includes control flow loop detection
optimization, \textit{+ Indep. Load} includes independent loads optimization,
\textit{New} includes both optimizations. \divine 3.3 was not able to verify
the hash set benchmarks.}
\label{tab:res:tau}
\end{table}

# Weak Memory Models

\label{sec:res:wm}

We evaluated relaxed memory models on the same benchmarks as in \cite{SRB15} and
additionally on a unit test for a concurrent hash table (`hs-2-1-0`). We used
Context-Switch-Directed-Reachability algorithm \cite{SRB14} in all weak memory
model evaluations, as it tends to find bugs in programs with weak memory models
faster (it explores runs with fewer context switches and therefore less store
buffer flushing earlier).

\autoref{tab:res:wm} shows state space sizes for programs with weak memory model
simulation and compares it to the state space size of the original program. We
can see that the size increase varies largely, but the increase is quite large,
anywhere from $7\times$ to $282\times$ increase for a store buffer with only one
slot. We can also see that the difference between total store order and more
relaxed memory models is not as significant as the store buffer size increase,
which suggests there is still a room for optimization of the TSO simulation.
Benchmark `hs-2-1-0` shows that the weak memory model simulation is not yet
easily applicable to more complex real-world code; in this case the verification
required \dmem{32585028} of memory and almost half a day of runtime on 48 cores,
while larger versions of this model did not fit into a $100\,\text{GB}$ memory
limit.  Nevertheless, for smaller real-world tests, such as `fifo`, the weak
memory model simulation can be used even on a common laptop.

\begin{table}[tp]
\begin{tabularx}{\textwidth}{|l|C|CCC|CCC|} \hline
Name  & SC & \multicolumn{3}{c|}{TSO} & \multicolumn{3}{c|}{TSO: Size Increase} \\
  & - & 1 & 2 & 3 & 1 & 2 & 3 \\ \hline
\texttt{simple}   &    \si{127} & \it\si{3445} & \it\si{5973} & \it\si{15663} & \speedup{3445}{127} & \speedup{5973}{127} & \speedup{15663}{127} \\
\texttt{peterson} &    \si{703} & \it\si{21837} & \it\si{53443} & \it\si{55665} & \speedup{21837}{703} & \speedup{53443}{703} & \speedup{55665}{703} \\
\texttt{fifo}     &    \si{791} & \si{14892} & \si{35865} & \si{48787} & \speedup{14892}{791} & \speedup{35865}{791} & \speedup{48787}{791} \\
\texttt{fifo-at}  &    \si{717} & \si{39539} & \si{166621} & \si{497229} & \speedup{39539}{717} & \speedup{166621}{717} & \speedup{497229}{717} \\
\texttt{fifo-bug} &\it\si{1611} & \it\si{11291} & \it\si{44192} & \it\si{68655} & \speedup{11291}{1611} & \speedup{44192}{1611} & \speedup{68655}{1611} \\
\texttt{hs-2-1-0} & \si{890973} & \si{250390514} & -- & -- & \speedup{250390514}{890973} & -- & -- \\ \hline % 251\,M & & \\ \hline
\end{tabularx}

\par\medskip\par

\begin{tabularx}{\textwidth}{|l|C|CCC|CCC|} \hline
Name  & SC & \multicolumn{3}{c|}{STD} & \multicolumn{3}{c|}{STD: Size Increase} \\
  & - & 1 & 2 & 3 & 1 & 2 & 3 \\ \hline
\texttt{simple}   &    \si{127} & \it\si{3522} & \it\si{8072} & \it\si{23609} & \speedup{3522}{127} & \speedup{8072}{127} & \speedup{23609}{127} \\
\texttt{peterson} &    \si{703} & \it\si{21981} & \it\si{56336} & \it\si{69787} & \speedup{21981}{703} & \speedup{56336}{703} & \speedup{69787}{703} \\
\texttt{fifo}     &    \si{791} & \si{18297} & \it\si{15648} & \it\si{22985} & \speedup{18297}{791} & \speedup{15648}{791} & \speedup{22985}{791} \\
\texttt{fifo-at}  &    \si{717} & \si{53498} & \si{255636} & \si{1067735} & \speedup{53498}{717} & \speedup{255636}{717} & \speedup{1067735}{717} \\
\texttt{fifo-bug} &\it\si{1611} & \it\si{12131} & \it\si{14142} & \it\si{21098} & \speedup{12131}{1611} & \speedup{14142}{1611} & \speedup{21098}{1611} \\
\texttt{hs-2-1-0} & \si{890973} & \si{251249798} & -- & -- & \speedup{251249798}{890973} & -- & -- \\ \hline
\end{tabularx}
\caption{A summary of the number of states in the state space for different weak
memory simulation settings. The first line specifies the memory model
(\textit{SC} = Sequential Consistency, that is no transformation, \textit{TSO} =
Total Store Order, \textit{STD} = the \llvm memory model. The second line gives
store buffer size.}
\label{tab:res:wm}
\end{table}

## Effects of Optimizations

The optimizations described in \autoref{sec:trans:wm:tau} were first evaluated
in the context of the TSO memory model simulation presented in \cite{SRB15}. The
results of this initial evaluation can be seen in \autoref{tab:res:wm:opt:old}.
This evaluation does not include any changes in $\tau+$ reduction. We can see
that the effects of the optimizations are significant, especially for private
loads optimization.

\begin{table}[tp]
\begin{tabularx}{\textwidth}{|l|c|CC|CC|} \hline
Name                & MEMICS & \multicolumn{2}{c|}{$+$ Load Private} & \multicolumn{2}{c|}{$+$ Locals} \\ 
\hline
\texttt{fifo-1}      & $44$ M  & $5.6$ M & $7.9\times$  & $1.2$ M & $36\times$ \\
\texttt{fifo-2}      & $338$ M & $51$ M  & $6.6\times$   & $11$ M & $30\times$ \\
\texttt{fifo-3}      & $672$ M & $51$ M  & $13\times$    & $11$ M & $60\times$  \\
\texttt{simple-1}    & $538$ K & $19$ K  & $28\times$   & $11$ K & $48\times$ \\
\texttt{peterson-2}  & $103$ K & $40$ K  & $2.6\times$   & $24$ K & $4.1\times$ \\
\texttt{pt\_mutex-2} & $1.6$ M & $12$ K  & $135\times$ & $7.5$ K & $216\times$ \\ \hline
\end{tabularx}

\caption{Effects of private load optimization and local private variable
optimization on the implementation from \cite{SRB15}. The number after model
name is store buffer size. The \textit{MEMICS} column contains state space size
for the original transformation, \textit{+ Load Private} contains state space
size and reduction over \textit{MEMICS} for the optimization which bypasses
store buffers for thread-private memory locations, \textit{+ Locals} also
includes the optimization which does not transform manipulations with local
variables which do not escape scope of the function.}
\label{tab:res:wm:opt:old}
\end{table}

The same optimizations were evaluated in the final version of the
transformation, these results can be seen in \autoref{tab:res:wm:opt}. Please
note that while the original transformation bypassed store buffers for
thread-private stores, the version proposed in this work does not, as this
optimization is not correct for the \llvm memory model. Nevertheless, the new
version performs an order of magnitude better in all cases, both thanks to
enhanced state space reductions and more efficient implementation.[^efimpl]

[^efimpl]: Namely, the flusher thread is now implemented in such a way that is
is guaranteed that if the store buffer associated with it contains a single
entry and this entry is flushed, the resulting state of the flusher thread will
be the same as the state of the flusher thread before the first entry is
inserted into the store buffer.

We can see that the effect of the optimizations of the store buffer
implementation varies significantly, but overall the improvement is around three
times reduction, with peak for `fifo-at` which exhibits up to several hundred
times reduction. This suggests that these reductions can have stronger effects on
bigger programs. However, due to time and resource constraints, we were not able
to verify this hypothesis with more large programs.

\begin{table}
\newcommand{\tline}[3]{\directlua{tex.sprint( wmoptline( "\luatexluaescapestring{#1}", { #2 }, "\luatexluaescapestring{#3}" ) )}}
\begin{tabularx}{\textwidth}{|l|C|CC|CC|} \hline
Name & No opt. & \multicolumn{2}{c|}{+ Locals} & \multicolumn{2}{c|}{+ Load Private} \\ \hline
\tline{simple-tso-1}{16514, 16511, 3445}{it} \\
\tline{simple-tso-2}{29260, 29260, 5973}{it} \\
\tline{simple-tso-3}{42024, 42024, 15663}{it} \\
\tline{simple-std-1}{16564, 16569, 3522}{it} \\
\tline{simple-std-2}{29788, 29786, 8072}{it} \\
\tline{simple-std-3}{51585, 51587, 23609}{it} \\
\hline
\tline{peterson-tso-1}{59959, 59894, 21837}{it} \\
\tline{peterson-tso-2}{149086, 149163, 53443}{it} \\
\tline{peterson-tso-3}{143901, 144025, 55665}{it} \\
\tline{peterson-std-1}{60158, 60167, 21981}{it} \\
\tline{peterson-std-2}{153511, 153523, 56336}{it} \\
\tline{peterson-std-3}{168426, 168449, 69787}{it} \\
\hline
\tline{fifo-tso-1}{43490, 43490, 14892}{} \\
\tline{fifo-tso-2}{110338, 110338, 35865}{} \\
\tline{fifo-tso-3}{159136, 159136, 48787}{} \\
\tline{fifo-std-1}{53170, 53170, 18297}{} \\
\tline{fifo-std-2}{45535, 46446, 15648}{it} \\
\tline{fifo-std-3}{74687, 74860, 22985}{it} \\
\hline
\tline{fifo-at-tso-1}{313602, 121400, 39539}{} \\
\tline{fifo-at-tso-2}{1106884, 522311, 166621}{} \\
\tline{fifo-at-tso-3}{5462435, 1458590, 497229}{} \\
\tline{fifo-at-std-1}{432828, 166382, 53498}{} \\
\tline{fifo-at-std-2}{32206999, 739349, 255636}{} \\
\tline{fifo-at-std-3}{0, 2795055, 1067735}{} \\
\hline
\tline{fifo-bug-tso-1}{34113, 35880, 11291}{it} \\
\tline{fifo-bug-tso-2}{140647, 140779, 44192}{it} \\
\tline{fifo-bug-tso-3}{220170, 217630, 68655}{it} \\
\tline{fifo-bug-std-1}{37298, 34473, 12131}{it} \\
\tline{fifo-bug-std-2}{43853, 43735, 14142}{it} \\
\tline{fifo-bug-std-3}{69906, 69809, 21098}{it} \\
\hline
\end{tabularx}

\caption{Effects of private load optimization and local private variable
optimization on the \llvm memory model simulation. The \textit{No opt.} column
includes none of the optimizations from \autoref{sec:trans:wm:tau}, \textit{+
Locals} does not instrument stores into local variables which do not escape the
scope of the function, and \textit{+ Load Private} also bypasses store buffers
for loads from memory which is considered thread-private by \divine.}
\label{tab:res:wm:opt}
\end{table}

\autoref{tab:res:wm:tau} shows effects of extended $\tau+$ reduction on the
\llvm memory model simulation. We can see that while the overall reduction is
similar to the effects of the improved $\tau+$ reduction on programs without the
memory model simulation, the reason is different. In this case, the improvement
is thanks to the improved control flow cycle detection mechanism and the
independent loads optimization has no effect. The cause is that `load`, `store`,
and `fence` instructions are replaced with calls, and without the control flow
cycle detection improvement it was not possible to perform two calls to the same
function on one edge in the state space.

\begin{table}
\newcommand{\tline}[3]{\directlua{tex.sprint( wmtauline( "\luatexluaescapestring{#1}", { #2 }, "\luatexluaescapestring{#3}" ) )}}
\begin{tabularx}{\textwidth}{|l|CCCC|C|} \hline
Name & Orig. $\tau+$ & + Control Flow & + Indep. Loads & New & Reduction \\
\hline
\tline{simple-tso-1}{5877, 3447, 5877, 3447}{it} \\
\tline{simple-tso-2}{10897, 5973, 10897, 5973}{it} \\
\tline{simple-tso-3}{24600, 15661, 24600, 15661}{it} \\
\tline{simple-std-1}{5904, 3522, 5904, 3522}{it} \\
\tline{simple-std-2}{13406, 8070, 13406, 8070}{it} \\
\tline{simple-std-3}{32449, 23615, 32449, 23615}{it} \\
\hline
\tline{peterson-tso-1}{25441, 21900, 25441, 21900}{it} \\
\tline{peterson-tso-2}{62950, 53419, 62950, 53419}{it} \\
\tline{peterson-tso-3}{65669, 55674, 65669, 55674}{it} \\
\tline{peterson-std-1}{25499, 21956, 25499, 21956}{it} \\
\tline{peterson-std-2}{66354, 56431, 66354, 56431}{it} \\
\tline{peterson-std-3}{81426, 69766, 81426, 69766}{it} \\
\hline
\tline{fifo-tso-1}{39141, 14892, 39141, 14892}{} \\
\tline{fifo-tso-2}{100468, 35865, 100468, 35865}{} \\
\tline{fifo-tso-3}{143871, 48787, 143871, 48787}{} \\
\tline{fifo-std-1}{48299, 18297, 48299, 18297}{} \\
\tline{fifo-std-2}{41630, 15733, 41630, 15733}{it} \\
\tline{fifo-std-3}{66079, 23375, 66079, 23375}{it} \\
\hline
\tline{fifo-at-tso-1}{114408, 39539, 114408, 39539}{} \\
\tline{fifo-at-tso-2}{489844, 166621, 489844, 166621}{} \\
\tline{fifo-at-tso-3}{1385531, 497229, 1385531, 497229}{} \\
\tline{fifo-at-std-1}{156846, 53498, 156846, 53498}{} \\
\tline{fifo-at-std-2}{703852, 255636, 703852, 255636}{} \\
\tline{fifo-at-std-3}{2633275, 1067735, 2633275, 1067735}{} \\
\hline
\tline{fifo-bug-tso-1}{32400, 11910, 32400, 11910}{it} \\
\tline{fifo-bug-tso-2}{128797, 45475, 128797, 45475}{it} \\
\tline{fifo-bug-tso-3}{200865, 66402, 200865, 66402}{it} \\
\tline{fifo-bug-std-1}{33682, 12077, 33682, 12077}{it} \\
\tline{fifo-bug-std-2}{39795, 14161, 39795, 14161}{it} \\
\tline{fifo-bug-std-3}{62985, 21467, 62985, 21467}{it} \\
\hline
\end{tabularx}

\caption{Effects of extended $\tau+$ reduction on the \llvm memory model
simulation. \textit{Reduction} shows the best achieved reduction.}
\label{tab:res:wm:tau}
\end{table}

# \llvm IR Optimizations

\label{sec:res:opt}

We also evaluated transformations intended for state space reduction presented in
\autoref{sec:trans:opt}. Namely, constant local variable elimination
(\autoref{sec:trans:opt:local}, const `alloca` in tables, the `paropt` pass in
\lart), constant global variable annotation (\autoref{sec:trans:opt:global},
cost global in tables, the `globals` pass in \lart), register zeroing
(\autoref{sec:trans:opt:lzero}, register zero in tables, the `register` pass in
\lart) and an older version of register zeroing pass which zeroes only values of
local variables (`alloca` zero in tables, the `alloca` pass in \lart). We also
evaluated combinations of these optimizations. Please note that the order of the
combination of these passes matter, constant local variable elimination must
precede register (or local variable) zeroing. Constant global variable
annotation does not interfere with any of the other reductions.

In \autoref{tab:res:opt:st} we can see the effect of these optimizations on the
state space size. The only optimization with visible effect on state space size
is constant local variable elimination. The effect of constant local variable
elimination in not large and it is likely due to elimination of some registers
which could have been used to distinguish otherwise equivalent states.

In \autoref{tab:res:opt:mem} we can see the effect of the same optimizations on
memory required for verification with lossless compression of the state space.
While these values are subject to some variations caused by the used compression
technique,[^tc] we can see that memory-wise the reductions have bigger effect.
Namely, we can see that constant global variable annotation has a positive
effect on memory requirements.

[^tc]: We use tree compression \cite{RSB15}. The efficiency of this reduction
technique depends on the layout and the size of the state and on the pattens of
changes in states. For this reason, even a slight variation in state layout can
cause measurable difference in compression ratio. Although these differences
are much smaller than the overall effect of the compression, they are still
visible in the table.

\begin{table}[tp]

\newcommand{\rname}[1]{\rotatebox{90}{\texttt{#1}\hspace*{0.5em}}}
\begin{tabularx}{\textwidth}{|l|CCCCC|} \hline
Name & \rname{fifo} & \rname{fifo-bug} & \rname{collision} & \rname{pt-rwlock} & \rname{elevator2} \\  \hline
no \lart              & 791 & \it 2876 & 1.96\,M &     4.48\,M & \si{17720078} \\  \hline
const \texttt{alloca} & 791 & \it 2876 & 1.96\,M & \bf 4.47\,M & \textbf{\si{11482370} }\\
const global          & 791 & \it 2876 & 1.96\,M &     4.48\,M & \si{17720078} \\
\texttt{alloca} zero  & 791 & \it 2876 & 1.96\,M &     4.48\,M & \si{17720078} \\
register zero         & 791 & \it 2876 & 1.96\,M &     4.48\,M & \si{17720078} \\
CA + CG               & 791 & \it 2876 & 1.96\,M & \bf 4.47\,M & \textbf{\si{11482370}} \\
CA + CG + AZ          & 791 & \it 2876 & 1.96\,M & \bf 4.47\,M & \textbf{\si{11482370}} \\
CA + CG + RZ          & 791 & \it 2876 & 1.96\,M & \bf 4.47\,M & \textbf{\si{11482370}} \\ \hline
Reduction             & $1\times$  &    $1\times$    &        $1\times$ &    $1\times$ & \speedup{17720078}{11482370} \\ \hline 
% RWL: NO=4476710, R=4472037
\end{tabularx}

\par\medskip\par

\begin{tabularx}{\textwidth}{|l|CCCC|} \hline
Name & \rname{lead-dkr} & \rname{hs-2-1-0} & \rname{hs-2-1-1} & \rname{hs-2-2-2} \\ \hline
no \lart              & \si{58148} & \si{890973} & \si{1341117} & \si{2328550} \\
const \texttt{alloca} & \textbf{\si{43376}} & \textbf{\si{874778}} & \textbf{\si{1317496}} & \textbf{\si{2292383}} \\
const global          & \si{58148} & \si{890973} & \si{1341117} & \si{2328550} \\
\texttt{alloca} zero  & \si{58148} & \si{903908} & \si{1356872} & \si{2348987} \\
register zero         & \si{58148} & \si{890973} & \si{1341117} & \si{2328550} \\
CA + CG               & \textbf{\si{43376}} & \textbf{\si{874778}} & \textbf{\si{1317496}} & \textbf{\si{2292383}} \\
CA + CG + AZ          & \textbf{\si{43376}} & \si{887715} & \si{1333253} & \si{2312822} \\
CA + CG + RZ          & \textbf{\si{43376}} & \textbf{\si{874778}} & \textbf{\si{1317496}} & \textbf{\si{2292383}} \\ \hline
Reduction             & \speedup{58148}{43376} & \speedup{890973}{874778} & \speedup{1341117}{1317496} & \speedup{2328550}{2292383} \\ \hline 
\end{tabularx}

\caption{Effects of \lart optimizations on state space size. \textit{Reduction}
shows the best achieved reduction.}
\label{tab:res:opt:st}
\end{table}

\begin{table}[tp]

\newcommand{\rname}[1]{\rotatebox{90}{\texttt{#1}\hspace*{0.5em}}}
\begin{tabularx}{\textwidth}{|l|CCCCC|} \hline
Name & \rname{fifo} & \rname{fifo-bug} & \rname{collision} & \rname{pt-rwlock} & \rname{elevator2} \\  \hline
no \lart              & \dmem{388724} & \it \dmem{388956} & \textbf{\dmem{487320}} & \dmem{1065352} & \dmem{1296532} \\  \hline
const \texttt{alloca} & \dmem{343388} & \it \dmem{351824} & \dmem{489428} & \dmem{1054764} & \dmem{1217588} \\
const global          & \dmem{389076} & \it \dmem{391584} & \dmem{512512} & \dmem{1115880} & \textbf{\dmem{1141484}} \\
\texttt{alloca} zero  & \dmem{405092} & \it \dmem{403580} & \dmem{524944} & \dmem{1115768} & \dmem{1459052} \\
register zero         & \dmem{391384} & \it \dmem{387960} & \dmem{513276} & \dmem{1102036} & \dmem{1438172} \\
CA + CG               & \textbf{\dmem{338960}} & \textbf{\textit{\dmem{339152}}}     & \dmem{487760} & \dmem{1038392} & \dmem{1328844} \\
CA + CG + AZ          & \dmem{339172} & \it \dmem{339172} & \dmem{487920} & \textbf{\dmem{1032924}} & \dmem{1328204} \\
CA + CG + RZ          & \dmem{342588} & \it \dmem{342588} & \dmem{488264} & \dmem{1035964} & \dmem{1324748} \\ \hline
Reduction             & \speedup{388724}{338960} & \speedup{388956}{339152} & \speedup{487320}{487320} & \speedup{1065352}{1032924} & \speedup{1296532}{1141484} \\ \hline 
\end{tabularx}

\par\medskip\par

\begin{tabularx}{\textwidth}{|l|CCCC|} \hline
Name & \rname{lead-dkr} & \rname{hs-2-1-0} & \rname{hs-2-1-1} & \rname{hs-2-2-2} \\ \hline
no \lart              & \dmem{659780} & \dmem{1200264} & \dmem{1207412} & \dmem{1266776} \\
const \texttt{alloca} & \dmem{353888} &  \dmem{572668} &  \textbf{\dmem{843024}} & \dmem{904460} \\
const global          & \dmem{394508} &  \dmem{937504} &  \dmem{945648} & \dmem{1009160} \\
\texttt{alloca} zero  & \dmem{407704} &  \dmem{970884} &  \dmem{992340} & \dmem{1070452} \\
register zero         & \dmem{424424} &  \dmem{935436} &  \dmem{946692} & \dmem{1006572}  \\
CA + CG               & \dmem{345060} &  \textbf{\dmem{559892}} &  \dmem{845604} &  \textbf{\dmem{873252}} \\
CA + CG + AZ          & \textbf{\dmem{342136}} &  \dmem{561504} &  \dmem{851300} &  \dmem{873828} \\
CA + CG + RZ          & \dmem{363988} &  \dmem{560404} &  \dmem{847116} &  \dmem{873736} \\ \hline
Reduction             & \speedup{659780}{342136} & \speedup{1200264}{559892} & \speedup{1200264}{847116} & \speedup{1266776}{873736} \\ \hline 
\end{tabularx}

\caption{Effects of \lart optimizations on memory required for verification.
\textit{Reduction} shows the best achieved reduction.}
\label{tab:res:opt:mem}
\end{table}

Finally, in \autoref{tab:res:wm:lopt}, we can see the effect of the two most
significant \lart optimizations, constant local variable elimination and
constant global variable annotation, on programs with the \llvm memory model
simulation. We can see that these optimizations reduced state space size up to
two times. We were not able to include more of hash set tests into this table
due to their size.

\begin{table}[tp]
\newcommand{\tline}[3]{\directlua{tex.sprint( wmoptline( "\luatexluaescapestring{#1}", { #2 }, "\luatexluaescapestring{#3}" ) )}}

\begin{tabularx}{\textwidth}{|l|C|CC|CC|} \hline
Name & No \lart & \multicolumn{2}{c|}{Const \texttt{alloca}} & \multicolumn{2}{c|}{+ Const Global} \\ \hline
\tline{simple-tso-1}{3445, 3358, 3362}{it} \\
\tline{simple-tso-2}{5973, 5859, 5789}{it} \\
\tline{simple-tso-3}{15663, 15431, 15382}{it} \\
\tline{simple-std-1}{3522, 3376, 3382}{it} \\
\tline{simple-std-2}{8072, 7512, 7449}{it} \\
\tline{simple-std-3}{23609, 19694, 19439}{it} \\
\hline
\tline{peterson-tso-1}{21837, 10795, 10993}{it} \\
\tline{peterson-tso-2}{53443, 33007, 32608}{it} \\
\tline{peterson-tso-3}{55665, 36026, 36448}{it} \\
\tline{peterson-std-1}{21981, 10965, 10771}{it} \\
\tline{peterson-std-2}{56336, 35581, 35518}{it} \\
\tline{peterson-std-3}{69787, 46224, 46141}{it} \\
\hline
\tline{fifo-tso-1}{14892, 12741, 12717}{} \\
\tline{fifo-tso-2}{35865, 30918, 30892}{} \\
\tline{fifo-tso-3}{48787, 42130, 42098}{} \\
\tline{fifo-std-1}{18297, 15700, 15674}{} \\
\tline{fifo-std-2}{15648, 13243, 13634}{it} \\
\tline{fifo-std-3}{22985, 19601, 19880}{it} \\
\hline
\tline{fifo-at-tso-1}{39539, 39289, 39265}{} \\
\tline{fifo-at-tso-2}{166621, 165930, 165904}{} \\
\tline{fifo-at-tso-3}{497229, 495975, 495943}{} \\
\tline{fifo-at-std-1}{53498, 53105, 53079}{} \\
\tline{fifo-at-std-2}{255636, 253624, 253478}{} \\
\tline{fifo-at-std-3}{1067735, 1054035, 1052147}{} \\
\hline
\tline{fifo-bug-tso-1}{11291, 10191, 10059}{it} \\
\tline{fifo-bug-tso-2}{44192, 38558, 38765}{it} \\
\tline{fifo-bug-tso-3}{68655, 57202, 57709}{it} \\
\tline{fifo-bug-std-1}{12131, 10576, 10411}{it} \\
\tline{fifo-bug-std-2}{14142, 12425, 11890}{it} \\
\tline{fifo-bug-std-3}{21098, 17821, 17895}{it} \\
\hline
\tline{hs-2-1-0-tso-1}{250390514, 184001826, 184001777}{} \\
\hline
\end{tabularx}

\caption{Results of weak memory model examples with \lart optimizations.}
\label{tab:res:wm:lopt}
\end{table}
