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
import sdc.gen.declaration;


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
    case NonEmptyStatementType.DeclarationStatement:
        return genDeclarationStatement(cast(DeclarationStatement) statement.node, semantic);
    case NonEmptyStatementType.ExpressionStatement:
        return genExpressionStatement(cast(ExpressionStatement) statement.node, semantic);
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

void genDeclarationStatement(DeclarationStatement statement, Semantic semantic)
{
    genDeclaration(statement.declaration, semantic);
}

void genReturnStatement(ReturnStatement statement, Semantic semantic)
{
    auto expr = genExpression(statement.expression, semantic);
    auto retval = LLVMBuildLoad(semantic.builder, expr, "retval");
    auto exprType = LLVMTypeOf(retval);
    auto retvalType = LLVMGetReturnType(semantic.functionType);
    assert(exprType == retvalType);
    LLVMBuildRet(semantic.builder, retval);
}

void genExpressionStatement(ExpressionStatement statement, Semantic semantic)
{
    genExpression(statement.expression, semantic);
}
