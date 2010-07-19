/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.sdcscope;

import std.string;

import llvm.c.Core;

import sdc.compilererror;
import sdc.ast.base;
import sdc.ast.declaration;
import sdc.gen.extract;


class DeclarationStore
{
    this() {}
    this(Node d, LLVMValueRef v, LLVMTypeRef t, DeclarationType decltype)
    {
        declaration = d;
        value = v;
        type = t;
        declarationType = decltype;
    }
    
    /** The type of declaration.
     *  Also dictates the type held in the declaration node.
     *  Note that if DeclarationType.Variable, the node type shall be
     *  SyntheticVariableDeclaration.
     */
    DeclarationType declarationType;
    Node declaration;
    LLVMValueRef value;
    LLVMTypeRef type;
    int readCount;
}


final class Scope
{
    bool builtReturn;
    
    void setDeclaration(string name, DeclarationStore val)
    {
        mDeclarations[name] = val;
    }
    
    DeclarationStore getDeclaration(string name)
    {
        auto p = name in mDeclarations;
        if (p) {
            auto d = *p;
            d.readCount++;
            return d;
        } else {
            return null;
        }
    }
    
    void checkUnused()
    {
        foreach (k, v; mDeclarations) {
            if (v.readCount == 0 && v.declarationType == DeclarationType.Variable) {
                auto synthVar = cast(SyntheticVariableDeclaration) v.declaration;
                if (synthVar is null) continue;  // An anonymous parameter.
                warning(v.declaration.location, format("unused variable '%s'.", extractIdentifier(synthVar.identifier)));
            }
        }
    }
    
    protected DeclarationStore[string] mDeclarations;
}
