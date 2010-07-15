/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.type;

import llvm.c.Core;

import sdc.compilererror;
import sdc.ast.declaration;
import sdc.gen.semantic;


LLVMTypeRef typeToLLVM(Type t, Semantic semantic)
{
    switch (t.type) {
    case TypeType.Primitive:
        return primitiveToLLVM(cast(PrimitiveType)t.node, semantic);
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
    default:
        error(t.location, "ICE: unimplemented primitive type.");
    }
    assert(false);
}
