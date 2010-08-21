/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.attribute;

import std.conv;
import std.string;

import sdc.compilererror;
import ast = sdc.ast.all;
import sdc.gen.base;
import sdc.gen.sdcmodule;

void declareAttributeSpecifier(ast.AttributeSpecifier attributeSpecifier, Module mod)
{
    panic("OH SHIT THINGS ARE GETTING REFACTORED, YO!");
    version (none) {
        auto oldLinkage = mod.currentLinkage;
        genAttribute(attributeSpecifier.attribute, mod);
        if (attributeSpecifier.declarationBlock !is null) {
            foreach (declDef; attributeSpecifier.declarationBlock.declarationDefinitions) {
                declareDeclarationDefinition(declDef, mod);
            }
            mod.currentLinkage = oldLinkage;
        }
    }
}

void genAttributeSpecifier(ast.AttributeSpecifier attributeSpecifier, Module mod)
{
    auto oldLinkage = mod.currentLinkage;
    genAttribute(attributeSpecifier.attribute, mod);
    if (attributeSpecifier.declarationBlock !is null) {
        foreach (declDef; attributeSpecifier.declarationBlock.declarationDefinitions) {
            genDeclarationDefinition(declDef, mod);
        }
        mod.currentLinkage = oldLinkage;
    }
}

void genAttribute(ast.Attribute attribute, Module mod)
{
    with (ast.AttributeType) {
    switch (attribute.type) {
    case ExternC, ExternCPlusPlus, ExternD, ExternPascal, ExternWindows, ExternSystem:
        mod.currentLinkage = cast(ast.Linkage) attribute.type;
        break;
    default:
        panic(attribute.location, format("unhandled attribute type '%s'.", to!string(attribute.type)));
    }
    }
}
