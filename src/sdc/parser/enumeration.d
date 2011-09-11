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
import sdc.parser.expression;

EnumDeclaration parseEnumDeclaration(TokenStream tstream)
{
    auto enumToken = match(tstream, TokenType.Enum);
    auto decl = new EnumDeclaration();
    
    if (tstream.lookahead(0).type == TokenType.Identifier &&
       (tstream.lookahead(1).type == TokenType.OpenBrace ||
        tstream.lookahead(1).type == TokenType.Colon)) {
        decl.name = parseIdentifier(tstream);
        
        if (tstream.peek.type == TokenType.Colon) {
            tstream.get();
            decl.base = parseType(tstream);
        }
        
        decl.memberList = parseEnumMembers(tstream);
        decl.location = (decl.base? decl.base : decl.name).location - enumToken.location;
    } else if (tstream.peek.type == TokenType.OpenBrace ||
               tstream.peek.type == TokenType.Colon) {
               
        if (tstream.peek.type == TokenType.Colon) {
            tstream.get();
            decl.base = parseType(tstream);
        }
        
        decl.memberList = parseEnumMembers(tstream);
        decl.location = decl.base? decl.base.location - enumToken.location : enumToken.location;
    } else {
        decl.memberList = new EnumMemberList;
        auto member = parseEnumMember(tstream, true);
        decl.memberList.location = member.location;

        if (member.initialiser is null) {
            throw new CompilerError(member.location, "manifest constant declaration must have initialiser.");
        }
        
        if (tstream.peek.type != TokenType.Semicolon) {
            throw new MissingSemicolonError(member.initialiser.location, "manifest constant declaration");
        }
        tstream.get();
        
        decl.memberList.members ~= member;
    }
    return decl;
}

private:
EnumMemberList parseEnumMembers(TokenStream tstream)
{
    auto list = new EnumMemberList;
    auto openBrace = match(tstream, TokenType.OpenBrace);
    
    while (tstream.peek.type != TokenType.CloseBrace) {
        list.members ~= parseEnumMember(tstream);
        
        if (tstream.peek.type == TokenType.Comma) {
            tstream.get();
        }
    }
    
    auto closeBrace = match(tstream, TokenType.CloseBrace);
    list.location = closeBrace.location - openBrace.location;
    return list;
}

EnumMember parseEnumMember(TokenStream tstream, bool manifestConstant = false)
{
    auto member = new EnumMember;
    
    if (tstream.lookahead(1).type != TokenType.Comma &&
        tstream.lookahead(1).type != TokenType.Assign &&
        tstream.lookahead(1).type != TokenType.CloseBrace) {
        member.type = parseType(tstream);
        
        if (!manifestConstant) {
            throw new CompilerError(member.type.location, "explicit type is only allowed for manifest constants.");
        }
    }
     
    member.location = tstream.peek.location;
    member.name = parseIdentifier(tstream);
    
    if (tstream.peek.type == TokenType.Assign) {
        tstream.get();
        member.initialiser = parseConditionalExpression(tstream);
        member.location = member.initialiser.location - member.location;
    }
    
    return member;
}
