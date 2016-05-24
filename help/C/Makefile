#
# This produces the index.cache file and converts all the .page files in this directory
# to HTML.
# 
# Adapted from http://www.mail-archive.com/gnome-doc-list@gnome.org/msg04608.html
# and the mal2html script in the yelp-xsl package.
#
# Copyright 2016 Software Freedom Conservancy Inc.
#

pages=$(wildcard *.page)

all: html.stamp index.cache

index.cache : $(pages)
	yelp-build cache $(pages)

html.stamp: index.cache $(pages)
	@rm -f html.stamp
	mkdir html
	yelp-build html -c index.cache -o html .
	@touch html.stamp

.PHONY: clean
clean:
	rm -rf html
	rm -f index.cache html.stamp

