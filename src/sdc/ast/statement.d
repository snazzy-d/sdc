/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.ast.statement;

import sdc.tokenstream;
import sdc.ast.base;
import sdc.ast.expression;
import sdc.ast.declaration;


enum StatementType
{
    Empty,
    NonEmpty,
    Scope
}

// ; | NonEmptyStatement | ScopeStatement
class Statement : Node
{
    StatementType type;
    Node node;  // Optional.
}


enum NoScopeNonEmptyStatementType
{
    NonEmpty,
    Block
}

class NoScopeNonEmptyStatement : Node
{
    NoScopeNonEmptyStatementType type;
    Node node;
}


enum NonEmptyOrScopeBlockStatementType { NonEmpty, ScopeBlock }

class NonEmptyOrScopeBlockStatement : Node
{
    NonEmptyOrScopeBlockStatementType type;
    Node node;
}


enum NoScopeStatementType
{
    Empty,
    NonEmpty,
    Block
}

class NoScopeStatement : Node
{
    NoScopeStatementType type;
    Node node;
}


enum ScopeStatementType
{
    NonEmpty,
    Block
}

// NonEmptyStatement | BlockStatement
class ScopeStatement : Node
{
    ScopeStatementType type;
    Node node;
}


enum NonEmptyStatementType
{
    LabeledStatement,
    ExpressionStatement,
    DeclarationStatement,
    IfStatement,
    WhileStatement,
    DoStatement,
    ForStatement,
    ForeachStatement,
    SwitchStatement,
    FinalSwitchStatement,
    CaseStatement,
    CaseRangeStatement,
    DefaultStatement,
    ContinueStatement,
    BreakStatement,
    ReturnStatement,
    GotoStatement,
    WithStatement,
    SynchronizedStatement,
    TryStatement,
    ScopeGuardStatement,
    ThrowStatement,
    AsmStatement,
    PragmaStatement,
    MixinStatement,
    ForeachRangeStatement,
    ConditionalStatement,
    StaticAssert,
    TemplateMixin
}

class NonEmptyStatement : Node
{
    NonEmptyStatementType type;
    Node node;
}


// { Statements? }
class BlockStatement : Node
{
    Statement[] statements;
}


// Identifier : NoScopeStatement
class LabeledStatement : Node
{
    Identifier identifier;
    NoScopeStatement statement;
}


// Expression ;
class ExpressionStatement : Node
{
    Expression expression;
}


// Declaration
class DeclarationStatement : Node
{
    Declaration declaration;
}

// if ( IfCondition ) ThenStatement (else ElseStatement)?
class IfStatement : Node
{
    IfCondition ifCondition;
    ThenStatement thenStatement;
    ElseStatement elseStatement;  // Optional.
}

enum IfConditionType
{
    ExpressionOnly,
    Identifier,
    Declarator
}

// Expression | auto Identifier = Expression | Declarator = Expression
class IfCondition : Node
{
    IfConditionType type;
    Expression expression;
    Node node;  // Optional.
}

class ThenStatement : Node
{
    ScopeStatement statement;
}

class ElseStatement : Node
{
    ScopeStatement statement;
}


// while ( Expression ) ScopeStatement
class WhileStatement : Node
{
    Expression expression;
    ScopeStatement statement;
}


// do ScopeStatement while ( Expression )
class DoStatement : Node
{
    ScopeStatement statement;
    Expression expression;
}


// for (ForInitialise ForTest; ForType) ScopeStatement
class ForStatement : Node
{
    ForInitialise initialise;
    ForTest test;
    ForIncrement increment;
    ScopeStatement statement;
}

enum ForInitialiseType { Empty, NoScopeNonEmpty }

class ForInitialise : Node
{
    ForInitialiseType type;
    Node node;  // Optional.
}

enum ForTestType { Empty, Expression }

class ForTest : Node
{
    ForTestType type;
    Node node;  // Optional.
}

enum ForIncrementType { Empty, Expression }

class ForIncrement : Node
{
    ForIncrementType type;
    Node node;  // Optional.
}


// foreach ( ForeachTypes ; Expression ) NonScopeNonEmptyStatement
class ForeachStatement : Node
{
    ForeachType[] foreachTypes;
    Expression aggregate;
    NoScopeNonEmptyStatement statement;
}

enum ForeachTypeType { RefTypeIdentifier, TypeIdentifier, RefIdentifier, Identifier }

class ForeachType : Node
{
    Type type;
    Identifier identifier;
}


// switch ( Expression ) ScopeStatement
class SwitchStatement : Node
{
    Expression expression;
    ScopeStatement statement;
}

// case ArgumentList : Statement
class CaseStatement : Node
{
    ArgumentList argumentList;
    Statement statement;
}

// case AssignExpression : .. case AssignExpression : Statement
class CaseRangeStatement : Node
{
    AssignExpression firstExpression;
    AssignExpression secondExpression;
    Statement statement;
}

// default : Statement
class DefaultStatement : Node
{
    Statement statement;
}


// final switch ( Expression ) Statement
class FinalSwitchStatement : Node
{
    Expression expression;
    ScopeStatement statement;
}


class ContinueStatement : Node
{
    Identifier identifier;  // Optional.
}


class BreakStatement : Node
{
    Identifier identifier;  // Optional.
}


class ReturnStatement : Node
{
    Expression expression;  // Optional.
}


enum GotoStatementType { Identifier, Default, Case, CaseExpression }

class GotoStatement : Node
{
    GotoStatementType type;
    Identifier identifier;  // Optional.
    Expression expression;  // Optional.
}

enum WithStatementType { Expression, Symbol, TemplateInstance }

class WithStatement : Node
{
    WithStatementType type;
    Node node;
    ScopeStatement statement;
}


class SynchronizedStatement : Node
{
    Expression expression;  // Optional.
    ScopeStatement statement;
}


class TryStatement : Node
{
    ScopeStatement statement;
}

class Catches : Node
{
    Catch[] catches;
    LastCatch lastCatch;
}

class Catch : Node
{
    CatchParameter parameter;
    NoScopeNonEmptyStatement statement;
}

class CatchParameter : Node
{
    Type type;
    Identifier identifier;  // XXX: Optional, grammar disagrees.
}

// catch NoScopeNonEmptyStatement
class LastCatch : Node
{
    NoScopeNonEmptyStatement statement;
}

// finally NoScopeNonEmptyStatement
class FinallyStatement : Node
{
    NoScopeNonEmptyStatement statement;
}


// throw Expression
class ThrowStatement : Node
{
    Expression expression;
}


enum ScopeGuardStatementType { Exit, Success, Failure }

class ScopeGuardStatement : Node
{
    ScopeGuardStatementType type;
    NonEmptyOrScopeBlockStatement statement;
}

// TODO: asm pragma mixin foreachrange 
