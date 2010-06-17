/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 * 
 * sdc.ast.declaration: AST nodes for declarations.
 */
module sdc.ast.declaration;

import sdc.tokenstream;
import sdc.ast.base;
import sdc.ast.expression;


class Declaration : Node
{
    bool isAlias;
    StorageClass[] storageClasses;  // Optional.
    BasicType basicType;  // Optional.
    Declarators declarators;  // Optional.
    
    // These are for auto declarations. If one is non-null they both have to be.
    Identifier autoIdentifier;
    AssignExpression autoAssignExpression;
    
    // TODO: FunctionBody
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
    Initialiser initialiser;  // Optional.
}

// Identifier (= Initialiser)?
class DeclaratorIdentifier : Node
{
    Identifier identifier;
    Initialiser initialiser;  // Optional.
}

class Declarator2 : Node
{
    BasicType2[] basicType2s;
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
    BasicType2[] basicType2s;  // Optional.
    Identifier identifier;  // Optional if declarator isn't null.
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
    Abstract = TokenType.Abstract,
    Auto = TokenType.Auto,
    Const = TokenType.Const,
    Deprecated = TokenType.Deprecated,
    Extern = TokenType.Extern,
    Final = TokenType.Final,
    Immutable = TokenType.Immutable,
    Inout = TokenType.Inout,
    Shared = TokenType.Shared,
    Nothrow = TokenType.Nothrow,
    Override = TokenType.Override,
    Pure = TokenType.Pure,
    Scope = TokenType.Scope,
    Static = TokenType.Static,
    Synchronized = TokenType.Synchronized,
}

class StorageClass : Node
{
    StorageClassType type;
}

enum BasicTypeType
{
    Bool = TokenType.Bool,
    Byte = TokenType.Byte,
    Ubyte = TokenType.Ubyte,
    Short = TokenType.Short,
    Ushort = TokenType.Ushort,
    Int = TokenType.Int,
    Uint = TokenType.Uint,
    Long = TokenType.Long,
    Ulong = TokenType.Ulong,
    Char = TokenType.Char,
    Wchar = TokenType.Wchar,
    Dchar = TokenType.Dchar,
    Float = TokenType.Float,
    Double = TokenType.Double,
    Real = TokenType.Real,
    Ifloat = TokenType.Ifloat,
    Idouble = TokenType.Idouble, 
    Ireal = TokenType.Ireal,
    Cfloat = TokenType.Cfloat,
    Cdouble = TokenType.Cdouble,
    Creal = TokenType.Creal,
    Void = TokenType.Void,
    
    // These four have to have a paren immediately following.
    Const = TokenType.Const,
    Immutable = TokenType.Immutable,
    Shared = TokenType.Shared,
    Inout = TokenType.Inout,
    
    GlobalIdentifierList = TokenType.End + 1,
    IdentifierList,
    Typeof,
    TypeofIdentifierList,
}

immutable ONE_WORD_TYPES = [
TokenType.Bool, TokenType.Byte, TokenType.Ubyte, TokenType.Short,
TokenType.Ushort, TokenType.Int, TokenType.Uint, TokenType.Long,
TokenType.Ulong, TokenType.Char, TokenType.Wchar, TokenType.Dchar,
TokenType.Float, TokenType.Double, TokenType.Real, TokenType.Ifloat,
TokenType.Idouble, TokenType.Ireal, TokenType.Cfloat, TokenType.Cdouble,
TokenType.Creal, TokenType.Void
];

immutable PAREN_TYPES = [
TokenType.Const,  TokenType.Immutable, TokenType.Shared, TokenType.Inout,
];

immutable IDENTIFIER_TYPEOF_TYPES = [
TokenType.Dot, TokenType.Identifier, TokenType.Typeof
];

class BasicType : Node
{
    BasicTypeType type;
    Type secondType;  // Optional.
    QualifiedName qualifiedName;  // Optional.
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

// NonVoidInitialiser (: NonVoidInitialiser)?
class ArrayMemberInitialisation : Node
{
    NonVoidInitialiser left;
    NonVoidInitialiser right;  // Optional.
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
    In = TokenType.In,
    Out = TokenType.Out,
    Ref = TokenType.Ref,
    Lazy = TokenType.Lazy,
}

/* This is a parameter for a function/delegate variable declaration,
 * so we don't have a declarator or default initialiser here, as is
 * specified in the D grammar (!!! - no basic type listed)
 */
class Parameter : Node
{
    InOutType inOutType; 
    BasicType basicType;
    BasicType2[] basicType2s;  // Optional.
    Identifier identifier;  // Optional.
}

enum DefaultInitialiserExpressionType
{
    Assign = TokenType.__File__ - 1,
    __File__ = TokenType.__File__,
    __Line__ = TokenType.__Line__,
}

class DefaultInitialiserExpression : Node
{
    DefaultInitialiserExpressionType type;
    AssignExpression assignExpression;  // Optional.
}
