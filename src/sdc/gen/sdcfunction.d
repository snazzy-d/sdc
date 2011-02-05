/**
 * Copyright 2011 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.sdcfunction;

import std.algorithm;
import std.array;
import std.string;

import llvm.c.Core;

import sdc.compilererror;
import sdc.global;
import sdc.location;
import sdc.mangle;
import sdc.util;
import sdc.ast.attribute;
import sdc.extract.base;
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
class FunctionType
{
    LLVMTypeRef functionType;
    
    Linkage linkage;
    Type returnType;
    Type[] argumentTypes;
    bool varargs;
    
    this(Type returnType, Type[] argumentTypes, bool varargs)
    {
        this.returnType = returnType;
        this.argumentTypes = argumentTypes;
        this.varargs = varargs;
        declare();
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
        foreach (ref t; argumentTypes) {
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
            functionType = LLVMFunctionType(LLVMInt32Type(), params.ptr, params.length, varargs);
        } else {
            functionType = LLVMFunctionType(returnType.llvmType, params.ptr, params.length, varargs);
        }
    }
}

/**
 * Function is an interface to the actual block of code that is the function.
 */
class Function
{
    FunctionType type;
    string simpleName;
    string mangledName;
    string[] argumentNames;
    Location[] argumentLocations;
    Location argumentListLocation;
    Type parentAggregate;
    Module mod = null;
    BasicBlock cfgEntry;
    BasicBlock cfgTail;
    
    LLVMValueRef llvmValue;
    
    this(FunctionType type)
    {
        this.type = type;
    }
    
    /**
     * Replace this function in place with a function that
     * is identical save for a single new argument.
     */
    void addArgument(Type argumentType, string argumentName)
    {
        type.argumentTypes ~= argumentType;
        argumentNames ~= argumentName;
        if (argumentLocations.length >= 1) {
            argumentLocations ~= argumentLocations[$ - 1];
        } else {
            argumentLocations ~= argumentListLocation;
        }
        type.declare();
        if (mod !is null) {
            auto m = mod;
            remove();
            add(m);
        }
    }
    
    /**
     * Assign this Function to the Module `mod`.
     * Function's can only be assigned to one Module at a time.   
     */
    void add(Module mod)
    {
        if (this.mod !is null) {
            if (mod !is this.mod) {
                throw new CompilerPanic("attemped to add assigned function '" ~ simpleName ~ "' to another module.");
            } else {
                // We're already assigned to this Module.
                return;
            }
        }
        mangledName = simpleName.idup;
        if (type.linkage == Linkage.ExternD) {
            mangleFunction(mangledName, this);
        }
        storeSpecial();
        llvmValue = LLVMAddFunction(mod.mod, toStringz(mangledName), type.functionType);
        this.mod = mod;
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
    
    void importToModule(Module mod)
    {
    }
    
    Value addressOf(Location location)
    {
        auto fptr = new FunctionPointerValue(mod, location, type);
        fptr.initialise(location, llvmValue);
        return fptr;
    }
    
    /**
     * Generate code to call this function.
     */
    Value call(Location location, Location[] argLocations, Value[] args)
    {
        if (mod is null) {
            throw new CompilerPanic(location, "attemped to call unassigned Function.");
        }
        auto v = buildCall(mod, type, llvmValue, simpleName, location, argLocations, args);
         
        Value val;
        if (type.returnType.dtype != DType.Void) {
            val = type.returnType.getValue(mod, location);
            val.initialise(location, v);
        } else {
            val = new VoidValue(mod, location);
        }
        return val;
    }
    
    private void storeSpecial()
    {
        if (mangledName == "malloc" && gcAlloc is null) {
            gcAlloc = this;
        } else if (mangledName == "realloc" && gcRealloc is null) {
            gcRealloc = this;
        }
    }
}

LLVMValueRef buildCall(Module mod, FunctionType type, LLVMValueRef llvmValue, string functionName, Location callLocation, Location[] argLocations, Value[] args)
{
    checkArgumentListLength(type, functionName, callLocation, argLocations, args);
    normaliseArguments(mod, type, argLocations, args);
    auto llvmArgs = array( map!"a.get"(args) );
    return LLVMBuildCall(mod.builder, llvmValue, llvmArgs.ptr, llvmArgs.length, "");
}

private void checkArgumentListLength(FunctionType type, string functionName, Location callLocation, ref Location[] argLocations, Value[] args)
{
    if (type.varargs) {
        if (type.argumentTypes.length > args.length) {
            throw new CompilerError(
                callLocation, 
                format("expected at least %s arguments, got %s.", type.argumentTypes.length, args.length),
                new CompilerError(
                    callLocation,
                    format(`parameters of "%s":`, functionName)
                )
            );
         }
    } else if (type.argumentTypes.length != args.length) {
        callLocation.column = callLocation.wholeLine;
        throw new CompilerError(
            callLocation, 
            format("expected %s arguments, got %s.", type.argumentTypes.length, args.length),
                new CompilerError(
                    callLocation,
                    format(`parameters of "%s":`, functionName)
                )
        );
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
    foreach (i, arg; type.argumentTypes) {
        args[i] = implicitCast(argLocations[i], args[i], arg);
        if (arg.isRef) {
            args[i].errorIfNotLValue(argLocations[i]);
            args[i] = args[i].addressOf();
        }
    }
}
