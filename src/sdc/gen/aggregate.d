/**
 * Copyright 2010-2011 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.aggregate;

import std.conv;
import std.exception;

import sdc.util;
import sdc.global;
import sdc.extract;
import sdc.compilererror;
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
    verbosePrint("Generating aggregate '" ~ name ~"'.", VerbosePrintColour.Red);
    verboseIndent++;


    auto type = new StructType(mod);
    type.fullName = mod.name.dup;
    type.fullName.identifiers ~= decl.name;
    
    auto currentScope = mod.currentScope;
    auto currentTypeScope = mod.typeScope;
    mod.typeScope = mod.currentScope = type.typeScope;
    currentScope.add(name, new Store(mod.currentScope, decl.name.location));
    
    auto oldAggregate = mod.aggregate;
    mod.aggregate = type;
    resolveDeclarationDefinitionList(decl.structBody.declarations, mod, type);

    Function[] functions;
    foreach (name, store; mod.currentScope.mSymbolTable) {
        if (store.storeType == StoreType.Type) {
            type.addMemberType(name, store.type);
        } else if (store.storeType == StoreType.Value) {
            type.addMemberVar(name, store.value.type);
        } else if (store.storeType == StoreType.Function) {
            functions ~= store.getFunction();  
        } else {
            throw new CompilerError(decl.location, "invalid aggregrate declaration type.");
        }
    }
    mod.currentScope = currentScope;
    mod.typeScope = currentTypeScope;
    mod.aggregate = oldAggregate;
    type.declare();
    foreach (fn; functions) {
        fn.type.parentAggregate = type;
        fn.addArgument(new PointerType(mod, type), "this");
        type.addMemberFunction(fn.simpleName, fn);
    }
    
    mod.currentScope.add(name, new Store(type, decl.name.location));

    verboseIndent--;
    verbosePrint("Done generating aggregate '" ~ name ~"'.", VerbosePrintColour.Red);
}

