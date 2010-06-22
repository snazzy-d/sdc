/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.semantic;

import std.range;

import sdc.ast.all;
public import sdc.gen.sdcscope;


/**
 * Stores and gives access to semantic information for a module.
 */
final class Semantic
{
    Scope globalScope;
    Scope[] nestedScopes;
    
    this()
    {
        globalScope = new Scope();
    }
    
    void pushScope()
    {
        nestedScopes ~= new Scope();
    }
    
    void popScope()
    in { assert(nestedScopes.length >= 1); }
    body
    {
        nestedScopes = nestedScopes[0 .. $ - 1];
    }
    
    Decl findDeclaration(string identifier)
    {
        foreach (nestedScope; retro(nestedScopes)) {
            if (nestedScope.lookupDeclaration(identifier) !is null) {
                return nestedScope.lookupDeclaration(identifier);
            }
        }
        return globalScope.lookupDeclaration(identifier);
    }
    
    void addDeclaration(string identifier, Decl declaration)
    {
        if (nestedScopes.length >= 1) {
            nestedScopes[$ - 1].addDeclaration(identifier, declaration);
        }
        return globalScope.addDeclaration(identifier, declaration);
    }
}
