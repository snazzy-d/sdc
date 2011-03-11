/**
 * Copyright 2010-2011 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.sdcclass;

import std.exception;
import std.stdio;
import std.range;

import sdc.util;
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
    ClassType base;
    if (decl.baseClassList !is null) {
        auto store = mod.search(extractQualifiedName(decl.baseClassList.superClass));
        if (store is null || store.storeType != StoreType.Type) {
            assert(false);  // TODO
        }
        base = cast(ClassType) store.type;
        if (base is null) {
            assert(false);  // TODO
        }
    }
    auto ctype = new ClassType(mod, base);
    ctype.fullName = new ast.QualifiedName(); 
    ctype.fullName.identifiers = mod.name.identifiers;
    ctype.fullName.identifiers ~= decl.identifier;
    mod.currentScope.add(extractIdentifier(decl.identifier), new Store(ctype));
        
    auto currentScope = mod.currentScope;
    mod.currentScope = new Scope();

    ast.DeclarationDefinition[] methods;        
    foreach (bodyDecl; decl.classBody.classBodyDeclarations) {
        genClassBodyDeclaration(bodyDecl, ctype, mod, methods);
    }
    
    
    foreach (name, store; mod.currentScope.mSymbolTable) {
        if (store.storeType == StoreType.Type) {
            ctype.addMemberVar(name, store.type);
        } else if (store.storeType == StoreType.Value) {
            ctype.addMemberVar(name, store.value.type);
        } else if (store.storeType == StoreType.Function) {
            throw new CompilerPanic(decl.location, "generated function in initial class generation pass."); 
        } else {
            throw new CompilerError(decl.location, "invalid class declaration type.");
        }
    }
    ctype.declare();
    
    foreach (method; methods) {
        method.parentType = ctype;
        genDeclarationDefinition(method, mod);
    }
    
    Function[] functions;
    foreach (name, store; ctype.typeScope.mSymbolTable) {
        if (store.storeType == StoreType.Function) {
            functions ~= store.getFunction();
        }
    }
    
    foreach (fn; functions) {
        fn.type.parentAggregate = ctype;
        fn.addArgument(ctype, "this");
        ctype.addMemberFunction(fn.simpleName, fn);
    }
    
    mod.currentScope = currentScope;
}

void genClassBodyDeclaration(ast.ClassBodyDeclaration bodyDecl, ClassType type, Module mod, ref ast.DeclarationDefinition[] methods)
{
    final switch (bodyDecl.type) with (ast.ClassBodyDeclarationType) {
    case Declaration:
    case Constructor:
        auto asDecldef = enforce(cast(ast.DeclarationDefinition) bodyDecl.node);
        if (asDecldef.type == ast.DeclarationDefinitionType.Declaration) {
            auto asDecl = enforce(cast(ast.Declaration) asDecldef.node);
            if (asDecl.type == ast.DeclarationType.Function) {
                methods ~= asDecldef;
                return;
            }
        }
        asDecldef.parentType = type;
        genDeclarationDefinition(asDecldef, mod);
        break;
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
    // Allocate the underlying class struct. 
    auto v = new ClassValue(mod, location, type);
    auto size = type.structType.getValue(mod, location).getSizeof(location);
    v.v = enforce(cast(PointerValue) mod.gcAlloc(location, size).performCast(location, v.v.type));
    
    
    // Allocate the vtable.
    // The vtable is methods.length + 1 for the TypeInfo at the beginning of the vtable.
    auto vtablesize = newSizeT(mod, location, 0).getSizeof(location).mul(location, newSizeT(mod, location, type.methods.length + 1));    
    auto vtablemem  = mod.gcAlloc(location, vtablesize).performCast(location, v.v.getMember(location, "__vptr").type);
    v.v.getMember(location, "__vptr").set(location, vtablemem);
     
    // Populate the vtable.
    foreach (i, method; type.methods) {
        auto indexv = newSizeT(mod, location, i + 1);  // Skip the TypeInfo's vtable index.
        // Generates code equivalent to "__vptr[i] = cast(void*) &methodFunction;". 
        v.v.getMember(location, "__vptr").index(location, indexv).set(location, type.methods[i].fn.addressOf(location).performCast(location, new PointerType(mod, new VoidType(mod))));
    }
    
    // Call the constructor.
    // TODO
    
    return v;
}
