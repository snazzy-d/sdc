/**
 * Copyright 2010-2011 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.parser.sdcclass;

import sdc.compilererror;
import sdc.tokenstream;
import sdc.ast.sdcclass;
import sdc.parser.base;


ClassDeclaration parseClassDeclaration(TokenStream tstream)
{
    auto decl = new ClassDeclaration();
    decl.location = tstream.peek.location;
    
    match(tstream, TokenType.Class);
    decl.identifier = parseIdentifier(tstream);
    if (tstream.peek.type == TokenType.Colon) {
        decl.baseClassList = parseBaseClassList(tstream);
    }
    decl.classBody = parseClassBody(tstream);
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

ClassBody parseClassBody(TokenStream tstream)
{
    auto cbody = new ClassBody();
    cbody.location = tstream.peek.location;
    
    match(tstream, TokenType.OpenBrace);
    while (tstream.peek.type != TokenType.CloseBrace) {
        cbody.classBodyDeclarations ~= parseClassBodyDeclaration(tstream);
    }
    match(tstream, TokenType.CloseBrace);
    return cbody;
}

ClassBodyDeclaration parseClassBodyDeclaration(TokenStream tstream)
{
    auto decl = new ClassBodyDeclaration();
    decl.location = tstream.peek.location;
    
    decl.node = parseDeclarationDefinition(tstream);
    return decl;
}
