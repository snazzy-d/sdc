/**
 * Copyright 2010-2011 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.aggregate;

import std.conv;
import std.exception;

import sdc.util;
import sdc.compilererror;
import sdc.extract.base;
import ast = sdc.ast.all;
import sdc.gen.sdcmodule;
import sdc.gen.type;
import sdc.gen.value;
import sdc.gen.base;
import sdc.gen.sdcfunction;


bool canGenAggregateDeclaration(ast.AggregateDeclaration decl, Module mod)
{
    bool b = true;
    foreach (declDef; decl.structBody.declarations) {
        b = b && canGenDeclarationDefinition(declDef, mod);
        if (!b) {
            break;
        }
    }
    return b;
}

void genAggregateDeclaration(ast.AggregateDeclaration decl, ast.DeclarationDefinition declDef, Module mod)
{
    final switch (decl.type) {
    case ast.AggregateType.Struct:
        break;
    case ast.AggregateType.Union:
        throw new CompilerPanic(decl.location, "unions are unimplemented.");
    }
    
    if (decl.structBody is null) {
        throw new CompilerPanic(decl.location, "aggregates with no body are unimplemented.");
    }
    
    auto name = extractIdentifier(decl.name);
    auto type = new StructType(mod);
    type.fullName = mod.name.dup;
    type.fullName.identifiers ~= decl.name;
    
    auto currentScope = mod.currentScope;
    mod.currentScope = type.typeScope;
    currentScope.add(name, new Store(mod.currentScope));
    foreach (innerDeclDef; decl.structBody.declarations) {
        innerDeclDef.parentType = type;
        genDeclarationDefinition(innerDeclDef, mod);
    }
    Function[] functions;
    foreach (name, store; mod.currentScope.mSymbolTable) {
        if (store.storeType == StoreType.Type) {
            type.addMemberVar(name, store.type);
        } else if (store.storeType == StoreType.Value) {
            type.addMemberVar(name, store.value.type);
        } else if (store.storeType == StoreType.Function) {
            functions ~= store.getFunction();  
        } else {
            throw new CompilerError(decl.location, "invalid aggregrate declaration type.");
        }
    }
    mod.currentScope = currentScope;
    type.declare();
    foreach (fn; functions) {
        fn.type.parentAggregate = type;
        fn.addArgument(new PointerType(mod, type), "this");
        type.addMemberFunction(fn.simpleName, fn);
    }
    
    mod.currentScope.add(name, new Store(type));
}
