/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.parser.aggregate;

import std.string;

import sdc.util;
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
        throw new CompilerError(
            aggregate.location, 
            format("aggregate declarations must begin with 'struct' or 'union', not '%s'.", tstream.peek.value)
        );
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
        structBody.declarations ~= parseDeclarationDefinition(tstream);
    }
    match(tstream, TokenType.CloseBrace);
    
    return structBody;
}
