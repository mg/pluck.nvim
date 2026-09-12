.PHONY: test format format-check

test:
	nvim --headless --clean -u NONE "+set runtimepath^=$(CURDIR)" "+luafile tests/run.lua" +qa

format:
	stylua lua plugin tests

format-check:
	stylua --check lua plugin tests
