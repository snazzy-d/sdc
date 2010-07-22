/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.type;

import std.string;

import llvm.c.Core;

import sdc.compilererror;
import sdc.ast.declaration;
import sdc.gen.semantic;
import sdc.gen.extract;



LLVMTypeRef typeToLLVM(Type t, Semantic semantic)
{
    LLVMTypeRef T;
    switch (t.type) {
    case TypeType.Primitive:
        T = primitiveToLLVM(cast(PrimitiveType) t.node, semantic);
        break;
    case TypeType.UserDefined:
        T = userDefinedTypeToLLVM(cast(UserDefinedType) t.node, semantic);
        break;
    default:
        error(t.location, "ICE: unimplemented type.");
    }
    
    foreach (suffix; t.suffixes) {
        final switch (suffix.type) {
        case TypeSuffixType.Pointer:
            T = LLVMPointerType(T, 0);
            break;
        case TypeSuffixType.DynamicArray:
        case TypeSuffixType.StaticArray:
        case TypeSuffixType.AssociativeArray:
            error(suffix.location, "ICE: unimplemented type suffix.");
        }
    }
    
    return T;
}

LLVMTypeRef primitiveToLLVM(PrimitiveType t, Semantic semantic)
{
    switch (t.type) {
    case PrimitiveTypeType.Bool:
        return LLVMInt1TypeInContext(semantic.context);
    case PrimitiveTypeType.Ubyte:
    case PrimitiveTypeType.Byte:
        return LLVMInt8TypeInContext(semantic.context);
    case PrimitiveTypeType.Ushort:
    case PrimitiveTypeType.Short:
        return LLVMInt16TypeInContext(semantic.context);
    case PrimitiveTypeType.Uint:
    case PrimitiveTypeType.Int:
        return LLVMInt32TypeInContext(semantic.context);
    case PrimitiveTypeType.Ulong:
    case PrimitiveTypeType.Long:
        return LLVMInt64TypeInContext(semantic.context);
    case PrimitiveTypeType.Ucent:
    case PrimitiveTypeType.Cent:
        return LLVMIntTypeInContext(semantic.context, 128);
    case PrimitiveTypeType.Float:
        return LLVMFloatTypeInContext(semantic.context);
    case PrimitiveTypeType.Double:
        return LLVMDoubleTypeInContext(semantic.context);
    case PrimitiveTypeType.Void:
        return LLVMVoidTypeInContext(semantic.context);
    default:
        error(t.location, "ICE: unimplemented primitive type.");
    }
    assert(false);
}

LLVMTypeRef userDefinedTypeToLLVM(UserDefinedType userDefinedType, Semantic semantic)
{
    auto name = extractQualifiedName(userDefinedType.qualifiedName);
    auto d    = semantic.getDeclaration(name);
    if (d is null || d.type is null) {
        error(userDefinedType.location, format("undefined type '%s'", name));
        assert(false);
    }
    return d.type;
}
