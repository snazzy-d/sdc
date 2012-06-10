/**
 * Copyright 2010-2011 Bernard Helyer.
 * This file is part of SDC.
 * See LICENCE or sdc.d for more details.
 */
module sdc.mangle;
version (SDCCOMPILER):

import std.conv;
import std.exception;
import std.string;

import sdc.util;
import sdc.compilererror;
import sdc.extract;
import sdc.gen.sdcmodule;
import sdc.gen.type;
import sdc.gen.value;
import sdc.gen.sdcfunction;
import sdc.ast.attribute;
import sdc.ast.base;

string startMangle()
{
    return "_D";
}

string mangleFunction(Function fn)
{
    auto mangledName = startMangle();
    if (fn.type.parentAggregate !is null) {
        mangleQualifiedName(mangledName, fn.type.parentAggregate.getFullName());
    } else {
        if (fn.type.mod.name is null) {
            throw new CompilerPanic("null module name.");
        }
        mangleQualifiedName(mangledName, fn.mod.name);
    }
    mangleLName(mangledName, fn.simpleName);
    if (fn.type.parentAggregate !is null && !fn.type.isStatic) {
        mangledName ~= "M";
    }
    mangleFunctionType(mangledName, fn.type);
    return mangledName;
}

void mangleFunctionType(ref string mangledName, FunctionType type)
{
    mangleCallConvention(mangledName, type.linkage);
    // TODO: mangle function attributes.
    foreach (paramType; type.parameterTypes) {
        mangleType(mangledName, paramType);
    }
    // TODO: Variadic functions have a different terminator here.
    mangledName ~= "Z";
    mangleType(mangledName, type.returnType);
}

void mangleQualifiedName(ref string mangledName, QualifiedName baseName)
{
    foreach (identifier; baseName.identifiers) {
        mangleLName(mangledName, extractIdentifier(identifier));
    }
}

void mangleLName(ref string mangledName, string name)
{
    mangledName ~= to!string(name.length) ~ name;
}

void mangleCallConvention(ref string mangledName, Linkage convention)
{
    final switch (convention) with (Linkage) {
    case C:
        mangledName ~= "U";
        break;
    case CPlusPlus:
        mangledName ~= "R";
        break;
    case D:
        mangledName ~= "F";
        break;
    case Windows:
        mangledName ~= "W";
        break;
    case Pascal:
        mangledName ~= "V";
        break;
    case System:
        version(Windows) {
            goto case Windows;
        } else {
            goto case C;
        }
    }
}

void mangleType(ref string mangledName, Type type)
{        
    final switch (type.dtype) with (DType) {
    case Inferred:
        break;
    case Complex:
    case None:
    case Scope:
        throw new CompilerPanic("attempted to mangle invalid type.");
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
    case Void:
        mangledName ~= "v";
        break;
    case StaticArray:
        auto asStaticArray = cast(StaticArrayType) type;
        assert(asStaticArray !is null);
        mangledName ~= format("G%s", asStaticArray.length);
        mangleType(mangledName, asStaticArray.getBase());
        break;
    case NullPointer:
    case Pointer:
        mangledName ~= "P";
        mangleType(mangledName, type.getBase());
        break;
    case Array:
        mangledName ~= "A";
        mangleType(mangledName, type.getBase());
        break;
    case Struct:
        mangledName ~= "S";
        mangleQualifiedName(mangledName, type.getFullName());
        break;
    case Enum:
        mangledName ~= "E";
        mangleQualifiedName(mangledName, type.getFullName());
        break;
    case Class:
        mangledName ~= "C";
        mangleQualifiedName(mangledName, type.getFullName());
        break;
    case Const:
        mangledName ~= "x";
        break;
    case Immutable:
        mangledName ~= "y";
        break;
    case Function:
        auto asFunction = cast(FunctionType) type;
        assert(asFunction !is null);
        mangleFunctionType(mangledName, asFunction);
        break;
    }
}
