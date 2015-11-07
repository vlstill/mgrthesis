ALL=$(wildcard *.md)

all : thesis.pdf
	make -C draft

thesis.pdf : thesis.tex $(ALL:.md=.tex)
	rubber -Wall --pdf $<

%.tex : %.md
	pandoc $< -o $@


