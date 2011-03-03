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
    
    auto firstValue = getKnown(mod, firstMember.location, base, 0);
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
        
        if (member.initialiser) {
            throw new CompilerPanic(member.initialiser.location, "enum member initialisers are unimplemented.");
        }
        
        auto v = getKnown(mod, member.location, base, 1);
        previousValue = previousValue.add(member.location, v);
        
        if (decl.name !is null) {
            type.addMember(extractIdentifier(member.name), v);
        } else {
            mod.currentScope.add(extractIdentifier(member.name), new Store(v));
        }
    }
    
    if (decl.name !is null) {
        auto name = extractIdentifier(decl.name);
        mod.currentScope.add(name, new Store(type));
    }
}

Value getKnown(Module mod, Location location, Type base, int init)
{
    switch (base.dtype) {
    case DType.Bool:
        auto v = new Known!BoolValue(mod, location);
        v.setKnown(cast(bool) init);
        return v;
    case DType.Byte:
        auto v = new Known!ByteValue(mod, location);
        v.setKnown(cast(byte) init);
        return v;
    case DType.Ubyte:
        auto v = new Known!UbyteValue(mod, location);
        v.setKnown(cast(ubyte) init);
        return v;
    case DType.Short:
        auto v = new Known!ShortValue(mod, location);
        v.setKnown(cast(short) init);
        return v;
    case DType.Ushort:
        auto v = new Known!UshortValue(mod, location);
        v.setKnown(cast(ushort) init);
        return v;
    case DType.Int:
        auto v = new Known!IntValue(mod, location);
        v.setKnown(init);
        return v;
    case DType.Uint:
        auto v = new Known!UintValue(mod, location);
        v.setKnown(init);
        return v;
    case DType.Long:
        auto v = new Known!LongValue(mod, location);
        v.setKnown(init);
        return v;
    case DType.Ulong:
        auto v = new Known!UlongValue(mod, location);
        v.setKnown(init);
        return v;
    case DType.Char:
        auto v = new Known!CharValue(mod, location);
        v.setKnown(cast(char) init);
        return v;
    case DType.Wchar:
        auto v = new Known!WcharValue(mod, location);
        v.setKnown(cast(wchar) init);
        return v;
    case DType.Dchar:
        auto v = new Known!DcharValue(mod, location);
        v.setKnown(init);
        return v;
    default:
        throw new CompilerError(location, format("cannot use type '%s' as enum base.", base.name));
    }
}
