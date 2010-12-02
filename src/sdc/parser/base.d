/**
 * Copyright 2010 Bernard Helyer.
 * Copyright 2010 Jakob Ovrum.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
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

Token match(TokenStream tstream, TokenType type)
{
    if (tstream.peek.type != type) {
        throw new CompilerError(
            tstream.peek.location, 
            format("expected '%s', got '%s'.",
                tokenToString[type],
                tstream.peek.value)
        );
    }
    return tstream.getToken();
}

Module parseModule(TokenStream tstream)
{
    auto mod = new Module();
    mod.location = tstream.peek.location;
    mod.tstream = tstream;
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
        if(tstream.peek.type != TokenType.Semicolon) {
            throw new MissingSemicolonError(modDec.name.location, "module declaration");
        }
        tstream.getToken();
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
    
    if (tstream.peek.type == TokenType.Struct || tstream.peek.type == TokenType.Union) {
        decldef.type = DeclarationDefinitionType.AggregateDeclaration;
        decldef.node = parseAggregateDeclaration(tstream);
    } else if (tstream.peek.type == TokenType.Enum) {
        decldef.type = DeclarationDefinitionType.EnumDeclaration;
        decldef.node = parseEnumDeclaration(tstream);
    } else if (tstream.peek.type == TokenType.Template) {
        decldef.type = DeclarationDefinitionType.TemplateDeclaration;
        decldef.node = parseTemplateDeclaration(tstream);
    } else if (tstream.peek.type == TokenType.Class) {
        decldef.type = DeclarationDefinitionType.ClassDeclaration;
        decldef.node = parseClassDeclaration(tstream);
    } else if (startsLikeConditional(tstream)) {
        decldef.type = DeclarationDefinitionType.ConditionalDeclaration;
        decldef.node = parseConditionalDeclaration(tstream);
    } else if (tstream.peek.type == TokenType.Import || (tstream.peek.type == TokenType.Static &&
                                                         tstream.lookahead(1).type == TokenType.Import)) {
        decldef.type = DeclarationDefinitionType.ImportDeclaration;
        decldef.node = parseImportDeclaration(tstream);
    } else if (startsLikeAttribute(tstream)) {
        decldef.type = DeclarationDefinitionType.AttributeSpecifier;
        decldef.node = parseAttributeSpecifier(tstream);
    }  else {
        decldef.type = DeclarationDefinitionType.Declaration;
        decldef.node = parseDeclaration(tstream);
    }
    
    return decldef;
}

QualifiedName parseQualifiedName(TokenStream tstream, bool allowLeadingDot=false)
{
    auto name = new QualifiedName();
    auto startLocation = tstream.peek.location;
    
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
    name.location = name.identifiers[$ - 1].location - startLocation;
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
