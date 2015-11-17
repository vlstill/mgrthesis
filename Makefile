ALL=$(wildcard *.md)

all : thesis.pdf
	make -C draft

thesis.pdf : thesis.tex $(ALL:.md=.tex)
	./latexwrap $<

thesis.bbl : bibliography.bib
	biber thesis

%.tex : %.md
	pandoc $< -o $@
	sed -i $@ -re 's/ \\cite/~\\cite/' \
		-e 's/^\\section\{@FIG:([^\}]*)\}.*$$/\\begin{figure}[\1]/' \
		-e 's/^\\section\{@eFIG\}.*$$/\\end{figure}/'
	@# sed -i $@ -re 's/\\label\{[^}]*-[^}]*\}//'


