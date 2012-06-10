/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC.
 * See LICENCE or sdc.d for more details.
 */
module sdc.ast.sdcmodule;

import std.path;

import sdc.compilererror;
import sdc.token;
import sdc.ast.base;
import sdc.ast.declaration;
import sdc.ast.attribute;
import sdc.ast.expression; // StaticAssert
import sdc.ast.visitor;


class Module : Node
{
    ModuleDeclaration moduleDeclaration;
    DeclarationDefinition[] declarationDefinitions;

    override void accept(AstVisitor visitor)
    {
        moduleDeclaration.accept(visitor);
        foreach (decl; declarationDefinitions) {
            decl.accept(visitor);
        }
        visitor.visit(this);
    }
}

// module QualifiedName ;
class ModuleDeclaration : Node
{
    QualifiedName name;

    override void accept(AstVisitor visitor)
    {
        name.accept(visitor);
        visitor.visit(this);
    }
}

enum DeclarationDefinitionType
{
    ImportDeclaration,
    EnumDeclaration,
    ClassDeclaration,
    InterfaceDeclaration,
    AggregateDeclaration,
    Declaration,
    Constructor,
    Destructor,
    Invariant,
    Unittest,
    StaticConstructor,
    StaticDestructor,
    SharedStaticConstructor,
    SharedStaticDestructor,
    ConditionalDeclaration,
    StaticAssert,
    TemplateDeclaration,
    TemplateMixin,
    MixinDeclaration,
    Empty,
}

enum BuildStage
{
    Unhandled,
    Deferred,
    ReadyToExpand,
    ReadyToRecurse,
    ReadyForCodegen,
    Done,
    DoneForever,
}

/**
 * A DeclarationDefinition is a top-level declaration.
 */
class DeclarationDefinition : Node
{
    DeclarationDefinitionType type;
    Node node;

    override void accept(AstVisitor visitor)
    {
        node.accept(visitor);
        visitor.visit(this);
    }
}

class StaticAssert : Node
{
    ConditionalExpression condition;
    ConditionalExpression message; // Optional

    override void accept(AstVisitor visitor)
    {
        condition.accept(visitor);
        if (message !is null) message.accept(visitor);
        visitor.visit(this);
    }
}

class Unittest : Node
{
    FunctionBody _body;

    override void accept(AstVisitor visitor)
    {
        _body.accept(visitor);
        visitor.visit(this);
    }
}
