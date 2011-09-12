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
    Statement thenStatement;
    Statement elseStatement;  // Optional.
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


// ( final )? switch ( Expression ) ScopeStatement
class SwitchStatement : Node
{
    bool isFinal;
    Expression controlExpression;
    Statement statement;
}

// Default statement and the two case statements.
class SwitchSubStatement : Node
{
    Statement[] statementList;
}

// case ArgumentList : StatementList
class CaseListStatement : SwitchSubStatement
{
    ConditionalExpression[] cases;
}

// case AssignExpression : .. case AssignExpression : StatementList
class CaseRangeStatement : SwitchSubStatement
{
    ConditionalExpression rangeBegin;
    ConditionalExpression rangeEnd;
}


class ContinueStatement : Node
{
    Identifier target;  // Optional.
}


class BreakStatement : Node
{
    Identifier target;  // Optional.
}


class ReturnStatement : Node
{
    Expression retval;  // Optional.
}


enum GotoStatementType { Identifier, Default, Case }

class GotoStatement : Node
{
    GotoStatementType type;
    Identifier target;  // Optional.
    Expression caseTarget;  // Optional.
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
    Expression exception;
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
    ConditionalExpression code;
}

class AsmStatement : Node
{
    Token[] tokens;
}
