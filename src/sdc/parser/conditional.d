/**
 * Copyright 2010 SDC Authors. See AUTHORS for more details.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.parser.conditional;

import sdc.compilererror;
import sdc.tokenstream;
import sdc.util;
import sdc.ast.base;
import sdc.ast.conditional;
import sdc.ast.sdcmodule;
import sdc.parser.base;
import sdc.parser.expression;
import sdc.parser.statement;
import sdc.parser.attribute;


ConditionalDeclaration parseConditionalDeclaration(TokenStream tstream)
{
    auto decl = new ConditionalDeclaration();
    decl.location = tstream.peek.location;
    
    // parse version = foo, or debug = foo
    if ((tstream.peek.type == TokenType.Version || tstream.peek.type == TokenType.Debug) 
        && tstream.lookahead(1).type == TokenType.Assign) {
        if (tstream.peek.type == TokenType.Version) {
            match(tstream, TokenType.Version);
            decl.type = ConditionalDeclarationType.VersionSpecification;
        } else if (tstream.peek.type == TokenType.Debug) {
            match(tstream, TokenType.Debug);
            decl.type = ConditionalDeclarationType.DebugSpecification;
        } else assert(false);
        match(tstream, TokenType.Assign);
        
        auto payload = parseIdentifier(tstream);
        if (decl.type == ConditionalDeclarationType.VersionSpecification) {
            auto spec = new VersionSpecification();
            spec.location = decl.location;
            spec.node = payload;
            decl.specification = spec;
        } else {
            auto spec = new DebugSpecification();
            spec.location = decl.location;
            spec.node = payload;
            decl.specification = spec;
        }
        match(tstream, TokenType.Semicolon);
        return decl;
    }
    
    
    decl.condition = parseCondition(tstream);
    decl.thenBlock = parseDeclarationBlock(tstream);
    if (tstream.peek.type == TokenType.Else) {
        match(tstream, TokenType.Else);
        decl.elseBlock = parseDeclarationBlock(tstream);
    }
    
    return decl;
}

ConditionalStatement parseConditionalStatement(TokenStream tstream)
{
    auto statement = new ConditionalStatement();
    statement.location = tstream.peek.location;
    
    statement.condition = parseCondition(tstream);
    statement.thenStatement = parseNoScopeNonEmptyStatement(tstream);
    if (tstream.peek.type == TokenType.Else) {
        match(tstream, TokenType.Else);
        statement.elseStatement = parseNoScopeNonEmptyStatement(tstream);
    }
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
        break;
    case TokenType.Debug:
        condition.conditionType = ConditionType.Debug;
        condition.condition = parseDebugCondition(tstream);
        break;
    case TokenType.Static:
        condition.conditionType = ConditionType.StaticIf;
        condition.condition = parseStaticIfCondition(tstream);
        break;
    default:
        throw new CompilerError(tstream.peek.location, "expected 'version', 'debug', or 'static' for compile time conditional.");
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
        throw new CompilerError(tstream.peek.location, "integer versions are unsupported.");
    case TokenType.Identifier:
        condition.type = VersionConditionType.Identifier;
        condition.identifier = parseIdentifier(tstream);
        break;
    case TokenType.Unittest:
        condition.type = VersionConditionType.Unittest;
        match(tstream, TokenType.Unittest);
        break;
    default:
        throw new CompilerError(tstream.peek.location, "version conditions should be either an integer, an identifier, or 'unittest'.");
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
        throw new CompilerError(tstream.peek.location, "integer debug levels are unsupported.");
    case TokenType.Identifier:
        condition.type = DebugConditionType.Identifier;
        condition.identifier = parseIdentifier(tstream);
        break;
    default:
        throw new CompilerError(tstream.peek.location, "expected identifier as debug condition.");
    }
    match(tstream, TokenType.CloseParen);
    return condition;
}

StaticIfCondition parseStaticIfCondition(TokenStream tstream)
{
    auto condition = new StaticIfCondition();
    condition.location = tstream.peek.location;
    
    match(tstream, TokenType.Static);
    match(tstream, TokenType.If);
    match(tstream, TokenType.OpenParen);
    condition.expression = parseAssignExpression(tstream);
    match(tstream, TokenType.CloseParen);
    return condition;
}
 
bool startsLikeConditional(TokenStream tstream)
{
    if (tstream.peek.type == TokenType.Version || tstream.peek.type == TokenType.Debug) {
        return true;
    }
    if (tstream.peek.type != TokenType.Static) {
        return false;
    }
    return tstream.lookahead(1).type == TokenType.If;
}
