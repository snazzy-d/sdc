/**
 * Copyright 2011 Bernard Helyer.
 * Copyright 2011 Jakob Ovrum.
 * This file is part of SDC.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.sdcfunction;

import std.algorithm;
import std.array;
import std.conv;
import std.string;
import core.runtime;

import llvm.c.Core;
import llvm.Ext;

import sdc.compilererror;
import sdc.aglobal;
import sdc.location;
import sdc.mangle;
import sdc.util;
import sdc.extract;
import sdc.ast.attribute;
import sdc.ast.declaration : FunctionDeclaration;
import sdc.ast.statement;
import sdc.gen.cfg;
import sdc.gen.type;
import sdc.gen.value;
import sdc.gen.sdcmodule;


/**
 * A function type consists of the return type and 
 * the types of a function's parameters, plus the
 * linkage (C, C++, D, etc) for calling convention
 * and mangling purposes.
 */
class FunctionType : Type
{
    Linkage linkage;
    Type returnType;
    Type[] parameterTypes;
    Type parentAggregate;
    bool isStatic;
    bool varargs;
    Module mod;
    
    this(Module mod, Type returnType, Type[] parameterTypes, bool varargs)
    {
        super(mod);
        dtype = DType.Function;
        this.returnType = returnType;
        this.parameterTypes = parameterTypes;
        this.varargs = varargs;
        declare();
        this.mod = mod;
    }
    
    /**
     * Create the LLVM function type based on current settings.
     * To update a type, simply call again. Any functions will
     * have to be removed and readded for changes to take effect,
     * however.
     */
    void declare()
    {
        LLVMTypeRef[] params;
        foreach (ref t; parameterTypes) {
            auto type = t;
            if (t.isRef) {
                type = new PointerType(type.mModule, type);
                t.isRef = true;
            }
            params ~= type.llvmType;
        }
        
        if (returnType.dtype == DType.Inferred) {
            /* The return type here doesn't matter, we just need
             * *something* to get a valid LLVM function type.
             * This will be then generated with the real return type.
             */
            // Will this work with undef? That would make more sense. TODO.
            mType = LLVMFunctionType(LLVMInt32Type(), params.ptr, cast(uint) params.length, varargs);
        } else {
            mType = LLVMFunctionType(returnType.llvmType, params.ptr, cast(uint) params.length, varargs);
        }
    }
    
    override Value getValue(Module mod, Location location)
    {
        throw new CompilerPanic(location, "attempted to getValue of a FunctionType.");
    }
    
    // TODO: change this when opEquals doesn't suck anymore.
    override bool equals(Type type)
    {
        auto fnType = cast(FunctionType) type;
        if (fnType is null ||
            linkage != fnType.linkage ||
            !returnType.equals(fnType.returnType) ||
            parameterTypes.length != fnType.parameterTypes.length) {
            return false;
        }
        
        foreach (i, param; parameterTypes) {
            if (!param.equals(fnType.parameterTypes[i])) {
                return false;
            }
        }
        
        return true;
    }
    
    /**
     * Create an equivalent FunctionType in the given Module.
     */
    override FunctionType importToModule(Module mod)
    {
        Type importType(Type t) { return t.importToModule(mod); }
        auto importedTypes = array( map!importType(parameterTypes) );   
            
        auto fn = new FunctionType(mod, returnType.importToModule(mod), importedTypes, varargs);
        fn.linkage = linkage;
        if (fn.parentAggregate !is null) {
            fn.parentAggregate = parentAggregate.importToModule(mod);
        }
        assert(parameterTypes.length == fn.parameterTypes.length);
        return fn;
    }
    
    enum ToStringType
    {
        Function,
        FunctionPointer,
        Delegate
    }
    
    /**
     * Get the string representation of this function either as a function,
     * function pointer or delegate.
     */
    string toString(ToStringType type)
    {
        auto namestr = returnType.name();
        
        if (type == ToStringType.FunctionPointer) {
            namestr ~= " function";
        } else if (type == ToStringType.Delegate) {
            namestr ~= " delegate";
        }
        
        if (linkage != Linkage.D) {
            namestr ~= " " ~ linkageToString(linkage);
        }
        
        namestr ~= "(";
        foreach (i, param; parameterTypes) {
            namestr ~= param.name();
            if (i < parameterTypes.length - 1) {
                namestr ~= ", ";
            }
        }
        return namestr ~ ")";
    }
    
    override string name() { return toString(ToStringType.Function); }
}

/**
 * Function is an interface to the actual block of code that is the function.
 */
class Function
{
    Location location;
    FunctionType type;
    string simpleName;
    string mangledName;
    string[] argumentNames;
    Location[] argumentLocations;
    Location argumentListLocation;
    Module mod = null;
    BasicBlock cfgEntry;
    BasicBlock cfgTail;
    LLVMBasicBlockRef currentBasicBlock;
    Label[string] labels;
    PendingGoto[] pendingGotos;
    /// This function was rewritten from void main to int main.
    bool convertedFromVoidMain;
    
    LLVMValueRef llvmValue;
    
    this(FunctionType type)
    {
        this.type = type;
    }
    
    /**
     * Replace this function in place with a function that
     * is identical save for a single new argument.
     */
    void addParameter(Type parameterType, string parameterName)
    {
        type.parameterTypes ~= parameterType;
        argumentNames ~= parameterName;
        if (argumentLocations.length >= 1) {
            argumentLocations ~= argumentLocations[$ - 1];
        } else {
            argumentLocations ~= argumentListLocation;
        }
        type.declare();
        if (mod !is null) {
            auto m = mod;
            remove();
            Type[] args = type.parameterTypes;
            if (parameterName == "this") {
                // Omit the this parameter from mangling.
                type.parameterTypes = type.parameterTypes[0 .. $ - 1];  // HAX!
            }
            add(m);
            type.parameterTypes = args;
        }
    }
    
    /**
     * Assign this Function to the Module `mod`.
     * Function's can only be assigned to one Module at a time.   
     */
    void add(Module mod, string forceMangle = null)
    {
        if (this.mod !is null) {
            if (mod !is this.mod) {
                throw new CompilerPanic("attemped to add assigned function '" ~ simpleName ~ "' to another module.");
            } else {
                // We're already assigned to this Module.
                return;
            }
        }
        
        this.mod = mod;
        
        if (simpleName == "main") {
            type.linkage = Linkage.C;
        }
        
        if (type.linkage == Linkage.D && forceMangle is null) {
            mangledName = mangleFunction(this);
        } else if (forceMangle !is null) {
            mangledName = forceMangle;
        } else {
            mangledName = simpleName;
        }
        
        auto mangledNamez = toStringz(mangledName);
        
        if (auto p = LLVMGetNamedFunction(mod.mod, mangledNamez)) {
            llvmValue = p;
            return;
        }
        
        verbosePrint("Adding function '" ~ mangledName ~ "' (" ~ to!string(cast(void*)this) ~ ") to LLVM module '" ~ to!string(mod.mod) ~ "'.", VerbosePrintColour.Yellow);
        llvmValue = LLVMAddFunction(mod.mod, mangledNamez, type.mType);
        if (type.linkage != Linkage.C) {
            LLVMSetFunctionCallConv(llvmValue, linkageToCallConv(type.linkage));
        }
    }
    
    /**
     * Remove this function from its currently assigned Module. 
     */
    void remove()
    {
        if (mod is null) {
            throw new CompilerPanic("attemped to remove unassigned function '" ~ simpleName ~ "'.");
        }
        mod = null;
        LLVMDeleteFunction(llvmValue);
    }
    
    Function importToModule(Module mod)
    {
        auto fn = new Function(type);
        
        fn.location = this.location;
        fn.type = type.importToModule(mod);
        fn.simpleName = this.simpleName;
        fn.argumentNames = this.argumentNames.dup;
        fn.argumentLocations = this.argumentLocations.dup;
        fn.argumentListLocation = this.argumentListLocation;
        fn.cfgEntry = this.cfgEntry;
        fn.cfgTail = this.cfgTail;
        fn.mod = null;
        fn.add(mod, this.mangledName);
        
        return fn;
    }
    
    Value addressOf(Location location)
    {
        auto fptr = new PointerValue(mod, location, type);
        fptr.initialise(location, llvmValue);
        return fptr;
    }
    
    /**
     * Generate code to call this function.
     */
    Value call(Location callLocation, Location[] argLocations, Value[] args)
    {
        if (mod is null) {
            throw new CompilerPanic(callLocation, "attemped to call unassigned Function.");
        }
        Value retVal;
        try {
            retVal = buildCall(mod, type, llvmValue, simpleName, callLocation, argLocations, args);
        } catch(ArgumentMismatchError error) {
            Location loc;
            string message;
            if (error.argNumber == ArgumentMismatchError.unspecified) {
                loc = argumentListLocation;
                message = format("parameters of '%s'.", simpleName); 
            } else {
                loc = argumentLocations[error.argNumber];
                message = format("parameter #%s of '%s'.", error.argNumber + 1, simpleName);
            }
            error.more = new CompilerErrorNote(loc, message);
            throw error;
        }
        return retVal;
    }
}

class Functions : Value
{
    Function[] functions;
    
    this(Module mod, Location location, Function[] functions)
    {
        super(mod, location);
        this.functions = functions;
        mType = functions[0].type;
    }
    
    override Value addressOf(Location location)
    {
        if (functions.length == 1) {
            return functions[0].addressOf(location);
        } else {
            if (mModule.functionPointerArguments is null) {
                throw new CompilerError(location, "cannot infer type of overloaded function.");
            } else {
                return resolveOverload(location, functions, *mModule.functionPointerArguments).addressOf(location);
            }
        }
    }
    
    override Value call(Location location, Location[] argumentLocations, Value[] arguments)
    {
        return resolveOverload(location, functions, arguments).call(location, argumentLocations, arguments);
    }
}

struct Label { Location location; BasicBlock block; LLVMBasicBlockRef bb; }
struct PendingGoto { Location location; string label; LLVMBasicBlockRef insertAt; BasicBlock block; }

Value buildCall(Module mod, FunctionType type, LLVMValueRef llvmValue, string functionName, Location callLocation, Location[] argLocations, Value[] args)
{
    checkArgumentListLength(type, functionName, callLocation, argLocations, args);
    normaliseArguments(mod, type, argLocations, args);
    auto llvmArgs = array( map!"a.get()"(args) );
    LLVMValueRef v;
    if (mod.catchTargetStack.length == 0) {
        v = LLVMBuildCall(mod.builder, llvmValue, llvmArgs.ptr, cast(uint) llvmArgs.length, "");
    } else {
        // function call in a try block
        auto catchB  = mod.catchTargetStack[$ - 1].catchBlock;
        auto catchBB = mod.catchTargetStack[$ - 1].catchBB;
        
        auto thenB  = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.llvmValue, "try");
        v = LLVMBuildInvoke(mod.builder, llvmValue, llvmArgs.ptr, cast(uint) llvmArgs.length, thenB, catchB, "");
        LLVMPositionBuilderAtEnd(mod.builder, thenB);
        
        auto parent = mod.currentFunction.cfgTail;
        auto newTry = new BasicBlock("try");
        parent.children ~= newTry;
        newTry.children ~= catchBB;
        mod.currentFunction.cfgTail = newTry;
    }
    
    if (type.linkage != Linkage.C) {
        LLVMSetInstructionCallConv(v, linkageToCallConv(type.linkage));
    }
    
    Value val;
    if (type.returnType.dtype != DType.Void) {
        val = type.returnType.getValue(mod, callLocation);
        val.initialise(callLocation, v);
    } else {
        val = new VoidValue(mod, callLocation);
    }
    
    return val;
}

private void checkArgumentListLength(FunctionType type, string functionName, Location callLocation, ref Location[] argLocations, Value[] args)
{
    if (type.varargs) {
        if (type.parameterTypes.length > args.length) {
            throw new ArgumentMismatchError(callLocation, format("expected at least %s arguments, got %s.", type.parameterTypes.length, args.length));
         }
    } else if (type.parameterTypes.length != args.length) {
        debugPrint(functionName);
        throw new ArgumentMismatchError(callLocation, format("expected %s arguments, got %s.", type.parameterTypes.length, args.length));
    }
    if (argLocations.length != args.length) {
        // Some arguments are hidden (e.g. this).
        assert(argLocations.length < args.length);
        argLocations ~= callLocation;
    }
}

/** 
 * Implicitly cast arguments to the respective parameter types.
 * If a parameter is ref, then get the address of the respective argument.
 */ 
private void normaliseArguments(Module mod, FunctionType type, Location[] argLocations, Value[] args)
in
{
    assert(args.length == argLocations.length);
}
body
{
    foreach (i, ref param; type.parameterTypes) {
        auto arg = args[i];
        if (param.isRef) {
            if (!args[i].type.equals(param)) {
                throw new CompilerError(argLocations[i], format("argument to ref parameter must be of exact type '%s', not '%s'.", param.name(), arg.type.name()));
            }
            arg.errorIfNotLValue(argLocations[i]);
            args[i] = arg.addressOf(argLocations[i]);
        } else {
            try {
                args[i] = implicitCast(argLocations[i], arg, param);
            } catch(CompilerError error) {
                throw new ArgumentMismatchError(error.location, error.msg, i);
            }
        }
    }
}

Function resolveOverload(Location location, Function[] functions, Value[] args)
in { assert(functions.length > 0); }
body
{
    bool implicit(Function fn) { return implicitMatches(fn, args); }
    bool explicit(Function fn) { return explicitMatches(fn, args); }
        
    if (functions.length == 1) {
        return functions[0];
    }
    
    auto explicitMatches = array( filter!explicit(functions) );
    if (explicitMatches.length == 1) {
        return explicitMatches[0];
    }
    
    throw new CompilerPanic("Failed to retrieve overloaded function.");
}

private bool implicitMatches(Function fn, Value[] args)
{
    return false;
}

private bool explicitMatches(Function fn, Value[] args)
{
    Type getType(Value v) { return v.type; }
    auto functionTypes = fn.type.parameterTypes;
    auto parameterTypes = array( map!getType(args) );
    return functionTypes == parameterTypes;
}

LLVMCallConv linkageToCallConv(ast.Linkage linkage)
{
    final switch(linkage) with(ast.Linkage) {
        case C:
            return LLVMCallConv.C;
        case D:
            return LLVMCallConv.Fast;
        case Pascal, CPlusPlus:
            throw new CompilerPanic("Pascal and C++ calling conventions are unsupported.");
        case Windows:
            return LLVMCallConv.X86Stdcall;
        case System:
            version(Windows)
                goto case Windows;
            else
                goto case C;
    }
}

string linkageToString(ast.Linkage linkage)
{
    final switch(linkage) with(ast.Linkage) {
        case C:
            return "C";
        case D:
            return "D";
        case Pascal:
            return "pascal";
        case CPlusPlus:
            return "C++";
        case Windows:
            return "stdcall";
        case System:
            version(Windows)
                goto case Windows;
            else
                goto case C;
    }
}