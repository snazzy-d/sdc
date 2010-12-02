/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.ast.sdctemplate;

import sdc.ast.base;
import sdc.ast.declaration;
import sdc.ast.expression;
import sdc.ast.sdcmodule;
import sdc.gen.value;
import sdc.gen.sdctemplate;


/*
 * Declaration.
 */

// template Identifier ( TemplateParameterList ) Constraint
class TemplateDeclaration : Node
{
    Identifier templateIdentifier;
    TemplateParameterList parameterList;
    Constraint constraint;  // Optional.
    DeclarationDefinition[] declDefs;
    
    // For codegen.
    TemplateCacheNode cacheTree;
}

// TemplateParameter (, TemplateParameter)?
class TemplateParameterList : Node
{
    TemplateParameter[] parameters;
}

enum TemplateParameterType
{
    Type,
    Value,
    Alias,
    Tuple,
    This
}

// One of the above.
class TemplateParameter : Node
{
    TemplateParameterType type;
    Node node;
}

// Identifier (: Specialisation)? (= Default)? 
class TemplateTypeParameter : Node
{
    Identifier identifier;
    Type specialisation;  // Optional.
    Type parameterDefault;  // Optional.
}

class TemplateValueParameter : Node
{
    VariableDeclaration declaration;
    ConditionalExpression specialisation;  // Optional.
    TemplateValueParameterDefault parameterDefault;  // Optional.
}

// : ConditionalExpression
class TemplateValueParameterSpecialisation : Node
{
    ConditionalExpression expression;
}

enum TemplateValueParameterDefaultType
{
    __File__,
    __Line__,
    ConditionalExpression
}

class TemplateValueParameterDefault : Node
{
    TemplateValueParameterDefaultType type;
    ConditionalExpression expression;  // Optional.
}

class TemplateAliasParameter : Node
{
    Identifier identifier;
    Type specialisation;  // Optional.
    Type parameterDefault;  // Optional.
}

class TemplateTupleParameter : Node
{
    Identifier identifier;
}

class TemplateThisParameter : Node
{
    TemplateTypeParameter templateTypeParameter;
}

class Constraint : Node
{
    Expression expression;
}

/*
 * Instantiation.
 */

// TemplateIdentifier ! (\( TemplateArgument+ \)| TemplateArgument
class TemplateInstance : Node
{
    Identifier identifier;
    TemplateArgument[] arguments;  // Optional.
    TemplateSingleArgument argument;  // Optional.
}

enum TemplateArgumentType
{
    Type,
    AssignExpression,
    Symbol
}

class TemplateArgument : Node
{
    TemplateArgumentType type;
    Node node;
}

class Symbol : Node
{
    bool leadingDot;
    SymbolTail tail;
}

enum SymbolTailType
{
    Identifier,
    TemplateInstance
}

class SymbolTail : Node
{
    SymbolTailType type;
    Node node;
    SymbolTail tail;
}

enum TemplateSingleArgumentType
{
    Identifier,
    BasicType,
    CharacterLiteral,
    StringLiteral,
    IntegerLiteral,
    FloatLiteral,
    True,
    False,
    Null,
    __File__,
    __Line__
}

class TemplateSingleArgument : Node
{
    TemplateSingleArgumentType type;
    Node node;  // Optional
}
