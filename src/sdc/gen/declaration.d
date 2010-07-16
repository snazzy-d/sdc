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




void genDeclaration(Declaration decl, Semantic semantic)
{
    final switch (decl.type) {
    case DeclarationType.Variable:
        genVariableDeclaration(cast(VariableDeclaration)decl.node, semantic);
        break;
    case DeclarationType.Function:
        genFunctionDeclaration(cast(FunctionDeclaration)decl.node, semantic);
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
            error(decl.location, format("declaration '%s' shadows declaration.", name));
        }
        auto store = new DeclarationStore();
        store.declaration = decl;
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
    }
}

void genFunctionDeclaration(FunctionDeclaration decl, Semantic semantic)
{
    debugPrint("genFunctionDeclaration");
    auto FT = LLVMFunctionType(typeToLLVM(decl.retval, semantic), null, 0, false);
    auto F  = LLVMAddFunction(semantic.mod, toStringz(extractIdentifier(decl.name)), FT);
    auto BB = LLVMAppendBasicBlockInContext(semantic.context, F, "entry");
    LLVMPositionBuilderAtEnd(semantic.builder, BB);
    
    semantic.functionType = FT;
    semantic.setDeclaration(extractIdentifier(decl.name), new DeclarationStore(decl, F, FT, DeclarationType.Function));
    semantic.pushScope();
    genFunctionBody(decl.functionBody, semantic);
    semantic.popScope();
    semantic.functionType = null;
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
        LLVMBuildStore(semantic.builder, genAssignExpression(cast(AssignExpression) initialiser.node, semantic), var);
        break;
    }
}
