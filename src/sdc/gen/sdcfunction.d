/**
 * Copyright 2011 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.sdcfunction;

import std.algorithm;
import std.array;
import std.conv;
import std.string;

import llvm.c.Core;
import llvm.Ext;

import sdc.compilererror;
import sdc.global;
import sdc.location;
import sdc.mangle;
import sdc.util;
import sdc.extract;
import sdc.ast.attribute;
import sdc.ast.declaration : FunctionDeclaration;
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
    Type parentAggregate;
    bool isStatic;
    bool varargs;
    Module mod;
    
    this(Module mod, Type returnType, Type[] argumentTypes, bool varargs, FunctionDeclaration astParent = null)
    {
        this.returnType = returnType;
        this.argumentTypes = argumentTypes;
        this.varargs = varargs;
        if (astParent !is null) {
            this.linkage = astParent.linkage;
            this.isStatic = astParent.searchAttributesBackwards(ast.AttributeType.Static);
        }
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
            functionType = LLVMFunctionType(LLVMInt32Type(), params.ptr, cast(uint) params.length, varargs);
        } else {
            functionType = LLVMFunctionType(returnType.llvmType, params.ptr, cast(uint) params.length, varargs);
        }
    }
    
    /**
     * Create an equivalent FunctionType in the given Module.
     */
    FunctionType importToModule(Module mod)
    {
        Type importType(Type t) { return t.importToModule(mod); }
        auto importedTypes = array( map!importType(argumentTypes) );    
            
        auto fn = new FunctionType(mod, returnType.importToModule(mod), importedTypes, varargs);
        if (fn.parentAggregate !is null) {
            fn.parentAggregate = parentAggregate.importToModule(mod);
        }
        assert(argumentTypes.length == fn.argumentTypes.length);
        return fn;
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
            Type[] args = type.argumentTypes;
            if (argumentName == "this") {
                // Omit the this parameter from mangling.
                type.argumentTypes = type.argumentTypes[0 .. $ - 1];  // HAX!
            }
            add(m);
            type.argumentTypes = args;
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
        mangledName = simpleName.idup;
        if (type.linkage == Linkage.ExternD && forceMangle is null) {
            mangleFunction(mangledName, this);
        } else if (forceMangle !is null) {
            mangledName = forceMangle;
        }
        verbosePrint("Adding function '" ~ mangledName ~ "' (" ~ to!string(cast(void*)this) ~ ") to LLVM module '" ~ to!string(mod.mod) ~ "'.", VerbosePrintColour.Yellow);
        llvmValue = LLVMAddFunction(mod.mod, toStringz(mangledName), type.functionType);
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
        auto fptr = new PointerValue(mod, location, new FunctionTypeWrapper(mod, type));
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
        return buildCall(mod, type, llvmValue, simpleName, location, argLocations, args);
    }
}

Value buildCall(Module mod, FunctionType type, LLVMValueRef llvmValue, string functionName, Location callLocation, Location[] argLocations, Value[] args)
{
    checkArgumentListLength(type, functionName, callLocation, argLocations, args);
    normaliseArguments(mod, type, argLocations, args);
    auto llvmArgs = array( map!"a.get"(args) );
    auto v = LLVMBuildCall(mod.builder, llvmValue, llvmArgs.ptr, cast(uint) llvmArgs.length, "");
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
        debugPrint(functionName);
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
            args[i] = args[i].addressOf(argLocations[i]);
        }
    }
}
