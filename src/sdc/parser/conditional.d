/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.parser.conditional;

import sdc.compilererror;
import sdc.tokenstream;
import sdc.ast.conditional;
import sdc.ast.sdcmodule;
import sdc.parser.base;
import sdc.parser.expression;


ConditionalDeclaration parseConditionalDeclaration(TokenStream tstream)
{
    auto decl = new ConditionalDeclaration();
    decl.location = tstream.peek.location;
    
    decl.condition = parseCondition(tstream);
    if (tstream.peek.type == TokenType.Colon) {
        match(tstream, TokenType.Colon);
        decl.type = ConditionDeclarationType.AlwaysOn;
        return decl;
    }
    decl.thenBlock = parseDeclarationDefinitionBlock(tstream);
    if (tstream.peek.type == TokenType.Else) {
        match(tstream, TokenType.Else);
        decl.elseBlock = parseDeclarationDefinitionBlock(tstream);
    }
    return decl;
}

DeclarationDefinition[] parseDeclarationDefinitionBlock(TokenStream tstream)
{
    DeclarationDefinition[] block;
    if (tstream.peek.type == TokenType.OpenBrace) {
        match(tstream, TokenType.OpenBrace);
        while (tstream.peek.type != TokenType.CloseBrace) {
            block ~= parseDeclarationDefinition(tstream);
        }
        match(tstream, TokenType.CloseBrace);
    } else {
        block ~= parseDeclarationDefinition(tstream);
    }
    return block;
}

ConditionalStatement parseConditionalStatement(TokenStream tstream)
{
    auto statement = new ConditionalStatement();
    statement.location = tstream.peek.location;
    
    return statement;
}

Condition parseCondition(TokenStream tstream)
{
    auto condition = new Condition();
    condition.location = tstream.peek.location;
    
    switch (tstream.peek.type) {
    case TokenType.Version:
        condition.conditionType = ConditionType.Version;
        condition.condition = parseVersionCondition(tstream);
    case TokenType.Debug:
        condition.conditionType = ConditionType.Debug;
        condition.condition = parseDebugCondition(tstream);
    case TokenType.Static:
        condition.conditionType = ConditionType.StaticIf;
        condition.condition = parseStaticIfCondition(tstream);
    default:
        error(tstream.peek.location, "expected 'version', 'debug', or 'static' for compile time conditional.");
    }
    return condition;
}

VersionCondition parseVersionCondition(TokenStream tstream)
{
    auto condition = new VersionCondition();
    condition.location = tstream.peek.location;
    
    match(tstream, TokenType.Version);
    match(tstream, TokenType.OpenParen);
    switch (tstream.peek.type) {
    case TokenType.IntegerLiteral:
        condition.type = VersionConditionType.Integer;
        condition.integer = parseIntegerLiteral(tstream);
        break;
    case TokenType.Identifier:
        condition.type = VersionConditionType.Identifier;
        condition.identifier = parseIdentifier(tstream);
        break;
    case TokenType.Unittest:
        condition.type = VersionConditionType.Unittest;
        break;
    default:
        error(tstream.peek.location, "version conditions should be either an integer, an identifier, or 'unittest'.");
    }
    match(tstream, TokenType.CloseParen);
    return condition;
}

DebugCondition parseDebugCondition(TokenStream tstream)
{
    auto condition = new DebugCondition();
    condition.location = tstream.peek.location;
    
    match(tstream, TokenType.Debug);
    if (tstream.peek.type != TokenType.OpenParen) {
        return condition;
    }
    match(tstream, TokenType.OpenParen);
    switch (tstream.peek.type) {
    case TokenType.IntegerLiteral:
        condition.type = DebugConditionType.Integer;
        condition.integer = parseIntegerLiteral(tstream);
        break;
    case TokenType.Identifier:
        condition.type = DebugConditionType.Identifier;
        condition.identifier = parseIdentifier(tstream);
        break;
    default:
        error(tstream.peek.location, "expected identifier or integer literal as debug condition.");
    }
    match(tstream, TokenType.CloseParen);
    return condition;
}

StaticIfCondition parseStaticIfCondition(TokenStream tstream)
{
    auto condition = new StaticIfCondition();
    condition.location = tstream.peek.location;
    
    condition.expression = parseAssignExpression(tstream);
    return condition;
}
 
