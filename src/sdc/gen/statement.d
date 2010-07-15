/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.statement;

import llvm.c.Core;

import sdc.compilererror;
import sdc.ast.statement;
import sdc.gen.semantic;
import sdc.gen.type;
import sdc.gen.expression;


void genBlockStatement(BlockStatement statement, Semantic semantic)
{
    foreach (s; statement.statements) {
        genStatement(s, semantic);
    }
}

void genStatement(Statement statement, Semantic semantic)
{
    final switch (statement.type) {
    case StatementType.Empty:
        return;
    case StatementType.NonEmpty:
        return genNonEmptyStatement(cast(NonEmptyStatement) statement.node, semantic);
    case StatementType.Scope:
        return genScopeStatement(cast(ScopeStatement) statement.node, semantic);
    }
    assert(false);
}

void genNonEmptyStatement(NonEmptyStatement statement, Semantic semantic)
{
    switch (statement.type) {
    case NonEmptyStatementType.ReturnStatement:
        return genReturnStatement(cast(ReturnStatement) statement.node, semantic);
    default:
        error(statement.location, "ICE: unimplemented non empty statement.");
    }
    assert(false);
}

void genScopeStatement(ScopeStatement statement, Semantic semantic)
{
    error(statement.location, "ICE: scope statement unimplemented.");
}

void genReturnStatement(ReturnStatement statement, Semantic semantic)
{
    auto expr = genExpression(statement.expression, semantic);
    auto exprType = LLVMTypeOf(expr);
    auto retvalType = typeToLLVM(semantic.currentFunction.retval, semantic);
    assert(exprType == retvalType);
    LLVMBuildRet(semantic.builder, expr);
}
