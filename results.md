
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

Please note that results for cases when property does not hold depend on timing
and number of processors used during the evaluation. To make these results
distinguishable they are set in cursive font. Programs used in the evaluation
are described in \autoref{tab:res:models}.

\begin{table}
\begin{tabularx}{\textwidth}{|lX|} \hline
\texttt{simple} & A program similar to the one in \autoref{fig:trans:wm:sb}, two
threads, each of them reads value written by the other one. Assertion violation
can be detected with total store order. Written in C++, does not use C++11 atomics. \\
\hline
\texttt{peterson} & A version of well-known Peterson's mutual exclusion
algorithm, valid under sequential consistency, not valid under total store order
or more relaxed model. Written in C++, no C++11 atomics. \\
\hline
\texttt{fifo} & A fast communication queue for producer-consumer use with one
producer and one consumer. This is used in \divine when running in distributed
environment. The queue is designed for X86, it is correct unless stores can be
reodered. Written in C++, the queue itself does not use C++11 atomics, the unit
test does use one relaxed (monotonic) atomic variable. \\
\hline
\texttt{fifo-at} & A modification of \texttt{fifo} which uses C++11 atomics to
ensure it works with memory models more relaxed then TSO. \\
\hline
\texttt{fifo-bug} & An older version of \texttt{fifo} which contains a data
race. \\
\hline
\texttt{fifo-large} & Larger version of \texttt{fifo} test. \\
\hline
\texttt{hs-$T$-$N$-$E$} & A hight-performance, lock-free shared memory
memory hash table used in \divine in shared memory setup~\cite{BRSW15}. Written
in C++, uses C++11 atomics heavily, mostly sequential consistency is used for
atomics. This model is parametrized, $T$ is number of threads, $N$ is number of
elements inserted by each thread (elements inserted by each thread are
distinct), $E$ is number of extra elements which are inserted by two threads. \\
\hline
\texttt{pt-rwlock} & A test for reader-writer lock in C. \\
\hline
\texttt{lead-dkr}  & A collision avoidance protocol written in C++, described in
\cite{Jensen96modellingand}. \\
\hline
\texttt{collision} & A leader election algorithm written in C++, described in \cite{dolev:an}. \\
\hline
\texttt{elevator2} & This model is C++ version of elevator model from BEEM
database \cite{beem}. It is a simulation of elevator planning. \\
\hline
\end{tabularx}
\caption{Description of programs used in the evaluation.}
\label{tab:res:models}
\end{table}

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

We evaluated relaxed memory models on the same benchmarks as in \cite{SRB15} and
additionally on a unit test for concurrent hash table (`hs-2-1-0`). We used
Context-Switch-Directed-Reachability algorithm \cite{SRB14} in all weak memory
model evaluations as it tends to find bugs in programs with weak memory models
faster (it explores runs with less context switches and therefore less store
buffer flushing earlier).

\autoref{tab:res:wm} shows state space sizes for programs with weak memory model
simulation and compares it to the state space size of the original program. We
can see that size increase varies largely, but the increase is quite large,
anywhere from $7\times$ to $282\times$ increase for store buffer with slot for
one store. We can also see that the difference between total store order and
more relaxed memory model is not as significant as store buffer size increase,
which suggests there is still a room for optimizations for TSO simulation.
Benchmark `hs-2-1-0` shows that weak memory simulation is not yet easily
applicable to more complex real-world code, in this case the verification
required \dmem{32585028} of memory and almost half a day of runtime on 48 cores
and larger versions of this model did not fit into $100\,\text{GB}$ memory limit.
Nevertheless, for smaller real-world tests, such as `fifo` weak memory model
simulation can be used even on common laptop.

\begin{table}[tp]
\begin{tabularx}{\textwidth}{|l|C|CCC|CCC|} \hline
  & SC & \multicolumn{3}{c|}{TSO} & \multicolumn{3}{c|}{TSO: Size increase} \\
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
  & SC & \multicolumn{3}{c|}{STD} & \multicolumn{3}{c|}{STD: Size increase} \\
  & - & 1 & 2 & 3 & 1 & 2 & 3 \\ \hline
\texttt{simple}   &    \si{127} & \it\si{3522} & \it\si{8072} & \it\si{23609} & \speedup{3522}{127} & \speedup{8072}{127} & \speedup{23609}{127} \\
\texttt{peterson} &    \si{703} & \it\si{21981} & \it\si{56336} & \it\si{69787} & \speedup{21981}{703} & \speedup{56336}{703} & \speedup{69787}{703} \\
\texttt{fifo}     &    \si{791} & \it\si{18297} & \it\si{15648} & \it\si{22985} & \speedup{18297}{791} & \speedup{15648}{791} & \speedup{22985}{791} \\
\texttt{fifo-at}  &    \si{717} & \si{53498} & \si{255636} & \si{1067735} & \speedup{53498}{717} & \speedup{255636}{717} & \speedup{1067735}{717} \\
\texttt{fifo-bug} &\it\si{1611} & \it\si{12131} & \it\si{14142} & \it\si{21098} & \speedup{12131}{1611} & \speedup{14142}{1611} & \speedup{21098}{1611} \\
\texttt{hs-2-1-0} & \si{890973} & \si{251249798} & -- & -- & \speedup{251249798}{890973} & -- & -- \\ \hline
\end{tabularx}
\caption{A summary of number of states in the state space for different weak
memory simulation settings. The first line specifies the memory model (SC =
Sequential Consistency, that is no transformation, TSO = Total Store Order, STD
= \llvm memory model. The second line gives store buffer size. If the number of
states is set in cursive it means that the property does not hold, and therefore
the number might differ.}
\label{tab:res:wm}
\end{table}

## Effects of Optimizations

The optimization described in \autoref{sec:trans:wm:tau} were first evaluated in
the context of the TSO memory model simulation presented in \cite{SRB15}. The
results of this initial evaluation can be seen in \autoref{tab:res:wm:opt:old},
*MEMICS* stands for the original version from \cite{SRB15}, *+ Load private*
allows store buffers to be bypassed for memory locations which are dynamically
detected to be thread private, and *+ Local* also avoids transformation for
instructions which manipulate local variables which do not escape scope of the
function in which they are defined. This evaluation does not include any changes
in $\tau+$ reduction. We can see that effects of the optimizations are
significant, especially for private loads optimization.

\begin{table}[tp]
\begin{tabularx}{\textwidth}{|l|c|CC|CC|C|} \hline
Model                & MEMICS & \multicolumn{2}{c|}{$+$ Load private} & \multicolumn{2}{c|}{$+$ Local}  & SC \\ \hline
\texttt{fifo-1}      & $44$ M  & $5.6$ M & $7.9\times$  & $1.2$ M & $4.6\times$ & $7$ K \\
\texttt{fifo-2}      & $338$ M & $51$ M  & $6.6\times$   & $11$ M & $4.6\times$  & $7$ K \\
\texttt{fifo-3}      & $672$ M & $51$ M  & $13\times$    & $11$ M & $4.6\times$  & $7$ K \\
\texttt{simple-1}    & $538$ K & $19$ K  & $28\times$   & $11$ K & $1.7\times$  & 251 \\
\texttt{peterson-2}  & $103$ K & $40$ K  & $2.6\times$   & $24$ K & $1.6\times$  & $1.4$ K \\
\texttt{pt\_mutex-2} & $1.6$ M & $12$ K  & $135\times$ & $7.5$ K & $1.6\times$ & 98 \\ \hline
\end{tabularx}

\caption{Effects of private load optimization and local private variable
optimization on the implementation from \cite{SRB15}. The number after model
name is store buffer size.}
\label{tab:res:wm:opt:old}
\end{table}

The same optimizations were evaluated in the final version of the
transformation, these results can be seen in \autoref{tab:res:wm:opt}. Please
note that while the original transformation bypassed store buffers for
thread-private stores, the version proposed in this work does not do it as this
optimization is not correct for \llvm memory model. Nevertheless, the new
version performs an order of magnitude better in all cases, both thanks to
enhanced state space reductions and more efficient implementation.



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

\begin{table}[tp]
\newcommand{\tline}[2]{\directlua{tex.sprint( wmoptline( "\luatexluaescapestring{#1}", { #2 } ) )}}

\begin{tabularx}{\textwidth}{|l|C|CC|CC|} \hline
Name & No \lart & \multicolumn{2}{c|}{Const \texttt{alloca}} & \multicolumn{2}{c|}{Const global} \\ \hline
\tline{simple-tso-1}{3445, 3358, 3362} \\
\tline{simple-tso-2}{5973, 5859, 5789} \\
\tline{simple-tso-3}{15663, 15431, 15382} \\
\tline{simple-std-1}{3522, 3376, 3382} \\
\tline{simple-std-2}{8072, 7512, 7449} \\
\tline{simple-std-3}{23609, 19694, 19439} \\
\hline
\tline{peterson-tso-1}{21837, 10795, 10993} \\
\tline{peterson-tso-2}{53443, 33007, 32608} \\
\tline{peterson-tso-3}{55665, 36026, 36448} \\
\tline{peterson-std-1}{21981, 10965, 10771} \\
\tline{peterson-std-2}{56336, 35581, 35518} \\
\tline{peterson-std-3}{69787, 46224, 46141} \\
\hline
\tline{fifo-tso-1}{14892, 12741, 12717} \\
\tline{fifo-tso-2}{35865, 30918, 30892} \\
\tline{fifo-tso-3}{48787, 42130, 42098} \\
\tline{fifo-std-1}{18297, 15700, 15674} \\
\tline{fifo-std-2}{15648, 13243, 13634} \\
\tline{fifo-std-3}{22985, 19601, 19880} \\
\hline
\tline{fifo-at-tso-1}{39539, 39289, 39265} \\
\tline{fifo-at-tso-2}{166621, 165930, 165904} \\
\tline{fifo-at-tso-3}{497229, 495975, 495943} \\
\tline{fifo-at-std-1}{53498, 53105, 53079} \\
\tline{fifo-at-std-2}{255636, 253624, 253478} \\
\tline{fifo-at-std-3}{1067735, 1054035, 1052147} \\
\hline
\tline{fifo-bug-tso-1}{11291, 10191, 10059} \\
\tline{fifo-bug-tso-2}{44192, 38558, 38765} \\
\tline{fifo-bug-tso-3}{68655, 57202, 57709} \\
\tline{fifo-bug-std-1}{12131, 10576, 10411} \\
\tline{fifo-bug-std-2}{14142, 12425, 11890} \\
\tline{fifo-bug-std-3}{21098, 17821, 17895} \\
\hline
\end{tabularx}

\caption{Results of weak memory model examples with \lart optimizations.}
\label{tab:res:wm:lopt}
\end{table}
