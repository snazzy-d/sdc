/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdl.d for more details.
 * 
 * parse.d: translate a TokenStream into a parse tree.
 */ 
module sdc.parse;

import std.string;

import sdc.compilererror;
import sdc.tokenstream;
import sdc.ast.base;
import sdc.ast.sdcmodule;


Module parse(TokenStream tstream)
{
    auto mod = new Module();
    parseModule(tstream, mod);
    return mod;
}

private:

void match(TokenStream tstream, TokenType type)
{
    if (tstream.peek.type != type) {
        error(tstream.peek.location, format("expected '%s', got '%s'",
                                            tokenToString[type],
                                            tokenToString[tstream.peek.type]));
    }
    tstream.getToken();
}

void parseModule(TokenStream tstream, Module mod)
{
    match(tstream, TokenType.Begin);
    mod.moduleDeclaration = new ModuleDeclaration();
    parseModuleDeclaration(tstream, mod.moduleDeclaration);
}                                        

void parseModuleDeclaration(TokenStream tstream, ModuleDeclaration modDec)
{
    if (tstream.peek.type == TokenType.Module) {
        // Explicit module declaration.
        match(tstream, TokenType.Module);
        modDec.name = new QualifiedName();
        parseQualifiedName(tstream, modDec.name);
        match(tstream, TokenType.Semicolon);
    } else {
        // Implicit module declaration.
    }
}

void parseQualifiedName(TokenStream tstream, QualifiedName name)
{
    auto ident = new Identifier();
    while (true) {
        parseIdentifier(tstream, ident);
        name.identifiers ~= ident;
        if (tstream.peek.type == TokenType.Dot) {
            match(tstream, TokenType.Dot);
            ident = new Identifier();
        } else {
            break;
        }
    }
}

void parseIdentifier(TokenStream tstream, Identifier ident)
{
    ident.token = tstream.peek;
    match(tstream, TokenType.Identifier);
}
