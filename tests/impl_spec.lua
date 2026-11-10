local h = dofile("tests/helpers.lua")
local impl = require("unreal.impl")

local HEADER = "Source/Mod/Public/Foo.h"
local CPP = "Source/Mod/Private/Foo.cpp"
local CPP_PREFIX = { '#include "Foo.h"' }

local function uclass(decls)
    local lines = { "#pragma once", "", "UCLASS()", "class AFoo : public AActor", "{", "\tGENERATED_BODY()", "public:" }
    for _, d in ipairs(decls) do
        table.insert(lines, "\t" .. d)
    end
    table.insert(lines, "};")
    return lines
end

local function ustruct(decls)
    local lines = { "#pragma once", "", "USTRUCT()", "struct FBar", "{", "\tGENERATED_BODY()" }
    for _, d in ipairs(decls) do
        table.insert(lines, "\t" .. d)
    end
    table.insert(lines, "};")
    return lines
end

local function uinterface(decls)
    local lines = {
        "#pragma once",
        "",
        "UINTERFACE()",
        "class UFoo : public UInterface",
        "{",
        "\tGENERATED_BODY()",
        "};",
        "",
        "class IFoo",
        "{",
        "\tGENERATED_BODY()",
        "public:",
    }
    for _, d in ipairs(decls) do
        table.insert(lines, "\t" .. d)
    end
    table.insert(lines, "};")
    return lines
end

local function create_impl(header, cursorOn, cppLines, colOn)
    h.project({ [HEADER] = header, [CPP] = cppLines or CPP_PREFIX })
    local row
    for i, line in ipairs(header) do
        if line:find(cursorOn, 1, true) then
            row = i
        end
    end
    assert(row)
    h.edit(HEADER, row)
    if colOn then
        local col = header[row]:find(colOn, 1, true)
        assert(col)
        vim.api.nvim_win_set_cursor(0, { row, col - 1 })
    end
    local headerBuf = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local function again()
        vim.api.nvim_set_current_buf(headerBuf)
        vim.api.nvim_win_set_cursor(0, cursor)
        impl.ImplementFunction()
    end
    impl.ImplementFunction()
    local cppBuf = vim.fn.bufnr(CPP)
    if cppBuf == -1 then
        return {}, again
    end
    local lines = vim.api.nvim_buf_get_lines(cppBuf, 0, -1, false)
    return vim.list_slice(lines, #(cppLines or CPP_PREFIX) + 1), again
end

local function stub(sig, super)
    local t = { "", sig }
    if super then
        table.insert(t, "\t: " .. super)
    end
    vim.list_extend(t, { "{", "\t// TODO:", "}" })
    return t
end

describe("impl.ImplementFunction", function()
    local notes

    before_each(function()
        notes = h.notifications()
    end)
    after_each(h.reset)

    local cases = {
        { "void", uclass({ "void Foo();" }), "void Foo();", stub("void AFoo::Foo()") },
        {
            "params + const",
            uclass({ "int32 Add(int32 A, int32 B) const;" }),
            "Add(",
            stub("int32 AFoo::Add(int32 A, int32 B) const"),
        },
        {
            "constructor with FObjectInitializer",
            uclass({ "AFoo(const FObjectInitializer& OI);" }),
            "AFoo(",
            stub("AFoo::AFoo(const FObjectInitializer& OI)", "Super(OI)"),
        },
        { "default constructor", uclass({ "AFoo();" }), "AFoo();", stub("AFoo::AFoo()", "Super()") },
        { "destructor", uclass({ "~AFoo();" }), "~AFoo", stub("AFoo::~AFoo()") },
        { "template return", uclass({ "TArray<int32> GetList();" }), "GetList", stub("TArray<int32> AFoo::GetList()") },
        { "qualified return", uclass({ "FVector::FReal Len();" }), "Len(", stub("FVector::FReal AFoo::Len()") },
        {
            "const pointer to const pointer return",
            uclass({ "const AActor* const* GetFoo() const;" }),
            "GetFoo",
            stub("const AActor* const* AFoo::GetFoo() const"),
        },
        {
            "default arguments",
            uclass({ 'void Fire(int32 A = 1, FString B = TEXT("x"));' }),
            "Fire(",
            stub("void AFoo::Fire(int32 A, FString B)"),
        },
        {
            "function pointer param",
            uclass({ "void Bind(void (*Cb)(int32 X), int32 Y);" }),
            "Bind(",
            stub("void AFoo::Bind(void (*Cb)(int32 X), int32 Y)"),
        },
        {
            "TFunction param",
            uclass({ "void Bind(TFunction<void(int32)> F);" }),
            "Bind(",
            stub("void AFoo::Bind(TFunction<void(int32)> F)"),
        },
        {
            "virtual override",
            uclass({ "virtual void Tick(float DeltaTime) override;" }),
            "Tick(",
            stub("void AFoo::Tick(float DeltaTime)"),
        },
        { "static", uclass({ "static void Reset();" }), "Reset(", stub("void AFoo::Reset()") },
        {
            "declaration across lines",
            uclass({ "void Foo(int32 A,", "\tint32 B);" }),
            "void Foo(int32 A,",
            stub("void AFoo::Foo(int32 A, int32 B)"),
        },
        { "API macro", uclass({ "MYMOD_API void Foo();" }), "MYMOD_API", stub("void AFoo::Foo()") },
        { "FORCEINLINE", uclass({ "FORCEINLINE void Foo();" }), "FORCEINLINE", stub("void AFoo::Foo()") },
        { "noexcept", uclass({ "void Foo() noexcept;" }), "noexcept", stub("void AFoo::Foo() noexcept") },
        { "final", uclass({ "virtual void Foo() override final;" }), "final", stub("void AFoo::Foo()") },
        {
            "member template",
            uclass({ "template<typename T> void Foo(T V);" }),
            "template<",
            { "", "template<typename T>", "void AFoo::Foo(T V)", "{", "\t// TODO:", "}" },
        },
        {
            "operator",
            uclass({ "bool operator==(const AFoo& O) const;" }),
            "operator==",
            stub("bool AFoo::operator==(const AFoo& O) const"),
        },
        {
            "cursor on UFUNCTION line",
            uclass({ "UFUNCTION(BlueprintCallable)", "void OnCall();" }),
            "UFUNCTION(BlueprintCallable)",
            stub("void AFoo::OnCall()"),
        },
        {
            "BlueprintNativeEvent",
            uclass({ "UFUNCTION(BlueprintNativeEvent)", "void OnHit();" }),
            "OnHit",
            stub("void AFoo::OnHit_Implementation()"),
        },
        {
            "Server RPC WithValidation",
            uclass({ "UFUNCTION(Server, Reliable, WithValidation)", "void ServerFire();" }),
            "ServerFire",
            vim.list_extend(stub("void AFoo::ServerFire_Implementation()"), stub("bool AFoo::ServerFire_Validate()")),
        },
        { "USTRUCT", ustruct({ "void Foo();" }), "void Foo();", stub("void FBar::Foo()") },
        { "interface", uinterface({ "void Foo();" }), "void Foo();", stub("void IFoo::Foo()") },
    }

    local OTHER_STUB = { '#include "Foo.h"', "", "void AFoo::Other()", "{", "\t// TODO:", "}" }

    local function signature(block)
        for _, line in ipairs(block) do
            if line ~= "" and not vim.startswith(line, "template") then
                return line
            end
        end
    end

    for _, case in ipairs(cases) do
        it(case[1] .. " -> stub after other stubs, cursor on signature, second run adds nothing", function()
            local appended, again = create_impl(case[2], case[3], OTHER_STUB)
            assert.are.same(case[4], appended)
            assert.are.equal(signature(case[4]), vim.api.nvim_get_current_line())

            local cppBuf = vim.api.nvim_get_current_buf()
            local before = vim.api.nvim_buf_get_lines(cppBuf, 0, -1, false)
            again()
            assert.are.same(before, vim.api.nvim_buf_get_lines(cppBuf, 0, -1, false))
            assert.are.equal(signature(case[4]), vim.api.nvim_get_current_line())
            assert.is_true(h.notified(notes, vim.log.levels.INFO))
        end)
    end

    local elaborated = {
        { "class", uclass({ "class AActor* GetOwnerActor();" }), "class AActor* AFoo::GetOwnerActor()", "all" },
        { "struct", uclass({ "struct FHitResult* GetHit();" }), "struct FHitResult* AFoo::GetHit()", "name" },
    }
    for _, case in ipairs(elaborated) do
        local line = case[2][#case[2] - 1]:gsub("^\t", "")
        local typeName = line:match("^%a+ (%w+)")
        local fnName = line:match("(%w+)%(")
        local cols = case[4] == "all" and { case[1], typeName, fnName } or { fnName }
        for _, col in ipairs(cols) do
            it("elaborated " .. case[1] .. " return, cursor on " .. col, function()
                assert.are.same(stub(case[3]), (create_impl(case[2], fnName, nil, col)))
            end)
        end
    end

    local ERROR, WARN = vim.log.levels.ERROR, vim.log.levels.WARN
    local noStub = {
        { "pure virtual", uclass({ "virtual void Foo() = 0;" }), "= 0", ERROR },
        { "deleted", uclass({ "AFoo(const AFoo&) = delete;" }), "= delete", ERROR },
        { "inline body", uclass({ "void Foo() {}" }), "void Foo() {}", ERROR },
        {
            "BlueprintImplementableEvent",
            uclass({ "UFUNCTION(BlueprintImplementableEvent)", "void OnBP();" }),
            "OnBP",
            WARN,
        },
    }

    for _, case in ipairs(noStub) do
        it(case[1] .. " -> no stub, " .. (case[4] == WARN and "warn" or "error"), function()
            assert.are.same({}, (create_impl(case[2], case[3])))
            assert.is_true(h.notified(notes, case[4]))
        end)
    end

    it("nested class -> qualified name", function()
        local header = {
            "#pragma once",
            "",
            "UCLASS()",
            "class AFoo : public AActor",
            "{",
            "\tGENERATED_BODY()",
            "public:",
            "\tclass FInner",
            "\t{",
            "\tpublic:",
            "\t\tvoid Foo();",
            "\t};",
            "};",
        }
        assert.are.same(stub("void AFoo::FInner::Foo()"), (create_impl(header, "void Foo();")))
    end)

    it("target .cpp already loaded with unsaved edits -> stub appended, edits kept", function()
        h.project({ [HEADER] = uclass({ "void Foo();" }), [CPP] = CPP_PREFIX })
        vim.cmd.edit(CPP)
        local cppBuf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(cppBuf, -1, -1, false, { "// unsaved" })
        h.edit(HEADER, 8)
        impl.ImplementFunction()
        local lines = vim.api.nvim_buf_get_lines(cppBuf, 0, -1, false)
        assert.are.same(vim.list_extend({ '#include "Foo.h"', "// unsaved" }, stub("void AFoo::Foo()")), lines)
    end)

    it("data member with template type -> error, nothing inserted", function()
        local appended = create_impl(uclass({ "TArray<int32> Items;" }), "Items;")
        assert.are.same({}, appended)
        assert.is_true(h.notified(notes, vim.log.levels.ERROR))
    end)

    describe("behaviour", function()
        it("from a .cpp -> 'Not a header file!'", function()
            h.project({ [CPP] = CPP_PREFIX })
            h.edit(CPP, 1)
            impl.ImplementFunction()
            assert.is_true(h.notified(notes, vim.log.levels.ERROR))
        end)

        it("no matching .cpp -> error", function()
            h.project({ [HEADER] = uclass({ "void Foo();" }) })
            h.edit(HEADER, 8)
            impl.ImplementFunction()
            assert.is_true(h.notified(notes, vim.log.levels.ERROR))
        end)

        it("cursor outside any class -> error", function()
            create_impl({ "#pragma once", "void Bar();" }, "void Bar();")
            assert.is_true(h.notified(notes, vim.log.levels.ERROR))
        end)

        it("cursor on a non-function line -> error, nothing inserted", function()
            local appended = create_impl(uclass({ "int32 Health;" }), "int32 Health;")
            assert.are.same({}, appended)
            assert.is_true(h.notified(notes, vim.log.levels.ERROR))
        end)

        it("same signature with different whitespace -> inserted again", function()
            local cpp = { '#include "Foo.h"', "", "void  AFoo::Foo()", "{", "}" }
            local appended = create_impl(uclass({ "void Foo();" }), "void Foo();", cpp)
            assert.are.same(stub("void AFoo::Foo()"), appended)
        end)

        it("switches to the cpp buffer, loading it if needed", function()
            create_impl(uclass({ "void Foo();" }), "void Foo();")
            assert.is_true(h.ends_with(vim.api.nvim_buf_get_name(0), CPP))
            assert.is_true(vim.api.nvim_buf_is_loaded(0))
        end)
    end)

    it("impl does not load unreal.search", function()
        h.unload()
        require("unreal.impl")
        local loaded = package.loaded["unreal.search"] ~= nil
        h.unload()
        assert.is_false(loaded)
    end)
end)
