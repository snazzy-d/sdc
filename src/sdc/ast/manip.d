/**
 * Copyright 2010 Bernard Helyer.
 * Copyright 2010 Jakob Ovrum.
 * This file is part of SDC.
 * See LICENCE or sdc.d for more details.
 */
module sdc.ast.manip;

import std.string;
import sdc.ast.all;

/*
 * This file have create a manipulate ast trees.
 */

/**
 * Create a simple ImportDeclaration that imports just
 * the given module name.
 *
 * Side-effects:
 *   None.
 *
 * Returns:
 *   Newly allocate and properly setup ImportDeclaration.
 */
ImportDeclaration synthesiseImport(string modname)
{
    auto decl = new ImportDeclaration();
    decl.isSynthetic = true;
    decl.importList = new ImportList();
    decl.importList.type = ImportListType.SingleSimple;
    auto imp = new Import();

    auto names = split(modname, ".");
    auto qname = new QualifiedName();
    foreach (name; names) {
        auto iname = new Identifier();
        iname.value = name;
        qname.identifiers ~= iname;
    }

    imp.moduleName = qname;
    decl.importList.imports ~= imp;
    return decl;
} 
