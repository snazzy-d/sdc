/**
 * Copyright 2010 Bernard Helyer.
 * Copyright 2010 Jakob Ovrum.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.parser.statement;

import sdc.util;
import sdc.tokenstream;
import sdc.compilererror;
import sdc.ast.statement;
import sdc.parser.base;
import sdc.parser.expression;
import sdc.parser.declaration;
import sdc.parser.conditional;


Statement parseStatement(TokenStream tstream)
{
    auto statement = new Statement();
    statement.location = tstream.peek.location;
    
    if (tstream.peek.type == TokenType.Semicolon) {
        match(tstream, TokenType.Semicolon);
        statement.type = StatementType.Empty;
    } else if (tstream.peek.type == TokenType.OpenBrace) {
        statement.type = StatementType.Scope;
        statement.node = parseScopeStatement(tstream);
    } else {
        statement.type = StatementType.NonEmpty;
        statement.node = parseNonEmptyStatement(tstream);
    }
    
    return statement;
}

ScopeStatement parseScopeStatement(TokenStream tstream)
{
    auto statement = new ScopeStatement();
    statement.location = tstream.peek.location;
    
    if (tstream.peek.type == TokenType.OpenBrace) {
        statement.type = ScopeStatementType.Block;
        statement.node = parseBlockStatement(tstream);
    } else {
        statement.type = ScopeStatementType.NonEmpty;
        statement.node = parseNonEmptyStatement(tstream);
    }
    
    return statement;
}

NonEmptyStatement parseNonEmptyStatement(TokenStream tstream)
{
    auto statement = new NonEmptyStatement();
    statement.location = tstream.peek.location;
    
    if (tstream.peek.type == TokenType.If) {
        statement.type = NonEmptyStatementType.IfStatement;
        statement.node = parseIfStatement(tstream);   
    } else if (tstream.peek.type == TokenType.While) {
        statement.type = NonEmptyStatementType.WhileStatement;
        statement.node = parseWhileStatement(tstream);
    } else if (tstream.peek.type == TokenType.Do) {
        statement.type = NonEmptyStatementType.DoStatement;
        statement.node = parseDoStatement(tstream);
    } else if (tstream.peek.type == TokenType.Return) {
        statement.type = NonEmptyStatementType.ReturnStatement;
        statement.node = parseReturnStatement(tstream);
    } else if (startsLikeConditional(tstream)) {
        statement.type = NonEmptyStatementType.ConditionalStatement;
        statement.node = parseConditionalStatement(tstream);
    } else if (tstream.lookahead(0).type == TokenType.Identifier &&
               tstream.lookahead(1).type == TokenType.Asterix &&
               tstream.lookahead(2).type == TokenType.Identifier) {
        // In D, this is always a declaration; unlike C.
        statement.type = NonEmptyStatementType.DeclarationStatement;
        statement.node = parseDeclarationStatement(tstream);
    } else if (startsLikeDeclaration(tstream)) {
        statement.type = NonEmptyStatementType.DeclarationStatement;
        statement.node = parseDeclarationStatement(tstream);
    } else {
        statement.type = NonEmptyStatementType.ExpressionStatement;
        statement.node = parseExpressionStatement(tstream);
    }
    
    return statement;
}

NoScopeNonEmptyStatement parseNoScopeNonEmptyStatement(TokenStream tstream)
{
    auto statement = new NoScopeNonEmptyStatement();
    statement.location = tstream.peek.location;
    
    if (tstream.peek.type == TokenType.OpenBrace) {
        statement.type = NoScopeNonEmptyStatementType.Block;
        statement.node = parseBlockStatement(tstream);
    } else {
        statement.type = NoScopeNonEmptyStatementType.NonEmpty;
        statement.node = parseNonEmptyStatement(tstream);
    }
    return statement;
}

BlockStatement parseBlockStatement(TokenStream tstream)
{
    auto block = new BlockStatement();
    block.location = tstream.peek.location;
    
    match(tstream, TokenType.OpenBrace);
    while (tstream.peek.type != TokenType.CloseBrace) {
        block.statements ~= parseStatement(tstream);
    }
    match(tstream, TokenType.CloseBrace);
    
    return block;
}

IfStatement parseIfStatement(TokenStream tstream)
{
    auto statement = new IfStatement();
    statement.location = tstream.peek.location;
    
    match(tstream, TokenType.If);
    match(tstream, TokenType.OpenParen);
    statement.ifCondition = parseIfCondition(tstream);
    match(tstream, TokenType.CloseParen);
    statement.thenStatement = parseThenStatement(tstream);
    if (tstream.peek.type == TokenType.Else) {
        match(tstream, TokenType.Else);
        statement.elseStatement = parseElseStatement(tstream);
    }
    
    return statement;
}

IfCondition parseIfCondition(TokenStream tstream)
{
    auto condition = new IfCondition();
    condition.location = tstream.peek.location;
    
    if (tstream.peek.type == TokenType.Auto) {
        condition.type = IfConditionType.Identifier;
        match(tstream, TokenType.Auto);
        condition.node = parseIdentifier(tstream);
        match(tstream, TokenType.Assign);
    } else {
        condition.type = IfConditionType.ExpressionOnly;
    }
    condition.expression = parseExpression(tstream);
    
    return condition;
}

ThenStatement parseThenStatement(TokenStream tstream)
{
    auto statement = new ThenStatement();
    statement.location = tstream.peek.location;
    statement.statement = parseScopeStatement(tstream);
    return statement;
}

ElseStatement parseElseStatement(TokenStream tstream)
{
    auto statement = new ElseStatement();
    statement.location = tstream.peek.location;
    statement.statement = parseScopeStatement(tstream);
    return statement;
}


WhileStatement parseWhileStatement(TokenStream tstream)
{
    auto statement = new WhileStatement();
    statement.location = tstream.peek.location;
    match(tstream, TokenType.While);
    match(tstream, TokenType.OpenParen);
    statement.expression = parseExpression(tstream);
    match(tstream, TokenType.CloseParen);
    statement.statement = parseScopeStatement(tstream);
    return statement;
}


DoStatement parseDoStatement(TokenStream tstream)
{
    auto statement = new DoStatement();
    statement.location = tstream.peek.location;
    match(tstream, TokenType.Do);
    statement.statement = parseScopeStatement(tstream);
    match(tstream, TokenType.While);
    match(tstream, TokenType.OpenParen);
    statement.expression = parseExpression(tstream);
    match(tstream, TokenType.CloseParen);
    match(tstream, TokenType.Semicolon);
    return statement;
}


ReturnStatement parseReturnStatement(TokenStream tstream)
{
    auto statement = new ReturnStatement();
    statement.location = tstream.peek.location;
    match(tstream, TokenType.Return);
    if (tstream.peek.type != TokenType.Semicolon) {
        statement.expression = parseExpression(tstream);
    }
    match(tstream, TokenType.Semicolon);
    return statement;
}

DeclarationStatement parseDeclarationStatement(TokenStream tstream)
{
    auto statement = new DeclarationStatement();
    statement.location = tstream.peek.location;
    statement.declaration = parseDeclaration(tstream);
    return statement;
}

ExpressionStatement parseExpressionStatement(TokenStream tstream)
{
    auto statement = new ExpressionStatement();
    statement.location = tstream.peek.location;
    statement.expression = parseExpression(tstream);
    if(tstream.peek.type != TokenType.Semicolon) {
        throw new MissingSemicolonError(tstream.lookbehind(1).location, "expression");
    }
    tstream.getToken();
    return statement;
}
