/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdl.d for more details.
 */ 
module sdc.ast.sdcmodule;

import std.stdio;
import std.path;

import libdjson.json;

import sdc.tokenstream;
import sdc.ast.base;



class ModuleNode : Node
{
    ModuleDeclarationNode moduleDeclaration;
    DeclarationDefinitionNode[] declarationDefinitions;
    
    override void parse(TokenStream tstream)
    {
        moduleDeclaration = new ModuleDeclarationNode();
        moduleDeclaration.parse(tstream);
        
        while (tstream.peek !is EOFToken) {
            switch (tstream.peek.type) {
            case TokenType.Import:
                auto importDecl = new ImportDeclarationNode();
                importDecl.parse(tstream);
                declarationDefinitions ~= importDecl;
                break;
            default:
                tstream.getToken();
                break;   // TMP swallow unknown
            }
        }
    }
    
    override void prettyPrint(JSONObject root)
    {
        auto localRoot = new JSONObject();
        moduleDeclaration.prettyPrint(localRoot);
        
        foreach (decldef; declarationDefinitions) {
            decldef.prettyPrint(localRoot);
        }
        
        root["Module"] = localRoot;
    }
}


class ModuleDeclarationNode : Node
{
    IdentifierNode[] packages;
    IdentifierNode name;
    
    override void parse(TokenStream tstream)
    {
        if (tstream.peek.type == TokenType.Module) {
            manualParse(tstream);
        } else {
            automaticParse(tstream);
        }
    }
    
    override void prettyPrint(JSONObject root)
    {
        auto localRoot = new JSONObject();
        auto modPackages = new JSONArray();
        foreach (modPackage; packages) {
            auto packageObj = new JSONObject();
            modPackage.prettyPrint(packageObj);
            modPackages ~= packageObj;
        }
        auto modName = new JSONObject();
        name.prettyPrint(modName);
        
        localRoot["packages"] = modPackages;
        localRoot["name"] = modName;
        root["ModuleDeclaration"] = localRoot;
    }
    
    protected void manualParse(TokenStream tstream)
    {
        tstream.match(TokenType.Module);
        auto ident = new IdentifierNode();
        ident.parse(tstream);
        while (tstream.peek.type == TokenType.Dot) {
            tstream.match(TokenType.Dot);
            packages ~= ident;
            ident = new IdentifierNode();
            ident.parse(tstream);
        }
        tstream.match(TokenType.Semicolon);
        name = ident;
    }
    
    protected void automaticParse(TokenStream tstream)
    {
        auto nameToken = new Token();
        nameToken.type = TokenType.Identifier;
        nameToken.value = tstream.filename;
        nameToken.value = std.path.basename(tstream.filename, "." ~ std.path.getExt(tstream.filename));
        nameToken.lineNumber = tstream.peek.lineNumber;
        name = new IdentifierNode();
        name.token = nameToken;
    }
}


abstract class DeclarationDefinitionNode : Node
{
}


class ImportDeclarationNode : DeclarationDefinitionNode
{
    ImportNode[] imports;
    
    override void parse(TokenStream tstream)
    {
        tstream.match(TokenType.Import);
        while (tstream.peek.type == TokenType.Identifier) {
            auto impnode = new ImportNode();
            impnode.parse(tstream);
            imports ~= impnode;
        }
        tstream.match(TokenType.Semicolon);
    }
    
    override void prettyPrint(JSONObject root)
    {
        auto localRoot = new JSONObject();
        auto _imports = new JSONArray();
        foreach (_import; imports) {
            auto importNode = new JSONObject();
            _import.prettyPrint(importNode);
            _imports ~= importNode;
        }
        
        localRoot["imports"] = _imports;
        root["ImportDeclaration"] = localRoot;
    }
}


class ImportNode : Node
{
    IdentifierNode[] fullyQualifiedIdentifier;
    IdentifierNode aliasIdentifier;  // OPTIONAL
    ImportBindNode[] importBinds;    // OPTIONAL
    
    override void parse(TokenStream tstream)
    {
        auto ident = new IdentifierNode();
        void parseFullyQualifiedIdentifier()
        {
            while (tstream.peek.type == TokenType.Dot) {
                tstream.match(TokenType.Dot);
                fullyQualifiedIdentifier ~= ident;
                ident = new IdentifierNode();
                ident.parse(tstream);
            }
            fullyQualifiedIdentifier ~= ident;
        }
        
        ident.parse(tstream);
        if (tstream.peek.type == TokenType.Dot) {
            parseFullyQualifiedIdentifier();
        } else if (tstream.peek.type == TokenType.Assign) {
            aliasIdentifier = ident;
            ident = new IdentifierNode();
            ident.parse(tstream);
            parseFullyQualifiedIdentifier();
        }
        
        switch (tstream.peek.type) {
        case TokenType.Colon:
            tstream.match(TokenType.Colon);
            auto bind = new ImportBindNode();
            bind.parse(tstream);
            importBinds ~= bind;
            while (tstream.peek.type == TokenType.Comma) {
                tstream.match(TokenType.Comma);
                bind = new ImportBindNode();
                bind.parse(tstream);
                importBinds ~= bind;
            }
            break;
        case TokenType.Semicolon:  // Fall through.
        case TokenType.Comma:
            break;
        default:
            tstream.error("unexpected token");
        }
    }
    
    override void prettyPrint(JSONObject root)
    {
        auto localRoot = new JSONObject();
        auto fullyQualified = new JSONArray();
        
        localRoot["FullyQualifiedImportName"] = fullyQualified;
        root["Import"] = localRoot;
    }
}


class ImportBindNode : Node
{
    IdentifierNode aliasName;  // OPTIONAL
    IdentifierNode realName;
    
    override void parse(TokenStream tstream)
    {
        auto ident = new IdentifierNode();
        ident.parse(tstream);
        if (tstream.peek.type == TokenType.Assign) {
            aliasName = ident;
            tstream.match(TokenType.Assign);
            realName = new IdentifierNode();
            realName.parse(tstream);
        } else {
            realName = ident;
        }
    }
}
