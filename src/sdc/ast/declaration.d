/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC.
 * See LICENCE or sdc.d for more details.
 */
module sdc.ast.declaration;

import sdc.token;
import sdc.ast.base;
import sdc.ast.expression;
import sdc.ast.statement;
import sdc.ast.attribute;
import sdc.ast.sdctemplate;
import sdc.ast.visitor;


enum DeclarationType
{
    Variable,
    Function,
    FunctionTemplate,
    Alias,
    AliasThis,
    Mixin,
}

class Declaration : Node
{
    DeclarationType type;
    Node node;

    override void accept(AstVisitor visitor)
    {
        node.accept(visitor);
        visitor.visit(this);
    }
}

class MixinDeclaration : Node
{
    ConditionalExpression expression;
    Declaration declarationCache;

    override void accept(AstVisitor visitor)
    {
        expression.accept(visitor);
        declarationCache.accept(visitor);
        visitor.visit(this);
    }
}

class VariableDeclaration : Node
{
    bool isAlias;
    bool isExtern;
    Type type;
    Declarator[] declarators;

    override void accept(AstVisitor visitor)
    {
        type.accept(visitor);
        foreach (decl; declarators) {
            decl.accept(visitor);
        }
        visitor.visit(this);
    }
}

class Declarator : Node
{
    Identifier name;
    Initialiser initialiser;  // Optional.

    override void accept(AstVisitor visitor)
    {
        name.accept(visitor);
        if (initialiser !is null) initialiser.accept(visitor);
        visitor.visit(this);
    }
}

class ParameterList : Node
{
    Parameter[] parameters;
    bool varargs = false;

    override void accept(AstVisitor visitor)
    {
        foreach (param; parameters) {
            param.accept(visitor);
        }
        visitor.visit(this);
    }
}
    
class FunctionDeclaration : Node
{
    Type returnType;
    QualifiedName name;
    ParameterList parameterList;
    FunctionBody functionBody;  // Optional.
    FunctionBody inContract; // Optional.
    FunctionBody outContract; // Optional.

    override void accept(AstVisitor visitor)
    {
        returnType.accept(visitor);
        name.accept(visitor);
        parameterList.accept(visitor);
        if (functionBody !is null) functionBody.accept(visitor);
        if (inContract !is null) inContract.accept(visitor);
        if (outContract !is null) outContract.accept(visitor);
        visitor.visit(this);
    }
}

enum FunctionBodyType
{
	In,
	Out,
	Body,
}

class FunctionBody : Node
{
    FunctionBodyType bodyType;
    Statement[] statements;

    override void accept(AstVisitor visitor)
    {
        foreach (statement; statements) {
            statement.accept(visitor);
        }
        visitor.visit(this);
    }
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
TokenType.Const, TokenType.Immutable, TokenType.Shared, TokenType.Inout,
TokenType.Function,
];


class Type : Node
{
    TypeType type;
    Node node;
    StorageType[] storageTypes;
    TypeSuffix[] suffixes;
    bool ctor = false;
    bool dtor = false;

    override void accept(AstVisitor visitor)
    {
        if (node !is null) node.accept(visitor);
        foreach (suffix; suffixes) {
            suffix.accept(visitor);
        }
        visitor.visit(this);
    }
}

enum TypeSuffixType
{
    Pointer,
    Array,
}

class TypeSuffix : Node
{
    TypeSuffixType type;
    Node node;  // Optional.

    override void accept(AstVisitor visitor)
    {
        if (node !is null) node.accept(visitor);
        visitor.visit(this);
    }
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

    override void accept(AstVisitor visitor)
    {
        visitor.visit(this);
    }
}

class UserDefinedType : Node
{
    IdentifierOrTemplateInstance[] segments;

    override void accept(AstVisitor visitor)
    {
        foreach (segment; segments) {
            segment.accept(visitor);
        }
        visitor.visit(this);
    }
}

class IdentifierOrTemplateInstance : Node
{
    bool isIdentifier;
    Node node;

    override void accept(AstVisitor visitor)
    {
        node.accept(visitor);
        visitor.visit(this);
    }
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

    override void accept(AstVisitor visitor)
    {
        if (expression !is null) expression.accept(visitor);
        if (qualifiedName !is null) qualifiedName.accept(visitor);
        visitor.visit(this);
    }
}

class FunctionPointerType : Node
{
    Type returnType;
    ParameterList parameters;

    override void accept(AstVisitor visitor)
    {
        returnType.accept(visitor);
        parameters.accept(visitor);
        visitor.visit(this);
    }
}

class DelegateType : Node
{
    Type returnType;
    ParameterList parameters;

    override void accept(AstVisitor visitor)
    {
        returnType.accept(visitor);
        parameters.accept(visitor);
        visitor.visit(this);
    }
}

enum ParameterAttribute
{
    None,
    In,
    Out,
    Ref,
    Lazy,
}

class Parameter : Node
{
    ParameterAttribute attribute;
    Type type;
    Identifier identifier;  // Optional.
    bool defaultArgumentFile = false;  // Optional.
    bool defaultArgumentLine = false;  // Optional.
    ConditionalExpression defaultArgument;  // Optional.

    override void accept(AstVisitor visitor)
    {
        type.accept(visitor);
        if (identifier !is null) identifier.accept(visitor);
        if (defaultArgument !is null) defaultArgument.accept(visitor);
        visitor.visit(this);
    }
}

enum InitialiserType
{
    Void,
    AssignExpression
}

class Initialiser : Node
{
    InitialiserType type;
    Node node; // Optional.

    override void accept(AstVisitor visitor)
    {
        if (node !is null) node.accept(visitor);
        visitor.visit(this);
    }
}

