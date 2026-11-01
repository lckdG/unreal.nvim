local h = dofile("tests/helpers.lua")
local impl = require("unreal.impl")

local HEADER = "Source/Mod/Public/Foo.h"
local CPP = "Source/Mod/Private/Foo.cpp"
local CPP_PREFIX = { '#include "Foo.h"' }

local function uclass(decls)
    local lines = { "#pragma once", "", "UCLASS()", "class AFoo : public AActor", "{", "\tGENERATED_BODY()", "public:" }
    for _, d in ipairs(decls) do table.insert(lines, "\t" .. d) end
    table.insert(lines, "};")
    return lines
end

local function ustruct(decls)
    local lines = { "#pragma once", "", "USTRUCT()", "struct FBar", "{", "\tGENERATED_BODY()" }
    for _, d in ipairs(decls) do table.insert(lines, "\t" .. d) end
    table.insert(lines, "};")
    return lines
end

local function uinterface(decls)
    local lines = {
        "#pragma once", "",
        "UINTERFACE()", "class UFoo : public UInterface", "{", "\tGENERATED_BODY()", "};", "",
        "class IFoo", "{", "\tGENERATED_BODY()", "public:",
    }
    for _, d in ipairs(decls) do table.insert(lines, "\t" .. d) end
    table.insert(lines, "};")
    return lines
end

local function create_impl(header, cursorOn, cppLines)
    h.project({ [HEADER] = header, [CPP] = cppLines or CPP_PREFIX })
    local row
    for i, line in ipairs(header) do
        if line:find(cursorOn, 1, true) then row = i end
    end
    assert(row, "cursor line not found: " .. cursorOn)
    h.edit(HEADER, row)
    impl.ImplementFunction()
    local cppBuf = vim.fn.bufnr(CPP)
    if cppBuf == -1 then return {} end
    local lines = vim.api.nvim_buf_get_lines(cppBuf, 0, -1, false)
    return vim.list_slice(lines, #(cppLines or CPP_PREFIX) + 1)
end

local function stub(sig, super)
    local t = { "", sig }
    if super then table.insert(t, "\t: " .. super) end
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
        { "params + const", uclass({ "int32 Add(int32 A, int32 B) const;" }), "Add(",
            stub("int32 AFoo::Add(int32 A, int32 B) const") },
        { "constructor with FObjectInitializer", uclass({ "AFoo(const FObjectInitializer& OI);" }), "AFoo(",
            stub("AFoo::AFoo(const FObjectInitializer& OI)", "Super(OI)") },
        { "default constructor", uclass({ "AFoo();" }), "AFoo();", stub("AFoo::AFoo()", "Super()") },
        { "destructor", uclass({ "~AFoo();" }), "~AFoo", stub("AFoo::~AFoo()") },
        { "pointer return", uclass({ "AActor* GetFoo();" }), "GetFoo", stub("AActor* AFoo::GetFoo()") },
        { "const reference return", uclass({ "const FString& GetName() const;" }), "GetName",
            stub("const FString& AFoo::GetName() const") },
        { "template return", uclass({ "TArray<int32> GetList();" }), "GetList", stub("TArray<int32> AFoo::GetList()") },
        { "qualified return", uclass({ "FVector::FReal Len();" }), "Len(", stub("FVector::FReal AFoo::Len()") },
        { "default argument", uclass({ "void Fire(int32 Count = 5);" }), "Fire(", stub("void AFoo::Fire(int32 Count)") },
        { "several default arguments", uclass({ 'void Fire(int32 A = 1, FString B = TEXT("x"));' }), "Fire(",
            stub("void AFoo::Fire(int32 A, FString B)") },
        { "leading const", uclass({ "const FString GetLabel();" }), "GetLabel", stub("const FString AFoo::GetLabel()") },
        { "virtual override", uclass({ "virtual void Tick(float DeltaTime) override;" }), "Tick(",
            stub("void AFoo::Tick(float DeltaTime)") },
        { "static", uclass({ "static void Reset();" }), "Reset(", stub("void AFoo::Reset()") },
        { "BlueprintNativeEvent", uclass({ "UFUNCTION(BlueprintNativeEvent)", "void OnHit();" }), "OnHit",
            stub("void AFoo::OnHit_Implementation()") },
        { "Client RPC", uclass({ "UFUNCTION(Client, Reliable)", "void ClientPing();" }), "ClientPing",
            stub("void AFoo::ClientPing_Implementation()") },
        { "NetMulticast RPC", uclass({ "UFUNCTION(NetMulticast, Unreliable)", "void Boom();" }), "Boom",
            stub("void AFoo::Boom_Implementation()") },
        { "USTRUCT", ustruct({ "void Foo();" }), "void Foo();", stub("void FBar::Foo()") },
        { "interface", uinterface({ "void Foo();" }), "void Foo();", stub("void IFoo::Foo()") },
    }

    for _, case in ipairs(cases) do
        it(case[1], function()
            assert.are.same(case[4], create_impl(case[2], case[3]))
        end)
    end

    it("Server RPC WithValidation -> _Implementation and _Validate", function()
        local appended = create_impl(
            uclass({ "UFUNCTION(Server, Reliable, WithValidation)", "void ServerFire();" }), "ServerFire")
        assert.is_true(vim.tbl_contains(appended, "void AFoo::ServerFire_Implementation()"), vim.inspect(appended))
        assert.is_true(vim.tbl_contains(appended, "bool AFoo::ServerFire_Validate()"), vim.inspect(appended))
    end)

    -- card: [CreateImpl] - Support pointer, reference and template return types
    local returnTypes = {
        { "pointer to pointer", uclass({ "UObject** GetPP();" }), "GetPP", stub("UObject** AFoo::GetPP()") },
        { "pointer return with params + const", uclass({ "UObject* GetFoo(int32 A, const FString& B) const;" }), "GetFoo",
            stub("UObject* AFoo::GetFoo(int32 A, const FString& B) const") },
        { "reference return", uclass({ "FVector& GetRef();" }), "GetRef", stub("FVector& AFoo::GetRef()") },
        { "const pointer to const pointer", uclass({ "const AActor* const* GetFoo() const;" }), "GetFoo",
            stub("const AActor* const* AFoo::GetFoo() const") },
        { "static const reference", uclass({ "static const TArray<int32>& GetArr();" }), "GetArr",
            stub("const TArray<int32>& AFoo::GetArr()") },
        { "virtual const pointer override", uclass({ "virtual const UObject* GetV(int32 A) const override;" }), "GetV",
            stub("const UObject* AFoo::GetV(int32 A) const") },
        { "UFUNCTION pointer return", uclass({ "UFUNCTION(BlueprintCallable)", "UObject* GetBp(int32 A);" }), "GetBp",
            stub("UObject* AFoo::GetBp(int32 A)") },
        { "UFUNCTION const pointer to const pointer", uclass({ "UFUNCTION()", "const AActor* const* GetBp() const;" }), "GetBp",
            stub("const AActor* const* AFoo::GetBp() const") },
        { "function pointer param", uclass({ "void Bind(void (*Cb)(int32 X), int32 Y);" }), "Bind(",
            stub("void AFoo::Bind(void (*Cb)(int32 X), int32 Y)") },
        { "TFunction param", uclass({ "void Bind(TFunction<void(int32)> F);" }), "Bind(",
            stub("void AFoo::Bind(TFunction<void(int32)> F)") },
        { "constructor with default argument", uclass({ "AFoo(const FObjectInitializer& OI = FObjectInitializer::Get());" }), "AFoo(",
            stub("AFoo::AFoo(const FObjectInitializer& OI)", "Super(OI)") },
        { "constructor with pointer param", uclass({ "AFoo(UObject* Outer);" }), "AFoo(",
            stub("AFoo::AFoo(UObject* Outer)", "Super(Outer)") },
    }

    for _, case in ipairs(returnTypes) do
        it(case[1], function()
            assert.are.same(case[4], create_impl(case[2], case[3]))
        end)
    end

    -- Test Cases note, "Gaps found in test review" impl rows 21-34
    local gaps = {
        { "21: declaration across lines", uclass({ "void Foo(int32 A,", "\tint32 B);" }), "void Foo(int32 A,",
            stub("void AFoo::Foo(int32 A, int32 B)") },
        { "22: API macro", uclass({ "MYMOD_API void Foo();" }), "MYMOD_API", stub("void AFoo::Foo()") },
        { "23: FORCEINLINE", uclass({ "FORCEINLINE void Foo();" }), "FORCEINLINE", stub("void AFoo::Foo()") },
        { "24: noexcept", uclass({ "void Foo() noexcept;" }), "noexcept", stub("void AFoo::Foo() noexcept") },
        { "27: final", uclass({ "virtual void Foo() override final;" }), "final", stub("void AFoo::Foo()") },
        { "28: member template", uclass({ "template<typename T> void Foo(T V);" }), "template<",
            { "", "template<typename T>", "void AFoo::Foo(T V)", "{", "\t// TODO:", "}" } },
        { "29: operator", uclass({ "bool operator==(const AFoo& O) const;" }), "operator==",
            stub("bool AFoo::operator==(const AFoo& O) const") },
        { "31: cursor on UFUNCTION line", uclass({ "UFUNCTION(BlueprintCallable)", "void OnCall();" }), "UFUNCTION(BlueprintCallable)",
            stub("void AFoo::OnCall()") },
    }

    for _, case in ipairs(gaps) do
        it(case[1], function()
            assert.are.same(case[4], create_impl(case[2], case[3]))
        end)
    end

    local noStub = {
        { "25: pure virtual", uclass({ "virtual void Foo() = 0;" }), "= 0" },
        { "26: deleted", uclass({ "AFoo(const AFoo&) = delete;" }), "= delete" },
        { "30: inline body", uclass({ "void Foo() {}" }), "void Foo() {}" },
        { "34: BlueprintImplementableEvent", uclass({ "UFUNCTION(BlueprintImplementableEvent)", "void OnBP();" }), "OnBP" },
    }

    for _, case in ipairs(noStub) do
        it(case[1] .. " -> no stub, notify", function()
            assert.are.same({}, create_impl(case[2], case[3]))
            assert.is_true(#notes > 0)
        end)
    end

    it("32: nested class -> qualified name", function()
        local header = {
            "#pragma once", "",
            "UCLASS()", "class AFoo : public AActor", "{", "\tGENERATED_BODY()", "public:",
            "\tclass FInner", "\t{", "\tpublic:", "\t\tvoid Foo();", "\t};",
            "};",
        }
        assert.are.same(stub("void AFoo::FInner::Foo()"), create_impl(header, "void Foo();"))
    end)

    it("33: target .cpp already loaded with unsaved edits -> stub appended, edits kept", function()
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
        assert.is_true(h.notified(notes, "Function does not have a name", vim.log.levels.ERROR))
    end)

    describe("behaviour", function()
        it("from a .cpp -> 'Not a header file!'", function()
            h.project({ [CPP] = CPP_PREFIX })
            h.edit(CPP, 1)
            impl.ImplementFunction()
            assert.is_true(h.notified(notes, "Not a header file!", vim.log.levels.ERROR))
        end)

        it("no matching .cpp -> error", function()
            h.project({ [HEADER] = uclass({ "void Foo();" }) })
            h.edit(HEADER, 8)
            impl.ImplementFunction()
            assert.is_true(h.notified(notes, "Cannot find corresponding cpp file!", vim.log.levels.ERROR))
        end)

        it("cursor outside any class -> error", function()
            create_impl({ "#pragma once", "void Bar();" }, "void Bar();")
            assert.is_true(h.notified(notes, "Unable to find class name for implementation creation!", vim.log.levels.ERROR))
        end)

        it("cursor on a non-function line -> error, nothing inserted", function()
            local appended = create_impl(uclass({ "int32 Health;" }), "int32 Health;")
            assert.are.same({}, appended)
            assert.is_true(h.notified(notes, "Function does not have a name", vim.log.levels.ERROR))
        end)

        it("already implemented -> info, cursor on it, nothing inserted", function()
            local cpp = { '#include "Foo.h"', "", "void AFoo::Foo()", "{", "}" }
            local appended = create_impl(uclass({ "void Foo();" }), "void Foo();", cpp)
            assert.are.same({}, appended)
            assert.is_true(h.notified(notes, "Function is already implemented at line 3", vim.log.levels.INFO))
            assert.are.equal(3, vim.api.nvim_win_get_cursor(0)[1])
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

        it("cursor lands on the new signature", function()
            create_impl(uclass({ "void Foo();" }), "void Foo();")
            local row = vim.api.nvim_win_get_cursor(0)[1]
            assert.are.equal("void AFoo::Foo()", vim.api.nvim_get_current_line(), "cursor row " .. row)
        end)

        it("flat module layout finds the cpp", function()
            h.project({ ["Source/Mod/Foo.h"] = uclass({ "void Foo();" }), ["Source/Mod/Foo.cpp"] = CPP_PREFIX })
            h.edit("Source/Mod/Foo.h", 8)
            impl.ImplementFunction()
            local lines = vim.api.nvim_buf_get_lines(vim.fn.bufnr("Source/Mod/Foo.cpp"), 0, -1, false)
            assert.is_true(vim.tbl_contains(lines, "void AFoo::Foo()"))
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
