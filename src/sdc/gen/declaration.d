/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.declaration;

import std.conv;

import llvm.c.Core;

import sdc.compilererror;
import sdc.util;
import sdc.extract.base;
import ast = sdc.ast.all;
import sdc.gen.sdcmodule;
import sdc.gen.type;
import sdc.gen.value;
import sdc.gen.statement;
import sdc.gen.expression;


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
        b = canGenDeclaration(cast(ast.Declaration) decl.node, mod);
        break;
    }
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
    foreach (parameter; decl.parameters) {
        auto t = astTypeToBackendType(parameter.type, mod, OnFailure.ReturnNull);
        retval = retval && t !is null;
    }
    return retval;
}


void declareDeclaration(ast.Declaration decl, Module mod)
{
    final switch (decl.type) {
    case ast.DeclarationType.Variable:
        declareVariableDeclaration(cast(ast.VariableDeclaration) decl.node, mod);
        break;
    case ast.DeclarationType.Function:
        declareFunctionDeclaration(cast(ast.FunctionDeclaration) decl.node, mod);
        break;
    case ast.DeclarationType.Alias:
        mod.isAlias = true;
        declareDeclaration(cast(ast.Declaration) decl.node, mod);
        mod.isAlias = false;
        break;
    }
}

void declareVariableDeclaration(ast.VariableDeclaration decl, Module mod)
{
    auto type = astTypeToBackendType(decl.type, mod, OnFailure.DieWithError);
    foreach (declarator; decl.declarators) {
        auto name = extractIdentifier(declarator.name);
        if (mod.isAlias) {
            mod.currentScope.add(name, new Store(type));
        }
    }
}

void declareFunctionDeclaration(ast.FunctionDeclaration decl, Module mod)
{
    auto type = new FunctionType(mod, decl);
    type.declare();
    auto name = extractIdentifier(decl.name);
    auto store = new Store(new FunctionValue(mod, decl.location, type, name));
    mod.currentScope.add(name, store);
}

void genDeclaration(ast.Declaration decl, Module mod)
{
    final switch (decl.type) {
    case ast.DeclarationType.Variable:
        genVariableDeclaration(cast(ast.VariableDeclaration) decl.node, mod);
        break;
    case ast.DeclarationType.Function:
        genFunctionDeclaration(cast(ast.FunctionDeclaration) decl.node, mod);
        break;
    case ast.DeclarationType.Alias:
        break;
    }
}

void genVariableDeclaration(ast.VariableDeclaration decl, Module mod)
{
    foreach (declarator; decl.declarators) {
        auto type = astTypeToBackendType(decl.type, mod, OnFailure.DieWithError);
        
        if (mod.currentScope is mod.globalScope) {
            throw new CompilerPanic(decl.location, "global variables are unimplemented.");
        }
        
        Value var;
        if (type.dtype == DType.Inferred) {
            if (declarator.initialiser is null || declarator.initialiser.type == ast.InitialiserType.Void) {
                throw new CompilerError(decl.location, "not enough information to infer type.");
            }
        } else {
            var = type.getValue(mod, declarator.location);
        }
        
        if (declarator.initialiser is null) {
            if (var.type.dtype != DType.Struct) {
                var.set(var.init(decl.location));
            }
        } else {
            if (declarator.initialiser.type == ast.InitialiserType.Void) {
                var.set(LLVMGetUndef(type.llvmType));
            } else if (declarator.initialiser.type == ast.InitialiserType.AssignExpression) {
                auto aexp = genAssignExpression(cast(ast.AssignExpression) declarator.initialiser.node, mod);
                if (type.dtype == DType.Inferred) {
                    type = aexp.type;
                    var = type.getValue(mod, decl.location);
                }
                aexp = implicitCast(aexp, type);
                if (var is null) {
                    throw new CompilerPanic(decl.location, "inferred type ended up with no value at declaration point.");
                }
                var.set(aexp);
            } else {
                throw new CompilerPanic(declarator.initialiser.location, "unhandled initialiser type.");
            }
        }
        mod.currentScope.add(extractIdentifier(declarator.name), new Store(var));
    }
}

void genFunctionDeclaration(ast.FunctionDeclaration decl, Module mod)
{
    auto name = extractIdentifier(decl.name);
    auto store = mod.globalScope.get(name);
    if (store is null) {
        throw new CompilerPanic(decl.location, "attempted to gen undeclared function.");
    }
    auto val = store.value();
    if (decl.functionBody is null) {
        // The function's code is defined elsewhere.
        return;
    }
    auto BB = LLVMAppendBasicBlockInContext(mod.context, val.get(), "entry");
    LLVMPositionBuilderAtEnd(mod.builder, BB);
    genFunctionBody(decl.functionBody, decl, val, mod);
}

void genFunctionBody(ast.FunctionBody functionBody, ast.FunctionDeclaration decl, Value func, Module mod)
{
    mod.pushScope();
    mod.currentFunction = cast(FunctionValue) func;
    assert(mod.currentFunction);
    auto functionType = cast(FunctionType) func.type;
    assert(functionType);
    
    // Add parameters into the functions namespace.
    foreach (i, argType; functionType.argumentTypes) {
        auto val = argType.getValue(mod, func.location);
        val.set(LLVMGetParam(func.get(), i));
        mod.currentScope.add(functionType.argumentNames[i], new Store(val));
    }
    
    mod.pushPath(PathType.Inevitable);
    genBlockStatement(functionBody.statement, mod);
    
    if (!mod.currentPath.functionEscaped) {
        if(decl.retval.type == ast.TypeType.Primitive) {
           auto prim = cast(ast.PrimitiveType)decl.retval.node;
           
           if(prim.type == ast.PrimitiveTypeType.Void) {
               LLVMBuildRetVoid(mod.builder);
               goto success;
           }
        }
        throw new CompilerError(decl.location, "function expected to return a value.");
    }
    
    success:
    mod.popPath();
    mod.currentFunction = null;
    mod.popScope();
}
