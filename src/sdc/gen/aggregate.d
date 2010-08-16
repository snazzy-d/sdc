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
    
    foreach (sdecl; decl.structBody.declarations) {
        genStructBodyDeclaration(sdecl, mod, type);
    }
    type.declare();
    
    mod.currentScope.add(name, new Store(type));
}

void genStructBodyDeclaration(ast.StructBodyDeclaration sdecl, Module mod, StructType stype)
{
    switch (sdecl.type) {
    case ast.StructBodyDeclarationType.Declaration:
        auto decl = cast(ast.Declaration) sdecl.node;
        if (decl.type != ast.DeclarationType.Variable) {
            panic(decl.location, "aggregate functions are unimplemented.");
        }
        auto vdec = cast(ast.VariableDeclaration) decl.node;
        auto type = astTypeToBackendType(vdec.type, mod);
        foreach (declarator; vdec.declarators) {
            auto name = extractIdentifier(declarator.name);
            stype.addMemberVar(name, type);
        }
        break;
    default:
        panic(sdecl.location, "unimplemented aggregate member.");
    }
}
