/**
 * Copyright 2010-2011 Bernard Helyer.
 * This file is part of SDC.
 * See LICENCE or sdc.d for more details.
 */
module sdc.ast.sdcclass;

import sdc.ast.base;
import sdc.ast.sdcmodule;


// class <Identifier> <BaseClassList>? <ClassBody>
class ClassDeclaration : Node
{
    Identifier identifier;
    BaseClassList baseClassList;  // Optional.
    ClassBody classBody;
}

// (: <SuperClass>, <Interfaces>?)
class BaseClassList : Node
{
    QualifiedName superClass;  // Optional.
    QualifiedName[] interfaceClasses;
}

// { DeclarationDefinition* }
class ClassBody : Node
{
    DeclarationDefinition[] declarations;
}
