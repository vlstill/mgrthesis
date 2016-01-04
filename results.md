
# Extensions of $\tau+$ Reduction

\begin{table}[tp]
\caption{Evaluation of improved $\tau+$ reduction. \divine 3.3 is used as a
reference, it does not include any changes described in this thesis.
\textit{Old} corresponds to original $\tau+$ reduction with several bugfixes,
\textit{+ Control Flow} includes control flow loop detection optimization,
\textit{+ Indep. Load} includes independent loads optimization, \textit{New}
includes both optimizations.}

\medskip
\begin{tabularx}{\textwidth}{l|C|CCCC|C}
Name & \divine 3.3 & Old & + Control Flow & + Indep. Load & New & Reduction \\ \hline
\texttt{fifo} & 1836 & 1793 & 1767 & 793 & 791 & $2.32\times$ \\
\texttt{fifo-bug} & \it 6.6 & \it 6.6\,k & \it 6.5\,k & \it 2.9\,k & \it 2.9\,k & $2.31\times$ \\
\texttt{lead-dkr} & 29.9\,k & 132\,k & 132\,k & 58\,k & 58\,k & $0.51\times$ \\ % OLD = 29921, NEW = 58148
\texttt{collision} & 3.1\,M & 3.3\,M & 3.3\,M & 2.0\,M & 2.0\,M & $1.56\times$ \\
\texttt{lead-basic} &  19.3\,k & \\ % OLD = 19341906
\texttt{lead-peters} &  12.3\,k & \\ % OLD = 12282933
\texttt{pt-rwlock} & 14.2\,k & \\ % OLD = 14237025
\texttt{elevator2} & 19\,M & 18\,M & 18\,M & 18\,M & 18\,M & $1.04\times$ \\
\texttt{hs-2-1-0} & & 1.88\,M & 1.88\,M & 1.0\,M & 891\,k & \\
\texttt{hs-2-1-1} & & 2.87\,M & 2.87\,M & 1.51\,M & 1.34\,M \\ % T=2871440, NEW=1341117
\texttt{hs-2-2-2} & & 4.99\,M & 4.99\,M & 2.62\,M & 2.33\,M \\ % T=4990846, NEW=2328550
\end{tabularx}
\end{table}

\label{sec:res:tau}

# \llvm IR Optimizations

\label{sec:res:opt}

# Weak Memory Models

\label{sec:res:wm}

\begin{table}[tp]
\caption{Description of programs used as weak memory model benchmarks.}

\medskip
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
\end{table}

\begin{table}[tp]
\caption{A summary of number of states in the state space for different weak
memory simulation settings. The first line specifies the memory model (SC =
Sequential Consistency, that is no transformation, TSO = Total Store Order, STD
= \llvm memory model. The second line gives store buffer size. If the number of
states is set in cursive it means that the property does not hold, and therefore
the number might differ. Context-Switch-Directed-Reachability algorithm was
used.}

\medskip
\begin{tabularx}{\textwidth}{l|C|CCC|CCC}
  & SC & \multicolumn{3}{c|}{TSO} & \multicolumn{3}{c}{STD} \\
  & - & 1 & 2 & 3 & 1 & 2 & 3 \\ \hline
\texttt{simple} & 127 & \it 3.5\,k & \it 6\,k & \it 16\,k & \it 3.5\,k & \it 8\,k & \it 24\,k \\
\texttt{peterson} & 703 & \it 22\,k & \it 53\,k & \it 56\,k & \it 22\,k & \it 56\,k & \it 70\,k \\
\texttt{fifo} & 791 & 15\,k & 36\,k & 48\,k & \it 18\,k & \textit{16\,k} & \textit{23\,k} \\
\texttt{fifo-at} & 717 & 40\,k & 167\,k & 497\,k & 53\,k & 256\,k & 1\,M \\
\texttt{fifo-bug} & \it 1.4\,k & \it 12\,k & \it 44\,k & \it 69\,k & \it 13\,k & \it 14\,k & \it 20\,k \\
\texttt{hs-2-1-0} & 890\,k & 250\,M & & & 251\,M & &
\end{tabularx}
\end{table}

## Effects of Optimizations

\begin{table}[tp]

\begin{tabularx}{\textwidth}{l|CCCC|C}
Name & No \lart & Cost \texttt{alloca} & \texttt{alloca} zero & Register zero & Reduction \\ \hline
\texttt{fifo} & 791 & 791 & 791 & 791 & $1\times$ \\
\texttt{fifo-bug} & \it 2876 & \it 2876 & \it 2876 & \it 2876 & $1\times$ \\
\texttt{hs-2-1-0} & 890\,k & 875\,k & 889\,k &  \\
\texttt{collision} & 1.96\,M & 1.96\,M & 1.96\,M & & \\
\texttt{pt-rwlock} & & 4.47\,k & 4.47\,k & 1.21\,k  \\ % REG = 1213395
\texttt{elevator2} & 17.7\,M &  \\ % NO = 17720078
\end{tabularx}
\end{table}
