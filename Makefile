ALL=$(wildcard *.md)

all : thesis.pdf
	make -C draft

thesis.pdf : thesis.tex $(ALL:.md=.tex) thesis.bbl
	./latexwrap $<

thesis.bbl : bibliography.bib thesis.bcf
	-biber thesis

thesis.bcf :
	./latexwrap -n1 $<


%.tex : %.md
	pandoc $< -o $@
	sed -i $@ -re 's/ \\cite/~\\cite/' \
		-e 's/^\\section\{@FIG:([^\}]*)\}.*$$/\\begin{figure}[\1]/' \
		-e 's/^\\section\{@eFIG\}.*$$/\\end{figure}/' \
		-e 's/\\begCaption/\\caption{/' -e 's/\\endCaption/\}/' \
		-e 's/\\begFigure/\\begin{figure}/' -e 's/\\endFigure/\\end{figure}/' \
		-e 's/\\begSplit/\\begin{minipage}[t]{0.48\\textwidth}/' \
		-e 's/\\Split/\\end{minipage}\\hfill\\begin{minipage}[t]{0.48\\textwidth}/' \
		-e 's/\\endSplit/\\end{minipage}/'

exvis.ll : exvis.cpp
	clang++ -std=c++14 -S -emit-llvm $< -O2

watch :
	while true; do inotifywait -e close_write,moved_to,create .; sleep 1; make; done

.PHONY: watch
