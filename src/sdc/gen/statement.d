/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.statement;

import std.stdio;

import sdc.compilererror;
import sdc.primitive;
import sdc.ast.statement;
import sdc.gen.base;
import sdc.gen.semantic;
import sdc.gen.expression;


void genBlockStatement(BlockStatement statement, File file, Semantic semantic)
{
    foreach(sstatement; statement.statements) {
        genStatement(sstatement, file, semantic);
    }
}

void genStatement(Statement statement, File file, Semantic semantic)
{
    if (statement.type == StatementType.Empty) {
    } else if (statement.type == StatementType.NonEmpty) {
        genNonEmptyStatement(cast(NonEmptyStatement) statement.node, file, semantic);
    }
}

void genScopeStatement(ScopeStatement statement, File file, Semantic semantic)
{
    semantic.pushScope();
    final switch (statement.type) {
    case ScopeStatementType.NonEmpty:
        genNonEmptyStatement(cast(NonEmptyStatement) statement.node, file, semantic);
        break;
    case ScopeStatementType.Block:
        genBlockStatement(cast(BlockStatement) statement.node, file, semantic);
        break;
    }
    semantic.popScope();
}

void genNonEmptyStatement(NonEmptyStatement statement, File file, Semantic semantic)
{
    switch (statement.type) {
    case NonEmptyStatementType.ExpressionStatement:
        genExpressionStatement(cast(ExpressionStatement) statement.node, file, semantic);
        break;
    case NonEmptyStatementType.DeclarationStatement:
        genDeclarationStatement(cast(DeclarationStatement) statement.node, file, semantic);
        break;
    case NonEmptyStatementType.ReturnStatement:
        genReturnStatement(cast(ReturnStatement) statement.node, file, semantic);
        break;
    case NonEmptyStatementType.IfStatement:
        genIfStatement(cast(IfStatement) statement.node, file, semantic);
        break;
    case NonEmptyStatementType.WhileStatement:
        genWhileStatement(cast(WhileStatement) statement.node, file, semantic);
        break;
    default:
        break;
    }
}

void genExpressionStatement(ExpressionStatement statement, File file, Semantic semantic)
{
    auto expr = genExpression(statement.expression, file, semantic);
}

void genDeclarationStatement(DeclarationStatement statement, File file, Semantic semantic)
{
    genDeclaration(statement.declaration, file, semantic);
}

void genReturnStatement(ReturnStatement statement, File file, Semantic semantic)
{
    semantic.currentScope.hasReturnStatement = true;
    if (statement.expression !is null) {
        auto expr = genExpression(statement.expression, file, semantic);
        auto retval = genVariable(Primitive(expr.primitive.size, expr.primitive.pointer - 1), "retval");
        asmgen.emitLoad(file, retval, expr);
        asmgen.emitReturn(file, retval);
    } else {
        asmgen.emitVoidReturn(file);
    }
}

void genIfStatement(IfStatement statement, File file, Semantic semantic)
{
    auto var = genIfCondition(statement.ifCondition, file, semantic);
    auto l1 = asmgen.genLabel("then");
    auto l2 = asmgen.genLabel("else");
    asmgen.emitIndirectBr(file, var, l1, l2);
    asmgen.emitLabel(file, l1);
    genThenStatement(statement.thenStatement, file, semantic);
    asmgen.emitLabel(file, l2);
    if (statement.elseStatement !is null) {
        genElseStatement(statement.elseStatement, file, semantic);
    }
}

Variable genIfCondition(IfCondition condition, File file, Semantic semantic)
{
    final switch (condition.type) {
    case IfConditionType.ExpressionOnly:
        break;
    case IfConditionType.Identifier:
        break;
    case IfConditionType.Declarator:
        break;
    }
    return genExpression(condition.expression, file, semantic);
}

void genThenStatement(ThenStatement statement, File file, Semantic semantic)
{
    genScopeStatement(statement.statement, file, semantic);
}

void genElseStatement(ElseStatement statement, File file, Semantic semantic)
{
    genScopeStatement(statement.statement, file, semantic);
}

void genWhileStatement(WhileStatement statement, File file, Semantic semantic)
{
    auto expr = genExpression(statement.expression, file, semantic);
    auto l1 = asmgen.genLabel("looptop");
    auto l2 = asmgen.genLabel("endloop");
    asmgen.emitIndirectBr(file, expr, l1, l2);
    asmgen.emitLabel(file, l1);
    genScopeStatement(statement.statement, file, semantic);
    expr = genExpression(statement.expression, file, semantic);
    asmgen.emitIndirectBr(file, expr, l1, l2);
    asmgen.emitLabel(file, l2);
}
