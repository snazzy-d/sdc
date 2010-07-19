/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.statement;

import std.conv;

import llvm.c.Core;

import sdc.util;
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
    semantic.pushScope();
    final switch (statement.type) {
    case ScopeStatementType.NonEmpty:
        genNonEmptyStatement(cast(NonEmptyStatement) statement.node, semantic);
        break;
    case ScopeStatementType.Block:
        genBlockStatement(cast(BlockStatement) statement.node, semantic);
        break;
    }
    semantic.popScope();
}

void genDeclarationStatement(DeclarationStatement statement, Semantic semantic)
{
    genDeclaration(statement.declaration, semantic);
}

void genReturnStatement(ReturnStatement statement, Semantic semantic)
{
    auto retvalType = LLVMGetReturnType(semantic.functionType);
    if (retvalType == LLVMVoidTypeInContext(semantic.context)) {
        if (statement.expression !is null) {
            error(statement.expression.location, "expression specified in void function.");
        }
        LLVMBuildRetVoid(semantic.builder);
        return;
    }
    
    
    auto expr = genExpression(statement.expression, semantic);
    auto retval = LLVMBuildLoad(semantic.builder, expr, "retval");
    auto exprType = LLVMTypeOf(retval);
    
    if (exprType != retvalType) {
        error(statement.expression.location, "expression does not match function return type. (ICE: no implicit casting)");
    }
    
    LLVMBuildRet(semantic.builder, retval);
}

void genExpressionStatement(ExpressionStatement statement, Semantic semantic)
{
    genExpression(statement.expression, semantic);
}
