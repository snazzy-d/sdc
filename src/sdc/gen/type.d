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
    switch (t.type) {
    case TypeType.Primitive:
        return primitiveToLLVM(cast(PrimitiveType) t.node, semantic);
    case TypeType.UserDefined:
        return userDefinedTypeToLLVM(cast(UserDefinedType) t.node, semantic);
    default:
        error(t.location, "ICE: unimplemented type.");
    }
    assert(false);
}

LLVMTypeRef primitiveToLLVM(PrimitiveType t, Semantic semantic)
{
    switch (t.type) {
    case PrimitiveTypeType.Int:
        return LLVMInt32TypeInContext(semantic.context);
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
