/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.statement;

import std.conv;
import std.string;

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
    case NonEmptyStatementType.IfStatement:
        return genIfStatement(cast(IfStatement) statement.node, semantic);
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

void genIfStatement(IfStatement statement, Semantic semantic)
{
    auto thenbb = LLVMAppendBasicBlockInContext(semantic.context, semantic.currentFunction, "thenbb");
    auto elsebb = LLVMAppendBasicBlockInContext(semantic.context, semantic.currentFunction, "elsebb");
    auto outbb = LLVMAppendBasicBlockInContext(semantic.context, semantic.currentFunction, "outbb");
    
    auto e    = genIfCondition(statement.ifCondition, semantic);    
    LLVMBuildCondBr(semantic.builder, e, thenbb, elsebb);
    LLVMPositionBuilderAtEnd(semantic.builder, thenbb);
    
    genThenStatement(statement.thenStatement, semantic);
    if (!semantic.disposedScope.builtReturn) {
        LLVMBuildBr(semantic.builder, outbb);
    }
    LLVMPositionBuilderAtEnd(semantic.builder, elsebb);
    
    if (statement.elseStatement !is null) {
        genElseStatement(statement.elseStatement, semantic);
        
        if (!semantic.disposedScope.builtReturn) {
            LLVMBuildBr(semantic.builder, outbb);
        }
        
        LLVMPositionBuilderAtEnd(semantic.builder, outbb);
    } else {
        LLVMBuildBr(semantic.builder, outbb);
        LLVMPositionBuilderAtEnd(semantic.builder, outbb);
    }
}

LLVMValueRef genIfCondition(IfCondition statement, Semantic semantic)
{
    final switch (statement.type) {
    case IfConditionType.ExpressionOnly:
        auto expr = genExpression(statement.expression, semantic);
        auto e    = LLVMBuildLoad(semantic.builder, expr, "ifcondition");
        assert(LLVMTypeOf(e) == LLVMInt1TypeInContext(semantic.context));
        return e;
    case IfConditionType.Identifier:
    case IfConditionType.Declarator:
        error(statement.location, "ICE: unhandled if condition type.");
        assert(false);
    }
    assert(false);
}

void genThenStatement(ThenStatement statement, Semantic semantic)
{
    genScopeStatement(statement.statement, semantic);
}

void genElseStatement(ElseStatement statement, Semantic semantic)
{
    genScopeStatement(statement.statement, semantic);
}

void genReturnStatement(ReturnStatement statement, Semantic semantic)
{
    semantic.currentScope.builtReturn = true;
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
