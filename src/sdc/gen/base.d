/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.base;

import std.string;

import llvm.c.Core;

import sdc.ast.sdcmodule;



LLVMModuleRef genModule(Module mod)
{
    auto context = LLVMGetGlobalContext();
    return LLVMModuleCreateWithNameInContext(toStringz(mod.tstream.filename), context);
}
