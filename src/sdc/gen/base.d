/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.base;

import std.stdio;
import std.conv;

import sdc.util;
import sdc.primitive;
import sdc.compilererror;
import sdc.ast.all;
import sdc.extract.base;
import sdc.extract.expression;
import sdc.gen.expression;
import sdc.gen.semantic;
public import asmgen = sdc.gen.llvm.base;


void genModule(Module mod, File file)
{
    auto semantic = new Semantic();
    asmgen.emitComment(file, extractQualifiedName(mod.moduleDeclaration.name));
    foreach (declarationDefinition; mod.declarationDefinitions) {
        genDeclaration(declarationDefinition.declaration, file, semantic);
    }
}


void genDeclaration(Declaration declaration, File file, Semantic semantic)
{
    if (declaration.type == DeclarationType.Function) {
        genFunctionDeclaration(cast(FunctionDeclaration) declaration.node, file, semantic);
    } else if (declaration.type == DeclarationType.Variable) {
        genVariableDeclaration(cast(VariableDeclaration) declaration.node, file, semantic);
    }
}

void genVariableDeclaration(VariableDeclaration declaration, File file, Semantic semantic)
{
    auto primitive = fullTypeToPrimitive(declaration.type);
    foreach (declarator; declaration.declarators) {
        auto var = genVariable(primitive, extractIdentifier(declarator.name));
        asmgen.emitAlloca(file, var);
        asmgen.emitStore(file, var, new Constant("0", primitive));
    }
}

void genFunctionDeclaration(FunctionDeclaration declaration, File file, Semantic semantic)
{
    asmgen.emitFunctionDeclaration(file, declaration);
    asmgen.incrementIndent();
    
    string functionName = extractIdentifier(declaration.name);
    semantic.addDeclaration(functionName, declaration);
    semantic.pushScope();
    foreach (parameter; declaration.parameters) if (parameter.identifier !is null) {
        /*
        auto var = new VariableDeclaration();
        var.location = parameter.location;
        var.type = parameter.type;
        var.name = parameter.identifier;
        string paramName = extractIdentifier(var.name);
        semantic.addDeclaration(paramName, var);*/
    }
    genBlockStatement(declaration.functionBody.statement, file, semantic);
    
    semantic.popScope();
    asmgen.decrementIndent();
    asmgen.emitCloseFunctionDeclaration(file, declaration);
}

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

void genNonEmptyStatement(NonEmptyStatement statement, File file, Semantic semantic)
{
    switch (statement.type) {
    case NonEmptyStatementType.DeclarationStatement:
        genDeclarationStatement(cast(DeclarationStatement) statement.node, file, semantic);
        break;
    case NonEmptyStatementType.ReturnStatement:
        genReturnStatement(cast(ReturnStatement) statement.node, file, semantic);
        break;
    default:
        break;
    }
}

void genDeclarationStatement(DeclarationStatement statement, File file, Semantic semantic)
{
    genDeclaration(statement.declaration, file, semantic);
}

void genReturnStatement(ReturnStatement statement, File file, Semantic semantic)
{
    auto expr = genExpression(statement.expression, file);
    auto retval = genVariable(Primitive(expr.primitive.size, expr.primitive.pointer - 1), "retval");
    asmgen.emitLoad(file, retval, expr);
    asmgen.emitReturn(file, retval);
}

