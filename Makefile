version := $(shell git tag|tail -1)

archive:
	git archive --format=tar.gz --prefix=configuration-$(version)/ -o configuration-$(version).tar.gz $(version)

clean:
	rm -f *.tar.gz

test_file := $(wildcard test/*)
test: plugins/*
	@for f in $(test_file); do \
		$$f; \
	done;


