ALL=$(wildcard *.md)

all : thesis.pdf
	make -C draft

thesis.pdf : thesis.tex $(ALL:.md=.tex) bibliography.bib
	rubber -Wall --pdf $<

%.tex : %.md
	pandoc $< -o $@


