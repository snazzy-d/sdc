/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.sdcclass;

import std.stdio;

import ast = sdc.ast.all;
import sdc.gen.sdcmodule;
import sdc.gen.type;


void genClassDeclaration(ast.ClassDeclaration decl, Module mod)
{
    auto ctype = new ClassType(mod);
    ctype.declare();
    mod.currentScope.add("tea", new Store(ctype));
}
