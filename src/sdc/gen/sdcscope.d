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


enum StoreType
{
    Variable,
    Function,
}

class Store
{
    StoreType stype;
    LLVMTypeRef type;
    LLVMValueRef value;
    Node declaration;
    int readCount;
}

final class VariableStore : Store
{
    this()
    {
        stype = StoreType.Variable;
    }
}

/**
 * Holds the declaration, and optionally, the definition of a function.
 */
final class FunctionStore : Store
{
    this()
    {
        stype = StoreType.Function;
    }
}


final class Scope
{
    bool builtReturn;
    
    void setDeclaration(string name, Store val)
    {
        mDeclarations[name] = val;
    }
    
    Store getDeclaration(string name)
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
            if (v.readCount == 0 && v.stype == StoreType.Variable) {
                auto synthVar = cast(SyntheticVariableDeclaration) v.declaration;
                if (synthVar is null) continue;  // An anonymous parameter.
                warning(v.declaration.location, format("unused variable '%s'.", extractIdentifier(synthVar.identifier)));
            }
        }
    }
    
    protected Store[string] mDeclarations;
}
