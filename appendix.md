# Archive Structure \label{sec:ap:archive}

The archive submitted with this thesis contains the sources of the thesis itself
and \darcs repository with \divine. The \divine repository is a snapshot of
\url{https://paradise.fi.muni.cz/~xstill/dev/divine/next-xstill} repository
taken at the time of submission of this thesis. You can use command `darcs log
-is` in `divine` subdirectory to browse changes to \divine. As the primary aim
of this thesis are \llvm transformations most of the implementation was done in
\lart, patches concerning \lart are prefixed with `LART`, they can be listed by
`darcs log -is --match 'name LART:'`.

# Compilation and Running of \divine and \lart

## Prerequisites \label{sec:ap:req}

In order to compile \divine and \lart it is necessary to have up-to-date Linux
distribution with C++14 capable compiler. The compilation was tested with GCC
5.3.0 and Clang 3.7.0, bota using libstdc++ 5.3.0 as C++ standard library.
Furthermore it is necessary to have \llvm 3.7.0 including development libraries,
Clang 3.7.0, and CMake.

## Compilation \label{sec:ap:compilation}

It should be sufficient to run the following commands in the root directory of
the archive, please pay attention to output of `configure` to see if it was able
to find \llvm and Clang:

```{.bash}
cd divine
./configure
cd _build
make lart divine
ls tools
```

The last command should show that there are binaries `divine` and `lart` in
`tools` subdirectory.

## Compilation of Program for \divine \label{sec:ap:dcompile}

An input for \divine is a \llvm bitcode file, this can be obtained from the
source using `divine compile` command, for example:

```{.bash}
./tools/divine compile model.cpp --cflags=-std=c++11
```

See `divine compile --help` for more details.

## Running \lart \label{sec:ap:lart}

The basic usage of \lart is: `lart <input> <output> [<pass> [...]]`, the `input`
and `output` are \llvm bitcode files, each pass is a \lart pass, a list of
passes can be seen by running `lart` without any parameters.

For example bitcode in `model.bc` can be instrumented with weak memory models
(\autoref{sec:trans:wm}) with store buffer limited to 2 entries with the
following command:

```{.bash}
# this is unrestricted LLVM memory model
./tools/lart model.bc model-wm.bc weakmem::2
# Total Store Order:
./tools/lart model.bc model-wm.bc weakmem:tso:2
```

## Running \divine \label{sec:ap:divine}

The model can be verified by \divine using `divine verify` command, this command
expects model name, and optionally several parameters such as algorithm and
reductions to be used and property to be verified. Among the most important
options is `--compression` which enables lossless tree compression, which highly
improves memory efficiency of \divine.

```{.bash}
# run DIVINE with default property (safety) on model-wm.bc
./tools/divine verify --compression model-wm.bc
# verify only assertion safety
./tools/divine verify --compression model-wm.bc -p assert
# use Context Switch Directed Reachability algorithm
./tools/divine verify --csdr --compression model-wm.bc
# verify exclusion LTL property (specified in the model)
./tools/divine verify --compression model-wm.bc -p exclusion
```
