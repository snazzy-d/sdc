/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 * 
 * sdc.ast.declaration: AST nodes for declarations.
 */
module sdc.ast.declaration;

import sdc.tokenstream;
import sdc.primitive;
import sdc.ast.base;
import sdc.ast.expression;
import sdc.ast.statement;


enum DeclarationType
{
    Variable,
    Function
}

class Declaration : Node
{
    DeclarationType type;
    Node node;
}

enum DeclType
{
    Variable,
    Function,
    SyntheticVariable
}

class Decl : Node
{
    DeclType dtype;
    Variable variable;  // Variable declaration for semantic purposes.
}

class VariableDeclaration : Decl
{
    this() { dtype = DeclType.Variable; }
    bool isAlias;
    Type type;
    Declarator[] declarators;
}

class SyntheticVariableDeclaration : Decl
{
    this() { dtype = DeclType.SyntheticVariable; }
    bool isAlias;
    bool isParameter;
    Type type;
    Identifier identifier;
    Initialiser initialiser;  // Optional.
}

class Declarator : Node
{
    Identifier name;
    Initialiser initialiser;  // Optional.
}
    
class FunctionDeclaration : Decl
{
    this() { dtype = DeclType.Function; }
    Type retval;
    Identifier name;
    Parameter[] parameters;
    FunctionBody functionBody;
}

class FunctionBody : Node
{
    BlockStatement statement;
    // TODO
}

enum TypeType
{
    Primitive,
    Inferred,
    UserDefined,
    Typeof,
    FunctionPointer,
    Delegate,
    ConstType,  // const(Type)
    ImmutableType,  // immutable(Type)
    SharedType,  // shared(Type)
    InoutType,  // inout(Type)
}

enum StorageType
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
immutable STORAGE_TYPES = [
TokenType.Abstract, TokenType.Auto, TokenType.Const,
TokenType.Deprecated, TokenType.Extern, TokenType.Final,
TokenType.Immutable, TokenType.Inout, TokenType.Shared,
TokenType.Nothrow, TokenType.Override, TokenType.Pure,
TokenType.Scope, TokenType.Static, TokenType.Synchronized
];

immutable PAREN_TYPES = [
TokenType.Const, TokenType.Immutable, TokenType.Shared, TokenType.Inout
];


class Type : Node
{
    TypeType type;
    Node node;
    StorageType[] storageTypes;
    TypeSuffix[] suffixes;
}

enum TypeSuffixType
{
    Pointer,
    DynamicArray,
    StaticArray,
    AssociativeArray
}

class TypeSuffix : Node
{
    TypeSuffixType type;
    Node node;  // Optional.
}

enum PrimitiveTypeType
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
    Cent = TokenType.Cent,
    Ucent = TokenType.Ucent,
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
}

class PrimitiveType : Node
{
    PrimitiveTypeType type;
}

class UserDefinedType : Node
{
    QualifiedName qualifiedName;
}

enum TypeofTypeType
{
    Return,
    This,
    Super,
    Expression
}

class TypeofType : Node
{
    TypeofTypeType type;
    Expression expression;  // Optional.
    QualifiedName qualifiedName;  // Optional.
}

class FunctionPointerType : Node
{
    Type retval;
    Parameter[] parameters;
}

class DelegateType : Node
{
    Type retval;
    Parameter[] parameters;
}

class Parameter : Node
{
    Type type;
    Identifier identifier;  // Optional.
}

enum InitialiserType
{
    Void,
    AssignExpression
}

class Initialiser : Node
{
    InitialiserType type;
    Node node;  // Optional.
}

