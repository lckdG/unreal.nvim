.PHONY: docs test lint format clean

DEPS_DIR := .deps
NVIM := nvim --headless --noplugin -u scripts/minimal_init.lua

# Override on machines without a `cc` alias, e.g. `make test CC=clang`
CC ?= cc
ifeq ($(OS),Windows_NT)
    PARSER_CFLAGS := -shared -Os
else
    PARSER_CFLAGS := -shared -Os -fPIC
endif

# Minimum Neovim version shown in the help file title, e.g. `make docs NVIM_VERSION=0.13`
NVIM_VERSION ?= 0.12

# doc/*.md -> doc/unreal.txt via panvimdoc's Docker image (needs Docker)
docs: $(DEPS_DIR)/panvimdoc
	docker buildx build --load -q -t unreal-nvim-panvimdoc $(DEPS_DIR)/panvimdoc
	docker run --rm -u $$(id -u):$$(id -g) -v "$(CURDIR)":/data -w /data unreal-nvim-panvimdoc \
		--project-name unreal --input-file doc/vimdoc.md --vim-version "NVIM v$(NVIM_VERSION)" \
		--description "Neovim plugin for Unreal Engine C++ projects" --toc true --treesitter true

test: $(DEPS_DIR)/plenary.nvim $(DEPS_DIR)/tree-sitter-unreal-cpp/parser/cpp.so
	$(NVIM) -c "PlenaryBustedDirectory tests/ { minimal_init = 'scripts/minimal_init.lua', sequential = true }"

# Needs stylua on PATH; style is in .stylua.toml
LUA_DIRS := lua tests scripts

lint:
	stylua --check $(LUA_DIRS)

format:
	stylua $(LUA_DIRS)

clean:
	rm -rf $(DEPS_DIR)

# Keep in sync with config.defaults.custom_treesitter.revision
UNREAL_CPP_REV := 2d2d5c19a9a83e432e43c041252106995614b29a

$(DEPS_DIR)/tree-sitter-unreal-cpp:
	git clone https://github.com/taku25/tree-sitter-unreal-cpp $@
	cd $@ && git checkout $(UNREAL_CPP_REV)

$(DEPS_DIR)/tree-sitter-unreal-cpp/parser/cpp.so: $(DEPS_DIR)/tree-sitter-unreal-cpp
	mkdir -p $(DEPS_DIR)/tree-sitter-unreal-cpp/parser
	cd $(DEPS_DIR)/tree-sitter-unreal-cpp && $(CC) -o parser/cpp.so -Isrc src/parser.c src/scanner.c $(PARSER_CFLAGS)

$(DEPS_DIR)/panvimdoc:
	git clone --depth 1 https://github.com/kdheepak/panvimdoc $@

$(DEPS_DIR)/plenary.nvim:
	git clone --depth 1 https://github.com/nvim-lua/plenary.nvim $@
