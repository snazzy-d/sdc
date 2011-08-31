/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.parser.sdcimport;

import std.string;

import sdc.compilererror;
import sdc.tokenstream;
import sdc.ast.sdcimport;
import sdc.parser.base;


ImportDeclaration parseImportDeclaration(TokenStream tstream)
{
    auto decl = new ImportDeclaration();
    decl.location = tstream.peek.location;
    
    if (tstream.peek.type == TokenType.Static) {
        match(tstream, TokenType.Static);
        decl.isStatic = true;
    }
    match(tstream, TokenType.Import);
    if (tstream.peek.type == TokenType.OpenParen) {
        match(tstream, TokenType.OpenParen);
        auto ident = match(tstream, TokenType.Identifier);
        switch (ident.value) {
        case "Java":
            decl.language = Language.Java;
            break;
        default:
            throw new CompilerError(ident.location, format("expected 'Java', not '%s'.", ident.value)); 
        }
        match(tstream, TokenType.CloseParen);
        do {
            decl.languageImports ~= parseStringLiteral(tstream);
            if (tstream.peek.type == TokenType.Comma) {
                tstream.get();
                continue;
            }
            break;
        } while (true);
    } else {
        decl.importList = parseImportList(tstream);
    }
    match(tstream, TokenType.Semicolon);
    return decl;
}

ImportList parseImportList(TokenStream tstream)
{
    auto list = new ImportList();
    list.location = tstream.peek.location;
    
    size_t l = 0;
    while (true) {
        l++;
        if (tstream.lookahead(l).type == TokenType.Identifier || tstream.lookahead(l).type == TokenType.Dot || tstream.lookahead(l).type == TokenType.Assign) {
            continue;
        } else if (tstream.lookahead(l).type == TokenType.Comma) {
            list.type = ImportListType.Multiple;
            break;
        } else if (tstream.lookahead(l).type == TokenType.Colon) {
            list.type = ImportListType.SingleBinder;
            break;
        } else if (tstream.lookahead(l).type == TokenType.Semicolon) {
            list.type = ImportListType.SingleSimple;
            break;
        } else {
            throw new CompilerError(tstream.lookahead(l).location, format("unknown token in import list: '%s'.", tstream.lookahead(l).value));
        }
    }
    
    final switch (list.type) {
    case ImportListType.SingleSimple:
        list.imports ~= parseImport(tstream);
        break;
    case ImportListType.SingleBinder:
        list.binder = parseImportBinder(tstream);
        if (tstream.peek.type != TokenType.Semicolon) {
            throw new CompilerError(tstream.peek.location, "only the final import in an import list may have a bind list.");
        }
        break;
    case ImportListType.Multiple:
        l = 0;
        while (true) {
            l++;
            if (tstream.lookahead(l).type == TokenType.Identifier || tstream.lookahead(l).type == TokenType.Dot || tstream.lookahead(l).type == TokenType.Assign) {
                continue;
            } else if (tstream.lookahead(l).type == TokenType.Comma) {
                list.imports ~= parseImport(tstream);
                match(tstream, TokenType.Comma);
                l = 0;
                continue;
            } else if (tstream.lookahead(l).type == TokenType.Colon) {
                list.binder = parseImportBinder(tstream);
                if (tstream.peek.type != TokenType.Semicolon) {
                    throw new CompilerError(tstream.peek.location, "only the final import in an import list may have a bind list.");
                }
                break;
            } else if (tstream.lookahead(l).type == TokenType.Semicolon) {
                list.imports ~= parseImport(tstream);
                break;
            } else {
                throw new CompilerError(tstream.lookahead(l).location, format("unknown token in import list: '%s'.", tstream.lookahead(l).value));
            }
        }
        break;
    }
    
    return list;
}

ImportBinder parseImportBinder(TokenStream tstream)
{
    auto binder = new ImportBinder();
    binder.location = tstream.peek.location;
    
    binder.theImport = parseImport(tstream);
    if (tstream.peek.type == TokenType.Colon) {
        match(tstream, TokenType.Colon);
        binder.binds ~= parseImportBind(tstream);
        while (tstream.peek.type == TokenType.Comma) {
            match(tstream, TokenType.Comma);
            binder.binds ~= parseImportBind(tstream);
        }
    }
    return binder;
}

ImportBind parseImportBind(TokenStream tstream)
{
    auto bind = new ImportBind();
    bind.location = tstream.peek.location;
    
    auto name = parseIdentifier(tstream);
    if (tstream.peek.type == TokenType.Assign) {
        match(tstream, TokenType.Assign);
        bind.aliasName = name;
        bind.name = parseIdentifier(tstream);
    } else {
        bind.name = name;
    }
    return bind;
}

Import parseImport(TokenStream tstream)
{
    auto theImport = new Import();
    theImport.location = tstream.peek.location;
    
    if (tstream.lookahead(1).type == TokenType.Assign) {
        theImport.moduleAlias = parseIdentifier(tstream);
        match(tstream, TokenType.Assign);
    }
    theImport.moduleName = parseQualifiedName(tstream);
    return theImport;
}

