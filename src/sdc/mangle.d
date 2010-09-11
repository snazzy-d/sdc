/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.mangle;

import std.conv;

import sdc.compilererror;
import sdc.gen.sdcmodule;
import sdc.ast.attribute;
import sdc.ast.base;
import sdc.ast.declaration;
import sdc.ast.expression;
import sdc.extract.base;


string mangleFunctionToD(Module mod, QualifiedName baseName, FunctionDeclaration functionDeclaration)
{
    auto mangledName = "_D";
    if (extractIdentifier(functionDeclaration.name) == "main") {
        return "_Dmain";
    }
    mangleQualifiedName(mangledName, baseName, functionDeclaration.name);
    // TODO: functions that require a this pointer get 'M' appended here.
    mangleCallConvention(mangledName, mod, mod.currentLinkage);
    // TODO: mangle function attributes
    foreach (parameter; functionDeclaration.parameters) {
        mangleType(mangledName, parameter.type);
    }
    // TODO: Variadic functions have a different terminator here.
    mangledName ~= "Z";
    mangleType(mangledName, functionDeclaration.retval);
    return mangledName;
}

private:

void mangleQualifiedName(ref string mangledName, QualifiedName baseName, Identifier name)
{
    foreach (identifier; baseName.identifiers) {
        mangleLName(mangledName, extractIdentifier(identifier));
    }
    mangleLName(mangledName, extractIdentifier(name));
}

void mangleLName(ref string mangledName, string name)
{
    mangledName ~= to!string(name.length) ~ name;
}

void mangleCallConvention(ref string mangledName, Module mod, Linkage convention)
{
    final switch (convention) with (Linkage) {
    case ExternC:
        mangledName ~= "U";
        break;
    case ExternCPlusPlus:
        mangledName ~= "R";
        break;
    case ExternD:
        mangledName ~= "F";
        break;
    case ExternWindows:
        mangledName ~= "W";
        break;
    case ExternPascal:
        mangledName ~= "V";
        break;
    case ExternSystem:
        goto case ExternC;
    }
}

void mangleTypeSuffixes(ref string mangledName, Type type)
{
    for (int i = type.suffixes.length; i > 0; i--) {
        // Once again, this isn't foreach (e; retro(l)) because of a DMD bug.
        auto suffix = type.suffixes[i - 1];
        final switch (suffix.type) with (TypeSuffixType) {
        case Pointer:
            mangledName ~= "P";
            break;
        case DynamicArray:
            mangledName ~= "A";
            break;
        case StaticArray:
            mangledName ~= "G";
            auto expr = cast(Expression) type.node;
            // TODO
            break;
        case AssociativeArray:
            mangledName ~= "H";
            mangleType(mangledName, cast(Type) type.node);
            break;
        }
    }
}

void manglePrimitiveType(ref string mangledName, PrimitiveType ptype)
{
    final switch (ptype.type) with (PrimitiveTypeType) {
    case Bool:
        mangledName ~= "b";
        break;
    case Byte:
        mangledName ~= "g";
        break;
    case Ubyte:
        mangledName ~= "h";
        break;
    case Short:
        mangledName ~= "s";
        break;
    case Ushort:
        mangledName ~= "t";
        break;
    case Int:
        mangledName ~= "i";
        break;
    case Uint:
        mangledName ~= "k";
        break;
    case Long:
        mangledName ~= "l";
        break;
    case Ulong:
        mangledName ~= "m";
        break;
    case Cent:
    case Ucent:
        panic(ptype.location, "the cent and ucent types are unimplemented.");
        break; 
    case Char:
        mangledName ~= "a";
        break;
    case Wchar:
        mangledName ~= "u";
        break;
    case Dchar:
        mangledName ~= "w";
        break;
    case Float:
        mangledName ~= "f";
        break;
    case Double:
        mangledName ~= "d";
        break;
    case Real:
        mangledName ~= "e";
        break;
    case Ifloat:
        mangledName ~= "o";
        break;
    case Idouble:
        mangledName ~= "p";
        break;
    case Ireal:
        mangledName ~= "j";
        break;
    case Cfloat:
        mangledName ~= "q";
        break;
    case Cdouble:
        mangledName ~= "r";
        break;
    case Creal:
        mangledName ~= "c";
        break;
    case Void:
        mangledName ~= "v";
        break;
    }
}

void mangleType(ref string mangledName, Type type)
{
    mangleTypeSuffixes(mangledName, type);
    
    final switch (type.type) with (TypeType) {
    case Primitive:
        manglePrimitiveType(mangledName, cast(PrimitiveType) type.node);
        break;
    case Inferred:
        // TODO
        break;
    case UserDefined:
        // TODO
        break;
    case Typeof:
        // TODO
        break;
    case FunctionPointer:
        mangledName ~= "P";
        // TODO
        break;
    case Delegate:
        // TODO
        mangledName ~= "D";
        break;
    case ConstType:
        mangledName ~= "x";
        mangleType(mangledName, cast(Type) type.node);
        break;
    case ImmutableType:
        mangledName ~= "y";
        mangleType(mangledName, cast(Type) type.node);
        break;
    case SharedType:
        mangledName ~= "O";
        mangleType(mangledName, cast(Type) type.node);
        break;
    case InoutType:
        break;
    }
}
