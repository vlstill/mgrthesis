ALL=$(wildcard *.md)

all : thesis.pdf archive_README.pdf
	make -C draft

thesis.pdf : thesis.tex $(ALL:.md=.tex) thesis.bbl
	./latexwrap $<

thesis-print.pdf : thesis-print.tex $(ALL:.md=.tex) thesis-print.bbl
	./latexwrap $<

thesis-print.tex : thesis.tex
	sed -e 's/linkcolor={.*}/linkcolor={black}/' \
		-e 's/citecolor={.*}/citecolor={black}/' \
		-e 's/urlcolor={.*}/urlcolor={black}/' \
		$< > $@

%.bbl : bibliography.bib %.bcf
	-biber $(@:.bbl=)

%.bcf :
	./latexwrap -n1 $(@:.bcf=.tex)

.PRECIOUS: %.bcf %.bbl

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

archive_README.md : appendix.md
	sed $< -re 's/\\divine/DIVINE/g' -e 's/\\lart/LART/g' \
		-e 's/\\darcs/darcs/g' -e 's/\\llvm/LLVM/g' \
		-e 's/\\label\{[^}]*\}//g' > $@

archive_README.pdf : archive_README.md
	pandoc $< -o $@ -V geometry:a4paper,margin=2.5cm

txt: $(ALL:.md=.txt)

.PHONY: txt

%.txt : %.md
	sed -e ':a;N;$$!ba;s/\n\n/@NL@/g' $< | \
		sed -e ':a;N;$$!ba;s/\n/ /g' -e 's/@NL@/\n\n/g' \
			-e 's/\\autoref{[^}]*}//g' -e 's/\\//g' > $@
