/**
 * Copyright 2010-2011 Bernard Helyer.
 * This file is part of SDC.
 * See LICENCE or sdc.d for more details.
 */
module sdc.parser.attribute;

import std.string;

import sdc.util;
import sdc.compilererror;
import sdc.tokenstream;
import sdc.parser.base;
import sdc.parser.expression;
import sdc.parser.sdcpragma;
import sdc.ast.attribute;
import sdc.ast.declaration;


AttributeSpecifier parseAttributeSpecifier(TokenStream tstream)
{
    auto attributeSpecifier = new AttributeSpecifier();
    attributeSpecifier.location = tstream.peek.location;

    auto name = tstream.peek.value;


    attributeSpecifier.attribute = parseAttribute(tstream);
    attributeSpecifier.declarationBlock = parseDeclarationBlock(tstream);


    return attributeSpecifier;
}

Attribute parseAtAttribute(TokenStream tstream)
{
    auto attribute = new Attribute();
    auto atToken = match(tstream, TokenType.At);
    if (tstream.peek.type != TokenType.Identifier) {
        throw new CompilerError(tstream.peek.location, format("expected identifier, not %s.", tokenToString[tstream.peek.type]));
    }
    auto ident = tstream.get();
    switch (ident.value) {
        case "safe": attribute.type = AttributeType.atSafe; break;
        case "trusted": attribute.type = AttributeType.atTrusted; break;
        case "system": attribute.type = AttributeType.atSystem; break;
        case "disable": attribute.type = AttributeType.atDisable; break;
        case "property": attribute.type = AttributeType.atProperty; break;
        default:
            throw new CompilerError(ident.location, format("expected attribute, not @%s.", ident.value));
    }
    attribute.location = ident.location - atToken.location;
    return attribute;
}

Attribute parseFunctionAttribute(TokenStream tstream)
{
    switch(tstream.peek.type) {
        case TokenType.At:
            return parseAtAttribute(tstream);
        case TokenType.Pure, TokenType.Nothrow,
             TokenType.Const, TokenType.Immutable,
             TokenType.Inout, TokenType.Shared:
            auto attribute = new Attribute();
            auto token = tstream.get();
            
            attribute.location = token.location;
            attribute.type = cast(AttributeType)token.type;
            return attribute;
        default:
    }
    return null;
}

Attribute parseAttribute(TokenStream tstream)
{
    auto attribute = new Attribute();
    attribute.location = tstream.peek.location;
    
    Attribute parseExtern()
    {
        match(tstream, TokenType.Extern);
        if (tstream.peek.type != TokenType.OpenParen) {
            throw new CompilerPanic(tstream.peek.location, "ICE: only linkage style extern supported.");
        }
        match(tstream, TokenType.OpenParen);
        switch (tstream.peek.value) {
        case "C":
            if (tstream.lookahead(1).type == TokenType.DoublePlus) {
                match(tstream, TokenType.Identifier);
                attribute.type = AttributeType.ExternCPlusPlus;
            } else {
                attribute.type = AttributeType.ExternC;
            }
            break;
        case "D":
            attribute.type = AttributeType.ExternD;
            break;
        case "Windows":
            attribute.type = AttributeType.ExternWindows;
            break;
        case "Pascal":
            attribute.type = AttributeType.ExternPascal;
            break;
        case "System":
            attribute.type = AttributeType.ExternSystem;
            break;
        default:
            throw new CompilerError(
                tstream.peek.location, 
                "unsupported extern linkage. Supported linkages are C, C++, D, Windows, Pascal, and System."
            );
        }
        tstream.get();
        match(tstream, TokenType.CloseParen);
        
        return attribute;
    }
    
    switch (tstream.peek.type) {
    case TokenType.Deprecated: case TokenType.Private:
    case TokenType.Package: case TokenType.Protected:
    case TokenType.Public: case TokenType.Export:
    case TokenType.Static: case TokenType.Final:
    case TokenType.Override: case TokenType.Abstract:
    case TokenType.Const: case TokenType.Auto:
    case TokenType.Scope: case TokenType.__Gshared:
    case TokenType.Shared: case TokenType.Immutable:
    case TokenType.Inout: case TokenType.Pure: 
    case TokenType.Nothrow:
        // Simple keyword attribute.
        attribute.type = cast(AttributeType) tstream.peek.type;
        tstream.get();
        break;
    case TokenType.At:
        return parseAtAttribute(tstream);
    case TokenType.Align:
        attribute.type = AttributeType.Align;
        attribute.node = parseAlignAttribute(tstream);
        break;
    case TokenType.Pragma:
        attribute.type = AttributeType.Pragma;
        attribute.node = parsePragma(tstream);
        break;
    case TokenType.Extern:
        return parseExtern();
    default:
        throw new CompilerError(
            tstream.peek.location, 
            format("bad attribute '%s'.", tokenToString[tstream.peek.type])
        );
    }
    
    return attribute;
}


bool startsLikeAttribute(TokenStream tstream)
{
    if (contains(PAREN_TYPES, tstream.peek.type) && tstream.lookahead(1).type == TokenType.OpenParen) {
        return false;
    }
    
    // Do not handle non-attribute extern
    if (tstream.peek.type == TokenType.Extern &&
        tstream.lookahead(1).type != TokenType.OpenParen &&
        tstream.lookahead(1).type != TokenType.OpenBrace &&
        tstream.lookahead(1).type != TokenType.Colon) {
        return false;
    }
    
    // Do not handle non-attribute shared
    if (tstream.peek.type == TokenType.Shared &&
        tstream.lookahead(1).type != TokenType.OpenParen &&
        tstream.lookahead(1).type != TokenType.OpenBrace &&
        tstream.lookahead(1).type != TokenType.Colon) {
        return false;
    }
    
    // Do not handle static ifs, asserts, imports, constructors and destructors.
    // TODO: I have a feeling this doesn't belong here...
    if (tstream.peek.type == TokenType.Static) {
        if (tstream.lookahead(1).type == TokenType.Assert ||
            tstream.lookahead(1).type == TokenType.Import ||
            tstream.lookahead(1).type == TokenType.This ||
            tstream.lookahead(1).type == TokenType.Tilde ||
            tstream.lookahead(1).type == TokenType.If) {
            return false;
        }
    }

    // Do not handle shared static constructors and destructors.
    // TODO: I have a feeling this doesn't belong here...
    if (tstream.peek.type == TokenType.Shared &&
        tstream.lookahead(1).type == TokenType.Static) {
        if (tstream.lookahead(2).type == TokenType.This ||
            tstream.lookahead(2).type == TokenType.Tilde) {
            return false;
        }
    }

    return contains(ATTRIBUTE_KEYWORDS, tstream.peek.type) || tstream.peek.type == TokenType.At;
}


AlignAttribute parseAlignAttribute(TokenStream tstream)
{
    auto alignAttribute = new AlignAttribute();
    alignAttribute.location = tstream.peek.location;
    match(tstream, TokenType.Align);
    if (tstream.peek.type == TokenType.OpenParen) {
        match(tstream, TokenType.OpenParen);
        alignAttribute.alignment = parseIntegerLiteral(tstream);
        match(tstream, TokenType.CloseParen);
    }
    return alignAttribute;
}

DeclarationBlock parseDeclarationBlock(TokenStream tstream, bool attributeBlock = false)
{
    auto declarationBlock = new DeclarationBlock();
    declarationBlock.location = tstream.peek.location;
    
    if (tstream.peek.type == TokenType.OpenBrace) {
        match(tstream, TokenType.OpenBrace);
        while (tstream.peek.type != TokenType.CloseBrace) {
            if (attributeBlock) declarationBlock.declarationDefinitions ~= parseAttributeBlock(tstream);
            else declarationBlock.declarationDefinitions ~= parseDeclarationDefinition(tstream);
        }
        match(tstream, TokenType.CloseBrace);
    } else if (tstream.peek.type == TokenType.Colon) {
        match(tstream, TokenType.Colon);
        while (tstream.peek.type != TokenType.End && tstream.peek.type != TokenType.CloseBrace) {
            if (attributeBlock) declarationBlock.declarationDefinitions ~= parseAttributeBlock(tstream); 
            else declarationBlock.declarationDefinitions ~= parseDeclarationDefinition(tstream);
        }
    } else {
        if (attributeBlock) declarationBlock.declarationDefinitions ~= parseAttributeBlock(tstream);
        else declarationBlock.declarationDefinitions ~= parseDeclarationDefinition(tstream);
    }
    
    return declarationBlock;
}
