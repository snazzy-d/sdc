/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.ast.conditional;

import sdc.ast.base;
import sdc.ast.declaration;
import sdc.ast.expression;
import sdc.ast.statement;

enum ConditionType
{
    Version,
    Debug,
    StaticIf
}

enum ConditionDeclarationType
{
    ConditionThenDeclarations,
    ConditionThenDeclarationsThenElse,
    ConditionOn
}

class ConditionalDeclaration : Node
{
    ConditionType conditionType;
    Node condition;
    Declaration[] thenBlock;
    Declaration[] elseBlock;  // Optional.
}

class ConditionalStatement : Node
{
    ConditionType conditionType;
    Node condition;
    NoScopeNonEmptyStatement thenStatement;
    NoScopeNonEmptyStatement elseStatement;  // Optional.
}

enum VersionConditionType
{
    Integer,
    Identifier,
    Unittest
}

class VersionCondition : Node
{
    VersionConditionType type;
    int integer;  // Optional.
    Identifier identifier;  // Optional.
}

enum DebugConditionType
{
    Simple,
    Integer,
    Identifier
}

class DebugCondition : Node
{
    DebugConditionType type;
    int integer;  // Optional.
    Identifier identifier;  // Optional.
}

class StaticIfCondition : Node
{
    AssignExpression expression;
}
