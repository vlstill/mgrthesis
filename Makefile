ALL=$(wildcard *.md)

all : thesis.pdf
	make -C draft

thesis.pdf : thesis.tex $(ALL:.md=.tex) bibliography.bib
	./latexwrap $<

%.tex : %.md
	pandoc $< -o $@


