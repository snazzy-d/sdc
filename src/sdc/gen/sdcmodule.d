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
import sdc.global;
import sdc.location;
import sdc.extract.base;
import sdc.gen.base;
import sdc.gen.type;
import sdc.gen.value;
import sdc.gen.sdcfunction;


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
    ast.DeclarationDefinition[] functionBuildList;
    Function currentFunction;
    Value base;
    Value callingAggregate;
    ast.Linkage currentLinkage = ast.Linkage.ExternD;
    ast.Access currentAccess = ast.Access.Public;
    bool isAlias;  // ewwww
    bool inferringFunction;  // OH GOD
    Function expressionFunction;  // WHAT THE FUCK IS WRONG WITH ME?
    TranslationUnit[] importedTranslationUnits;
    string arch;

    this(ast.QualifiedName name)
    {
        if (name is null) {
            throw new CompilerPanic("Module called with null name argument.");
        }
        this.name = name;
        context = LLVMGetGlobalContext();
        mod     = LLVMModuleCreateWithNameInContext(toStringz(extractQualifiedName(name)), context);
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
        auto cmd = format(`llc -march=%s -o "%s" "%s"`, arch, toFilename, fromFilename);
        system(cmd);
    }
    
    void optimiseBitcode(string filename)
    {
        auto cmd = format("opt -std-compile-opts -o %s %s", filename, filename);
        system(cmd);
    }
    
    /**
     * Optimise the generated code in place.
     */
    @disable void optimise()
    {
        auto passManager = LLVMCreatePassManager();
        scope (exit) LLVMDisposePassManager(passManager);
        LLVMAddInstructionCombiningPass(passManager);
        LLVMAddPromoteMemoryToRegisterPass(passManager);
        LLVMAddInternalizePass(passManager, false);
        LLVMRunPassManager(passManager, mod);
    }

    void pushScope()
    {
        mScopeStack ~= new Scope();
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
                tustore = new Store(tustore.type.importToModule(this));
            } else if (tustore.storeType == StoreType.Function) {
                tustore = new Store(tustore.getFunction.importToModule(this));
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
    int scopeDepth() @property
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

        auto ident = new ast.Identifier();
        ident.value = "dup";
        auto qual = new ast.QualifiedName();
        qual.identifiers = name.identifiers.dup ~ ident;
        auto mod = new Module(qual);
        
        mod.globalScope = globalScope.importToModule(mod);
        mod.currentScope = currentScope.importToModule(mod);
        mod.functionBuildList = functionBuildList.dup;
        if (currentFunction !is null) {
            currentFunction.importToModule(mod);
        }
        if (base !is null) {
            mod.base = base.importToModule(mod);
        }
        if (callingAggregate !is null) {
            mod.callingAggregate = callingAggregate.importToModule(mod);
        }
        mod.currentLinkage = currentLinkage;
        mod.currentAccess = currentAccess;
        mod.isAlias = isAlias;
        mod.importedTranslationUnits = mod.importedTranslationUnits.dup;
        mod.arch = arch;
        
        foreach (_scope; mScopeStack) {
            mod.mScopeStack ~= _scope.importToModule(mod);
        }
        mod.mFailureList = mFailureList;
        mod.mVersionIdentifiers = mVersionIdentifiers;
        mod.mTestedVersionIdentifiers = mTestedVersionIdentifiers;
        mod.mDebugIdentifiers = mDebugIdentifiers;
        mod.mTestedDebugIdentifiers = mTestedDebugIdentifiers;
        
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
        
    protected Scope[] mScopeStack;
    protected LookupFailure[] mFailureList;
    protected bool[string] mVersionIdentifiers;
    protected bool[string] mTestedVersionIdentifiers;
    protected bool[string] mDebugIdentifiers;
    protected bool[string] mTestedDebugIdentifiers;
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
    StoreType storeType;
    Object object;
    
    this(Value value)
    {
        storeType = StoreType.Value;
        object = value;
    }
    
    this(Type type)
    {
        storeType = StoreType.Type;
        object = type;
    }
    
    this(Scope _scope)
    {
        storeType = StoreType.Scope;
        object = _scope;
    }
    
    this(ast.TemplateDeclaration _template)
    {
        storeType = StoreType.Template;
        object = _template;
    }
    
    this(Function fn)
    {
        storeType = StoreType.Function;
        object = fn;
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
    
    Function getFunction() @property
    {
        assert(storeType == StoreType.Function);
        auto fn = cast(Function) object;
        assert(fn);
        return fn;
    }
    
    Store importToModule(Module mod)
    {
        Store store;
        final switch (storeType) with (StoreType) {
        case Value:
            return new Store(value.importToModule(mod));
        case Type:
            return new Store(type.importToModule(mod));
        case Scope:
            return new Store(getScope());
        case Function:
            return new Store(getFunction().importToModule(mod));
        case Template:
            return this;  
        }
    }
}

class Scope
{
    void add(string name, Store store)
    {
        mSymbolTable[name] = store;
    }
    
    Store get(string name)
    {
        auto p = name in mSymbolTable;
        return p is null ? null : *p;
    }
    
    Scope importToModule(Module mod)
    {
        auto _scope = new Scope();
        foreach (name, store; mSymbolTable) {
            _scope.add(name, store.importToModule(mod));
        }
        return _scope;
    }
    
    Store[string] mSymbolTable;
}
