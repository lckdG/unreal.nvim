.PHONY: docs test lint clean

DEPS_DIR := .deps
NVIM := nvim --headless --noplugin -u scripts/minimal_init.lua

# Override on machines without a `cc` alias, e.g. `make docs CC=clang`
CC ?= cc
ifeq ($(OS),Windows_NT)
    PARSER_CFLAGS := -shared -Os
else
    PARSER_CFLAGS := -shared -Os -fPIC
endif

docs: $(DEPS_DIR)/tree-sitter-lua/parser/lua.so $(DEPS_DIR)/plenary.nvim
	$(NVIM) -c "luafile scripts/gendocs.lua"

test: $(DEPS_DIR)/plenary.nvim
	@echo "TODO: wire test runner (e.g. plenary busted)"

lint:
	@echo "TODO: wire linter (e.g. stylua/luacheck)"

clean:
	rm -rf $(DEPS_DIR)

$(DEPS_DIR)/tree-sitter-lua:
	git clone --depth 1 https://github.com/tjdevries/tree-sitter-lua $@

$(DEPS_DIR)/tree-sitter-lua/parser/lua.so: $(DEPS_DIR)/tree-sitter-lua
	mkdir -p $(DEPS_DIR)/tree-sitter-lua/parser
	cd $(DEPS_DIR)/tree-sitter-lua && $(CC) -o parser/lua.so -Isrc src/parser.c src/scanner.c $(PARSER_CFLAGS)

$(DEPS_DIR)/plenary.nvim:
	git clone --depth 1 https://github.com/nvim-lua/plenary.nvim $@
