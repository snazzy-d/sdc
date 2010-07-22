/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.declaration;

import std.string;

import llvm.c.Core;

import sdc.util;
import sdc.compilererror;
import sdc.ast.expression;
import sdc.ast.declaration;
import sdc.gen.expression;
import sdc.gen.semantic;
import sdc.gen.type;
import sdc.gen.extract;
import sdc.gen.statement;


void declareDeclaration(Declaration decl, Semantic semantic)
{
    final switch (decl.type) {
    case DeclarationType.Variable:
        break;
    case DeclarationType.Function:
        declareFunctionDeclaration(cast(FunctionDeclaration) decl.node, semantic);
        break;
    }
}

void genDeclaration(Declaration decl, Semantic semantic)
{
    final switch (decl.type) {
    case DeclarationType.Variable:
        genVariableDeclaration(cast(VariableDeclaration) decl.node, semantic);
        break;
    case DeclarationType.Function:
        auto FD = cast(FunctionDeclaration) decl.node;
        if (FD.functionBody !is null) {
            genFunctionDeclaration(cast(FunctionDeclaration) decl.node, semantic);
        }
        break;
    }
}

void genVariableDeclaration(VariableDeclaration decl, Semantic semantic)
{
    auto type = typeToLLVM(decl.type, semantic);
    foreach (declarator; decl.declarators) {
        auto name = extractIdentifier(declarator.name);
        auto d = semantic.getDeclaration(name);
        if (d !is null) {
            error(decl.location, format("declaration '%s' shadows declaration at '%s'.", name, d.declaration.location));
        }
        auto store = new DeclarationStore();
        store.declaration = new SyntheticVariableDeclaration(decl, declarator);
        store.declarationType = DeclarationType.Variable;
        store.type = type;
        if (decl.isAlias) {
            if (declarator.initialiser !is null) {
                error(declarator.location, "alias declaration may not have an initialiser.");
            }
            semantic.setDeclaration(name, store);
            continue;
        }
        store.value = LLVMBuildAlloca(semantic.builder, type, toStringz(name));
        
        if (declarator.initialiser !is null) {
            genInitialiser(declarator.initialiser, semantic, store.value, store.type);
        } else {
            LLVMBuildStore(semantic.builder, LLVMConstInt(type, 0, false), store.value);
        }
        semantic.setDeclaration(name, store);
    }
}

void declareFunctionDeclaration(FunctionDeclaration decl, Semantic semantic)
{
    LLVMTypeRef[] params;
    foreach (parameter; decl.parameters) {
        params ~= typeToLLVM(parameter.type, semantic);
    }
    auto FT = LLVMFunctionType(typeToLLVM(decl.retval, semantic), params.ptr, params.length, false);
    auto F  = LLVMAddFunction(semantic.mod, toStringz(extractIdentifier(decl.name)), FT);
    semantic.setDeclaration(extractIdentifier(decl.name), new DeclarationStore(decl, F, FT, DeclarationType.Function));
}

void genFunctionDeclaration(FunctionDeclaration decl, Semantic semantic)
{
    auto d = semantic.getDeclaration(extractIdentifier(decl.name));
    if (d is null || d.declarationType != DeclarationType.Function) {
        error(decl.location, "ICE: attempted to declare non-existent function.");
    }
    
    auto F  = d.value;
    auto FT = d.type;
    auto BB = LLVMAppendBasicBlockInContext(semantic.context, F, "entry");
    LLVMPositionBuilderAtEnd(semantic.builder, BB);
        
    semantic.functionType = FT;
    semantic.currentFunction = F;
    semantic.pushScope();
    
    auto numberOfParams = LLVMCountParams(F);
    assert(numberOfParams == decl.parameters.length);
    foreach (i, parameter; decl.parameters) {
        // Anonymous parameter.
        if (parameter.identifier is null) continue;
        
        auto name = extractIdentifier(parameter.identifier);
        auto p = LLVMGetParam(F, i);
        auto v = LLVMBuildAlloca(semantic.builder, LLVMTypeOf(p), toStringz(name));
        LLVMBuildStore(semantic.builder, p, v);
        auto synth = new SyntheticVariableDeclaration();
        synth.location = parameter.location;
        synth.identifier = parameter.identifier;
        synth.type = parameter.type;
        semantic.setDeclaration(extractIdentifier(parameter.identifier), new DeclarationStore(synth, v, null, DeclarationType.Variable));
    }
        
    genFunctionBody(decl.functionBody, semantic);
    if (!semantic.currentScope.builtReturn) {
        if (LLVMGetReturnType(FT) == LLVMVoidTypeInContext(semantic.context)) {
            LLVMBuildRetVoid(semantic.builder);
        } else {
            error(decl.location, "control reaches end of non-void function.");
        }
    }
    
    semantic.popScope();
    semantic.functionType = null;
    semantic.currentFunction = null;
}

void genFunctionBody(FunctionBody fbody, Semantic semantic)
{
    genBlockStatement(fbody.statement, semantic);
}

void genInitialiser(Initialiser initialiser, Semantic semantic, LLVMValueRef var, LLVMTypeRef type)
{
    final switch (initialiser.type) {
    case InitialiserType.Void:
        LLVMBuildStore(semantic.builder, LLVMGetUndef(type), var);
        break;
    case InitialiserType.AssignExpression:
        auto expr = genAssignExpression(cast(AssignExpression) initialiser.node, semantic);
        auto init = LLVMBuildLoad(semantic.builder, expr, "init");
        if (LLVMTypeOf(init) != type) {
            error(initialiser.location, "assign expression does not match declaration type. (ICE: no implicit casting).");
        }
        LLVMBuildStore(semantic.builder, init, var);
        break;
    }
}
