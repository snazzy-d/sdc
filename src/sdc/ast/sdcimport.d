/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC.
 * See LICENCE or sdc.d for more details.
 */
module sdc.ast.sdcimport;

import sdc.ast.base;
import sdc.ast.visitor;


// static? import (\(Identifier\) stringliterallist | importList);
class ImportDeclaration : Node
{
    bool isStatic;
    bool isSynthetic;
    ImportList importList;  // Not if the below exist.
    Language language = Language.D;  // Optional.
    StringLiteral[] languageImports;  // Optional.

    override void accept(AstVisitor visitor)
    {
        if (importList !is null) importList.accept(visitor);
        foreach (imp; languageImports) {
            imp.accept(visitor);
        }
        visitor.visit(this);
    }
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

    override void accept(AstVisitor visitor)
    {
        foreach (imp; imports) {
            imp.accept(visitor);
        }
        binder.accept(visitor);
        visitor.visit(this);
    }
}

// theImport (: binds+ [via ,])?
class ImportBinder : Node
{
    Import theImport;
    ImportBind[] binds;  // Optional.

    override void accept(AstVisitor visitor)
    {
        theImport.accept(visitor);
        foreach (bind; binds) {
            bind.accept(visitor);
        }
        visitor.visit(this);
    }
}

// (aliasName =)? name
class ImportBind : Node
{
    Identifier name;
    Identifier aliasName;  // Optional.

    override void accept(AstVisitor visitor)
    {
        name.accept(visitor);
        if (aliasName !is null) aliasName.accept(visitor);
        visitor.visit(this);
    }
}

// (moduleAlias =)? moduleName
class Import : Node
{
    QualifiedName moduleName;
    Identifier moduleAlias;  // Optional.

    override void accept(AstVisitor visitor)
    {
        moduleName.accept(visitor);
        if (moduleAlias !is null) moduleAlias.accept(visitor);
        visitor.visit(this);
    }
}
