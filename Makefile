.PHONY: all test deploy

DEPLOY_DIR=~/Sites/books

all:
	cd src; find . -iname '*.p?' -exec perl -c {} \;

test: all

deploy:
	cd src; cp -f _htaccess .htaccess 
	cd src; rsync -avz --delete . ${DEPLOY_DIR}
