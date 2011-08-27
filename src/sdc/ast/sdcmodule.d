/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
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
import gen = sdc.gen.type;


class Module : Node
{
    ModuleDeclaration moduleDeclaration;
    DeclarationDefinition[] declarationDefinitions;
}

// module QualifiedName ;
class ModuleDeclaration : Node
{
    QualifiedName name;
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
    
    /* The following are for codegen purposes.
     * It's kinda icky, I know.
     */
    Attribute[] attributes;
    BuildStage buildStage;
    bool importedSymbol;
    QualifiedName parentName;
    gen.Type parentType;
}

class StaticAssert : Node
{
    AssignExpression condition;
    AssignExpression message; // Optional
}

class Unittest : Node
{
    FunctionBody _body;
}
