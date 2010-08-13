/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.declaration;

import llvm.c.Core;

import sdc.compilererror;
import sdc.extract.base;
import ast = sdc.ast.all;
import sdc.gen.sdcmodule;
import sdc.gen.type;
import sdc.gen.value;
import sdc.gen.statement;
import sdc.gen.expression;


void declareDeclaration(ast.Declaration decl, Module mod)
{
    final switch (decl.type) {
    case ast.DeclarationType.Variable:
        panic(decl.location, "global variables are unimplemented.");
        assert(false);
    case ast.DeclarationType.Function:
        declareFunctionDeclaration(cast(ast.FunctionDeclaration) decl.node, mod);
        break;
    }
}

void declareFunctionDeclaration(ast.FunctionDeclaration decl, Module mod)
{
    auto type = new FunctionType(mod, decl);
    type.declare();
    auto name = extractIdentifier(decl.name);
    mod.currentScope.add(new FunctionValue(mod, decl.location, type, name), name);
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
    }
}

void genVariableDeclaration(ast.VariableDeclaration decl, Module mod)
{
    foreach (declarator; decl.declarators) {
        auto var = astTypeToBackendValue(decl.type, mod);
        if (declarator.initialiser is null) {
            var.set(var.init(decl.location));
        } else {
            if (declarator.initialiser.type == ast.InitialiserType.Void) {
                panic(declarator.initialiser.location, "void initialisers are unimplemented.");
            } else if (declarator.initialiser.type == ast.InitialiserType.AssignExpression) {
                var.set(genAssignExpression(cast(ast.AssignExpression) declarator.initialiser.node, mod));
            } else {
                panic(declarator.initialiser.location, "unhandled initialiser type.");
            }
        }
        mod.currentScope.add(var, extractIdentifier(declarator.name));
    }
}

void genFunctionDeclaration(ast.FunctionDeclaration decl, Module mod)
{
    auto name = extractIdentifier(decl.name);
    auto val = mod.currentScope.get(name);
    if (val is null) {
        panic(decl.location, "attempted to gen undeclared function.");
    }
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
    
    auto functionType = cast(FunctionType) func.type();
    assert(functionType);
    foreach (i, argType; functionType.argumentTypes) {
        auto val = argType.getValue(func.location);
        val.set(LLVMGetParam(func.get(), i));
        auto name = extractIdentifier(decl.parameters[i].identifier);
        mod.currentScope.add(val, name);
    }
    
    mod.pushPath(PathType.Inevitable);
    genBlockStatement(functionBody.statement, mod);
    if (!mod.currentPath.functionEscaped) {
        error(functionBody.location, "function expected to return a value.");
    }
    mod.popPath();
    mod.popScope();
}
