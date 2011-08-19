/**
 * Copyright 2010-2011 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.declaration;

import std.algorithm;
import std.array;
import std.conv;
import std.string;
import std.exception;

import llvm.c.Core;

import sdc.compilererror;
import sdc.lexer;
import sdc.location;
import sdc.source;
import sdc.util;
import sdc.extract;
import sdc.global;
import ast = sdc.ast.all;
import sdc.gen.cfg;
import sdc.gen.sdcmodule;
import sdc.gen.type;
import sdc.gen.value;
import sdc.gen.statement;
import sdc.gen.expression;
import sdc.gen.sdcfunction;
import sdc.parser.declaration;
import sdc.java.mangle;


bool canGenDeclaration(ast.Declaration decl, Module mod)
{
    bool b;
    final switch (decl.type) {
    case ast.DeclarationType.Variable:
        b = canGenVariableDeclaration(cast(ast.VariableDeclaration) decl.node, mod);
        break;
    case ast.DeclarationType.Function:
        b = canGenFunctionDeclaration(cast(ast.FunctionDeclaration) decl.node, mod);
        break;
    case ast.DeclarationType.Alias:
        b = canGenAliasDeclaration(cast(ast.VariableDeclaration) decl.node, mod);
        break;
    case ast.DeclarationType.AliasThis:
        return true;  // noooooooooooooooooooooooooooooo
    case ast.DeclarationType.Mixin:
        auto asMixin = cast(ast.MixinDeclaration) decl.node;
        genMixinDeclaration(asMixin, mod);
        b = canGenDeclaration(asMixin.declarationCache, mod);
        break;
    }
    return b;
}

bool canGenAliasDeclaration(ast.VariableDeclaration decl, Module mod)
{
    auto b = canGenVariableDeclaration(decl, mod);
    return b;
}

bool canGenVariableDeclaration(ast.VariableDeclaration decl, Module mod)
{
    auto type = astTypeToBackendType(decl.type, mod, OnFailure.ReturnNull);
    return type !is null;
}

bool canGenFunctionDeclaration(ast.FunctionDeclaration decl, Module mod)
{
    bool retval = astTypeToBackendType(decl.retval, mod, OnFailure.ReturnNull) !is null;
    foreach (parameter; decl.parameterList.parameters) {
        auto t = astTypeToBackendType(parameter.type, mod, OnFailure.ReturnNull);
        retval = retval && t !is null;
    }
    return retval;
}


void declareDeclaration(ast.Declaration decl, ast.DeclarationDefinition declDef, Module mod)
{
    final switch (decl.type) {
    case ast.DeclarationType.Variable:
        declareVariableDeclaration(cast(ast.VariableDeclaration) decl.node, mod);
        break;
    case ast.DeclarationType.Function:
        declareFunctionDeclaration(cast(ast.FunctionDeclaration) decl.node, declDef, mod);
        break;
    case ast.DeclarationType.Alias:
        declareAliasDeclaration(cast(ast.VariableDeclaration) decl.node, declDef, mod);
        break;
    case ast.DeclarationType.AliasThis:
        break;
    case ast.DeclarationType.Mixin:
        auto asMixin = cast(ast.MixinDeclaration) decl.node;
        genMixinDeclaration(asMixin, mod);
        declareDeclaration(asMixin.declarationCache, declDef, mod);
        break;
    }
}

void declareAliasDeclaration(ast.VariableDeclaration decl, ast.DeclarationDefinition declDef, Module mod)
{
    declareVariableDeclaration(decl, mod);
}

void declareVariableDeclaration(ast.VariableDeclaration decl, Module mod)
{
    auto type = astTypeToBackendType(decl.type, mod, OnFailure.DieWithError);
    foreach (declarator; decl.declarators) {
        auto name = extractIdentifier(declarator.name);
        if (decl.isAlias) {
            verbosePrint("Adding alias '" ~ name ~ "' for " ~ type.name ~ ".", VerbosePrintColour.Green);
            if (type.dtype == DType.Function) {
                // alias <function name> foo;
                // !!! A complete look up should be performed, not this current hackish implementation.
                auto asUserDefinedType = enforce(cast(ast.UserDefinedType) decl.type.node);
                if (!asUserDefinedType.segments[$ - 1].isIdentifier) {
                    throw new CompilerPanic(decl.location, "aliasing template functions is unimplemented.");
                }
                auto fnname = extractIdentifier(cast(ast.Identifier) asUserDefinedType.segments[$ - 1].node);
                auto fn = mod.search(fnname);
                if (fn is null) {
                    throw new CompilerPanic(decl.location, "couldn't find aliased function.");
                }
                mod.currentScope.add(name, new Store(fn.getFunctions()));
            } else {
                mod.currentScope.add(name, new Store(type, declarator.name.location));
            }
        }
    }
}

/// Create and add the function, but generate no code.
void declareFunctionDeclaration(ast.FunctionDeclaration decl, ast.DeclarationDefinition declDef, Module mod)
{
    auto retval = astTypeToBackendType(decl.retval, mod, OnFailure.DieWithError);
    Type[] params;
    string[] names;
    foreach (param; decl.parameterList.parameters) {
        params ~= astTypeToBackendType(param.type, mod, OnFailure.DieWithError);
        if (param.attribute == ast.ParameterAttribute.Ref) {
            params[$ - 1].isRef = true;
        }
        names ~= param.identifier !is null ? extractIdentifier(param.identifier) : "";
    }
    
    auto fntype = new FunctionType(mod, retval, params, decl.parameterList.varargs, decl);
    auto fn = new Function(fntype);
    if (decl.name.identifiers.length == 1) {
        fn.simpleName = extractQualifiedName(decl.name);
    } else {
        // implementing java native function
        fn.simpleName = javaMangle(decl.name);
        fntype.linkage = ast.Linkage.ExternC; 
    }
    fn.argumentNames = names;
    auto store = new Store(fn, decl.name.location);
    
    // This is the important part: the function is added to the appropriate scope.
    if (declDef.parentType !is null) {
        declDef.parentType.typeScope.add(fn.simpleName, store);
    } else {
        mod.currentScope.add(fn.simpleName, fn);
    }
    decl.fn = fn;
    
    fn.type.declare();
    fn.add(mod);
}

void genMixinDeclaration(ast.MixinDeclaration decl, Module mod)
{
    if (decl.declarationCache !is null) {
        return;
    }
    auto val = genAssignExpression(decl.expression, mod);
    if (!val.isKnown || !isString(val.type)) {
        throw new CompilerError(decl.location, "a mixin expression must be a string known at compile time.");
    }
    auto source = new Source(val.knownString, val.location);
    auto tstream = lex(source);
    tstream.getToken();  // Skip BEGIN
    decl.declarationCache = parseDeclaration(tstream);
}

void genDeclaration(ast.Declaration decl, ast.DeclarationDefinition declDef, Module mod)
{
    final switch (decl.type) {
    case ast.DeclarationType.Variable:
        genVariableDeclaration(cast(ast.VariableDeclaration) decl.node, mod);
        break;
    case ast.DeclarationType.Function:
        genFunctionDeclaration(cast(ast.FunctionDeclaration) decl.node, declDef, mod);
        break;
    case ast.DeclarationType.Alias:
        break;
    case ast.DeclarationType.AliasThis:
        genAliasThis(cast(ast.Identifier) decl.node, mod);
        break;
    case ast.DeclarationType.Mixin:
        auto asMixin = cast(ast.MixinDeclaration) decl.node;
        assert(asMixin.declarationCache);
        genDeclaration(asMixin.declarationCache, declDef, mod);
        break;
    }
}

void genAliasThis(ast.Identifier identifier, Module mod)
{
    mod.aggregate.aliasThises ~= extractIdentifier(identifier);
}

void genVariableDeclaration(ast.VariableDeclaration decl, Module mod)
{
    Value[] args;
    
    auto type = astTypeToBackendType(decl.type, mod, OnFailure.DieWithError);
    if (type.dtype == DType.Pointer && type.getBase().dtype == DType.Function) {
        Value getDefaultValue(Type t) { return t.getValue(mod, decl.location); }
        
        auto asPointer = enforce(cast(PointerType) type);
        auto asFunction = enforce(cast(FunctionType) asPointer.base);
        args = array( map!getDefaultValue(asFunction.argumentTypes) );
        mod.functionPointerArguments = &args;     
    }
     
    foreach (declarator; decl.declarators) {          
        Value var;
        if (type.dtype == DType.Inferred) {
            if (declarator.initialiser is null || declarator.initialiser.type == ast.InitialiserType.Void) {
                throw new CompilerError(decl.location, "not enough information to infer type.");
            }
        } else {
            var = type.getValue(mod, declarator.location);
        }
        
        if (declarator.initialiser is null) {
            var.initialise(decl.location, var.getInit(decl.location));
        } else {
            if (declarator.initialiser.type == ast.InitialiserType.Void) {
                var.initialise(decl.location, LLVMGetUndef(type.llvmType));
            } else if (declarator.initialiser.type == ast.InitialiserType.AssignExpression) {
                auto aexp = genAssignExpression(cast(ast.AssignExpression) declarator.initialiser.node, mod);
                if (type.dtype == DType.Inferred) {
                    type = aexp.type;
                    var = type.getValue(mod, decl.location);
                }
                aexp = implicitCast(declarator.initialiser.location, aexp, type);
                if (var is null) {
                    throw new CompilerPanic(decl.location, "inferred type ended up with no value at declaration point.");
                }
                var.initialise(decl.location, aexp);
            } else {
                throw new CompilerPanic(declarator.initialiser.location, "unhandled initialiser type.");
            }
        }
        var.lvalue = true;
        mod.currentScope.add(extractIdentifier(declarator.name), new Store(var));
    }
    
    mod.functionPointerArguments = null;
}

void genFunctionDeclaration(ast.FunctionDeclaration decl, ast.DeclarationDefinition declDef, Module mod)
{
    if (decl.functionBody is null) {
        // The function's code is defined elsewhere.
        return;
    }
    
    if (decl.fn is null) {
        throw new CompilerPanic(decl.location, "attempted to gen undeclared function.");
    }
       
    verbosePrint("Building function '" ~ decl.fn.mangledName ~ "'.", VerbosePrintColour.Yellow);
    verboseIndent++;
    
    // Next, we generate the actual function body's code.
    auto BB = LLVMAppendBasicBlockInContext(mod.context, decl.fn.llvmValue, "entry");
    LLVMPositionBuilderAtEnd(mod.builder, BB);
    genFunctionBody(decl.functionBody, decl, mod);
    
    verboseIndent--;
    verbosePrint("Done building function '" ~ decl.fn.mangledName ~ "'.", VerbosePrintColour.Yellow);
}

void genFunctionBody(ast.FunctionBody functionBody, ast.FunctionDeclaration decl, Module mod)
{
    auto fn = decl.fn;
    mod.pushScope();
    mod.currentFunction = fn;
    assert(mod.currentFunction);
    
    // Add parameters into the functions namespace.
    foreach (i, argType; fn.type.argumentTypes) {
        Value val;
        if (argType.isRef) {
            auto dummy = argType.getValue(mod, decl.location);
            auto r = new ReferenceValue(mod, decl.location, dummy);
            r.setReferencePointer(decl.location, LLVMGetParam(fn.llvmValue, cast(uint) i));
            val = r;  
        } else {
            val = argType.getValue(mod, decl.location);
            val.initialise(decl.location, LLVMGetParam(fn.llvmValue, cast(uint) i));
        }
        val.lvalue = true;
        mod.currentScope.add(fn.argumentNames[i], new Store(val));
    }
    fn.currentBasicBlock = LLVMGetLastBasicBlock(fn.llvmValue);
    assert(fn.currentBasicBlock !is null);
    genBlockStatement(functionBody.statement, mod);
    
    // Resolve any forward gotos (i.e. we know the addresses of all labels now).
    while (!mod.currentFunction.pendingGotos.empty) {
        auto pending = mod.currentFunction.pendingGotos.front;
        mod.currentFunction.pendingGotos.popFront;
        auto p = pending.label in mod.currentFunction.labels;
        if (p is null) {
            throw new CompilerError(pending.location, format("undefined label '%s'.", pending.label));
        }
        assert(pending.insertAt !is null);
        LLVMPositionBuilderAtEnd(mod.builder, pending.insertAt);
        LLVMBuildBr(mod.builder, p.bb);
        pending.block.children ~= p.block;
    }
    
    // Check the CFG for connectivity.
    if (mod.currentFunction.cfgEntry.canReach(mod.currentFunction.cfgTail)) {
        if (fn.type.returnType.dtype == DType.Void) {
            LLVMBuildRetVoid(mod.builder);
        } else {
            throw new CompilerError(
                decl.location, 
                format(`function "%s" expected to return a value of type "%s".`,
                    mod.currentFunction.simpleName, 
                    fn.type.returnType.name()
                )
            );
        }
    } else if (!mod.currentFunction.cfgTail.isExitBlock) {
        LLVMBuildRet(mod.builder, LLVMGetUndef(fn.type.returnType.llvmType));
    }
    
    mod.currentFunction = null;
    mod.popScope();
}
