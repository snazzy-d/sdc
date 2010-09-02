/**
 * Copyright 2010 Bernard Helyer
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
    if (mod.currentLinkage != ast.Linkage.ExternC) {
        panic(decl.location, "only extern (C) linkage is currently supported.");
    }
    
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
    mod.currentScope.add(name, new Store(new FunctionValue(mod, decl.location, type, name)));
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
        
        if (mod.scopeDepth == 0) {
            panic(decl.location, "global variables are unimplemented.");
        }
        
        auto var = type.getValue(declarator.location);
        
        if (declarator.initialiser is null) {
            if (var.type.dtype != DType.Struct) {
                var.set(var.init(decl.location));
            }
        } else {
            if (declarator.initialiser.type == ast.InitialiserType.Void) {
                var.set(LLVMGetUndef(type.llvmType));
            } else if (declarator.initialiser.type == ast.InitialiserType.AssignExpression) {
                auto aexp = genAssignExpression(cast(ast.AssignExpression) declarator.initialiser.node, mod);
                aexp = implicitCast(aexp, type);
                var.set(aexp);
            } else {
                panic(declarator.initialiser.location, "unhandled initialiser type.");
            }
        }
        mod.currentScope.add(extractIdentifier(declarator.name), new Store(var));
    }
}

void genFunctionDeclaration(ast.FunctionDeclaration decl, Module mod)
{
    auto name = extractIdentifier(decl.name);
    auto store = mod.currentScope.get(name);
    if (store is null) {
        panic(decl.location, "attempted to gen undeclared function.");
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
    
    // Add parameters into the functions namespace.
    auto functionType = cast(FunctionType) func.type();
    assert(functionType);
    foreach (i, argType; functionType.argumentTypes) {
        auto val = argType.getValue(func.location);
        val.set(LLVMGetParam(func.get(), i));
        auto ident = decl.parameters[i].identifier;
        if (ident is null) {
            // Anonymous parameter.
            continue;
        }
        mod.currentScope.add(extractIdentifier(ident), new Store(val));
    }
    
    mod.pushPath(PathType.Inevitable);
    genBlockStatement(functionBody.statement, mod);
    if (!mod.currentPath.functionEscaped) {
        error(functionBody.location, "function expected to return a value.");
    }
    
    mod.popPath();
    mod.currentFunction = null;
    mod.popScope();
}
