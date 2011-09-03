/**
 * Copyright 2010 Bernard Helyer.
 * Copyright 2011 Jakob Ovrum.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.sdcimport;

import std.algorithm;
import std.array;
import std.string;
import file = std.file;
import path = std.path;

import sdc.util;
import sdc.compilererror;
import sdc.location;
import sdc.aglobal;
import sdc.source;
import sdc.lexer;
import sdc.extract;
import ast = sdc.ast.all;
import parser = sdc.parser.all;
import sdc.gen.base;
import sdc.gen.sdcmodule;
version (xlang) import sdc.binder.c;


bool canGenImportDeclaration(ast.ImportDeclaration importDeclaration, Module mod)
{
    string getName(ast.Import imp) { return extractQualifiedName(imp.moduleName); }
    auto imports = filter!"a !is null"(map!getTranslationUnit(map!getName(importDeclaration.importList.imports)));
    return count!"a.gModule is null"(imports) == 0;
}

void genImportDeclaration(ast.ImportDeclaration importDeclaration, Module mod)
{
    version (xlang) {
        if (importDeclaration.language == ast.Language.Java) {
            throw new CompilerPanic(importDeclaration.location, "import (Java) is unimplemented.");
        }
        if (importDeclaration.language == ast.Language.C) {
            foreach (imp; importDeclaration.languageImports) {
                auto header = extractStringLiteral(imp);
                bindC(mod, header);
            }
            return;
        }
    }
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

private string searchImport(string impPath)
{
    if (file.exists(impPath) && file.isfile(impPath)) {
        return impPath;
    } else {
        auto impInterfacePath = impPath ~ 'i';
        if (file.exists(impInterfacePath) && file.isfile(impInterfacePath)) {
            return impInterfacePath;
        }
    }
    
    foreach (importPath; importPaths) {
        auto fullPath = importPath ~ path.sep ~ impPath;
        if (file.exists(fullPath) && file.isfile(fullPath)) {
            return fullPath;
        }
        
        fullPath ~= 'i';
        
        if (file.exists(fullPath) && file.isfile(fullPath)) {
            return fullPath;
        }
    }
    return null;
}

void genImport(Location location, ast.Import theImport, Module mod)
{
    auto name = extractQualifiedName(theImport.moduleName);
    auto moduleName = extractQualifiedName(mod.name);
    if (name == moduleName) return;  // Ignore self imports. 

    verbosePrint("Generating import '" ~ name ~ "'.");
    auto tu = getTranslationUnit(name);
    if (tu !is null) {
        if (!mod.importedTranslationUnits.contains(tu)) {
            mod.importedTranslationUnits ~= tu;
        }
        return;
    }

    auto impPath = extractModulePath(theImport.moduleName);
    auto fullPath = searchImport(impPath);
    if (fullPath is null) {
        CompilerError err;
        if (theImport.moduleName.location.filename is null) {
            err = new CompilerError(
                format(`implicitly imported module "%s" could not be found.`, name)
            );
        } else {
            err = new CompilerError(
                theImport.moduleName.location,
                format(`module "%s" could not be found.`, impPath)
            );
        }
        
        err.more = new CompilerErrorNote(format(`tried path "%s"`, impPath));
        
        auto next = err.more;
        foreach (importPath; importPaths) {
            next.more = new CompilerErrorNote(
                format(`tried path "%s"`, importPath ~ path.sep ~ impPath)
            );
            next = next.more;
        }
        throw err;
    }
    
    tu = new TranslationUnit();
    tu.tusource = TUSource.Import;
    tu.compile = false;
    tu.filename = fullPath;
    tu.source = new Source(fullPath);
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
    
    mod.importedTranslationUnits ~= tu;
    
    tu.gModule = genModule(tu.aModule, tu);
}
