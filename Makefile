.PHONY: all test always

%.pl: always
	perl -c $@

%.pm: always
	perl -c $@

all: M/DB.pm M/Const.pm M/Render.pm conf.pl w.pl e.pl f.pl

test: all
