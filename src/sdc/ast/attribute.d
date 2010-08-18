/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.ast.attribute;

import sdc.token;
import sdc.ast.base;
import sdc.ast.expression;
import sdc.ast.sdcmodule;


enum AttributeType
{
    Deprecated = TokenType.Deprecated,
    
    Private = TokenType.Private,
    Package = TokenType.Package,
    Protected = TokenType.Protected,
    Public = TokenType.Public,
    Export = TokenType.Export,
    
    Static = TokenType.Static,
    Final = TokenType.Final,
    Override = TokenType.Override,
    Abstract = TokenType.Abstract,
    Const = TokenType.Const,
    Auto = TokenType.Auto,
    Scope = TokenType.Scope,
    __Gshared = TokenType.__Gshared,
    Shared = TokenType.Shared,
    Immutable = TokenType.Immutable,
    Inout = TokenType.Inout,
    atDisable = TokenType.atDisable,
    
    Align = TokenType.Align,
    Pragma = TokenType.Pragma,
    
    Extern = TokenType.Extern,
    ExternC = TokenType.End + 1,
    ExternCPlusPlus,
    ExternD,
    ExternWindows,
    ExternPascal,
    ExternSystem,
}

enum Linkage
{
    ExternC = AttributeType.ExternC,
    ExternCPlusPlus,
    ExternD,
    ExternWindows,
    ExternPascal,
    ExternSystem,
}

immutable ATTRIBUTE_KEYWORDS = [
TokenType.Deprecated, TokenType.Private, TokenType.Package,
TokenType.Protected, TokenType.Public, TokenType.Export,
TokenType.Static, TokenType.Final, TokenType.Override,
TokenType.Abstract, TokenType.Const, TokenType.Auto,
TokenType.Scope, TokenType.__Gshared, TokenType.Shared,
TokenType.Immutable, TokenType.Inout, TokenType.atDisable,
TokenType.Align, TokenType.Pragma, TokenType.Extern
];

immutable ACCESS = [
AttributeType.Public, AttributeType.Protected, AttributeType.Private,
AttributeType.Package, AttributeType.Export
];

// Attribute (:|DeclarationBlock)
class AttributeSpecifier : Node
{
    Attribute attribute;
    DeclarationBlock declarationBlock;  // Optional.
}

class Attribute : Node
{
    AttributeType type;
    Node node;  // Optional.
}

class AlignAttribute : Node
{
    IntegerLiteral integerLiteral;  // Optional.
}

class PragmaAttribute : Node
{
    Identifier identifier;
    ArgumentList argumentList;  // Optional.
}

// DeclarationDefinition | { DeclarationDefinition* }
class DeclarationBlock : Node
{
    DeclarationDefinition[] declarationDefinitions;
}
