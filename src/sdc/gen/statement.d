/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.statement;

import llvm.c.Core;

import sdc.compilererror;
import ast = sdc.ast.all;
import sdc.gen.sdcmodule;
import sdc.gen.expression;
import sdc.gen.value;


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

void genNonEmptyStatement(ast.NonEmptyStatement statement, Module mod)
{
    switch (statement.type) {
    default:
        panic(statement.location, "unimplemented non empty statement type.");
        assert(false);
    case ast.NonEmptyStatementType.ReturnStatement:
        genReturnStatement(cast(ast.ReturnStatement) statement.node, mod);
        break;
    }
}

void genReturnStatement(ast.ReturnStatement statement, Module mod)
{
    auto val = genExpression(statement.expression, mod);
    LLVMBuildRet(mod.builder, val.get());
}
