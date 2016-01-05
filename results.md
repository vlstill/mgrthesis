In this chapter we will evaluate the transformations proposed in
\autoref{chap:trans}. All measurements were done on Linux on X86_64 machines
with enough memory to run verification of the program in question. All numbers
are taken from \divine's report (`--report` option to `verify` command). Number
of states is `States-Visited` from the report, which is the number of unique
states in the state space of the program; Memory usage is `Memory-Used` from the
report, which is peak of total memory used during the verification. All
measurements were performed with lossless tree compression enabled
(`--compression`) and, unless explicitly stated otherwise, default setting of
$\tau+$ reduction (which includes changes described in
\autoref{sec:trans:tauextend}).

# Extensions of $\tau+$ Reduction

\label{sec:res:tau}

\autoref{tab:res:tau} shows state space sizes of several models with the
original $\tau+$ reductions and with the extensions described in
\autoref{sec:trans:tauextend}. It also includes state space sizes in \divine
3.3, which is the version before any modification described in this thesis.
While both \divine 3.3 and the new version with original reduction implement the
same reduction strategy the numbers can differ because of two bugs which were
fixed since \divine 3.3. The first bug is that \divine 3.3 never considered
`memcpy` to be visible operation, which could cause some runs to be missed; with
this bug fixed, the state space size can grow. The second bug is that if a
visible instruction is at the beginning of a basic block, \divine 3.3 emitted
state immediately after this instruction; fixing this bug could cause state
space size to decrease.

We can see in the table that in all but one case the extended $\tau+$ reduction
performs better then \divine 3.3 and in all cases it performs better than the
implementation of original reduction in the new version of \divine. The one
difference is `lead-dkr`, the reason is that this program uses `memcpy` heavily
and therefore is affected by the bug fix. If we consider fixed implementation as
baseline for `lead-dkr` the new reduction represent $2.27\times$ improvement.
Overall the improvement was $1.05\times$ to $3.18\times$ for benchmarked models,
which is a good improvement on already heavy reductions of the original $\tau+$.
We can also see that independent loads optimization has higher impact that
control flow loop detection optimization, but the latter still provides
measurable improvement (up to $1.5\times$ reduction).

\begin{table}[tp]
\begin{tabularx}{\textwidth}{|l|C|CCCC|C|} \hline
Name & \divine 3.3 & Old & + Control Flow & + Indep. Load & New & Reduction \\ \hline
\texttt{fifo}      &     \si{1836} &     \si{1793} &     \si{1767} &     \si{793}  &     \si{791}  & \speedup{1836}{791} \\
\texttt{fifo-bug}  &     \textit{\si{6641}} &     \textit{\si{6614}} &     \textit{\si{6454}} &     \textit{\si{2882}} &     \textit{\si{2876}} & \speedup{6641}{2876} \\
\texttt{lead-dkr}  &    \si{29921} &   \si{131715} &   \si{131712} &    \si{58151} &    \si{58148} & \speedup{29921}{58148} \\
\texttt{collision} &  \si{3064791} &  \si{3280980} &  \si{3280978} &  \si{1960480} &  \si{1960478} & \speedup{3064791}{1960478} \\
% \texttt{lead-basic} &  19.3\,k & \\ % OLD = 19341906
% \texttt{lead-peters} &  12.3\,k & \\ % OLD = 12282933
\texttt{pt-rwlock} & \si{14237025} & \si{14237027} &  \si{8661079} &  \si{6542607} &  \si{4476710} & \speedup{14237025}{4476710} \\
\texttt{elevator2} & \si{18567508} & \si{18233787} & \si{18233786} & \si{17720079} & \si{17720078} & \speedup{18567508}{17720078} \\
\texttt{hs-2-1-0}  & \it error     &  \si{1875067} &  \si{1873150} &  \si{1008098} &   \si{890973} & \speedup{1875067}{890973} \\
\texttt{hs-2-1-1}  & \it error     &  \si{2871440} &  \si{2869311} &  \si{1505397} &  \si{1341117} & \speedup{2871440}{1341117} \\
\texttt{hs-2-2-2}  & \it error     &  \si{4990846} &  \si{4988242} &  \si{2622816} &  \si{2328550} & \speedup{4990846}{2328550} \\ \hline
\end{tabularx}
\caption{Evaluation of improved $\tau+$ reduction. \divine 3.3 is used as a
reference, it does not include any changes described in this thesis.
\textit{Old} corresponds to original $\tau+$ reduction with several bugfixes,
\textit{+ Control Flow} includes control flow loop detection optimization,
\textit{+ Indep. Load} includes independent loads optimization, \textit{New}
includes both optimizations.}

\label{tab:res:tau}
\end{table}

# Weak Memory Models

\iffalse
\label{sec:res:wm}

\begin{table}[tp]
\begin{tabularx}{\textwidth}{lX}
\texttt{simple} & A program similar to the one in \autoref{fig:trans:wm:sb}, two
threads, each of them reads value written by the other one. Assertion violation
can be detected with total store order. Written in C++, does not use C++11 atomics. \\ \hline

\texttt{peterson} & A version of well-known Peterson's mutual exclusion
algorithm, valid under sequential consistency, not valid under total store order
or more relaxed model. Written in C++, no C++11 atomics. \\ \hline

\texttt{fifo} & A fast communication queue for producer-consumer use with one
producer and one consumer. This is used in \divine when running in distributed
environment. The queue is designed for X86, it is correct unless stores can be
reodered. Written in C++, the queue itself does not use C++11 atomics, the unit
test does use one relaxed (monotonic) atomic variable. \\ \hline

\texttt{fifo-at} & A modification of \texttt{fifo} which uses C++11 atomics to
ensure it works with memory models more relaxed then TSO. \\ \hline

\texttt{fifo-bug} & An older version of \texttt{fifo} which contains a data
race. \\ \hline

\texttt{fifo-large} & Larger version of \texttt{fifo} test. \\ \hline

\texttt{hs-$T$-$N$-$E$} & A hight-performance, lock-free shared memory
memory hash table used in \divine in shared memory setup \cite{BRSW15}. Written
in C++, uses C++11 atomics heavily, mostly sequential consistency is used for
atomics. This model is parametrized, $T$ is number of threads, $N$ is number of
elements inserted by each thread (elements inserted by each thread are
distinct), $E$ is number of extra elements which are inserted by two threads.
\end{tabularx}
\caption{Description of programs used as weak memory model benchmarks.}
\end{table}
\fi

\begin{table}[tp]
\begin{tabularx}{\textwidth}{|l|C|CCC|CCC|} \hline
  & SC & \multicolumn{3}{c|}{TSO} & \multicolumn{3}{c|}{STD} \\
  & - & 1 & 2 & 3 & 1 & 2 & 3 \\ \hline
\texttt{simple}   &    \si{127} & \it 3.5\,k & \it 6\,k & \it 16\,k & \it 3.5\,k & \it 8\,k & \it 24\,k \\
\texttt{peterson} &    \si{703} & \it 22\,k & \it 53\,k & \it 56\,k & \it 22\,k & \it 56\,k & \it 70\,k \\
\texttt{fifo}     &    \si{791} & 15\,k & 36\,k & 48\,k & \it 18\,k & \textit{16\,k} & \textit{23\,k} \\
\texttt{fifo-at}  &    \si{717} & 40\,k & 167\,k & 497\,k & 53\,k & 256\,k & 1\,M \\
\texttt{fifo-bug} &      \textit{1.4\,k} & \it 12\,k & \it 44\,k & \it 69\,k & \it 13\,k & \it 14\,k & \it 20\,k \\
\texttt{hs-2-1-0} & \si{890973} & \si{250390514} & & & 251\,M & & \\ \hline
\end{tabularx}
\caption{A summary of number of states in the state space for different weak
memory simulation settings. The first line specifies the memory model (SC =
Sequential Consistency, that is no transformation, TSO = Total Store Order, STD
= \llvm memory model. The second line gives store buffer size. If the number of
states is set in cursive it means that the property does not hold, and therefore
the number might differ. Context-Switch-Directed-Reachability algorithm was
used.}
\label{tab:res:wm}
\end{table}

## Effects of Optimizations

# \llvm IR Optimizations

\label{sec:res:opt}

\begin{table}[tp]

\newcommand{\rname}[1]{\rotatebox{90}{\texttt{#1}\hspace*{1em}}}
\begin{tabularx}{\textwidth}{|l|CCCCC|} \hline
Name & \rname{fifo} & \rname{fifo-bug} & \rname{collision} & \rname{pt-rwlock} & \rname{elevator2} \\  \hline
no \lart              & 791 & \it 2876 & 1.96\,M &     4.48\,M & \si{17720078} \\  \hline
const \texttt{alloca} & 791 & \it 2876 & 1.96\,M & \bf 4.47\,M & \textbf{\si{11482370} }\\
const global          & 791 & \it 2876 & 1.96\,M &     4.48\,M & \si{17720078} \\
alloca zero           & 791 & \it 2876 & 1.96\,M &     4.48\,M & \si{17720078} \\
register zero         & 791 & \it 2876 & 1.96\,M &     4.48\,M & \si{17720078} \\
CA + CG               & 791 & \it 2876 & 1.96\,M & \bf 4.47\,M & \textbf{\si{11482370}} \\
CA + CG + AZ          & 791 & \it 2876 & 1.96\,M & \bf 4.47\,M & \textbf{\si{11482370}} \\
CA + CG + RZ          & 791 & \it 2876 & 1.96\,M & \bf 4.47\,M & \textbf{\si{11482370}} \\ \hline
Reduction             & $1\times$  &    $1\times$    &        $1\times$ &    $1.001\times$ & \speedup{17720078}{11482370} \\ \hline 
% RWL: NO=4476710, R=4472037
\end{tabularx}
\caption{Effects of \lart optimizations on state space size.}
\label{tab:res:opt:st}
\end{table}

\begin{table}[tp]

\newcommand{\rname}[1]{\rotatebox{90}{\texttt{#1}\hspace*{1em}}}
\begin{tabularx}{\textwidth}{|l|CCCCC|} \hline
Name & \rname{fifo} & \rname{fifo-bug} & \rname{collision} & \rname{pt-rwlock} & \rname{elevator2} \\  \hline
no \lart              & \dmem{388724} & \it \dmem{388956} & \textbf{\dmem{487320}} & \dmem{1065352} & \dmem{1296532} \\  \hline
const \texttt{alloca} & \dmem{343388} & \it \dmem{351824} & \dmem{489428} & \dmem{1054764} & \dmem{1217588} \\
const global          & \dmem{389076} & \it \dmem{391584} & \dmem{512512} & \dmem{1115880} & \textbf{\dmem{1141484}} \\
alloca zero           & \dmem{405092} & \it \dmem{403580} & \dmem{524944} & \dmem{1115768} & \dmem{1459052} \\
register zero         & \dmem{391384} & \it \dmem{387960} & \dmem{513276} & \dmem{1102036} & \dmem{1438172} \\
CA + CG               & \textbf{\dmem{338960}} & \textbf{\textit{\dmem{339152}}}     & \dmem{487760} & \dmem{1038392} & \dmem{1328844} \\
CA + CG + AZ          & \dmem{339172} & \it \dmem{339172} & \dmem{487920} & \textbf{\dmem{1032924}} & \dmem{1328204} \\
CA + CG + RZ          & \dmem{342588} & \it \dmem{342588} & \dmem{488264} & \dmem{1035964} & \dmem{1324748} \\ \hline
Reduction             & \speedup{388724}{338960} & \speedup{388956}{339152} & \speedup{487320}{487320} & \speedup{1065352}{1032924} & \speedup{1296532}{1141484} \\ \hline 
\end{tabularx}
\caption{Effects of \lart optimizations on memory required for verification.}
\label{tab:res:opt:mem}
\end{table}
