ALL=$(wildcard *.md)

all : thesis.pdf
	make -C draft

thesis.pdf : thesis.tex $(ALL:.md=.tex) thesis.bbl
	./latexwrap $<

thesis.bbl : bibliography.bib
	biber thesis

%.tex : %.md
	pandoc $< -o $@


