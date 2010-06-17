/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.base;

import std.stdio;

import sdc.compilererror;
import sdc.ast.all;
import sdc.extract.base;
import asmgen = sdc.gen.llvm.base;




void genModule(Module mod, File file)
{
    asmgen.comment(file, 0, extractQualifiedName(mod.moduleDeclaration.name));
    foreach (declarationDefinition; mod.declarationDefinitions) {
        genDeclarationDefinition(declarationDefinition, file);
    }
}

void genDeclarationDefinition(DeclarationDefinition decldef, File file)
{
    genDeclaration(decldef.declaration, file);
}

void genDeclaration(Declaration decl, File file)
{
    if (decl.functionBody !is null) {
        genFunctionDeclaration(decl, file);
        genFunctionBody(decl.functionBody, file);
    } else {
        genVariableDeclaration(decl, file);
    }
}

void genFunctionDeclaration(Declaration decl, File file)
{
    asmgen.functionDefinition(file, 0, decl.basicType, 
                              decl.declarators.declaratorInitialiser.declarator.identifier.value,
                              decl.declarators.declaratorInitialiser.declarator.declaratorSuffixes[0].parameters.parameters);
}

void genFunctionBody(FunctionBody functionBody, File file)
{
    genBlockStatement(functionBody.statement, file);
}

void genBlockStatement(BlockStatement block, File file)
{
    foreach (statement; block.statements) {
        genStatement(statement, file);
    }
}

void genStatement(Statement statement, File file)
{
    final switch (statement.type) {
    case StatementType.Empty:
        break;
    case StatementType.NonEmpty:
        genNonEmptyStatement(cast(NonEmptyStatement)statement.node, file);
        break;
    case StatementType.Scope:
        genScopeStatement(cast(ScopeStatement)statement.node, file);
        break;
    }
}

void genNonEmptyStatement(NonEmptyStatement statement, File file)
{
    switch (statement.type) {
    case NonEmptyStatementType.ReturnStatement:
        genReturnStatement(cast(ReturnStatement)statement.node, file);
        break;
    default:
        error(statement.location, "ERROR");
        assert(false);
    }
}

void genScopeStatement(ScopeStatement statement, File file)
{
}

void genReturnStatement(ReturnStatement statement, File file)
{
}

void genVariableDeclaration(Declaration decl, File file)
{
}
