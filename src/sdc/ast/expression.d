/**
 * Copyright 2010-2012 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 * TODO: AssignExpr has been replaced with ConditionalExpr. Update the comments.
 */
module sdc.ast.expression;

import sdc.token;
import sdc.ast.base;
import sdc.ast.declaration;


// AssignExpression (, Expression)?
class Expression : Node
{
    ConditionalExpression conditionalExpression;
    Expression expression;  // Optional.
}

// binaryExpression (? Expression : ConditionalExpression)?
class ConditionalExpression : Node
{
    BinaryExpression binaryExpression;
    Expression expression;  // Optional.
    ConditionalExpression conditionalExpression;  // Optional.
}

// These are in order of least to greatest precedence.
enum BinaryOperation
{
    None,
    Assign,  // =
    AddAssign,  // +=
    SubAssign,  // -=
    MulAssign,  // *=
    DivAssign,  // /=
    ModAssign,  // %=
    AndAssign,  // &=
    OrAssign,   // |=
    XorAssign,  // ^=
    CatAssign,  // ~=
    ShiftLeftAssign,  // <<=
    SignedShiftRightAssign,  // >>=
    UnsignedShiftRightAssign,  // >>>=
    PowAssign,  // ^^=
    LogicalOr,  // ||
    LogicalAnd,  // &&
    BitwiseOr,  // |
    BitwiseXor,  // ^
    BitwiseAnd,  // &
    Equality,  // == 
    NotEquality,  // !=
    Is,  // is
    NotIs,  // !is
    In,  // in
    NotIn,  // !in
    Less,  // <
    LessEqual,  // <=
    Greater,  // >
    GreaterEqual,  // >=
    Unordered,  // !<>=
    UnorderedEqual,  // !<>
    LessGreater,  // <>
    LessEqualGreater,  // <>=
    UnorderedLessEqual,  // !>
    UnorderedLess, // !>=
    UnorderedGreaterEqual,  // !<
    UnorderedGreater,  // !<=
    LeftShift,  // <<
    SignedRightShift,  // >>
    UnsignedRightShift,  // >>>
    Addition,  // +
    Subtraction,  // -
    Concat,  // ~
    Division,  // /
    Multiplication,  // *
    Modulus,  // %
    Pow,  // ^^
}

bool isLeftAssociative(BinaryOperation operator)
{
    return operator != BinaryOperation.Assign;
}

bool undergoesIntegralPromotion(BinaryOperation operation)
{
    switch (operation) with (BinaryOperation) {
    case AddAssign, SubAssign, MulAssign, DivAssign, ModAssign,
         AndAssign, OrAssign, XorAssign,
         ShiftLeftAssign, SignedShiftRightAssign, UnsignedShiftRightAssign,
         BitwiseOr, BitwiseXor, BitwiseAnd, Less, LessEqual,
         Greater, GreaterEqual, Unordered, UnorderedEqual, LessGreater,
         LessEqualGreater, UnorderedLessEqual, UnorderedLess,
         UnorderedGreaterEqual, UnorderedGreater, LeftShift, SignedRightShift,
         UnsignedRightShift, Addition, Multiplication, Division, Subtraction,
         Modulus:
        return true;
    default:
        return false;
    }   
}

class BinaryExpression : Node
{
    UnaryExpression v;
    BinaryOperation operation;
    BinaryExpression rhs;  // Optional.
}

enum UnaryPrefix
{
    None,
    AddressOf,  // &
    PrefixInc,  // ++
    PrefixDec,  // --
    Dereference,  // *
    UnaryPlus,  // +
    UnaryMinus,  // -
    LogicalNot,  // !
    BitwiseNot,  // ~
    Cast,  // cast (type) unaryExpr
    New,
}

class UnaryExpression : Node
{
    PostfixExpression postfixExpression;  // Optional.
    UnaryPrefix unaryPrefix;
    UnaryExpression unaryExpression;  // Optional.
    NewExpression newExpression;  // Optional.
    CastExpression castExpression;  // Optional.
}

class NewExpression : Node
{
    Type type;  // new *
    ConditionalExpression conditionalExpression;  // new blah[*]
    ArgumentList argumentList;  // new blah(*)
}

// cast ( Type ) UnaryExpression
class CastExpression : Node
{
    Type type;
    UnaryExpression unaryExpression;
}

enum PostfixType
{
    Primary,
    Dot,  // . QualifiedName  // XXX: specs say a new expression can go here: DMD disagrees.
    PostfixInc,  // ++
    PostfixDec,  // --
    Parens,  // ( ArgumentList* )
    Index,  // [ ArgumentList ]
    Slice,  // [ (ConditionalExpression .. ConditionalExpression)* ]
}

// PostfixExpression (. Identifier|++|--|(ArgumentList)|[ArgumentList]|[ConditionalExpression .. ConditionalExpression)
class PostfixExpression : Node
{
    PostfixType type;
    PostfixExpression postfixExpression;  // Optional.
    Node firstNode;  // Optional.
    Node secondNode;  // Optional.
}

class ArgumentList : Node
{
    ConditionalExpression[] expressions;
}

enum PrimaryType
{
    Identifier,
    GlobalIdentifier,  // . Identifier
    TemplateInstance,
    This,
    Super,
    Null,
    True,
    False,
    Dollar,
    __File__,
    __Line__,
    IntegerLiteral,
    FloatLiteral,
    CharacterLiteral,
    StringLiteral,
    ArrayLiteral,
    AssocArrayLiteral,
    FunctionLiteral,
    AssertExpression,
    MixinExpression,
    ImportExpression,
    BasicTypeDotIdentifier,
    ComplexTypeDotIdentifier,
    Typeof,
    TypeidExpression,
    IsExpression,
    ParenExpression,
    TraitsExpression,
}

class PrimaryExpression : Node
{
    PrimaryType type;
    
    /* What should be instantiated here depends 
     * on the above primary expression type.
     */
    Node node;
    Node secondNode;  // Optional.
}

// [ (AssignExpr, )* ]
class ArrayExpression : Node
{
    ConditionalExpression[] elements;
}

// [ KeyValuePair (, KeyValuePair)* ]
class AssocArrayExpression : Node
{
    KeyValuePair[] elements;
}

// AssignExpr : AssignExpr
class KeyValuePair : Node
{
    ConditionalExpression key;
    ConditionalExpression value;
}

// assert ( AssignExpr (, AssignExpr)? )
class AssertExpression : Node
{
    ConditionalExpression condition;
    ConditionalExpression message;  // Optional.
}

// mixin ( AssertExpr )
class MixinExpression : Node
{
    ConditionalExpression conditionalExpression;
}

// import ( ConditionalExpression )
class ImportExpression : Node
{
    ConditionalExpression conditionalExpression;
}

enum TypeofExpressionType
{
    Expression,
    Return,
}

class TypeofExpression : Node
{
    TypeofExpressionType type;
    Expression expression;  // Optional.
}

class TypeidExpression : Node
{
    // Mutually exclusive.
    Type type;
    Expression expression;
}

enum IsOperation
{
    SemanticCheck,  // is(T)
    ImplicitType,  // is(foo : t)
    ExplicitType,  // is(foo == t)
}

enum IsSpecialisation
{
    Type,
    Struct = TokenType.Struct,
    Union = TokenType.Union,
    Class = TokenType.Class,
    Interface = TokenType.Interface,
    Enum = TokenType.Enum,
    Function = TokenType.Function,
    Delegate = TokenType.Delegate,
    Super = TokenType.Super,
    Const = TokenType.Const,
    Immutable = TokenType.Immutable,
    Inout = TokenType.Inout,
    Shared = TokenType.Shared,
    Return = TokenType.Return,
}

class IsExpression : Node
{
    IsOperation operation;
    Type type;
    Identifier identifier;  // Optional.
    IsSpecialisation specialisation; // Optional.
    Type specialisationType; // Optional.
    // TODO: Template pararameters.
}

enum TraitsKeyword
{
    isAbstractClass,
    isArithmetic,
    isAssociativeArray,
    isFinalClass,
    isFloating,
    isIntegral,
    isScalar,
    isStaticArray,
    isUnsigned,
    isVirtualFunction,
    isAbstractFunction,
    isFinalFunction,
    isStaticFunction,
    isRef,
    isOut,
    isLazy,
    hasMember,
    identifier,
    getMember,
    getOverloads,
    getVirtualFunctions,
    classInstanceSize,
    allMembers,
    derivedMembers,
    isSame,
    compiles,
}


class TraitsExpression : Node
{
    TraitsKeyword keyword;
    TraitsArguments traitsArguments;
}

class TraitsArguments : Node
{
    TraitsArgument traitsArgument;
    TraitsArguments traitsArguments;  // Optional.
}

class TraitsArgument : Node
{
    // Mutually exclusive.
    Type type;
    ConditionalExpression conditionalExpression;
}
