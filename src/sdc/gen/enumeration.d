/**
 * Copyright 2010 Jakob Ovrum.
 * Copyright 2011 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.enumeration;

import std.string;

import sdc.util;
import sdc.compilererror;
import sdc.location;
import sdc.extract.base;
import ast = sdc.ast.all;
import sdc.gen.sdcmodule;
import sdc.gen.type;
import sdc.gen.value;
import sdc.gen.base;
import sdc.gen.expression;



void genEnumDeclaration(ast.EnumDeclaration decl, Module mod)
{
    auto firstMember = decl.memberList.members[0];    
    Type base;
    Value initialiser;
    
    if (decl.base is null) {
        if (decl.memberList.members[0].initialiser !is null) {
            // Infer the type from the first initialiser.
            initialiser = genAssignExpression(firstMember.initialiser, mod);
            base = initialiser.type;
        } else { 
            // Otherwise assume int.
            base = new IntType(mod);
        }
    } else {
        base = astTypeToBackendType(decl.base, mod, OnFailure.DieWithError);
    }
    
    auto type = new EnumType(mod, base);
    type.fullName = mod.name.dup;
    type.fullName.identifiers ~= decl.name;
    
    auto firstValue = getKnown(mod, firstMember.location, base);
    if (firstMember.initialiser) {
        if (initialiser is null) initialiser = genAssignExpression(firstMember.initialiser, mod);
        firstValue.set(firstMember.initialiser.location, initialiser);
    }
    Value previousValue = firstValue;
    
    //firstValue.initialise(firstValue.location, firstValue.getInit(firstValue.location));
    type.addMember(extractIdentifier(firstMember.name), firstValue);
    if (decl.name !is null) {
        type.addMember(extractIdentifier(firstMember.name), firstValue);
    } else {
        mod.currentScope.add(extractIdentifier(firstMember.name), new Store(firstValue));
    }
    
    foreach(i; 1..decl.memberList.members.length) {
        auto member = decl.memberList.members[i];
        
        auto v = getKnown(mod, member.location, base);
        
        if (member.initialiser) {
            initialiser = genAssignExpression(member.initialiser, mod);
            v.set(member.initialiser.location, initialiser);
            previousValue = v;
        } else {
            auto one = new IntValue(mod, member.location, 1);
            previousValue = previousValue.add(member.location, one);
        }
        
        if (decl.name !is null) {
            type.addMember(extractIdentifier(member.name), previousValue);
        } else {
            mod.currentScope.add(extractIdentifier(member.name), new Store(previousValue));
        }
    }
    
    if (decl.name !is null) {
        auto name = extractIdentifier(decl.name);
        mod.currentScope.add(name, new Store(type));
    }
}

Value getKnown(Module mod, Location location, Type base)
{
    switch (base.dtype) {
    case DType.Bool:
        auto v = new Known!BoolValue(mod, location);
        return v;
    case DType.Byte:
        auto v = new Known!ByteValue(mod, location);
        return v;
    case DType.Ubyte:
        auto v = new Known!UbyteValue(mod, location);
        return v;
    case DType.Short:
        auto v = new Known!ShortValue(mod, location);
        return v;
    case DType.Ushort:
        auto v = new Known!UshortValue(mod, location);
        return v;
    case DType.Int:
        auto v = new Known!IntValue(mod, location);
        return v;
    case DType.Uint:
        auto v = new Known!UintValue(mod, location);
        return v;
    case DType.Long:
        auto v = new Known!LongValue(mod, location);
        return v;
    case DType.Ulong:
        auto v = new Known!UlongValue(mod, location);
        return v;
    case DType.Char:
        auto v = new Known!CharValue(mod, location);
        return v;
    case DType.Wchar:
        auto v = new Known!WcharValue(mod, location);
        return v;
    case DType.Dchar:
        auto v = new Known!DcharValue(mod, location);
        return v;
    default:
        throw new CompilerError(location, format("cannot use type '%s' as enum base.", base.name));
    }
}
