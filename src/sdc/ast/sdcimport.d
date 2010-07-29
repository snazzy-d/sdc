/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.ast.sdcimport;

import sdc.ast.base;


// static? import importList ;
class ImportDeclaration : Node
{
    bool isStatic;
    ImportList importList;
}

// binders+ [via ,] 
class ImportList : Node
{
    ImportBinder[] binders;
}

// theImport (: binds+ [via ,])?
class ImportBinder : Node
{
    Import theImport;
    ImportBind[] binds;  // Optional.
}

// name (= aliasName)?
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
