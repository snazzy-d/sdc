/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdl.d for more details.
 * 
 * parse.d: translate a TokenStream into a parse tree.
 */ 
module sdc.parser.base;

import std.string;
import std.path;

import sdc.compilererror;
import sdc.tokenstream;
import sdc.ast.all;
import sdc.parser.all;


Module parse(TokenStream tstream)
{
    return parseModule(tstream);
}

void match(TokenStream tstream, TokenType type)
{
    if (tstream.peek.type != type) {
        error(tstream.peek.location, format("expected '%s', got '%s'",
                                            tokenToString[type],
                                            tstream.peek.value));
    }
    tstream.getToken();
}

Module parseModule(TokenStream tstream)
{
    auto mod = new Module();
    mod.location = tstream.peek.location;
    match(tstream, TokenType.Begin);
    parseDeclaration(tstream);
    //mod.moduleDeclaration = parseModuleDeclaration(tstream);
    return mod;
}                                        

ModuleDeclaration parseModuleDeclaration(TokenStream tstream)
{
    auto modDec = new ModuleDeclaration();
    if (tstream.peek.type == TokenType.Module) {
        // Explicit module declaration.
        modDec.location = tstream.peek.location;
        match(tstream, TokenType.Module);
        modDec.name = parseQualifiedName(tstream);
        match(tstream, TokenType.Semicolon);
    } else {
        // Implicit module declaration.
        modDec.name = new QualifiedName();
        auto ident = new Identifier();
        ident.value = basename(tstream.filename, "." ~ getExt(tstream.filename));
        modDec.name.identifiers ~= ident;
    }
    return modDec;
}

QualifiedName parseQualifiedName(TokenStream tstream)
{
    auto name = new QualifiedName();
    name.location = tstream.peek.location;
    while (true) {
        name.identifiers ~= parseIdentifier(tstream);
        if (tstream.peek.type == TokenType.Dot) {
            match(tstream, TokenType.Dot);
        } else {
            break;
        }
    }
    return name;
}

Identifier parseIdentifier(TokenStream tstream)
{
    auto ident = new Identifier();
    ident.value = tstream.peek.value;
    ident.location = tstream.peek.location;
    match(tstream, TokenType.Identifier);
    return ident;
}

IntegerLiteral parseIntegerLiteral(TokenStream tstream)
{
    auto integerLiteral = new IntegerLiteral();
    integerLiteral.value = tstream.peek.value;
    integerLiteral.location = tstream.peek.location;
    match(tstream, TokenType.IntegerLiteral);
    return integerLiteral;
}
