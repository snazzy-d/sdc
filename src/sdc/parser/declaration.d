/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.parser.declaration;

import std.string;
import std.conv;
import std.contracts;

import sdc.util;
import sdc.tokenstream;
import sdc.compilererror;
import sdc.ast.declaration;
import sdc.parser.base;
import sdc.parser.expression;
import sdc.parser.statement;


Declaration parseDeclaration(TokenStream tstream)
{
    auto declaration = new Declaration();
    declaration.location = tstream.peek.location;
    
    if (isVariableDeclaration(tstream)) {
        declaration.type = DeclarationType.Variable;
        declaration.node = parseVariableDeclaration(tstream);
    } else {
        declaration.type = DeclarationType.Function;
        declaration.node = parseFunctionDeclaration(tstream);
    }
    
    return declaration;
}


/**
 * Non destructively determines if the next declaration
 * is a variable.
 */
bool isVariableDeclaration(TokenStream tstream)
{
    if (tstream.peek.type == TokenType.Alias) {
        return true;
    }
    size_t lookahead = 1;
    Token token;
    while (true) {
        token = tstream.lookahead(lookahead);
        if (token.type == TokenType.End || token.type == TokenType.OpenBrace) {
            return false;
        } else if (token.type == TokenType.Semicolon) {
            return true;
        }
        lookahead++;
    }
    assert(false);
}


VariableDeclaration parseVariableDeclaration(TokenStream tstream)
{
    auto declaration = new VariableDeclaration();
    declaration.location = tstream.peek.location;
    
    if (tstream.peek.type == TokenType.Alias) {
        match(tstream, TokenType.Alias);
        declaration.isAlias = true;
    }
    
    declaration.type = parseType(tstream);
    if (tstream.peek.type == TokenType.Function) {
        declaration.type.type = TypeType.FunctionPointer;
        declaration.type.node = parseFunctionPointerType(tstream, declaration.type);
        auto suffixes = parseTypeSuffixes(tstream, Placed.Sanely);
        declaration.type.suffixes ~= suffixes;
    } else if (tstream.peek.type == TokenType.Delegate) {
        declaration.type.type = TypeType.Delegate;
        declaration.type.node = parseDelegateType(tstream, declaration.type);
        auto suffixes = parseTypeSuffixes(tstream, Placed.Sanely);
        declaration.type.suffixes ~= suffixes;
    } else if (tstream.peek.type == TokenType.OpenParen &&
               tstream.lookahead(1).type == TokenType.Asterix) {
        // bizarro world function pointer/array declaration
        // Holy shit folks, it's a trainwreck. Forgive me.
        auto location = tstream.peek.location;
        match(tstream, TokenType.OpenParen);
        match(tstream, TokenType.Asterix);
        
        auto suffixes = parseTypeSuffixes(tstream, Placed.Sanely);
        auto declarator = new Declarator();
        declarator.location = tstream.peek.location;
        declarator.name = parseIdentifier(tstream);
        suffixes ~= parseTypeSuffixes(tstream, Placed.Insanely);
        match(tstream, TokenType.CloseParen);
        if (tstream.peek.type == TokenType.OpenParen) {
            // e.g. (*x)()
            declaration.type.type = TypeType.FunctionPointer;
            auto node = new FunctionPointerType();
            node.location = location;
            node.parameters = parseParameters(tstream);
            declaration.type.node = node;
            suffixes ~= parseTypeSuffixes(tstream, Placed.Insanely);
        } else if (tstream.peek.type == TokenType.OpenBracket) {
            // e.g. (*x)[3]
            suffixes ~= parseTypeSuffixes(tstream, Placed.Insanely);
        } else {
            error(tstream.peek.location, "expected '(' or '[', not '%s'.");
        }
        if (tstream.peek.type == TokenType.Assign) {
            declarator.initialiser = parseInitialiser(tstream);
        }
        match(tstream, TokenType.Semicolon);
        declaration.declarators ~= declarator;
        declaration.type.suffixes ~= suffixes;
        
        return declaration;
    }
        
    
    auto declarator = new Declarator();
    declarator.location = tstream.peek.location;
    declarator.name = parseIdentifier(tstream);
    auto suffixes = parseTypeSuffixes(tstream, Placed.Insanely);
    if (tstream.peek.type == TokenType.Assign) {
        declarator.initialiser = parseInitialiser(tstream);
    }
    declaration.declarators ~= declarator;
    if (suffixes.length > 0 && tstream.peek.type != TokenType.Semicolon) {
        error(tstream.peek.location, "with multiple declarations, no declaration can use a c-style type suffix.");
    }
    declaration.type.suffixes ~= suffixes;
    while (tstream.peek.type != TokenType.Semicolon) {
        match(tstream, TokenType.Comma);
        declarator = new Declarator();
        declarator.location = tstream.peek.location;
        declarator.name = parseIdentifier(tstream);
        if (tstream.peek.type == TokenType.Assign) {
            declarator.initialiser = parseInitialiser(tstream);
        }
        declaration.declarators ~= declarator;
    }
    match(tstream, TokenType.Semicolon);
    
    return declaration;
}


FunctionDeclaration parseFunctionDeclaration(TokenStream tstream)
{
    auto declaration = new FunctionDeclaration();
    declaration.location = tstream.peek.location;
    
    declaration.retval = parseType(tstream);
    declaration.name = parseIdentifier(tstream);
    declaration.parameters = parseParameters(tstream);
    declaration.functionBody = parseFunctionBody(tstream);
    
    return declaration;
}

FunctionBody parseFunctionBody(TokenStream tstream)
{
    auto functionBody = new FunctionBody();
    functionBody.location = tstream.peek.location;
    functionBody.statement = parseBlockStatement(tstream);
    return functionBody;
}

immutable TokenType[] PRIMITIVE_TYPES = [
TokenType.Bool, TokenType.Byte, TokenType.Ubyte,
TokenType.Short, TokenType.Ushort, TokenType.Int,
TokenType.Uint, TokenType.Long, TokenType.Ulong,
TokenType.Char, TokenType.Wchar, TokenType.Dchar,
TokenType.Float, TokenType.Double, TokenType.Real,
TokenType.Ifloat, TokenType.Idouble, TokenType.Ireal,
TokenType.Cfloat, TokenType.Cdouble, TokenType.Creal,
TokenType.Void ];

immutable TokenType[] STORAGE_CLASSES = [
TokenType.Abstract, TokenType.Auto, TokenType.Const,
TokenType.Deprecated, TokenType.Extern, TokenType.Final,
TokenType.Immutable, TokenType.Inout, TokenType.Shared,
TokenType.Nothrow, TokenType.Override, TokenType.Pure,
TokenType.Scope, TokenType.Static, TokenType.Synchronized
];


Type parseType(TokenStream tstream)
{
    auto type = new Type();
    type.location = tstream.peek.location;
    
    while (contains(STORAGE_TYPES, tstream.peek.type)) {
        if (contains(PAREN_TYPES, tstream.peek.type)) {
            if (tstream.lookahead(1).type == TokenType.OpenParen) {
                break;
            }
        }
        type.storageTypes ~= cast(StorageType) tstream.peek.type;
        tstream.getToken();
    }
    
    if (type.storageTypes.length > 0 &&
        tstream.peek.type == TokenType.Identifier &&
        tstream.lookahead(1).type == TokenType.Assign) {
        //    
        type.type = TypeType.Inferred;
        // TODO
    }

    if (contains(PRIMITIVE_TYPES, tstream.peek.type)) {
        type.type = TypeType.Primitive;
        type.node = parsePrimitiveType(tstream);
    } else if (tstream.peek.type == TokenType.Dot ||
               tstream.peek.type == TokenType.Identifier) {
        type.type = TypeType.UserDefined;
        type.node = parseUserDefinedType(tstream);
    } else if (tstream.peek.type == TokenType.Typeof) {
        type.type = TypeType.Typeof;
        type.node = parseTypeofType(tstream);
    } else if (tstream.peek.type == TokenType.Const) {
        type.type = TypeType.ConstType;
        match(tstream, TokenType.Const);
        match(tstream, TokenType.OpenParen);
        type.node = parseType(tstream);
        match(tstream, TokenType.CloseParen);
    } else if (tstream.peek.type == TokenType.Immutable) {
        type.type = TypeType.ImmutableType;
        match(tstream, TokenType.Immutable);
        match(tstream, TokenType.OpenParen);
        type.node = parseType(tstream);
        match(tstream, TokenType.CloseParen);
    } else if (tstream.peek.type == TokenType.Shared) {
        type.type = TypeType.SharedType;
        match(tstream, TokenType.Shared);
        match(tstream, TokenType.OpenParen);
        type.node = parseType(tstream);
        match(tstream, TokenType.CloseParen);
    } else if (tstream.peek.type == TokenType.Inout) {
        type.type = TypeType.InoutType;
        match(tstream, TokenType.Inout);
        match(tstream, TokenType.OpenParen);
        type.node = parseType(tstream);
        match(tstream, TokenType.CloseParen);
    }
    
    type.suffixes = parseTypeSuffixes(tstream, Placed.Sanely);
    
    return type;
}

enum Placed { Sanely, Insanely }
TypeSuffix[] parseTypeSuffixes(TokenStream tstream, Placed placed)
{
    auto SUFFIX_STARTS = placed == Placed.Sanely ?
                         [TokenType.Asterix, TokenType.OpenBracket] :
                         [TokenType.OpenBracket];
        
    TypeSuffix[] suffixes;
    while (contains(SUFFIX_STARTS, tstream.peek.type)) {
        auto suffix = new TypeSuffix();
        if (placed == Placed.Sanely && tstream.peek.type == TokenType.Asterix) {
            match(tstream, TokenType.Asterix);
            suffix.type = TypeSuffixType.Pointer;
        } else if (tstream.peek.type == TokenType.OpenBracket) {
            match(tstream, TokenType.OpenBracket);
            if (tstream.peek.type == TokenType.CloseBracket) {
                suffix.type = TypeSuffixType.DynamicArray;
            } else if (contains(PRIMITIVE_TYPES, tstream.peek.type) ||
                       tstream.peek.type == TokenType.Identifier ||
                       (tstream.peek.type == TokenType.Dot &&
                        tstream.lookahead(1).type == TokenType.Identifier)) {
                suffix.node = parseType(tstream);
                suffix.type = TypeSuffixType.AssociativeArray;
            } else {
                suffix.node = parseExpression(tstream);
                suffix.type = TypeSuffixType.StaticArray;
            }
            match(tstream, TokenType.CloseBracket);
        } else {
            assert(false);
        }
        suffixes ~= suffix;
    }
    return suffixes;
}

/**
 * Non-destructively determine, if the stream is on a primitive type,
 * what kind of declaration follows; a simple primitive variable,
 * a function pointer, or a delegate.
 */
TypeType typeFromPrimitive(TokenStream tstream)
in
{
    assert(contains(PRIMITIVE_TYPES, tstream.peek.type));
}
out(result)
{
    assert(result == TypeType.Primitive ||
           result == TypeType.FunctionPointer ||
           result == TypeType.Delegate);
}
body
{
    auto result = TypeType.Primitive;
    size_t lookahead = 1;
    while (true) {
        auto token = tstream.lookahead(lookahead);
        if (token.type == TokenType.OpenParen) {
            int nesting = 1;
            while (nesting > 0) {
                lookahead++;
                token = tstream.lookahead(lookahead);
                switch (token.type) {
                case TokenType.End:
                    error(tstream.peek.location, "expected declaration, got EOF.");
                    assert(false);
                case TokenType.OpenParen:
                    nesting++;
                    break;
                case TokenType.CloseParen:
                    nesting--;
                    break;
                default:
                    break;
                }
            }
            lookahead++;
        }
        if (token.type == TokenType.End) {
            error(tstream.peek.location, "expected declaration, got EOF.");
            assert(false);
        } else if (token.type == TokenType.Identifier) {
            break;
        } else if (token.type == TokenType.Delegate) {
            return TypeType.Delegate;
        } else if (token.type == TokenType.Function) {
            return TypeType.FunctionPointer;
        }
        lookahead++;
    }
    return result;
}


PrimitiveType parsePrimitiveType(TokenStream tstream)
{
    auto primitive = new PrimitiveType();
    primitive.location = tstream.peek.location;
    enforce(contains(PRIMITIVE_TYPES, tstream.peek.type));
    primitive.type = cast(PrimitiveTypeType) tstream.peek.type;
    tstream.getToken();
    return primitive;
}

UserDefinedType parseUserDefinedType(TokenStream tstream)
{
    auto type = new UserDefinedType();
    type.location = tstream.peek.location;
    type.qualifiedName = parseQualifiedName(tstream, true);
    return type;
}

TypeofType parseTypeofType(TokenStream tstream)
{
    auto type = new TypeofType();
    type.location = tstream.peek.location;
    
    match(tstream, TokenType.Typeof);
    match(tstream, TokenType.OpenParen);
    if (tstream.peek.type == TokenType.This) {
        type.type = TypeofTypeType.This;
    } else if (tstream.peek.type == TokenType.Super) {
        type.type = TypeofTypeType.Super;
    } else if (tstream.peek.type == TokenType.Return) {
        type.type = TypeofTypeType.Return;
    } else {
        type.type = TypeofTypeType.Expression;
        type.expression = parseExpression(tstream);
    }
    match(tstream, TokenType.CloseParen);
    
    if (tstream.peek.type == TokenType.Dot) {
        match(tstream, TokenType.Dot);
        type.qualifiedName = parseQualifiedName(tstream);
    }
    
    return type;
}

FunctionPointerType parseFunctionPointerType(TokenStream tstream, Type retval)
{
    auto type = new FunctionPointerType();
    type.location = tstream.peek.location;
    
    type.retval = retval;
    match(tstream, TokenType.Function);
    type.parameters = parseParameters(tstream);
    
    return type;
}

DelegateType parseDelegateType(TokenStream tstream, Type retval)
{
    auto type = new DelegateType();
    type.location = tstream.peek.location;
    
    type.retval = retval;
    match(tstream, TokenType.Delegate);
    type.parameters = parseParameters(tstream);
    
    return type;
}

Parameter[] parseParameters(TokenStream tstream)
{
    Parameter[] parameters;
    
    match(tstream, TokenType.OpenParen);
    while (tstream.peek.type != TokenType.CloseParen) {
        auto parameter = new Parameter();
        parameter.location = tstream.peek.location;
        parameter.type = parseType(tstream);
        if (tstream.peek.type == TokenType.Identifier) {
            parameter.identifier = parseIdentifier(tstream);
        }
        parameters ~= parameter;
        if (tstream.peek.type == TokenType.CloseParen) {
            break;
        }
        tstream.getToken();
    }
    match(tstream, TokenType.CloseParen);
    
    return parameters;
}

Initialiser parseInitialiser(TokenStream tstream)
{
    auto initialiser = new Initialiser();
    initialiser.location = tstream.peek.location;
    match(tstream, TokenType.Assign);
    
    switch (tstream.peek.type) {
    case TokenType.Void:
        match(tstream, TokenType.Void);
        initialiser.type = InitialiserType.Void;
        break;
    default:
        initialiser.type = InitialiserType.AssignExpression;
        initialiser.node = parseAssignExpression(tstream);
        break;
    }
    
    return initialiser;
}


bool startsLikeDeclaration(TokenStream tstream)
{
    /* TODO: this is horribly incomplete. The TokenStream should be 
     * thoroughly (but non-destructively) examined, not the simple
     * 'search through keywords' function that is here now.
     */
    auto t = tstream.peek.type;
    return t == TokenType.Alias || contains(PRIMITIVE_TYPES, t) || contains(STORAGE_CLASSES, t);
}

