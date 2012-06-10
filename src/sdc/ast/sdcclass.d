/**
 * Copyright 2010-2011 Bernard Helyer.
 * This file is part of SDC.
 * See LICENCE or sdc.d for more details.
 */
module sdc.ast.sdcclass;

import sdc.ast.base;
import sdc.ast.sdcmodule;
import sdc.ast.visitor;


// class <Identifier> <BaseClassList>? <ClassBody>
class ClassDeclaration : Node
{
    Identifier identifier;
    BaseClassList baseClassList;  // Optional.
    ClassBody classBody;

    override void accept(AstVisitor visitor)
    {
        identifier.accept(visitor);
        if (baseClassList !is null) baseClassList.accept(visitor);
        classBody.accept(visitor);
        visitor.visit(this);
    }
}

// (: <SuperClass>, <Interfaces>?)
class BaseClassList : Node
{
    QualifiedName superClass;  // Optional.
    QualifiedName[] interfaceClasses;

    override void accept(AstVisitor visitor)
    {
        if (superClass !is null) superClass.accept(visitor);
        foreach (c; interfaceClasses) {
            c.accept(visitor);
        }
        visitor.visit(this);
    }
}

// { DeclarationDefinition* }
class ClassBody : Node
{
    DeclarationDefinition[] declarations;

    override void accept(AstVisitor visitor)
    {
        foreach (decl; declarations) {
            decl.accept(visitor);
        }
        visitor.visit(this);
    }
}
