.PHONY: all test

all:
	cd src; find . -iname '*.p?' -exec perl -c {} \;

test: all
