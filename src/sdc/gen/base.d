/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.base;

import std.string;

import llvm.c.Core;

import sdc.ast.sdcmodule;
import sdc.gen.semantic;



LLVMModuleRef genModule(Module mod)
{
    auto semantic = new Semantic();
    semantic.mod = LLVMModuleCreateWithNameInContext(toStringz(mod.tstream.filename), semantic.context);
    return semantic.mod;
}
