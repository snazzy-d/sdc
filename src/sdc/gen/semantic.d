/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.semantic;

import std.array;
import std.conv;
import std.range;

import sdc.util;
import sdc.ast.all;
public import sdc.gen.sdcscope;

/**
 * Stores and gives access to semantic information for a module.
 */
final class Semantic
{
    Scope globalScope;
    
    this()
    {
        globalScope = new Scope();
    }
    
    void pushScope()
    {
        mNestedScopes ~= new Scope();
    }
    
    void popScope()
    in { assert(mNestedScopes.length > 0); }
    body
    {
        mNestedScopes.popBack();
    }
    
    Decl findDeclaration(string identifier, bool forceGlobal = false)
    {
        if (!forceGlobal) foreach (nestedScope; retro(mNestedScopes)) {
            if (nestedScope.lookupDeclaration(identifier) !is null) {
                return nestedScope.lookupDeclaration(identifier);
            }
        }
        return globalScope.lookupDeclaration(identifier);
    }
    
    void addDeclaration(string identifier, Decl declaration, bool forceGlobal = false)
    {
        if (mNestedScopes.length > 0 && !forceGlobal) {
            return mNestedScopes.back.addDeclaration(identifier, declaration);
        }
        return globalScope.addDeclaration(identifier, declaration);
    }
    
    Scope currentScope() @property
    {
        if (mNestedScopes.length > 0) return mNestedScopes.back;
        else return globalScope;
    }
    
    int scopeDepth() @property
    {
        return mNestedScopes.length;
    }
    
    void pushAttribute(AttributeType attribute)
    {
        mAttributeStack ~= attribute;
    }
    
    void popAttribute()
    {
        mAttributeStack.popBack();
    }
    
    bool isAttributeActive(AttributeType attribute)
    {
        return contains(mAttributeStack, attribute);
    }
    
    private Scope[] mNestedScopes;
    private AttributeType[] mAttributeStack;
}
