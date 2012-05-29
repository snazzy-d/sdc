/**
 * Copyright 2010-2011 Bernard Helyer.
 * This file is part of SDC.
 * See LICENCE or sdc.d for more details.
 */
module sdc.ast.statement;

import sdc.token;
import sdc.ast.base;
import sdc.ast.expression;
import sdc.ast.declaration;
import sdc.ast.sdcpragma;
import sdc.ast.visitor;


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

    override void accept(AstVisitor visitor)
    {
        if (node !is null) node.accept(visitor);
        visitor.visit(this);
    }
}

class BlockStatement : Node
{
    Statement[] statements;

    override void accept(AstVisitor visitor)
    {
        foreach (s; statements) s.accept(visitor);
        visitor.visit(this);
    }
}


// Identifier : NoScopeStatement
class LabeledStatement : Node
{
    Identifier identifier;
    Statement statement;

    override void accept(AstVisitor visitor)
    {
        identifier.accept(visitor);
        statement.accept(visitor);
        visitor.visit(this);
    }
}


// Expression ;
class ExpressionStatement : Node
{
    Expression expression;

    override void accept(AstVisitor visitor)
    {
        expression.accept(visitor);
        visitor.visit(this);
    }
}


// Declaration
class DeclarationStatement : Node
{
    Declaration declaration;

    override void accept(AstVisitor visitor)
    {
        declaration.accept(visitor);
        visitor.visit(this);
    }
}

// if ( IfCondition ) ThenStatement (else ElseStatement)?
class IfStatement : Node
{
    IfCondition ifCondition;
    Statement thenStatement;
    Statement elseStatement;  // Optional.

    override void accept(AstVisitor visitor)
    {
        ifCondition.accept(visitor);
        thenStatement.accept(visitor);
        if (elseStatement !is null) elseStatement.accept(visitor);
        visitor.visit(this);
    }
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

    override void accept(AstVisitor visitor)
    {
        expression.accept(visitor);
        if (node !is null) node.accept(visitor);
        visitor.visit(this);
    }
}


// while ( Expression ) ScopeStatement
class WhileStatement : Node
{
    Expression expression;
    Statement statement;

    override void accept(AstVisitor visitor)
    {
        expression.accept(visitor);
        statement.accept(visitor);
        visitor.visit(this);
    }
}


// do ScopeStatement while ( Expression )
class DoStatement : Node
{
    Statement statement;
    Expression expression;

    override void accept(AstVisitor visitor)
    {
        statement.accept(visitor);
        expression.accept(visitor);
        visitor.visit(this);
    }
}


// for (ForInitialise ForTest; ForType) Statement
class ForStatement : Node
{
    Statement initialise; // Optional.
    Expression test; // Optional.
    Expression increment; // Optional.
    Statement statement;

    override void accept(AstVisitor visitor)
    {
        if (initialise !is null) initialise.accept(visitor);
        if (test !is null) test.accept(visitor);
        if (increment !is null) increment.accept(visitor);
        statement.accept(visitor);
        visitor.visit(this);
    }
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

    override void accept(AstVisitor visitor)
    {
        foreach (t; foreachTypes) t.accept(visitor);
        expression.accept(visitor);
        if (rangeEnd !is null) rangeEnd.accept(visitor);
        statement.accept(visitor);
        visitor.visit(this);
    }
}

enum ForeachTypeType { Explicit, Implicit }

class ForeachType : Node
{
    ForeachTypeType type;
    bool isRef;
    Identifier identifier;
    Type explicitType; // Optional.

    override void accept(AstVisitor visitor)
    {
        identifier.accept(visitor);
        if (explicitType !is null) explicitType.accept(visitor);
        visitor.visit(this);
    }
}


// ( final )? switch ( Expression ) ScopeStatement
class SwitchStatement : Node
{
    bool isFinal;
    Expression controlExpression;
    Statement statement;

    override void accept(AstVisitor visitor)
    {
        controlExpression.accept(visitor);
        statement.accept(visitor);
        visitor.visit(this);
    }
}

// Default statement and the two case statements.
class SwitchSubStatement : Node
{
    Statement[] statementList;

    override void accept(AstVisitor visitor)
    {
        foreach (s; statementList) s.accept(visitor);
        visitor.visit(this);
    }
}

// case ArgumentList : StatementList
class CaseListStatement : SwitchSubStatement
{
    ConditionalExpression[] cases;

    override void accept(AstVisitor visitor)
    {
        foreach (c; cases) c.accept(visitor);
        visitor.visit(this);
    }
}

// case AssignExpression : .. case AssignExpression : StatementList
class CaseRangeStatement : SwitchSubStatement
{
    ConditionalExpression rangeBegin;
    ConditionalExpression rangeEnd;

    override void accept(AstVisitor visitor)
    {
        rangeBegin.accept(visitor);
        rangeEnd.accept(visitor);
        visitor.visit(this);
    }
}


class ContinueStatement : Node
{
    Identifier target;  // Optional.

    override void accept(AstVisitor visitor)
    {
        if (target !is null) target.accept(visitor);
        visitor.visit(this);
    }
}


class BreakStatement : Node
{
    Identifier target;  // Optional.

    override void accept(AstVisitor visitor)
    {
        if (target !is null) target.accept(visitor);
        visitor.visit(this);
    }
}


class ReturnStatement : Node
{
    Expression retval;  // Optional.

    override void accept(AstVisitor visitor)
    {
        if (retval !is null) retval.accept(visitor);
        visitor.visit(this);
    }
}


enum GotoStatementType { Identifier, Default, Case }

class GotoStatement : Node
{
    GotoStatementType type;
    Identifier target;  // Optional.
    Expression caseTarget;  // Optional.

    override void accept(AstVisitor visitor)
    {
        if (target !is null) target.accept(visitor);
        if (caseTarget !is null) caseTarget.accept(visitor);
        visitor.visit(this);
    }
}

enum WithStatementType { Expression, Symbol, TemplateInstance }

class WithStatement : Node
{
    WithStatementType type;
    Node node;
    Statement statement;

    override void accept(AstVisitor visitor)
    {
        node.accept(visitor);
        statement.accept(visitor);
        visitor.visit(this);
    }
}


class SynchronizedStatement : Node
{
    Expression expression;  // Optional.
    Statement statement;

    override void accept(AstVisitor visitor)
    {
        if (expression !is null) expression.accept(visitor);
        statement.accept(visitor);
        visitor.visit(this);
    }
}


class TryStatement : Node
{
    Statement statement;
    
    // When you uncomment these, update sdc.gen.dryrun.labelGatherStatement!
    //Catches catches;  // Optional
    //FinallyStatement finallyStatement;
    
    Statement catchStatement;  // TMP

    override void accept(AstVisitor visitor)
    {
        statement.accept(visitor);
        catchStatement.accept(visitor);
        visitor.visit(this);
    }
}

class Catches : Node
{
    Catch[] catches;
    LastCatch lastCatch;

    override void accept(AstVisitor visitor)
    {
        foreach (c; catches) c.accept(visitor);
        lastCatch.accept(visitor);
        visitor.visit(this);
    }
}

class Catch : Node
{
    CatchParameter parameter;
    Statement statement;

    override void accept(AstVisitor visitor)
    {
        parameter.accept(visitor);
        statement.accept(visitor);
        visitor.visit(this);
    }
}

class CatchParameter : Node
{
    Type type;
    Identifier identifier;  // XXX: Optional, grammar disagrees.

    override void accept(AstVisitor visitor)
    {
        type.accept(visitor);
        if (identifier !is null) identifier.accept(visitor);
        visitor.visit(this);
    }
}

// catch NoScopeNonEmptyStatement
class LastCatch : Node
{
    Statement statement;

    override void accept(AstVisitor visitor)
    {
        statement.accept(visitor);
        visitor.visit(this);
    }
}

// finally NoScopeNonEmptyStatement
class FinallyStatement : Node
{
    Statement statement;

    override void accept(AstVisitor visitor)
    {
        statement.accept(visitor);
        visitor.visit(this);
    }
}


// throw Expression
class ThrowStatement : Node
{
    Expression exception;

    override void accept(AstVisitor visitor)
    {
        exception.accept(visitor);
        visitor.visit(this);
    }
}


enum ScopeGuardStatementType { Exit, Success, Failure }

class ScopeGuardStatement : Node
{
    ScopeGuardStatementType type;
    Statement statement;

    override void accept(AstVisitor visitor)
    {
        statement.accept(visitor);
        visitor.visit(this);
    }
}

class PragmaStatement : Node
{
    Pragma thePragma;
    Statement statement; // Optional

    override void accept(AstVisitor visitor)
    {
        thePragma.accept(visitor);
        if (statement !is null) statement.accept(visitor);
        visitor.visit(this);
    }
}

class MixinStatement : Node
{
    ConditionalExpression code;

    override void accept(AstVisitor visitor)
    {
        code.accept(visitor);
        visitor.visit(this);
    }
}

class AsmStatement : Node
{
    Token[] tokens;

    override void accept(AstVisitor visitor)
    {
        visitor.visit(this);
    }
}
