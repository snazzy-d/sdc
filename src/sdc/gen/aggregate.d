/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.aggregate;

import std.conv;

import sdc.util;
import sdc.compilererror;
import sdc.extract.base;
import ast = sdc.ast.all;
import sdc.gen.sdcmodule;
import sdc.gen.type;
import sdc.gen.value;
import sdc.gen.base;


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

void genAggregateDeclaration(ast.AggregateDeclaration decl, Module mod)
{
    final switch (decl.type) {
    case ast.AggregateType.Struct:
        break;
    case ast.AggregateType.Union:
        panic(decl.location, "unions are unimplemented.");
    }
    
    if (decl.structBody is null) {
        panic(decl.location, "aggregates with no body are unimplemented.");
    }
    
    auto name = extractIdentifier(decl.name);
    auto type = new StructType(mod);
    type.name = mod.name.dup;
    type.name.identifiers ~= decl.name;
    
    auto currentScope = mod.currentScope;
    mod.currentScope = new Scope();
    currentScope.add(name, new Store(mod.currentScope));
    foreach (declDef; decl.structBody.declarations) {
        genDeclarationDefinition(declDef, mod);
    }
    FunctionValue[] functions;
    foreach (name, store; mod.currentScope.mSymbolTable) {
        if (store.storeType == StoreType.Type) {
            type.addMemberVar(name, store.type);
        } else if (store.storeType == StoreType.Value) {
            if (store.value.type.dtype != DType.Function) {
                type.addMemberVar(name, store.value.type);
            } else {
                auto func = cast(FunctionValue) store.value;
                assert(func);
                functions ~= func;
                
            }
        } else {
            error(decl.location, "invalid aggregrate declaration type.");
        }
    }
    mod.currentScope = currentScope;
    type.declare();
    foreach (func; functions) {
        auto ft = cast(FunctionType) func.type;
        assert(ft);
        ft.parent = type;
        type.addMemberFunction(func.name, func.newWithAddedArgument(new PointerType(mod, type), "this"));
    }
    
    mod.currentScope.add(name, new Store(type));
}
