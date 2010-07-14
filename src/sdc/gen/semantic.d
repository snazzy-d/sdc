/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.semantic;

import llvm.c.Core;


/**
 * I'm going to be honest here. Semantic is a big grab bag of shit
 * needed for codegen, intended to be passes around like a cheap
 * whore.
 */
class Semantic
{
    LLVMContextRef context;
    LLVMModuleRef mod;
    
    this()
    {
        context = LLVMGetGlobalContext();
    }
}
