/**
 * Copyright 2010-2011 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.sdcclass;

import std.exception;
import std.stdio;

import sdc.compilererror;
import sdc.global;
import sdc.location;
import ast = sdc.ast.all;
import sdc.gen.base;
import sdc.gen.sdcmodule;
import sdc.gen.sdcfunction;
import sdc.gen.type;
import sdc.gen.value;
import sdc.extract.base;


bool canGenClassDeclaration(ast.ClassDeclaration decl, Module mod)
{
    if (decl.baseClassList !is null) {
        return mod.search(extractQualifiedName(decl.baseClassList.superClass)) !is null;
    }
    return true;
}

void genClassDeclaration(ast.ClassDeclaration decl, Module mod)
{
    auto ctype = new ClassType(mod, null);
    mod.currentScope.add(extractIdentifier(decl.identifier), new Store(ctype));
        
    auto currentScope = mod.currentScope;
    mod.currentScope = new Scope();
        
    foreach (bodyDecl; decl.classBody.classBodyDeclarations) {
        genClassBodyDeclaration(bodyDecl, mod);
    }
    
    Function[] functions;
    foreach (name, store; mod.currentScope.mSymbolTable) {
        if (store.storeType == StoreType.Type) {
            ctype.addMemberVar(name, store.type);
        } else if (store.storeType == StoreType.Value) {
            ctype.addMemberVar(name, store.value.type);
        } else if (store.storeType == StoreType.Function) {
            functions ~= store.getFunction();  
        } else {
            throw new CompilerError(decl.location, "invalid class declaration type.");
        }
    }
    ctype.declare();
    foreach (fn; functions) {
        fn.type.parentAggregate = ctype;
        fn.addArgument(new PointerType(mod, ctype), "this");
        ctype.addMemberFunction(fn.simpleName, fn);
    }
    mod.currentScope = currentScope;
}

void genClassBodyDeclaration(ast.ClassBodyDeclaration bodyDecl, Module mod)
{
    final switch (bodyDecl.type) with (ast.ClassBodyDeclarationType) {
    case Declaration:
        genDeclarationDefinition(cast(ast.DeclarationDefinition) bodyDecl.node, mod);
    case Constructor:
    case Destructor:
    case StaticConstructor:
    case StaticDestructor:
    case Invariant:
    case UnitTest:
    case ClassAllocator:
    case ClassDeallocator:
        throw new CompilerPanic(bodyDecl.location, "unhandled body declaration type.");
    }
}

ClassValue newClass(Module mod, Location location, ClassType type, ast.ArgumentList argumentList)
{
    auto v = new ClassValue(mod, location, type);
    auto size = type.structType.getValue(mod, location).getSizeof(location);
    v.v = enforce(cast(PointerValue) gcAlloc.call(location, [location], [size]).performCast(location, v.v.type));
    return v;
}
