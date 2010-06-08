/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdl.d for more details.
 */
module sdc.ast.declaration;

import sdc.tokenstream;
import sdc.ast.base;
import sdc.ast.expression;


class Declaration : Node
{
    bool isAlias;
    StorageClass[] storageClasses;  // Optional.
    BasicType basicType;  // Optional, if there is a StorageClass.
    Declarators declarators;  // Optional.
}

class Type : Node
{
    BasicType basicType;
    Declarator2 declarator2;
}

// DeclaratorInitialiser (, DeclaratorIdentifier (, DeclaratorIdentifier)*)?
class Declarators : Node
{
    DeclaratorInitialiser declaratorInitialiser;
    DeclaratorIdentifier[] declaratorIdentifiers;
}

// Declarator (= Initialiser)?
class DeclaratorInitialiser : Node
{
    Declarator declarator;
    Initialiser initialiser;
}

class DeclaratorIdentifier : Node
{
    Identifier identifier;
    Initialiser initialiser;
}

class Declarator2 : Node
{
    BasicType2 basicType2;
    Declarator2 declarator2;
    DeclaratorSuffix[] declaratorSuffixes;  // Optional.
}

enum DeclaratorSuffixType
{
    DynamicArray,
    StaticArray,
    AssociativeArray,
    TemplateParameters,
}

class DeclaratorSuffix : Node
{
    DeclaratorSuffixType suffixType;
    AssignExpression assignExpression;
    Type type;
    // TODO: Template stuff.
}

class Declarator : Node
{
    BasicType2 basicType2;  // Optional.
    Declarator declarator;  // Optional.
    Identifier identifier;  // Optional.
    DeclaratorSuffix[] declaratorSuffixes;  // Optional.
}

enum BasicType2Type
{
    Pointer,
    DynamicArray,
    StaticArray,
    TupleSlice,
    AssociativeArray,
    Delegate,
    Function,
}

enum FunctionAttribute
{
    Nothrow,
    Pure,
}

class BasicType2 : Node
{
    BasicType2Type type;
    AssignExpression firstAssignExpression;  // Optional.
    AssignExpression secondAssignExpression;  // Optional.
    Type aaType;  // Optional.
    Parameters parameters;  // Optional.
    FunctionAttribute[] functionAttributes;  // Optional.
}

enum StorageClassType
{
    Abstract,
    Auto,
    Const,
    Deprecated,
    Extern,
    Final,
    Immutable,
    Inout,
    Shared,
    Nothrow,
    Override,
    Pure,
    Scope,
    Static,
    Synchronized,
}

class StorageClass : Node
{
    StorageClassType type;
}

enum BasicTypeType
{
    Bool,
    Byte,
    Ubyte,
    Short,
    Ushort,
    Int,
    Uint,
    Long,
    Ulong,
    Char,
    Wchar,
    Dchar,
    Float,
    Double,
    Real,
    Ifloat,
    Idouble,
    Ireal,
    Cfloat,
    Cdouble,
    Creal,
    Void,
    GlobalIdentifierList,
    IdentifierList,
    Typeof,
    TypeofIdentifierList,
    Const,
    Immutable,
    Shared,
    Inout,
}

class BasicType : Node
{
    BasicTypeType type;
    Type secondType;
}

class Initialiser : Node
{
    // Mutually exclusive.
    VoidInitialiser voidInitialiser;
    NonVoidInitialiser nonVoidInitialiser;
}

class VoidInitialiser : Node
{
}

class NonVoidInitialiser : Node
{
    AssignExpression assignExpression;
    ArrayInitialiser arrayInitialiser;
    StructInitialiser structInitialiser;
}

// [ (ArrayMemberInitialisation (, ArrayMemberInitialisation)*)? ]
class ArrayInitialiser : Node
{
    ArrayMemberInitialisation[] arrayMemberInitialisations;
}

// NonVoidInitialiser | AssignExpression : NonVoidInitialiser
class ArrayMemberInitialisation : Node
{
    NonVoidInitialiser nonVoidInitialiser;
    AssignExpression assignExpression;  // 
}

// { (StructMemberInitialiser (, StructMemberInitialiser)*)? }
class StructInitialiser : Node
{
    StructMemberInitialiser[] structMemberInitialisers;  // Optional.
}

// (Identifier :)? NonVoidInitialiser
class StructMemberInitialiser : Node
{
    NonVoidInitialiser nonVoidInitialiser;
    Identifier identifier;  // Optional
}

// \( (Parameter (, Parameter)*)? \)
class Parameters : Node
{
    Parameter[] parameters;
}

enum InOutType
{
    None,
    In,
    Out,
    Ref,
    Lazy,
}

class Parameter : Node
{
    InOutType inOutType; 
    /* !!!
     * The grammar says that a parameter has a declarator. This has
     * two problems. Firstly, a Declarator doesn't include a BasicType.
     * And secondly, a Declarator requires an Identifier. The following
     * (valid) function definition requires the former, and doesn't have
     * the latter:
     * 
     * int function(int, int) a;
     * 
     * So I've replaced the Declarator with BasicType and BasicType2.
     */
    //Declarator declarator; 
    BasicType basicType;
    BasicType2[] basicType2;  // Optional.
    DefaultInitialiserExpression defaultInitialiserExpression;  // Optional.
}

enum DefaultInitialiserExpressionType
{
    Assign,
    __File__,
    __Line__,
}

class DefaultInitialiserExpression : Node
{
    DefaultInitialiserExpressionType type;
    AssignExpression assignExpression;  // Optional.
}
