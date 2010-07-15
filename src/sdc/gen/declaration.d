/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.declaration;

import std.string;

import llvm.c.Core;

import sdc.ast.declaration;
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
}

void genFunctionDeclaration(FunctionDeclaration decl, Semantic semantic)
{
    semantic.currentFunction = decl;
    auto FT = LLVMFunctionType(typeToLLVM(decl.retval, semantic), null, 0, false);
    auto F  = LLVMAddFunction(semantic.mod, toStringz(extractIdentifier(decl.name)), FT);
    auto BB = LLVMAppendBasicBlockInContext(semantic.context, F, "entry");
    LLVMPositionBuilderAtEnd(semantic.builder, BB);
    genFunctionBody(decl.functionBody, semantic);
    semantic.currentFunction = null;
}

void genFunctionBody(FunctionBody fbody, Semantic semantic)
in { assert(semantic.currentFunction !is null); }
body
{
    genBlockStatement(fbody.statement, semantic);
}
