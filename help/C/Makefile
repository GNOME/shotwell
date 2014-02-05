#
# This produces the index.cache file and converts all the .page files in this directory
# to HTML.
# 
# Adapted from http://www.mail-archive.com/gnome-doc-list@gnome.org/msg04608.html
# and the mal2html script in the yelp-xsl package.
#
# Copyright 2010-2014 Yorba Foundation
#

pages=$(wildcard *.page)
htmls=$(patsubst %.page,%.html,$(pages))

all: $(htmls) index.cache

index.cache : $(pages)
	echo '<cache:cache xmlns:cache="http://projectmallard.org/cache/1.0/" xmlns="http://projectmallard.org/1.0/">' > index.temp
	for page in $(pages); do \
	  echo "<page cache:href='file://`pwd`/$$page'/>" >> index.temp; \
	done
	echo '</cache:cache>' >> index.temp
	xsltproc `pkg-config --variable xsltdir gnome-doc-utils`/mallard/cache/mal-cache.xsl index.temp > index.cache
	rm index.temp

$(htmls) : index.cache
$(htmls) : %.html : %.page
	xsltproc \
	  --stringparam mal.cache.file `pwd`/index.cache \
	  --param mal.chunk.chunk_top 1 \
	  `pkg-config --variable mal2html gnome-doc-utils` $<

.PHONY: clean
clean:
	rm -f index.cache *.html index.css index.temp

