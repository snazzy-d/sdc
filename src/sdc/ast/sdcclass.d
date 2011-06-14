/**
 * Copyright 2010-2011 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.ast.sdcclass;

import sdc.ast.base;


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

// { ClassBodyDeclaration* }
class ClassBody : Node
{
    ClassBodyDeclaration[] classBodyDeclarations;
}

enum ClassBodyDeclarationType
{
    Declaration,
    Constructor,
    Destructor,
    StaticConstructor,
    StaticDestructor,
    Invariant,
    UnitTest,
    ClassAllocator,
    ClassDeallocator,
}

class ClassBodyDeclaration : Node
{
    ClassBodyDeclarationType type;
    Node node;
}
