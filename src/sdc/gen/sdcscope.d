/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.sdcscope;

import llvm.c.Core;

import sdc.ast.base;
import sdc.ast.declaration;


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
    
    DeclarationType declarationType;
    Node declaration;
    LLVMValueRef value;
    LLVMTypeRef type;
}


final class Scope
{
    void setDeclaration(string name, DeclarationStore val)
    {
        mDeclarations[name] = val;
    }
    
    DeclarationStore getDeclaration(string name)
    {
        auto p = name in mDeclarations;
        return p ? *p : null;
    }
    
    protected DeclarationStore[string] mDeclarations;
}
