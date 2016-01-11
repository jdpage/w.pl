.PHONY: all test deploy setup

DEPLOY_DIR=~/Sites/books

all:
	cd src; find . -iname '*.p?' -exec perl -MVi::QuickFix -Tc {} \;

test: all
	prove -Isrc -T

setup:
	cpanm --quiet --installdeps --notest .

deploy:
	cd src; cp -f _htaccess .htaccess 
	cd src; rsync -avz --delete --exclude "_*" --exclude "conf.pl" --exclude ".htaccess" --exclude "*.swp" . ${DEPLOY_DIR}
