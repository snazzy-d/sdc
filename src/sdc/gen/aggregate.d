/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.aggregate;

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
    
    foreach (declDef; decl.structBody.declarations) {
        genDeclarationDefinition(declDef, mod);
        // Nope, we're not adding stuff yet. Patience, it will come!
    }
    type.declare();
    
    mod.currentScope.add(name, new Store(type));
}
