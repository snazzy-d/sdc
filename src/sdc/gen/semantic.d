/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.semantic;

import llvm.c.Core;

import sdc.ast.declaration;


/**
 * I'm going to be honest here. Semantic is a big grab bag of shit
 * needed for codegen, intended to be passed around like a cheap
 * whore.
 */
class Semantic
{
    LLVMContextRef context;
    LLVMModuleRef mod;
    LLVMBuilderRef builder;
    
    FunctionDeclaration currentFunction;
    
    this()
    {
        context = LLVMGetGlobalContext();
        builder = LLVMCreateBuilderInContext(context);
    }
}
