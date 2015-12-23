.PHONY: all test deploy

DEPLOY_DIR=~/Sites/books

all:
	cd src; find . -iname '*.p?' -exec perl -MVi::QuickFix -Tc {} \;

test:
	cd src; find . -iname '*.p?' -exec perl -Tc {} \;


deploy:
	cd src; cp -f _htaccess .htaccess 
	cd src; rsync -avz --delete --exclude "_*" --exclude "*.swp" . ${DEPLOY_DIR}
