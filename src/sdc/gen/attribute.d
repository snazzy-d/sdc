/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.attribute;

import std.conv;
import std.stdio;

import sdc.util;
import sdc.compilererror;
import sdc.gen.base;
import sdc.gen.semantic;
import sdc.ast.attribute;


void genAttribute(Attribute attribute, File file, Semantic semantic)
{
    final switch (attribute.type) {
    case AttributeType.Deprecated:
        break;
    case AttributeType.Private:
        break;
    case AttributeType.Package:
        break;
    case AttributeType.Protected:
        break;
    case AttributeType.Public:
        break;
    case AttributeType.Export:
        break;
    case AttributeType.Static:
        break;
    case AttributeType.Final:
        break;
    case AttributeType.Override:
        break;
    case AttributeType.Abstract:
        break;
    case AttributeType.Const:
        semantic.pushAttribute(AttributeType.Const);
        break;
    case AttributeType.Auto:
        break;
    case AttributeType.Scope:
        break;
    case AttributeType.__Gshared:
        break;
    case AttributeType.Shared:
        break;
    case AttributeType.Immutable:
        break;
    case AttributeType.Inout:
        break;
    case AttributeType.atDisable:
        break;
    case AttributeType.Align:
        break;
    case AttributeType.Pragma:
        break;
    case AttributeType.Extern:
        break;
    case AttributeType.ExternC:
    case AttributeType.ExternCPlusPlus:
    case AttributeType.ExternD:
    case AttributeType.ExternWindows:
    case AttributeType.ExternPascal:
    case AttributeType.ExternSystem:
        break;
    }
}
