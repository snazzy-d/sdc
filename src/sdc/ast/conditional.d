/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.ast.conditional;

import sdc.ast.base;
import sdc.ast.expression;
import sdc.ast.sdcmodule;
import sdc.ast.statement;
import sdc.ast.attribute;


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
}

class ConditionalStatement : Node
{
    Condition condition;
    Statement thenStatement;
    Statement elseStatement;  // Optional.
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
}

// version = foo
class VersionSpecification : Node
{
    Node node;
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
}

// debug = foo
class DebugSpecification : Node
{
    Node node;
}

class StaticIfCondition : Node
{
    AssignExpression expression;
}
