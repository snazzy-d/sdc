/**
 * Copyright 2010-2011 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.sdcmodule;

import std.conv;
import std.exception;
import std.process;
import std.stdio;
import std.string;
import std.range;

import llvm.c.Analysis;
import llvm.c.BitWriter;
import llvm.c.Core;
import llvm.c.transforms.Scalar;
import llvm.c.transforms.IPO;

import sdc.compilererror;
import sdc.util;
import sdc.aglobal;
import sdc.location;
import sdc.extract;
import sdc.gen.base;
import sdc.gen.type;
import sdc.gen.value;
import sdc.gen.sdcfunction;
import sdc.gen.cfg;


/**
 * Module encapsulates the code generated for a module.
 * 
 * Also, GOD OBJECT
 */ 
class Module
{
    ast.QualifiedName name;
    LLVMContextRef context;
    LLVMModuleRef  mod;
    LLVMBuilderRef builder;
    Scope globalScope;
    Scope currentScope;
    TranslationUnit translationUnit;
    ast.DeclarationDefinition[] functionBuildList;
    Function currentFunction;
    Value base;
    Value callingAggregate;
    ast.Access currentAccess = ast.Access.Public;
    Value[]* functionPointerArguments; 

    //ReturnTypeHolder[] returnTypes;
    
    CatchTargets[] catchTargetStack;
    TranslationUnit[] importedTranslationUnits;
    string arch;
    Type aggregate;
    
    this(ast.QualifiedName name)
    {
        if (name is null) {
            throw new CompilerPanic("Module called with null name argument.");
        }
        this.name = name;
        context = LLVMGetGlobalContext();
        auto mname = extractQualifiedName(name);
        mod     = LLVMModuleCreateWithNameInContext(toStringz(mname), context);
        verbosePrint("Creating LLVM module '" ~ to!string(mod) ~ "' for module '" ~ mname ~ "'.", VerbosePrintColour.Yellow);
        builder = LLVMCreateBuilderInContext(context);
        
        globalScope = new Scope();
        currentScope = globalScope;
    }
        
    ~this()
    {
        LLVMDisposeModule(mod);
        LLVMDisposeBuilder(builder);
    }
    
    /**
     * Verify that the generated bit code is correct.
     * If it isn't, an error will be printed and the process will be aborted.
     */
    void verify()
    {
        auto failed = LLVMVerifyModule(mod, LLVMVerifierFailureAction.PrintMessage, null);
        if (failed) {
            LLVMDumpModule(mod);
            throw new CompilerPanic("Module verification failed.");
        }
    }
    
    /**
     * Dump a human readable form of the generated code to stderr.
     */
    void dump()
    {
        LLVMDumpModule(mod);
    }
    
    /**
     * Write the bitcode to a specified file.
     */
    void writeBitcodeToFile(string filename)
    {
        LLVMWriteBitcodeToFile(mod, toStringz(filename));
    }
    
    void writeNativeAssemblyToFile(string fromFilename, string toFilename)
    {
        auto cmd = format(`llc %s -march=%s -o "%s" "%s"`, PIC ? "--relocation-model=pic" : "", arch, toFilename, fromFilename);
        verbosePrint(cmd);
        auto exitCode = system(cmd);
        assert(exitCode == 0, "llc failed");
    }
    
    void optimiseBitcode(string filename)
    {
        auto cmd = format("opt -std-compile-opts -o %s %s", filename, filename);
        verbosePrint(cmd);
        auto exitCode = system(cmd);
        assert(exitCode == 0, "opt failed");
    }

    void pushScope()
    {
        auto newScope = new Scope();
        if (mScopeStack.length > 0) {
            newScope.parent = mScopeStack[$ - 1];
        } else {
            newScope.parent = globalScope;
        }
        mScopeStack ~= newScope;
        currentScope = mScopeStack[$ - 1];
    }
    
    void popScope()
    {
        assert(mScopeStack.length >= 1);
        mScopeStack = mScopeStack[0 .. $ - 1];
        currentScope = mScopeStack.length >= 1 ? mScopeStack[$ - 1] : globalScope;
    }
    
    Store search(string name)
    {
        // "Look up the symbol in the current scope."
        auto store = localSearch(name);
        if (store !is null) {
            // "If found, lookup ends successfully."
            goto exit;
        }
        
        // "Look up the symbol in the current module's scope."
        store = globalScope.get(name);
        if (store !is null) {
            // "If found, lookup ends successfully."
            goto exit;
        }
        
        // "Look up the symbol in _all_ imported modules."
        assert(store is null);
        foreach (tu; importedTranslationUnits) {
            void checkAccess(ast.Access access)
            {
                if (access != ast.Access.Public) {
                    throw new CompilerError("cannot access symbol '" ~ name ~ "', as it is declared private.");
                }
            }
            if (tu.gModule is null) {
                return null;
            }
            auto tustore = tu.gModule.globalScope.get(name);
            if (tustore is null) {
                continue;
            }

            if (tustore.storeType == StoreType.Value) {
                checkAccess(tustore.value.access);
                tustore = new Store(tustore.value.importToModule(this));
            } else if (tustore.storeType == StoreType.Type) {
                checkAccess(tustore.type.access);
                tustore = new Store(tustore.type.importToModule(this), Location());
            } else if (tustore.storeType == StoreType.Function) {
                tustore = new Store(importList(tustore.getFunctions(), this));
            }

            if (store is null) { 
                store = tustore;
                continue;
            }

            /* "If found in more than one module, 
             *  and the symbol is not the name of a function,
             *  fail with 'duplicated symbol' error message."
             */
            if (store.storeType == StoreType.Value) {
                throw new CompilerError("duplicate symbol '" ~ name ~ "'.");
            } else {
                /* "...if the symbol is the name of a function,
                 *  apply cross-module overload resolution."
                 */
                throw new CompilerPanic("no cross-module overload resolution!");
            }
        }
        
    exit:
        return store;
    }
    
    Store localSearch(string name)
    {
        foreach (localScope; retro(mScopeStack)) {
            auto v = localScope.get(name);
            if (v !is null) {
                return v;
            }
        }
        return null;
    }
    
    /**
     * Returns: the depth of the current scope.
     *          A value of zero means the current scope is global.
     */
    size_t scopeDepth() @property
    {
        return mScopeStack.length;
    }
    
    /**
     * Set a given version identifier for this module.
     */
    void setVersion(Location loc, string s)
    {
        if (isReserved(s)) {
            throw new CompilerError(loc, format("can't set reserved version identifier '%s'.", s));
        }
        if (s in mVersionIdentifiers || isVersionIdentifierSet(s)) {
            throw new CompilerError(loc, format("version identifier '%s' is already set.", s));
        }
        mVersionIdentifiers[s] = true;
    }
    
    void setDebug(Location loc, string s)
    {
        if (s in mDebugIdentifiers || isDebugIdentifierSet(s)) {
            throw new CompilerError(loc, format("debug identifier '%s' is already set.", s));
        }
        mDebugIdentifiers[s] = true;
    }
    
    bool isVersionSet(string s)
    {
        mTestedVersionIdentifiers[s] = true;
        auto result = isVersionIdentifierSet(s);
        if (!result) {
            result = (s in mVersionIdentifiers) !is null;
        }
        return result;
    }
    
    bool isDebugSet(string s)
    {
        mTestedDebugIdentifiers[s] = true;
        auto result = isDebugIdentifierSet(s);
        if (!result) {
            result = (s in mDebugIdentifiers) !is null;
        }
        return result;
    }
    
    bool hasVersionBeenTested(string s)
    {
        return (s in mTestedVersionIdentifiers) !is null;
    }
    
    bool hasDebugBeenTested(string s)
    {
        return (s in mTestedDebugIdentifiers) !is null;
    }
    
    /**
     * This is here for when you need to generate code in a contex
     * that will be discarded.
     * Usually to get the type of a given expression without side effects,
     * e.g. `int i; typeof(i++) j; assert(i == 0);`
     * 
     * WARNING: Do NOT generate code from a dup'd module --
     *          THE CODE GENERATED WILL BE INVALID/INCORRECT.   :)
     *          Further more, all variables will be reset to their init.
     */
    Module dup() @property
    {
        mDupCount++;
        auto ident = new ast.Identifier();
        ident.value = "dup";
        auto qual = new ast.QualifiedName();
        qual.identifiers = name.identifiers.dup ~ ident;
        auto mod = new Module(qual);
        
        mod.globalScope = globalScope.importToModule(mod);
        mod.currentScope = currentScope.importToModule(mod);
        mod.functionBuildList = functionBuildList.dup;
        // This will be imported when the scope stack is imported.
        mod.currentFunction = currentFunction;
        if (base !is null) {
            mod.base = base.importToModule(mod);
        }
        if (callingAggregate !is null) {
            mod.callingAggregate = callingAggregate.importToModule(mod);
        }
        
        mod.currentAccess = currentAccess;
        mod.importedTranslationUnits = importedTranslationUnits.dup;
        foreach (tu; mod.importedTranslationUnits) {
            if (tu.gModule.mDupCount == 0) {
                tu.gModule = tu.gModule.dup;
            }
        }
        mod.arch = arch;
        
        foreach (_scope; mScopeStack) {
            mod.mScopeStack ~= _scope.importToModule(mod);
        }
        mod.mFailureList = mFailureList;
        mod.mVersionIdentifiers = mVersionIdentifiers;
        mod.mTestedVersionIdentifiers = mTestedVersionIdentifiers;
        mod.mDebugIdentifiers = mDebugIdentifiers;
        mod.mTestedDebugIdentifiers = mTestedDebugIdentifiers;
        mDupCount--;
        
        return mod;
    }
    
    void addFailure(LookupFailure lookupFailure)
    {
        mFailureList ~= lookupFailure;
    }
    
    const(LookupFailure[]) lookupFailures() @property
    {
        return mFailureList;
    }

    Value gcAlloc(Location location, Value n)
    {
        auto voidPointer = new PointerType(this, new VoidType(this));
        auto sizeT = getSizeT(this);
        auto allocType = new FunctionType(this, voidPointer, [sizeT], false);
        allocType.linkage = ast.Linkage.ExternC;
        allocType.declare();

        LLVMValueRef mallocFn = LLVMGetNamedFunction(mod, "malloc");
        if (mallocFn is null) {
            auto fn = new Function(allocType);
            fn.simpleName = "malloc";
            fn.add(this);
            mallocFn = fn.llvmValue;
        }

        return buildCall(this, allocType, mallocFn, "malloc", location, [n.location], [n]);
    }

    Value gcRealloc(Location location, Value p, Value n)
    {
        auto voidPointer = new PointerType(this, new VoidType(this));
        auto sizeT = getSizeT(this);
        auto reallocType = new FunctionType(this, voidPointer, [voidPointer, sizeT], false);
        reallocType.linkage = ast.Linkage.ExternC;
        reallocType.declare();

        LLVMValueRef reallocFn = LLVMGetNamedFunction(mod, "realloc");
        if (reallocFn is null) {
            auto fn = new Function(reallocType);
            fn.simpleName = "realloc";
            fn.add(this);
            reallocFn = fn.llvmValue;
        }

        return buildCall(this, reallocType, reallocFn, "realloc", location, [p.location, n.location], [p, n]);
    }
    
    // We should totally abstract these in-built references into something a bit neater
    void rtAssert(Location location, Value condition, Value message)
    {
        auto voidType = new VoidType(this);
        auto boolType = new BoolType(this);
        auto stringType = new ArrayType(this, new CharType(this));
        auto intType = new IntType(this);
        auto assertType = new FunctionType(this, voidType, [boolType, stringType, intType, stringType], false);
        assertType.linkage = ast.Linkage.ExternC;
        assertType.declare();

        LLVMValueRef assertFn = LLVMGetNamedFunction(mod, "__d_assert");
        if (assertFn is null) {
            auto fn = new Function(assertType);
            fn.simpleName = "__d_assert";
            fn.add(this);
            assertFn = fn.llvmValue;
        }
        
        if (message is null) {
            message = new StringValue(this, location, "assert failed");
        }
        
        auto line = new IntValue(this, location, cast(int)location.line);
        auto filename = new StringValue(this, location, location.filename);
        
        buildCall(this, assertType, assertFn, "__d_assert", location,
                  [condition.location, message.location, line.location, filename.location],
                  [condition, message, line, filename]);
    }

    protected Scope[] mScopeStack;
    protected LookupFailure[] mFailureList;
    protected bool[string] mVersionIdentifiers;
    protected bool[string] mTestedVersionIdentifiers;
    protected bool[string] mDebugIdentifiers;
    protected bool[string] mTestedDebugIdentifiers;
    protected int mDupCount;
}

struct ReturnTypeHolder
{
    Type returnType;
    Location location;
}

struct CatchTargets
{
    LLVMBasicBlockRef catchBlock;
    BasicBlock catchBB;
}

struct LookupFailure
{
    string name;
    Location location;
}

enum StoreType
{
    Value,
    Type,
    Scope,
    Template,
    Function,
}

class Store
{
    Location location;
    StoreType storeType;
    Object object;
    Function[] functions;
    Scope parentScope;
    
    this(Value value)
    {
        storeType = StoreType.Value;
        object = value;
        location = value.location;
    }
    
    this(Type type, Location location)
    {
        storeType = StoreType.Type;
        object = type;
        this.location = location;
    }
    
    this(Scope _scope, Location location)
    {
        storeType = StoreType.Scope;
        object = _scope;
        this.location = location;
    }
    
    this(ast.TemplateDeclaration _template)
    {
        storeType = StoreType.Template;
        object = _template;
        location = _template.location;
    }
    
    this(Function fn, Location location)
    {
        storeType = StoreType.Function;
        addFunction(fn);
        this.location = location;
    }
    
    this(Function[] functions)
    {
        storeType = StoreType.Function;
        this.functions ~= functions;
    }
    
    Value value() @property
    {
        assert(storeType == StoreType.Value);
        auto val = cast(Value) object;
        assert(val);
        return val;
    }
    
    Type type() @property
    {
        assert(storeType == StoreType.Type);
        auto type = cast(Type) object;
        assert(type);
        return type;
    }
    
    Scope getScope() @property
    {
        assert(storeType == StoreType.Scope);
        auto _scope = cast(Scope) object;
        assert(_scope);
        return _scope;
    }
    
    ast.TemplateDeclaration getTemplate() @property
    {
        assert(storeType == StoreType.Template);
        auto _template = cast(ast.TemplateDeclaration) object;
        assert(_template);
        return _template;
    }
    
    void addFunction(Function fn)
    {
        assert(storeType == StoreType.Function);
        functions ~= fn;
    }
    
    Function[] getFunctions() @property
    {
        assert(storeType == StoreType.Function);
        return functions;
    }
    
    Store importToModule(Module mod)
    {
        Store store;
        final switch (storeType) with (StoreType) {
        case Value:
            return new Store(value.importToModule(mod));
        case Type:
            return new Store(type.importToModule(mod), Location());
        case Scope:
            return new Store(getScope(), Location());
        case Function:
            return new Store(importList(getFunctions(), mod));
        case Template:
            return this;  
        }
    }
}

class Scope
{
    Scope parent;
    
    void add(string name, Store store)
    {
        if (auto p = definedInParents(name)) {
            if (p.parentScope.parent !is null) {
                throw new CompilerError(store.location, format("declaration of '%s' shadows declaration at '%s'.", name, p.location));
            }
        }
        if (auto p = name in mSymbolTable) {
            if (p.storeType != StoreType.Scope) {
                throw new CompilerError(store.location, format("redefinition of '%s', defined at '%s'.", name, p.location));
            }
        }
        mSymbolTable[name] = store;
        store.parentScope = this;
    }
    
    void add(string name, Function fn)
    {
        if (auto p = name in mSymbolTable) {
            p.addFunction(fn);
        } else {
            mSymbolTable[name] = new Store(fn, fn.location);
        }
    }
    
    void redefine(string name, Store store)
    {
        if (name in mSymbolTable) {
            mSymbolTable[name] = store;
            store.parentScope = this;
        } else {
            throw new CompilerPanic(store.location, format("tried to redefine undefined store."));
        }
    }
    
    Store get(string name)
    {
        return mSymbolTable.get(name, null);
    }
    
    Scope importToModule(Module mod)
    {
        auto _scope = new Scope();
        foreach (name, store; mSymbolTable) {
            _scope.add(name, store.importToModule(mod));
        }
        return _scope;
    }
    
    Store* definedInParents(string name)
    {
        Scope current = parent;
        while (current !is null) {
            if (auto p = name in current.mSymbolTable) {
                return p;
            }
            current = current.parent;
        }
        return null; 
    }
    
    Store[string] mSymbolTable;
}
