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

test: $(DEPS_DIR)/plenary.nvim $(DEPS_DIR)/tree-sitter-unreal-cpp/parser/cpp.so
	$(NVIM) -c "PlenaryBustedDirectory tests/ { minimal_init = 'scripts/minimal_init.lua', sequential = true }"

lint:
	@echo "TODO: wire linter (e.g. stylua/luacheck)"

clean:
	rm -rf $(DEPS_DIR)

$(DEPS_DIR)/tree-sitter-lua:
	git clone --depth 1 https://github.com/tjdevries/tree-sitter-lua $@

$(DEPS_DIR)/tree-sitter-lua/parser/lua.so: $(DEPS_DIR)/tree-sitter-lua
	mkdir -p $(DEPS_DIR)/tree-sitter-lua/parser
	cd $(DEPS_DIR)/tree-sitter-lua && $(CC) -o parser/lua.so -Isrc src/parser.c src/scanner.c $(PARSER_CFLAGS)

# Keep in sync with config.defaults.custom_treesitter.revision
UNREAL_CPP_REV := 2d2d5c19a9a83e432e43c041252106995614b29a

$(DEPS_DIR)/tree-sitter-unreal-cpp:
	git clone https://github.com/taku25/tree-sitter-unreal-cpp $@
	cd $@ && git checkout $(UNREAL_CPP_REV)

$(DEPS_DIR)/tree-sitter-unreal-cpp/parser/cpp.so: $(DEPS_DIR)/tree-sitter-unreal-cpp
	mkdir -p $(DEPS_DIR)/tree-sitter-unreal-cpp/parser
	cd $(DEPS_DIR)/tree-sitter-unreal-cpp && $(CC) -o parser/cpp.so -Isrc src/parser.c src/scanner.c $(PARSER_CFLAGS)

$(DEPS_DIR)/plenary.nvim:
	git clone --depth 1 https://github.com/nvim-lua/plenary.nvim $@
