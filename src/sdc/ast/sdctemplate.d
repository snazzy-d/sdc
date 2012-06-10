/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC.
 * See LICENCE or sdc.d for more details.
 */
module sdc.ast.sdctemplate;

import sdc.ast.base;
import sdc.ast.declaration;
import sdc.ast.expression;
import sdc.ast.sdcmodule;
import sdc.ast.visitor;


/*
 * Declaration.
 */

// template Identifier ( TemplateParameterList ) Constraint
class TemplateDeclaration : Node
{
    Identifier templateIdentifier;
    TemplateParameterList parameterList;
    Constraint constraint;  // Optional.
    DeclarationDefinition[] declDefs;

    override void accept(AstVisitor visitor)
    {
        templateIdentifier.accept(visitor);
        parameterList.accept(visitor);
        if (constraint !is null) constraint.accept(visitor);
        foreach (d; declDefs) d.accept(visitor);
        visitor.visit(this);
    }
}

// TemplateParameter (, TemplateParameter)?
class TemplateParameterList : Node
{
    TemplateParameter[] parameters;

    override void accept(AstVisitor visitor)
    {
        foreach (p; parameters) p.accept(visitor);
        visitor.visit(this);
    }
}

enum TemplateParameterType
{
    Type,
    Value,
    Alias,
    Tuple,
    This
}

// One of the above.
class TemplateParameter : Node
{
    TemplateParameterType type;
    Node node;

    override void accept(AstVisitor visitor)
    {
        node.accept(visitor);
        visitor.visit(this);
    }
}

// Identifier (: Specialisation)? (= Default)? 
class TemplateTypeParameter : Node
{
    Identifier identifier;
    Type specialisation;  // Optional.
    Type parameterDefault;  // Optional.

    override void accept(AstVisitor visitor)
    {
        identifier.accept(visitor);
        if (specialisation !is null) specialisation.accept(visitor);
        if (parameterDefault !is null) parameterDefault.accept(visitor);
        visitor.visit(this);
    }
}

class TemplateValueParameter : Node
{
    VariableDeclaration declaration;
    ConditionalExpression specialisation;  // Optional.
    TemplateValueParameterDefault parameterDefault;  // Optional.

    override void accept(AstVisitor visitor)
    {
        declaration.accept(visitor);
        if (specialisation !is null) specialisation.accept(visitor);
        if (parameterDefault !is null) parameterDefault.accept(visitor);
        visitor.visit(this);
    }
}

// : ConditionalExpression
class TemplateValueParameterSpecialisation : Node
{
    ConditionalExpression expression;

    override void accept(AstVisitor visitor)
    {
        expression.accept(visitor);
        visitor.visit(this);
    }
}

enum TemplateValueParameterDefaultType
{
    __File__,
    __Line__,
    ConditionalExpression
}

class TemplateValueParameterDefault : Node
{
    TemplateValueParameterDefaultType type;
    ConditionalExpression expression;  // Optional.

    override void accept(AstVisitor visitor)
    {
        if (expression !is null) expression.accept(visitor);
        visitor.visit(this);
    }
}

class TemplateAliasParameter : Node
{
    Identifier identifier;
    Type specialisation;  // Optional.
    Type parameterDefault;  // Optional.

    override void accept(AstVisitor visitor)
    {
        identifier.accept(visitor);
        if (specialisation !is null) specialisation.accept(visitor);
        visitor.visit(this);
    }
}

class TemplateTupleParameter : Node
{
    Identifier identifier;

    override void accept(AstVisitor visitor)
    {
        identifier.accept(visitor);
        visitor.visit(this);
    }
}

class TemplateThisParameter : Node
{
    TemplateTypeParameter templateTypeParameter;

    override void accept(AstVisitor visitor)
    {
        templateTypeParameter.accept(visitor);
        visitor.visit(this);
    }
}

class Constraint : Node
{
    Expression expression;

    override void accept(AstVisitor visitor)
    {
        expression.accept(visitor);
        visitor.visit(this);
    }
}

/*
 * Instantiation.
 */

// TemplateIdentifier ! (\( TemplateArgument+ \)| TemplateArgument
class TemplateInstance : Node
{
    Identifier identifier;
    TemplateArgument[] arguments;  // Optional.
    TemplateSingleArgument argument;  // Optional.

    override void accept(AstVisitor visitor)
    {
        identifier.accept(visitor);
        foreach (a; arguments) a.accept(visitor);
        if (argument !is null) argument.accept(visitor);
        visitor.visit(this);
    }
}

enum TemplateArgumentType
{
    Type,
    AssignExpression,
    Symbol
}

class TemplateArgument : Node
{
    TemplateArgumentType type;
    Node node;

    override void accept(AstVisitor visitor)
    {
        node.accept(visitor);
        visitor.visit(this);
    }
}

class Symbol : Node
{
    bool leadingDot;
    SymbolTail tail;

    override void accept(AstVisitor visitor)
    {
        tail.accept(visitor);
        visitor.visit(this);
    }
}

enum SymbolTailType
{
    Identifier,
    TemplateInstance
}

class SymbolTail : Node
{
    SymbolTailType type;
    Node node;
    SymbolTail tail;

    override void accept(AstVisitor visitor)
    {
        node.accept(visitor);
        tail.accept(visitor);
        visitor.visit(this);
    }
}

enum TemplateSingleArgumentType
{
    Identifier,
    BasicType,
    CharacterLiteral,
    StringLiteral,
    IntegerLiteral,
    FloatLiteral,
    True,
    False,
    Null,
    __File__,
    __Line__
}

class TemplateSingleArgument : Node
{
    TemplateSingleArgumentType type;
    Node node;  // Optional

    override void accept(AstVisitor visitor)
    {
        if (node !is null) node.accept(visitor);
        visitor.visit(this);
    }
}
