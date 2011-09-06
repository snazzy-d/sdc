/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.ast.sdcimport;

import sdc.ast.base;


// static? import (\(Identifier\) stringliterallist | importList);
class ImportDeclaration : Node
{
    bool isStatic;
    bool isSynthetic;
    ImportList importList;  // Not if the below exist.
    Language language = Language.D;  // Optional.
    StringLiteral[] languageImports;  // Optional.
}

enum Language
{
    D,
    Java,
    C,
}

enum ImportListType
{
    SingleSimple,
    SingleBinder,
    Multiple,
}


class ImportList : Node
{
    ImportListType type;
    Import[] imports;
    ImportBinder binder;
}

// theImport (: binds+ [via ,])?
class ImportBinder : Node
{
    Import theImport;
    ImportBind[] binds;  // Optional.
}

// (aliasName =)? name
class ImportBind : Node
{
    Identifier name;
    Identifier aliasName;  // Optional.
}

// (moduleAlias =)? moduleName
class Import : Node
{
    QualifiedName moduleName;
    Identifier moduleAlias;  // Optional.
}
