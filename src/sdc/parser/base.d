/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
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
    mod.moduleDeclaration = parseModuleDeclaration(tstream);
    while (tstream.peek.type != TokenType.End) {
        mod.declarationDefinitions ~= parseDeclarationDefinition(tstream);
    }
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

DeclarationDefinition parseDeclarationDefinition(TokenStream tstream)
{
    auto decldef = new DeclarationDefinition();
    decldef.location = tstream.peek.location;
    decldef.declaration = parseDeclaration(tstream);
    return decldef;
}

QualifiedName parseQualifiedName(TokenStream tstream, bool allowLeadingDot=false)
{
    auto name = new QualifiedName();
    name.location = tstream.peek.location;
    if (allowLeadingDot && tstream.peek.type == TokenType.Dot) {
        match(tstream, TokenType.Dot);
        name.leadingDot = true;
    }
    
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

T parseLiteral(T, TokenType E)(TokenStream tstream)
{
    auto literal = new T();
    literal.value = tstream.peek.value;
    literal.location = tstream.peek.location;
    match(tstream, E);
    return literal;
}

alias parseLiteral!(Identifier, TokenType.Identifier) parseIdentifier;
alias parseLiteral!(IntegerLiteral, TokenType.IntegerLiteral) parseIntegerLiteral;
alias parseLiteral!(FloatLiteral, TokenType.FloatLiteral) parseFloatLiteral;
alias parseLiteral!(StringLiteral, TokenType.StringLiteral) parseStringLiteral;
alias parseLiteral!(CharacterLiteral, TokenType.CharacterLiteral) parseCharacterLiteral;
