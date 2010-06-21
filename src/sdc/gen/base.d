/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.base;

import std.stdio;
import std.conv;

import sdc.primitive;
import sdc.compilererror;
import sdc.ast.all;
import sdc.extract.base;
import sdc.extract.expression;
import sdc.gen.expression;
public import asmgen = sdc.gen.llvm.base;


void genModule(Module mod, File file)
{
    asmgen.emitComment(file, extractQualifiedName(mod.moduleDeclaration.name));
    foreach (declarationDefinition; mod.declarationDefinitions) {
        genDeclaration(declarationDefinition.declaration, file);
    }
}


void genDeclaration(Declaration declaration, File file)
{
    if (declaration.type == DeclarationType.Function) {
        genFunctionDeclaration(cast(FunctionDeclaration) declaration.node, file);
    }
}


void genFunctionDeclaration(FunctionDeclaration declaration, File file)
{
    asmgen.emitFunctionDeclaration(file, declaration);
    asmgen.incrementIndent();
    genBlockStatement(declaration.functionBody.statement, file);
    asmgen.decrementIndent();
    asmgen.emitCloseFunctionDeclaration(file, declaration);
}

void genBlockStatement(BlockStatement statement, File file)
{
    foreach(sstatement; statement.statements) {
        genStatement(sstatement, file);
    }
}

void genStatement(Statement statement, File file)
{
    if (statement.type == StatementType.Empty) {
    } else if (statement.type == StatementType.NonEmpty) {
        genNonEmptyStatement(cast(NonEmptyStatement) statement.node, file);
    }
}

void genNonEmptyStatement(NonEmptyStatement statement, File file)
{
    switch (statement.type) {
    case NonEmptyStatementType.ReturnStatement:
        genReturnStatement(cast(ReturnStatement) statement.node, file);
        break;
    default:
        break;
    }
}

void genReturnStatement(ReturnStatement statement, File file)
{
    auto expr = genExpression(statement.expression, file);
    auto retval = genVariable(Primitive(expr.primitive.size, expr.primitive.pointer - 1), "retval");
    asmgen.emitLoad(file, retval, expr);
    asmgen.emitReturn(file, retval);
}

