/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.sdcimport;

import std.string;

import sdc.util;
import sdc.compilererror;
import sdc.global;
import sdc.extract.base;
import ast = sdc.ast.all;
import sdc.gen.sdcmodule;


bool canGenImportDeclaration(ast.ImportDeclaration importDeclaration, Module mod)
{
    return true;
}

ast.ImportDeclaration synthesiseImport(string modname)
{
    with (ast) {
        auto decl = new ImportDeclaration();
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
} 

void genImportDeclaration(ast.ImportDeclaration importDeclaration, Module mod)
{
    return genImportList(importDeclaration.importList, mod);
}

void genImportList(ast.ImportList importList, Module mod)
{
    final switch (importList.type) {
    case ast.ImportListType.SingleSimple:
        foreach (imp; importList.imports) {
            genImport(imp, mod);
        }
        break;
    case ast.ImportListType.SingleBinder:
        panic(importList.location, "TODO: single binder import list.");
        break;
    case ast.ImportListType.Multiple:
        panic(importList.location, "TODO: multiple import list.");
        break;
    }
}

void genImportBinder(ast.ImportBinder importBinder, Module mod)
{
}

void genImportBind(ast.ImportBind importBind, Module mod)
{
}

void genImport(ast.Import theImport, Module mod)
{
    auto name = extractQualifiedName(theImport.moduleName);
    auto tu = getTranslationUnit(name);
    if (tu is null) {
        panic(theImport.moduleName.location, "TODO: Search through import paths for module.");
    }
    if (mod.importedTranslationUnits.contains(tu)) {
        return;
    }
    mod.importedTranslationUnits ~= tu;
}
