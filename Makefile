full-rebuild:
	rm -rf .shake docs; stack build && stack exec build-site

.PHONY: full-rebuild
