/**
 * Copyright 2010 Jakob Ovrum.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
 module sdc.gen.enumeration;

import sdc.util;
import sdc.compilererror;
import sdc.extract.base;
import ast = sdc.ast.all;
import sdc.gen.sdcmodule;
import sdc.gen.type;
import sdc.gen.value;
import sdc.gen.base;
import sdc.gen.expression;



void genEnumDeclaration(ast.EnumDeclaration decl, Module mod)
{    
    if (decl.name !is null) {
        Type base;
        if (decl.base is null) {
            base = new IntType(mod);
        } else {
            base = astTypeToBackendType(decl.base, mod, OnFailure.DieWithError);
        }
        
        auto type = new EnumType(mod, base);
        type.fullName = mod.name.dup;
        type.fullName.identifiers ~= decl.name;
        
        auto firstMember = decl.memberList.members[0];
        if (firstMember.initialiser) {
            throw new CompilerPanic(firstMember.initialiser.location, "enum member initialisers are unimplemented.");
        }
        
        //auto firstValue = base.getValue(mod, firstMember.location);
        auto firstValue = new Known!IntValue(mod, firstMember.location);
        firstValue.setKnown(0);
        Value previousValue = firstValue;
        
        //firstValue.initialise(firstValue.location, firstValue.getInit(firstValue.location));
        type.addMember(extractIdentifier(firstMember.name), firstValue);
        
        foreach(i; 1..decl.memberList.members.length) {
            auto member = decl.memberList.members[i];
            
            if (member.initialiser) {
                throw new CompilerPanic(member.initialiser.location, "enum member initialisers are unimplemented.");
            }
            
            auto v = new Known!IntValue(mod, firstMember.location);
            v.setKnown(1);
            previousValue = previousValue.add(member.location, v);
            
            
            type.addMember(extractIdentifier(member.name), v);
        }
        
        auto name = extractIdentifier(decl.name);
        mod.currentScope.add(name, new Store(type));
    } else {
        throw new CompilerPanic(decl.location, "anonymous enums are unimplemented.");
    }
}
