/**
 * Copyright 2010-2011 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.ast.statement;

import sdc.token;
import sdc.ast.base;
import sdc.ast.expression;
import sdc.ast.declaration;
import sdc.ast.sdcpragma;


enum StatementType
{
    EmptyStatement,
    BlockStatement,
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

// ; | NonEmptyStatement | ScopeStatement
class Statement : Node
{
    StatementType type;
    Node node;  // Optional.
}

class BlockStatement : Node
{
    Statement[] statements;
}


// Identifier : NoScopeStatement
class LabeledStatement : Node
{
    Identifier identifier;
    Statement statement;
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
    Statement statement;
}

class ElseStatement : Node
{
    Statement statement;
}


// while ( Expression ) ScopeStatement
class WhileStatement : Node
{
    Expression expression;
    Statement statement;
}


// do ScopeStatement while ( Expression )
class DoStatement : Node
{
    Statement statement;
    Expression expression;
}


// for (ForInitialise ForTest; ForType) Statement
class ForStatement : Node
{
    Statement initialise; // Optional.
    Expression test; // Optional.
    Expression increment; // Optional.
    Statement statement;
}

enum ForIncrementType { Empty, Expression }

class ForIncrement : Node
{
    ForIncrementType type;
    Node node;  // Optional.
}

// foreach ( ForeachTypes ; Expression (.. Expression)?) Statement
enum ForeachForm { Aggregate, Range }

class ForeachStatement : Node
{
    ForeachForm form;
    ForeachType[] foreachTypes;
    Expression expression; // Aggregate or range start.
    Expression rangeEnd; // Optional.
    Statement statement;
}

enum ForeachTypeType { Explicit, Implicit }

class ForeachType : Node
{
    ForeachTypeType type;
    bool isRef;
    Identifier identifier;
    Type explicitType; // Optional.
}


// switch ( Expression ) ScopeStatement
class SwitchStatement : Node
{
    Expression expression;
    Statement statement;
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
    Statement statement;
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


enum GotoStatementType { Identifier, Default, Case }

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
    Statement statement;
}


class SynchronizedStatement : Node
{
    Expression expression;  // Optional.
    Statement statement;
}


class TryStatement : Node
{
    Statement statement;
    
    // When you uncomment these, update sdc.gen.dryrun.labelGatherStatement!
    //Catches catches;  // Optional
    //FinallyStatement finallyStatement;
    
    Statement catchStatement;  // TMP
}

class Catches : Node
{
    Catch[] catches;
    LastCatch lastCatch;
}

class Catch : Node
{
    CatchParameter parameter;
    Statement statement;
}

class CatchParameter : Node
{
    Type type;
    Identifier identifier;  // XXX: Optional, grammar disagrees.
}

// catch NoScopeNonEmptyStatement
class LastCatch : Node
{
    Statement statement;
}

// finally NoScopeNonEmptyStatement
class FinallyStatement : Node
{
    Statement statement;
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
    Statement statement;
}

class PragmaStatement : Node
{
    Pragma thePragma;
    Statement statement; // Optional
}

class MixinStatement : Node
{
    AssignExpression expression;
}

class AsmStatement : Node
{
    Token[] tokens;
}
