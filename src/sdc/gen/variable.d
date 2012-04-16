/**
 * Copyright 2011 Bernard Helyer.
 * This file is part of SDC.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.variable;

import llvm.c.Core;

import sdc.location;
import sdc.gen.type;
import sdc.gen.value;


class Variable
{
    LLVMValueRef mValue;
    Type type;
    
    void set(Location location, Value v)
    {
        type = v.type;
        LLVMTypeRef pointer = LLVMPointerType(v.type.llvmType, 0);
        mValue = LLVMBuildAlloca(v.getModule().builder, pointer, "var_set");
        LLVMBuildStore(v.getModule().builder, v.get(), mValue);
    }
    
    Value get(Location location)
    {
        auto v = type.getValue(type.mModule, location);
        v.mValue = LLVMBuildLoad(type.mModule.builder, mValue, "var_get");
        return v;
    }
}

