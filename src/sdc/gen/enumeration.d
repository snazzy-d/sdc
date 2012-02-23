/**
 * Copyright 2010 Jakob Ovrum.
 * Copyright 2011-2012 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.enumeration;

import std.string;

import sdc.util;
import sdc.compilererror;
import sdc.location;
import sdc.extract;
import ast = sdc.ast.all;
import sdc.gen.sdcmodule;
import sdc.gen.type;
import sdc.gen.value;
import sdc.gen.base;
import sdc.gen.expression;
import sdc.interpreter.base;


void genEnumDeclaration(ast.EnumDeclaration decl, Module mod)
{
    auto interpreter = new Interpreter(mod.translationUnit);
    Type base;

    if (decl.base !is null) {
        // If base ends up null, we'll try to infer it later.   
        base = astTypeToBackendType(decl.base, mod, OnFailure.DieWithError);
    }
    
    i.Value[] members;
    foreach (j, member; decl.memberList.members) {
        if (base is null && member.initialiser is null) {
            base = new IntType(mod);
        }
        if (member.initialiser !is null) {
            members ~= interpreter.evaluate(member.location, member.initialiser); 
            if (base is null) {
                base = dtypeToType(members[$-1].type, mod);
            }
        } else {
            if (j == 0) {
                // If no explicit initialiser and this is the first member, use zero.
                members ~= i.Value.create(member.location, interpreter, base, 0);
            } else {
                // Otherwise, use the last member plus one.
                members ~= members[$-1].add(new i.IntValue(1));
            }
        }
    }

    auto type = new EnumType(mod, base);
    type.fullName = mod.name.dup;
    type.fullName.identifiers ~= decl.name;
    
    // Add each member to the module or enum namespace.
    if (decl.name !is null) foreach (j, v; members) {
        ast.EnumMember m = decl.memberList.members[j];
        type.addMember(extractIdentifier(m.name), v.toGenValue(mod, m.location));
    } else foreach (j, v; members) {
        ast.EnumMember m = decl.memberList.members[j];
        mod.currentScope.add(extractIdentifier(m.name), new Store(v.toGenValue(mod, m.location)));
    }

    // If this is a named enum, add the enum type to the module namespace.
    if (decl.name !is null) {
        auto name = extractIdentifier(decl.name);
        mod.currentScope.add(name, new Store(type, decl.name.location));
    }
}
