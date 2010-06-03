/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdl.d for more details.
 */
module sdc.ast.base;

import std.string;

import sdc.compilererror;
import sdc.tokenstream;


void match(TokenStream tstream, TokenType type)
{
    if (tstream.peek.type != type) {
        error(tstream.peek.location, 
              format("expected '%s', got '%s'", 
                     tokenToString[type], 
                     tokenToString[tstream.peek.type])
             );
    }
    tstream.getToken();
}

class Node
{
}

// ident(.ident)*
class QualifiedName : Node
{
    Identifier[] identifiers;
    
    this(TokenStream tstream)
    {
        auto ident = new Identifier(tstream);
        while (true) {
            identifiers ~= ident;
            if (tstream.peek.type == TokenType.Dot) {
                match(tstream, TokenType.Dot);
                ident = new Identifier(tstream);
            } else {
                break;
            }
        }
    }
    
    this(TokenStream tstream, string ident)
    {
        auto identifier = new Identifier(tstream, ident);
        identifiers ~= identifier;
    }
}

class Identifier : Node
{
    Token token;
    
    this(TokenStream tstream)
    {
        token = tstream.peek;
        match(tstream, TokenType.Identifier);
    }
    
    this(TokenStream tstream, string ident)
    {
        token = new Token();
        token.location = tstream.peek.location;
        token.type = TokenType.Identifier;
        token.value = ident;
    }
}
