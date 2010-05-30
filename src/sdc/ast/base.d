/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdl.d for more details.
 */ 
module sdc.ast.base;

import std.stdio;

import libdjson.json;

import sdc.tokenstream;



class Node
{
    void parse(TokenStream tstream)
    {
    }
    
    void prettyPrint(JSONObject root)
    {
        root["Node"] = new JSONObject();
    }
}


class IdentifierNode : Node
{
    Token token;
    
    override void parse(TokenStream tstream)
    {
        token = tstream.match(TokenType.Identifier);
    }
    
    override void prettyPrint(JSONObject root)
    {
        root["Identifier"] = new JSONString(token.value);
    }
}
