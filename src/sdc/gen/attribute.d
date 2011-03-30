/**
 * Copyright 2010-2011 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.attribute;

import std.conv;
import std.string;

import sdc.global;
import sdc.util;
import sdc.compilererror;
import ast = sdc.ast.all;
import sdc.gen.base;
import sdc.gen.sdcmodule;
import sdc.gen.type;


bool canGenAttributeSpecifier(ast.AttributeSpecifier attributeSpecifier, Module mod)
{
    return canGenAttribute(attributeSpecifier.attribute, mod);
}

bool canGenAttribute(ast.Attribute attribute, Module mod)
{
    final switch (attribute.type) with (ast.AttributeType) {
    case Deprecated: case Private: case Package:
    case Protected: case Public: case Export:
    case Static: case Final: case Override:
    case Abstract: case Const: case Auto:
    case Scope: case __Gshared: case Shared:
    case Immutable: case Inout: case atDisable:
    case Align: case Extern: case ExternC:
    case ExternCPlusPlus: case ExternD: case ExternWindows:
    case ExternPascal: case ExternSystem:
    case Pure: case Nothrow: case atSafe: case atTrusted:
    case atSystem:
        return true;
    case Pragma:
        return false;
    }
}

enum saveAttributeString = q{
    auto oldLinkage = mod.currentLinkage;
    auto oldStatic  = mod.isStatic;
    auto oldNoThrow = mod.isNoThrow;
    auto oldTrust   = mod.currentTrustLevel;
};

enum handleAttributeString = q{
    switch (attribute.type) with (ast.AttributeType) {
    case ExternC, ExternCPlusPlus, ExternD, ExternPascal, ExternWindows, ExternSystem:
        mod.currentLinkage = cast(ast.Linkage) attribute.type;
        break;
    case Static:
        mod.isStatic = true;
        break;
    case Nothrow:
        mod.isNoThrow = true;
        break;
    case atSafe: case atTrusted: case atSystem:
        mod.currentTrustLevel = attribute.type;
        break;
    default:
        throw new CompilerPanic(attribute.location, format("unhandled attribute type '%s'.", to!string(attribute.type)));
    }
};

enum restoreAttributeString = q{
    mod.currentLinkage = oldLinkage;
    mod.isStatic = oldStatic;
    mod.isNoThrow = oldNoThrow;
    mod.currentTrustLevel = oldTrust;
};
