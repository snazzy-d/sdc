/**
 * Copyright 2010-2011 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.mangle;

import std.conv;
import std.exception;

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

void mangleFunction(ref string mangledName, Function fn)
{
    if (mangledName == "main") {
        // TMP
        return;
    }
    mangledName = startMangle();
    if (fn.type.parentAggregate !is null) {
        QualifiedName name;
        if (fn.type.parentAggregate.dtype == DType.Struct) {
            auto asStruct = enforce(cast(StructType) fn.type.parentAggregate);
            name = asStruct.fullName;
        } else {
            auto asClass = enforce(cast(ClassType) fn.type.parentAggregate);
            name = asClass.fullName;
        }
        mangleQualifiedName(mangledName, name);
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
}

void mangleFunctionType(ref string mangledName, FunctionType type)
{
    mangleCallConvention(mangledName, type.linkage);
    // TODO: mangle function attributes.
    foreach (paramType; type.argumentTypes) {
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
        version(Windows) {
            goto case ExternWindows;
        } else {
            goto case ExternC;
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
    case NullPointer:
    case Pointer:
        auto asPointer = cast(PointerType) type;
        assert(asPointer);
        mangledName ~= "P";
        mangleType(mangledName, asPointer.base);
        break;
    case Array:
        auto asArray = cast(ArrayType) type;
        assert(asArray);
        mangledName ~= "A";
        mangleType(mangledName, asArray.base);
        break;
    case Struct:
        mangledName ~= "S";
        auto asStruct = cast(StructType) type;
        assert(asStruct);
        mangleQualifiedName(mangledName, asStruct.fullName);
        break;
    case Enum:
        mangledName ~= "E";
        mangleQualifiedName(mangledName, type.getFullName());
        break;
    case Class:
        mangledName ~= "C";
        auto asClass = cast(ClassType) type;
        assert(asClass);
        mangleQualifiedName(mangledName, asClass.fullName);
        break;
    case Const:
        mangledName ~= "x";
        break;
    case Immutable:
        mangledName ~= "y";
        break;
    case Function:
        auto asFunction = cast(FunctionTypeWrapper) type;
        assert(asFunction);
        mangleFunctionType(mangledName, asFunction.functionType);
        break;
    }
}
