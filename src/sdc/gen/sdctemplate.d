/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.sdctemplate;

import sdc.extract.base;
import sdc.gen.base;
import sdc.gen.sdcmodule;
import sdc.gen.value;
import ast = sdc.ast.all;


Value genTemplateInstance(ast.TemplateInstance instance, Module mod)
{
    return null;
}

void genTemplateDeclaration(ast.TemplateDeclaration decl, Module mod)
{
    mod.currentScope.add(extractIdentifier(decl.templateIdentifier), new Store(decl));
}
