/**
 * Copyright 2010 Jakob Ovrum.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.parser.enumeration;

import sdc.compilererror;
import sdc.tokenstream;
import sdc.ast.base;
import sdc.ast.enumeration;
import sdc.parser.base;
import sdc.parser.declaration;

EnumDeclaration parseEnumDeclaration(TokenStream tstream)
{
    auto enumToken = match(tstream, TokenType.Enum);
    auto decl = new EnumDeclaration();
    
    if (tstream.lookahead(0).type == TokenType.Identifier &&
       (tstream.lookahead(1).type == TokenType.OpenBrace ||
        tstream.lookahead(1).type == TokenType.Colon)) {
        decl.type = EnumType.Named;
        decl.name = parseIdentifier(tstream);
        
        if (tstream.peek.type == TokenType.Colon) {
            tstream.getToken();
            decl.base = parseType(tstream);
        }
        
        decl.memberList = parseEnumMembers(tstream);
        decl.location = (decl.base? decl.base : decl.name).location - enumToken.location;
    } else if (tstream.peek.type == TokenType.OpenBrace ||
               tstream.peek.type == TokenType.Colon) {
        decl.type = EnumType.Anonymous;
        
        if (tstream.peek.type == TokenType.Colon) {
            tstream.getToken();
            decl.base = parseType(tstream);
        }
        
        decl.memberList = parseEnumMembers(tstream);
        decl.location = decl.base? decl.base.location - enumToken.location : enumToken.location;
    } else {
        throw new CompilerPanic(tstream.peek.location, "manifest constants not implemented.");
    }
    return decl;
}

private:
EnumMemberList parseEnumMembers(TokenStream tstream)
{
    auto list = new EnumMemberList;
    auto openBrace = match(tstream, TokenType.OpenBrace);
    
    while (tstream.peek.type != TokenType.CloseBrace) {
        auto member = new EnumMember;
        member.name = parseIdentifier(tstream);
        list.members ~= member;
        
        if (tstream.peek.type == TokenType.Comma) {
            tstream.getToken();
        }
    }
    
    auto closeBrace = match(tstream, TokenType.CloseBrace);
    list.location = closeBrace.location - openBrace.location;
    return list;
}