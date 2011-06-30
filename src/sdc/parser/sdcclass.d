/**
 * Copyright 2010-2011 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.parser.sdcclass;

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
    auto decldef = new DeclarationDefinition();
    decldef.location = tstream.peek.location;
    decldef.type = DeclarationDefinitionType.Declaration;
    auto decl = new Declaration();
    decl.location = tstream.peek.location;
    decl.type = DeclarationType.Function;
    auto fdecl = new FunctionDeclaration();
    fdecl.location = tstream.peek.location;
    fdecl.retval = new Type();
    fdecl.retval.type = TypeType.UserDefined;
    auto udefinedType = new UserDefinedType();
    udefinedType.location = tstream.peek.location;
    udefinedType.segments ~= new IdentifierOrTemplateInstance();
    auto ident = new Identifier();
    ident.location = tstream.peek.location;
    ident.value = name;
    udefinedType.segments[0].location = tstream.peek.location;
    udefinedType.segments[0].isIdentifier = true;
    udefinedType.segments[0].node = ident;
    fdecl.retval.node = udefinedType;
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
