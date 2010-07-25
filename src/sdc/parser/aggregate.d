/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.parser.aggregate;

import std.string;

import sdc.compilererror;
import sdc.tokenstream;
import sdc.ast.base;
import sdc.ast.aggregate;
import sdc.parser.base;
import sdc.parser.declaration;


AggregateDeclaration parseAggregateDeclaration(TokenStream tstream)
{
    auto aggregate = new AggregateDeclaration();
    aggregate.location = tstream.peek.location;
    
    if (tstream.peek.type == TokenType.Struct) {
        match(tstream, TokenType.Struct);
        aggregate.type = AggregateType.Struct;
    } else if (tstream.peek.type == TokenType.Union) {
        match(tstream, TokenType.Union);
        aggregate.type = AggregateType.Union;
    } else {
        error(aggregate.location, format("aggregate declarations must begin with 'struct' or 'union', not '%s'.", tstream.peek.value));
    }
    
    aggregate.name = parseIdentifier(tstream);
    
    if (tstream.peek.type == TokenType.Semicolon) {
        match(tstream, TokenType.Semicolon);
    } else {
        aggregate.structBody = parseStructBody(tstream);
    }
    
    return aggregate;
}

StructBody parseStructBody(TokenStream tstream)
{
    auto structBody = new StructBody();
    structBody.location = tstream.peek.location;
    
    match(tstream, TokenType.OpenBrace);
    while (tstream.peek.type != TokenType.CloseBrace) {
        structBody.declarations ~= parseStructBodyDeclaration(tstream);
    }
    match(tstream, TokenType.CloseBrace);
    
    return structBody;
}

StructBodyDeclaration parseStructBodyDeclaration(TokenStream tstream)
{
    auto decl = new StructBodyDeclaration();
    decl.location = tstream.peek.location;
    
    switch (tstream.peek.type) {
    case TokenType.Static:
        break;
    case TokenType.Invariant:
        break;
    case TokenType.Unittest:
        break;
    case TokenType.This:
        break;
    case TokenType.Alias:
        break;
    default:
        decl.type = StructBodyDeclarationType.Declaration;
        decl.node = parseDeclaration(tstream);
        break;
    }
    
    return decl;
}
