/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.ast.statement;

import sdc.ast.base;


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
