/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.base;

import std.string;

import llvm.c.Core;

import sdc.compilererror;
import sdc.location;
import sdc.ast.sdcmodule;
import sdc.ast.declaration;
import sdc.gen.semantic;
import sdc.gen.declaration;



LLVMModuleRef genModule(Module mod)
{
    auto semantic = new Semantic();
    semantic.mod = LLVMModuleCreateWithNameInContext(toStringz(mod.tstream.filename), semantic.context);
    
    foreach (declaration; mod.declarationDefinitions) {
        declareDeclarationDefinition(declaration, semantic);
    }
    
    foreach (declaration; mod.declarationDefinitions) {
        genDeclarationDefinition(declaration, semantic);
    }
    
    return semantic.mod;
}

void declareDeclarationDefinition(DeclarationDefinition declDef, Semantic semantic)
{
    switch (declDef.type) {
    case DeclarationDefinitionType.Declaration:
        declareDeclaration(cast(Declaration) declDef.node, semantic);
        break;
    default:
        break;
    }
}

void genDeclarationDefinition(DeclarationDefinition declDef, Semantic semantic)
{
    switch (declDef.type) {
    case DeclarationDefinitionType.Declaration:
        genDeclaration(cast(Declaration) declDef.node, semantic);
        break;
    default:
        error(declDef.location, "unsupported declaration definition.");
    }
}


void genCast(Location location, Semantic semantic, LLVMTypeRef to, ref LLVMValueRef val)
{
    switch (LLVMGetTypeKind(to)) {
    case LLVMTypeKind.Integer:
        val = LLVMBuildIntCast(semantic.builder, val, to, "cast");
        break;
    default:
        error(location, "invalid cast.");
    }
}

