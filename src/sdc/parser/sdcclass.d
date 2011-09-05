/**
 * Copyright 2010-2011 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.parser.sdcclass;


import std.string;

import sdc.compilererror;
import sdc.tokenstream;
import sdc.extract;
import sdc.ast.base;
import sdc.ast.sdcclass;
import sdc.ast.declaration;
import sdc.ast.sdcmodule;
import sdc.parser.base;
import sdc.parser.declaration;


ClassDeclaration parseClassDeclaration(TokenStream tstream)
{
    auto decl = new ClassDeclaration();
    decl.location = tstream.peek.location;
    
    match(tstream, TokenType.Class);
    decl.identifier = parseIdentifier(tstream);
    if (tstream.peek.type == TokenType.Colon) {
        decl.baseClassList = parseBaseClassList(tstream);
    }
    decl.classBody = parseClassBody(tstream, extractIdentifier(decl.identifier));
    return decl;
}

BaseClassList parseBaseClassList(TokenStream tstream)
{
    auto list = new BaseClassList();
    list.location = tstream.peek.location;
    
    match(tstream, TokenType.Colon);
    list.superClass = parseQualifiedName(tstream);
    while (tstream.peek.type == TokenType.Comma) {
        match(tstream, TokenType.Comma);
        list.interfaceClasses ~= parseQualifiedName(tstream);
    }
    return list;
}

ClassBody parseClassBody(TokenStream tstream, string name)
{
    auto cbody = new ClassBody();
    cbody.location = tstream.peek.location;
    
    match(tstream, TokenType.OpenBrace);
    while (tstream.peek.type != TokenType.CloseBrace) {
        cbody.declarations ~= parseDeclarationDefinition(tstream);
    }
    match(tstream, TokenType.CloseBrace);
    return cbody;
}

DeclarationDefinition parseConstructor(TokenStream tstream, string name)
{
    // All this shit is synthesising a function declaration.
    DeclarationDefinitionType type;
    auto firstToken = tstream.peek;

    // Handle static and shared static.
    switch (tstream.peek.type) {
    case TokenType.Shared:
        match(tstream, TokenType.Shared);
        match(tstream, TokenType.Static);
        type = DeclarationDefinitionType.SharedStaticConstructor;
        break;
    case TokenType.Static:
        match(tstream, TokenType.Static);
        type = DeclarationDefinitionType.StaticConstructor;
        break;
    case TokenType.This:
        type = DeclarationDefinitionType.Constructor;
        break;
    default:
        auto str = format("Expected 'this', 'static this' or 'shared static "
                          "this', got '%s'", firstToken.value);
        throw new CompilerError(firstToken.location, str);
    }
    
    // Common for all constructors.
    auto decldef = new DeclarationDefinition();
    decldef.location = tstream.peek.location - firstToken.location;
    decldef.type = DeclarationDefinitionType.Constructor;
    
    auto decl = new Declaration();
    decl.location = tstream.peek.location - firstToken.location;
    decl.type = DeclarationType.Function;
    
    auto fdecl = new FunctionDeclaration();
    fdecl.location = tstream.peek.location - firstToken.location;
    fdecl.returnType = new Type();
    fdecl.returnType.ctor = true;
    
    auto ident = new Identifier();
    fdecl.name = new QualifiedName();
    fdecl.name.location = tstream.peek.location;
    fdecl.name.identifiers ~= new Identifier();
    fdecl.name.identifiers[0].value = "__ctor";
    
    match(tstream, TokenType.This);
    fdecl.parameterList = parseParameters(tstream);
    fdecl.functionBody = parseFunctionBody(tstream);
    decl.node = fdecl;
    decldef.node = decl;
    
    return decldef;
}

DeclarationDefinition parseDestructor(TokenStream tstream, string name)
{
    // All this shit is synthesising a function declaration.
    DeclarationDefinitionType type;
    auto firstToken = tstream.peek;

    // Handle static and shared static.
    switch (tstream.peek.type) {
    case TokenType.Shared:
        tstream.get();
        match(tstream, TokenType.Static);
        match(tstream, TokenType.Tilde);
        type = DeclarationDefinitionType.SharedStaticDestructor;
        break;
    case TokenType.Static:
        tstream.get();
        match(tstream, TokenType.Tilde);
        type = DeclarationDefinitionType.StaticDestructor;
        break;
    case TokenType.Tilde:
        tstream.get();
        type = DeclarationDefinitionType.Destructor;
        break;
    default:
        auto str = format("Expected '~this', 'static ~this' or 'shared "
                          "static ~this', got '%s'", firstToken.value);
        throw new CompilerError(firstToken.location, str);
    }

    // Common for all destructors.
    auto decldef = new DeclarationDefinition();
    decldef.location = tstream.peek.location - firstToken.location;
    decldef.type = type;

    auto decl = new Declaration();
    decl.location = tstream.peek.location - firstToken.location;
    decl.type = DeclarationType.Function;

    auto fdecl = new FunctionDeclaration();
    fdecl.location = tstream.peek.location - firstToken.location;
    fdecl.returnType = new Type();
    fdecl.returnType.dtor = true;

    auto ident = new Identifier();
    fdecl.name = new QualifiedName();
    fdecl.name.location = tstream.peek.location - tstream.previous.location;
    fdecl.name.identifiers ~= new Identifier();
    fdecl.name.identifiers[0].value = "__dtor";

    match(tstream, TokenType.This);
    match(tstream, TokenType.OpenParen);
    match(tstream, TokenType.CloseParen);
    fdecl.functionBody = parseFunctionBody(tstream);
    decl.node = fdecl;
    decldef.node = decl;

    return decldef;
}
