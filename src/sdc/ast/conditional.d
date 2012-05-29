/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC.
 * See LICENCE or sdc.d for more details.
 */
module sdc.ast.conditional;

import sdc.ast.base;
import sdc.ast.expression;
import sdc.ast.sdcmodule;
import sdc.ast.statement;
import sdc.ast.attribute;
import sdc.ast.visitor;


enum ConditionalDeclarationType
{
    Block,
    VersionSpecification,
    DebugSpecification,
}

class ConditionalDeclaration : Node
{
    ConditionalDeclarationType type;
    Condition condition;
    DeclarationDefinition[] thenBlock;  // Optional.
    DeclarationDefinition[] elseBlock;  // Optional.
    Node specification;  // Optional.

    override void accept(AstVisitor visitor)
    {
        condition.accept(visitor);
        foreach (declDef; thenBlock) {
            declDef.accept(visitor);
        }
        foreach (declDef; elseBlock) {
            declDef.accept(visitor);
        }
        if (specification !is null) specification.accept(visitor);
        visitor.visit(this);
    }
}

class ConditionalStatement : Node
{
    Condition condition;
    Statement thenStatement;
    Statement elseStatement;  // Optional.

    override void accept(AstVisitor visitor)
    {
        condition.accept(visitor);
        thenStatement.accept(visitor);
        if (elseStatement !is null) elseStatement.accept(visitor);
        visitor.visit(this);
    }
}

enum ConditionType
{
    Version,
    Debug,
    StaticIf
}

class Condition : Node
{
    ConditionType type;
    Node condition;

    override void accept(AstVisitor visitor)
    {
        condition.accept(visitor);
        visitor.visit(this);
    }
}

enum VersionConditionType
{
    Identifier,
    Unittest
}

class VersionCondition : Node
{
    VersionConditionType type;
    Identifier identifier; // Optional

    override void accept(AstVisitor visitor)
    {
        if (identifier !is null) identifier.accept(visitor);
        visitor.visit(this);
    }
}

// version = foo
class VersionSpecification : Node
{
    Node node;

    override void accept(AstVisitor visitor)
    {
        node.accept(visitor);
        visitor.visit(this);
    }
}

enum DebugConditionType
{
    Simple,
    Identifier
}

class DebugCondition : Node
{
    DebugConditionType type;
    Identifier identifier; // Optional

    override void accept(AstVisitor visitor)
    {
        if (identifier !is null) identifier.accept(visitor);
        visitor.visit(this);
    }
}

// debug = foo
class DebugSpecification : Node
{
    Node node;

    override void accept(AstVisitor visitor)
    {
        node.accept(visitor);
        visitor.visit(this);
    }
}

class StaticIfCondition : Node
{
    ConditionalExpression expression;

    override void accept(AstVisitor visitor)
    {
        expression.accept(visitor);
        visitor.visit(this);
    }
}
