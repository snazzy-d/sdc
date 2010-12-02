/**
 * Copyright 2010 Bernard Helyer.
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
    SuperClass superClass;  // Optional.
    InterfaceClass[] interfaceClasses;
}

enum Protection
{
    None,
    Private,
    Package,
    Public,
    Export
}

// <Protection> <Identifier>
class SuperClass : Node
{
    Protection protection;
    Identifier identifier;
}

// <Protection> <Identifier>
class InterfaceClass : Node
{
    Protection protection;
    Identifier identifier;
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
