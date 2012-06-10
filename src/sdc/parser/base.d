/**
 * Copyright 2010-2011 Bernard Helyer.
 * Copyright 2010 Jakob Ovrum.
 * This file is part of SDC.
 * See LICENCE or sdc.d for more details.
 */
module sdc.parser.base;

import std.string;
import std.path;
import std.conv;
import std.exception;

import sdc.util;
import sdc.compilererror;
import sdc.tokenstream;
import sdc.extract;
import sdc.ast.all;
import sdc.parser.all;


Module parse(TokenStream tstream)
{
    return parseModule(tstream);
}

Token match(TokenStream tstream, TokenType type)
{
    auto token = tstream.get();
    
    if (token.type != type) {
        throw new CompilerError(
            token.location, 
            format("expected '%s', got '%s'.",
                tokenToString[type],
                token.value)
        );
    }
    
    return token;
}

Module parseModule(TokenStream tstream)
{
    auto mod = new Module();
    mod.location = tstream.peek.location;
    match(tstream, TokenType.Begin);
    mod.moduleDeclaration = parseModuleDeclaration(tstream);

    auto name = extractQualifiedName(mod.moduleDeclaration.name);


    
    while (tstream.peek.type != TokenType.End) {
        mod.declarationDefinitions ~= parseAttributeBlock(tstream);
    }
    
    auto implicitObjectImport = new DeclarationDefinition();
    implicitObjectImport.type = DeclarationDefinitionType.ImportDeclaration;
    implicitObjectImport.node = synthesiseImport("object");
    mod.declarationDefinitions ~= implicitObjectImport;




    return mod;
}                                        

/// Parses an attribute, if there is one, then parses a regular top level block.
DeclarationDefinition[] parseAttributeBlock(TokenStream tstream)
{
    bool parsingAttribute = startsLikeAttribute(tstream);
    Attribute attribute;
    string name;
    if (parsingAttribute) {
        attribute = parseAttribute(tstream);
    
        name = to!string(attribute.type);


    }
    
    auto block = parseDeclarationBlock(tstream, parsingAttribute);
    foreach (declDef; block.declarationDefinitions) {
        if (parsingAttribute) {
            declDef.attributes ~= attribute;
            declDef.node.attributes ~= attribute;
        }
        if (declDef.type == DeclarationDefinitionType.Declaration) {
            auto asDecl = enforce(cast(Declaration) declDef.node);
            if (parsingAttribute) {
                asDecl.node.attributes ~= attribute;
            }
        }
    }
    
    if (parsingAttribute) {


    }
    
    return block.declarationDefinitions;
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
        tstream.get();
    } else {
        // Implicit module declaration.
        modDec.name = new QualifiedName();
        auto ident = new Identifier();
        ident.value = baseName(tstream.filename, extension(tstream.filename));
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
    } else if (tstream.peek.type == TokenType.Unittest) {
        decldef.type = DeclarationDefinitionType.Unittest;
        decldef.node = parseUnittest(tstream);
    } else if (tstream.peek.type == TokenType.This) {
        return parseConstructor(tstream, "this");
    } else if (tstream.peek.type == TokenType.Tilde &&
               tstream.lookahead(1).type == TokenType.This) {
        return parseDestructor(tstream, "~this");
    } else if (tstream.peek.type == TokenType.Static &&
               tstream.lookahead(1).type == TokenType.This) {
        return parseConstructor(tstream, "static this");
    } else if (tstream.peek.type == TokenType.Static &&
               tstream.lookahead(1).type == TokenType.Tilde) {
        return parseDestructor(tstream, "static ~this");
    } else if (tstream.peek.type == TokenType.Shared &&
               tstream.lookahead(1).type == TokenType.Static &&
               tstream.lookahead(2).type == TokenType.This) {
        return parseConstructor(tstream, "shared static this");
    } else if (tstream.peek.type == TokenType.Shared &&
               tstream.lookahead(1).type == TokenType.Static &&
               tstream.lookahead(2).type == TokenType.Tilde) {
        return parseDestructor(tstream, "shared static ~this");
    } else if (startsLikeConditional(tstream)) {
        decldef.type = DeclarationDefinitionType.ConditionalDeclaration;
        decldef.node = parseConditionalDeclaration(tstream);
    } else if (tstream.peek.type == TokenType.Import || (tstream.peek.type == TokenType.Static &&
                                                         tstream.lookahead(1).type == TokenType.Import)) {
        decldef.type = DeclarationDefinitionType.ImportDeclaration;
        decldef.node = parseImportDeclaration(tstream);
    } else if (tstream.peek.type == TokenType.Static &&
               tstream.lookahead(1).type == TokenType.Assert) {
        decldef.type = DeclarationDefinitionType.StaticAssert;
        decldef.node = parseStaticAssert(tstream);
    } else {
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

StaticAssert parseStaticAssert(TokenStream tstream)
{
    auto staticAssert = new StaticAssert();
    auto firstToken = match(tstream, TokenType.Static);
    match(tstream, TokenType.Assert);
    match(tstream, TokenType.OpenParen);
    staticAssert.condition = parseConditionalExpression(tstream);
    
    if (tstream.peek.type == TokenType.Comma) {
        tstream.get();
        staticAssert.message = parseConditionalExpression(tstream);
    }
    
    auto lastToken = match(tstream, TokenType.CloseParen);
    
    staticAssert.location = lastToken.location - firstToken.location;
    
    if (tstream.peek.type != TokenType.Semicolon) {
        throw new MissingSemicolonError(lastToken.location, "static assert");
    }
    tstream.get();
    return staticAssert;
}

Unittest parseUnittest(TokenStream tstream)
{
    match(tstream, TokenType.Unittest);
    auto unit = new Unittest();
    unit._body = parseFunctionBody(tstream);
    return unit;
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
