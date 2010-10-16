/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.statement;

import std.conv;

import llvm.c.Core;

import sdc.tokenstream;
import sdc.compilererror;
import sdc.util;
import sdc.global;
import ast = sdc.ast.all;
import sdc.gen.base;
import sdc.gen.sdcmodule;
import sdc.gen.declaration;
import sdc.gen.expression;
import sdc.gen.value;
import sdc.gen.type;
import sdc.parser.declaration;
import sdc.parser.expression;
import sdc.extract.base;


void genBlockStatement(ast.BlockStatement blockStatement, Module mod)
{
    foreach (statement; blockStatement.statements) {
        genStatement(statement, mod);
    }
}

void genStatement(ast.Statement statement, Module mod)
{
    final switch (statement.type) {
    case ast.StatementType.Empty:
        break;
    case ast.StatementType.NonEmpty:
        genNonEmptyStatement(cast(ast.NonEmptyStatement) statement.node, mod);
        break;
    case ast.StatementType.Scope:
        genScopeStatement(cast(ast.ScopeStatement) statement.node, mod);
        break;
    }
}

void genScopeStatement(ast.ScopeStatement statement, Module mod)
{
    final switch (statement.type) {
    case ast.ScopeStatementType.NonEmpty:
        genNonEmptyStatement(cast(ast.NonEmptyStatement) statement.node, mod);
        break;
    case ast.ScopeStatementType.Block:
        genBlockStatement(cast(ast.BlockStatement) statement.node, mod);
        break;
    }
}

void genNoScopeNonEmptyStatement(ast.NoScopeNonEmptyStatement statement, Module mod)
{
    final switch (statement.type) {
    case ast.NoScopeNonEmptyStatementType.NonEmpty:
        genNonEmptyStatement(cast(ast.NonEmptyStatement) statement.node, mod);
        break;
    case ast.NoScopeNonEmptyStatementType.Block:
        genBlockStatement(cast(ast.BlockStatement) statement.node, mod);
        break;
    }
}


void genNonEmptyStatement(ast.NonEmptyStatement statement, Module mod)
{
    switch (statement.type) {
    default:
        throw new CompilerPanic(statement.location, "unimplemented non empty statement type.");
        assert(false);
    case ast.NonEmptyStatementType.IfStatement:
        genIfStatement(cast(ast.IfStatement) statement.node, mod);
        break;
    case ast.NonEmptyStatementType.WhileStatement:
        genWhileStatement(cast(ast.WhileStatement) statement.node, mod);
        break;
    case ast.NonEmptyStatementType.ExpressionStatement:
        genExpressionStatement(cast(ast.ExpressionStatement) statement.node, mod);
        break;
    case ast.NonEmptyStatementType.DeclarationStatement:
        genDeclarationStatement(cast(ast.DeclarationStatement) statement.node, mod);
        break;
    case ast.NonEmptyStatementType.ReturnStatement:
        genReturnStatement(cast(ast.ReturnStatement) statement.node, mod);
        break;
    case ast.NonEmptyStatementType.ConditionalStatement:
        genConditionalStatement(cast(ast.ConditionalStatement) statement.node, mod);
        break;
    }
}

void genIfStatement(ast.IfStatement statement, Module mod)
{
    LLVMBasicBlockRef ifBB, elseBB;
    
    mod.pushScope();
    mod.pushPath(PathType.Optional);
    genIfCondition(statement.ifCondition, mod, ifBB, elseBB);
    auto endifBB = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.get(), "endif");
    LLVMPositionBuilderAtEnd(mod.builder, ifBB);
    genThenStatement(statement.thenStatement, mod);
    if (!mod.currentPath.functionEscaped) {
        LLVMBuildBr(mod.builder, endifBB);
    }
    mod.popPath();
    mod.popScope();
    
    LLVMPositionBuilderAtEnd(mod.builder, elseBB);
    if (statement.elseStatement !is null) {
        mod.pushScope();
        mod.pushPath(PathType.Optional);
        genElseStatement(statement.elseStatement, mod);
        if (!mod.currentPath.functionEscaped) {
            LLVMBuildBr(mod.builder, endifBB);
        }
        mod.popPath();
        mod.popScope();
    } else {
        LLVMBuildBr(mod.builder, endifBB);
    }
    LLVMPositionBuilderAtEnd(mod.builder, endifBB);
}

void genIfCondition(ast.IfCondition condition, Module mod, ref LLVMBasicBlockRef ifBB, ref LLVMBasicBlockRef elseBB)
{ 
    auto expr = genExpression(condition.expression, mod);
    
    final switch (condition.type) {
    case ast.IfConditionType.ExpressionOnly:
        break;
    case ast.IfConditionType.Identifier:
    case ast.IfConditionType.Declarator:
        throw new CompilerPanic("unimplemented if condition type.");
    }
    
    ifBB = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.get(), "iftrue");
    elseBB = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.get(), "else");
    LLVMBuildCondBr(mod.builder, expr.get(), ifBB, elseBB);
}

void genThenStatement(ast.ThenStatement statement, Module mod)
{
    genScopeStatement(statement.statement, mod);
}

void genElseStatement(ast.ElseStatement statement, Module mod)
{
    genScopeStatement(statement.statement, mod);
}

void genWhileStatement(ast.WhileStatement statement, Module mod)
{    
    auto looptopBB = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.get(), "looptop");
    auto loopbodyBB = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.get(), "loopbody");
    auto loopendBB = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.get(), "loopend");

    LLVMBuildBr(mod.builder, looptopBB);
    mod.pushScope();
    mod.pushPath(PathType.Optional);
    LLVMPositionBuilderAtEnd(mod.builder, looptopBB);
    auto expr = genExpression(statement.expression, mod);
    LLVMBuildCondBr(mod.builder, expr.get(), loopbodyBB, loopendBB);
    LLVMPositionBuilderAtEnd(mod.builder, loopbodyBB);
    genScopeStatement(statement.statement, mod);
    LLVMBuildBr(mod.builder, looptopBB);
    mod.popPath();
    mod.popScope();
    LLVMPositionBuilderAtEnd(mod.builder, loopendBB);
}

void genExpressionStatement(ast.ExpressionStatement statement, Module mod)
{
    genExpression(statement.expression, mod);
}

void genDeclarationStatement(ast.DeclarationStatement statement, Module mod)
{
    genDeclaration(statement.declaration, mod);
}

void genReturnStatement(ast.ReturnStatement statement, Module mod)
{
    mod.currentPath.functionEscaped = true;
    auto t = (cast(FunctionType) mod.currentFunction.type).returnType;
    if (t.dtype == DType.Void) {
        LLVMBuildRetVoid(mod.builder);
        return; 
    }
    auto val = genExpression(statement.expression, mod);
    val = implicitCast(val.location, val, t);
    LLVMBuildRet(mod.builder, val.get());
}

void genConditionalStatement(ast.ConditionalStatement statement, Module mod)
{
    if (genCondition(statement.condition, mod)) {
        genNoScopeNonEmptyStatement(statement.thenStatement, mod);
    } else {
        if (statement.elseStatement !is null) {
            genNoScopeNonEmptyStatement(statement.elseStatement, mod);
        }
    }
}
