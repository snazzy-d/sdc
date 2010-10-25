/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.sdcimport;

import std.string;
import file = std.file;

import sdc.util;
import sdc.compilererror;
import sdc.location;
import sdc.global;
import sdc.source;
import sdc.lexer;
import sdc.extract.base;
import ast = sdc.ast.all;
import parser = sdc.parser.all;
import sdc.gen.base;
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
    return genImportList(importDeclaration.location, importDeclaration.importList, mod);
}

void genImportList(Location loc, ast.ImportList importList, Module mod)
{
    final switch (importList.type) {
    case ast.ImportListType.SingleSimple:
        foreach (imp; importList.imports) {
            genImport(loc, imp, mod);
        }
        break;
    case ast.ImportListType.SingleBinder:
        throw new CompilerPanic(importList.location, "TODO: single binder import list.");
    case ast.ImportListType.Multiple:
        throw new CompilerPanic(importList.location, "TODO: multiple import list.");
    }
}

void genImportBinder(ast.ImportBinder importBinder, Module mod)
{
}

void genImportBind(ast.ImportBind importBind, Module mod)
{
}

void genImport(Location location, ast.Import theImport, Module mod)
{
    auto name = extractQualifiedName(theImport.moduleName);
    auto tu = getTranslationUnit(name);
    if(tu !is null) {
        if (!mod.importedTranslationUnits.contains(tu)) {
            mod.importedTranslationUnits ~= tu;
        }
        return;
    }

    auto path = extractModulePath(theImport.moduleName);
    if (!file.exists(path)) {
        throw new CompilerError(
            theImport.moduleName.location,
            format(`source "%s" could not be found.`, path)
        );
    }
    if(!file.isfile(path)) {
        throw new CompilerError(
            theImport.moduleName.location,
            format(`source "%s" is not a file.`, path)
        );
    }
    
    tu = new TranslationUnit();
    tu.tusource = TUSource.Import;
    tu.filename = path;
    tu.source = new Source(path);
    tu.tstream = lex(tu.source);
    tu.aModule = parser.parseModule(tu.tstream);
    
    auto moduleDecl = extractQualifiedName(tu.aModule.moduleDeclaration.name);
    if (moduleDecl != name) {
        throw new CompilerError(
            theImport.moduleName.location,
            `name of imported module does not match import directive.`,
            new CompilerError(
                tu.aModule.moduleDeclaration.name.location,
                `module declaration:`
            )
        );
    }
    
    addTranslationUnit(name, tu);
    mod.importedTranslationUnits ~= tu;
    
    tu.gModule = genModule(tu.aModule);
}
