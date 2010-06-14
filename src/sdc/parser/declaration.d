/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.parser.declaration;

import std.string;
import std.conv;

import sdc.util;
import sdc.tokenstream;
import sdc.compilererror;
import sdc.ast.declaration;
import sdc.parser.base;
import sdc.parser.expression;


Declaration parseDeclaration(TokenStream tstream)
{
    auto decl = new Declaration();
    decl.location = tstream.peek.location;
    
    if (tstream.peek.type == TokenType.Alias) {
        match(tstream, TokenType.Alias);
        decl.isAlias = true;
    }
    
    while (startsLikeStorageClass(tstream)) {
        decl.storageClasses ~= parseStorageClass(tstream);
    }
    
    // auto declaration: '<storage> <identifier> <=> <assignexpr>'
    if (decl.storageClasses.length >= 1 &&
    tstream.peek.type == TokenType.Identifier &&
    tstream.lookahead(1).type == TokenType.Assign) {
        decl.autoIdentifier = parseIdentifier(tstream);
        match(tstream, TokenType.Assign);
        if (decl.isAlias) {
            error(decl.location, "alias declaration cannot have an initialiser");
        }
        decl.autoAssignExpression = parseAssignExpression(tstream);
        match(tstream, TokenType.Semicolon);
    } else {
        decl.basicType = parseBasicType(tstream);
        decl.declarators = parseDeclarators(tstream);
        if (decl.isAlias && decl.declarators !is null) {
            if (decl.declarators.declaratorInitialiser.initialiser !is null) {
                error(decl.location, "alias declaration cannot have an initaliser");
            }
        }
    }
    // TODO FunctionBody
    
    return decl;
}

StorageClass parseStorageClass(TokenStream tstream)
{
    auto storageClass = new StorageClass();
    storageClass.location = tstream.peek.location;
    storageClass.type = cast(StorageClassType) tstream.peek.type;
    match(tstream, cast(TokenType) storageClass.type);
    return storageClass;
}

bool startsLikeStorageClass(TokenStream tstream)
{
    immutable TokenType[] SimpleStorageClasses =
        [TokenType.Abstract, TokenType.Auto, 
        TokenType.Deprecated, TokenType.Extern, TokenType.Final,
        TokenType.Nothrow, TokenType.Override, TokenType.Pure,
        TokenType.Scope, TokenType.Static, TokenType.Synchronized];
    immutable ComplicatedStorageClasses =
        [TokenType.Const, TokenType.Shared, TokenType.Immutable,
        TokenType.Inout];
        
    if (contains(SimpleStorageClasses, tstream.peek.type)) {
        return true;
    } else if (contains(ComplicatedStorageClasses, tstream.peek.type)) {
        if (tstream.lookahead(1).type == TokenType.OpenParen) {
            /* For example, 'const(int)' should be parsed
             * as a type -- not a storage class.
             */   
            return false;
        }
        return true;
    }
    return false;
}

/// Returns: true if the current peek could be the start of a BasicType.
bool startsLikeBasicType(TokenStream tstream)
{
    return contains(ONE_WORD_TYPES,          tstream.peek.type) ||
           contains(PAREN_TYPES,             tstream.peek.type) ||
           contains(IDENTIFIER_TYPEOF_TYPES, tstream.peek.type);
}

BasicType parseBasicType(TokenStream tstream)
{
    auto basicType = new BasicType();
    basicType.location = tstream.peek.location;
        
    if (contains(ONE_WORD_TYPES, tstream.peek.type)) {
        basicType.type = cast(BasicTypeType) tstream.peek.type;
        tstream.getToken();
    } else if (contains(PAREN_TYPES, tstream.peek.type)) {
        basicType.type = cast(BasicTypeType) tstream.peek.type;
        tstream.getToken();
        match(tstream, TokenType.OpenParen);
        basicType.secondType = parseType(tstream);
        match(tstream, TokenType.CloseParen);
    } else if (contains(IDENTIFIER_TYPEOF_TYPES, tstream.peek.type)) {
        if (tstream.peek.type == TokenType.Dot) {
            basicType.type = BasicTypeType.GlobalIdentifierList;
        } else {
            basicType.type = BasicTypeType.IdentifierList;
        }
        basicType.qualifiedName = parseQualifiedName(tstream, true);
    } else {
        // TODO: typeof
        error(basicType.location, format("expected basic type, not '%s'", tstream.peek.value));
    }
    
    return basicType;
}

bool startsLikeBasicType2(TokenStream tstream)
{
    if (contains([TokenType.Asterix, TokenType.OpenBracket, TokenType.Delegate, TokenType.Function], tstream.peek.type)) {
        return true;
    } else if (tstream.peek.type == TokenType.OpenParen && tstream.lookahead(1).type == TokenType.Asterix) {
        return true;
    }
    return false;
}

BasicType2 parseBasicType2(TokenStream tstream)
{
    auto basicType2 = new BasicType2();
    basicType2.location = tstream.peek.location;
    
    if (tstream.peek.type == TokenType.Asterix) {
        match(tstream, TokenType.Asterix);
        basicType2.type = BasicType2Type.Pointer;
    } else if (tstream.peek.type == TokenType.OpenBracket) {
        match(tstream, TokenType.OpenBracket);
        if (tstream.peek.type == TokenType.CloseBracket) {
            match(tstream, TokenType.CloseBracket);
            basicType2.type = BasicType2Type.DynamicArray;
        } else {
            if (startsLikeBasicType(tstream)) {
                basicType2.aaType = parseType(tstream);
                basicType2.type = BasicType2Type.AssociativeArray;
            } else {
                basicType2.firstAssignExpression = parseAssignExpression(tstream);
                if (tstream.peek.type == TokenType.DoubleDot) {
                    match(tstream, TokenType.DoubleDot);
                    basicType2.secondAssignExpression = parseAssignExpression(tstream);
                    basicType2.type = BasicType2Type.TupleSlice;
                } else {
                    basicType2.type = BasicType2Type.StaticArray;
                }
                match(tstream, TokenType.CloseBracket);
            }
        }
    } else if (tstream.peek.type == TokenType.Delegate) {
        match(tstream, TokenType.Delegate);
        basicType2.type = BasicType2Type.Delegate;
        basicType2.parameters = parseParameters(tstream);
    } else if (tstream.peek.type == TokenType.Function) {
        match(tstream, TokenType.Function);
        basicType2.type = BasicType2Type.Function;
        basicType2.parameters = parseParameters(tstream);
    } else if (tstream.peek.type == TokenType.OpenParen) {
        error(tstream.peek.location, "c style array/function pointers are unsupported");
    }
    
    return basicType2;
}

Parameters parseParameters(TokenStream tstream)
{
    auto parameters = new Parameters();
    parameters.location = tstream.peek.location;
    
    match(tstream, TokenType.OpenParen);
    while (tstream.peek.type != TokenType.CloseParen) {
        parameters.parameters ~= parseParameter(tstream);
        if (tstream.peek.type == TokenType.Comma) {
            match(tstream, TokenType.Comma);
        } else {
            if (tstream.peek.type != TokenType.CloseParen) {
                error(tstream.peek.location, format("expected ')', not '%s'", tstream.peek.value));
            }
        }
    }
    match(tstream, TokenType.CloseParen);
    
    return parameters;
}

Parameter parseParameter(TokenStream tstream)
{
    immutable TokenType[] inOuts = 
    [TokenType.In, TokenType.Out, TokenType.Ref, TokenType.Lazy];
    
    auto parameter = new Parameter();
    parameter.location = tstream.peek.location;
    
    if (contains(inOuts, tstream.peek.type)) {
        parameter.inOutType = cast(InOutType) tstream.peek.type;
        tstream.getToken();
    }
    
    parameter.basicType = parseBasicType(tstream);
    
    while (startsLikeBasicType2(tstream)) {
        parameter.basicType2 ~= parseBasicType2(tstream);
    }
        
    return parameter;
}

Declarator parseDeclarator(TokenStream tstream)
{
    auto decl = new Declarator();
    decl.location = tstream.peek.location;
    
    while (startsLikeBasicType2(tstream)) {
        decl.basicType2s ~= parseBasicType2(tstream);
    }
    
    decl.identifier = parseIdentifier(tstream);
    
    while (startsLikeDeclaratorSuffix(tstream)) {
        decl.declaratorSuffixes ~= parseDeclaratorSuffix(tstream);
    }
    
    return decl;
}

Declarator2 parseDeclarator2(TokenStream tstream)
{
    auto decl2 = new Declarator2();
    decl2.location = tstream.peek.location;

    while (startsLikeBasicType2(tstream)) {
        decl2.basicType2s ~= parseBasicType2(tstream);
    }
    // TODO: the paren shit.
    
    return decl2;
}

Declarators parseDeclarators(TokenStream tstream)
{
    auto decls = new Declarators();
    decls.location = tstream.peek.location;
    
    decls.declaratorInitialiser = parseDeclaratorInitialiser(tstream);
    while (tstream.peek.type == TokenType.Comma) {
        match(tstream, TokenType.Comma);
        decls.declaratorIdentifiers ~= parseDeclaratorIdentifier(tstream);
    }
    
    match(tstream, TokenType.Semicolon);
    
    return decls;
}

DeclaratorInitialiser parseDeclaratorInitialiser(TokenStream tstream)
{
    auto declInit = new DeclaratorInitialiser();
    declInit.location = tstream.peek.location;
    
    declInit.declarator = parseDeclarator(tstream);
    if (tstream.peek.type == TokenType.Assign) {
        match(tstream, TokenType.Assign);
        declInit.initialiser = parseInitialiser(tstream);
    }
    
    return declInit;
}

DeclaratorIdentifier parseDeclaratorIdentifier(TokenStream tstream)
{
    auto declIdent = new DeclaratorIdentifier();
    declIdent.location = tstream.peek.location;
    
    declIdent.identifier = parseIdentifier(tstream);
    if (tstream.peek.type == TokenType.Assign) {
        match(tstream, TokenType.Assign);
        declIdent.initialiser = parseInitialiser(tstream);
    }
    
    return declIdent;
}

Initialiser parseInitialiser(TokenStream tstream)
{
    auto init = new Initialiser();
    init.location = tstream.peek.location;
    
    if (tstream.peek.type == TokenType.Void) {
        init.voidInitialiser = parseVoidInitialiser(tstream);
    } else {
        init.nonVoidInitialiser = parseNonVoidInitialiser(tstream);
    }
    
    return init;
}

VoidInitialiser parseVoidInitialiser(TokenStream tstream)
{
    auto voidInit = new VoidInitialiser();
    voidInit.location = tstream.peek.location;
    match(tstream, TokenType.Void);
    return voidInit;
}

NonVoidInitialiser parseNonVoidInitialiser(TokenStream tstream)
{
    auto nonVoidInit = new NonVoidInitialiser();
    nonVoidInit.location = tstream.peek.location;
    
    if (tstream.peek.type == TokenType.OpenBracket) {
        nonVoidInit.arrayInitialiser = parseArrayInitialiser(tstream);
    } else if (tstream.peek.type == TokenType.OpenBrace) {
        // TODO: Struct literals.
    } else {
        nonVoidInit.assignExpression = parseAssignExpression(tstream);
    }
    
    return nonVoidInit;
}

ArrayInitialiser parseArrayInitialiser(TokenStream tstream)
{
    auto arrayInit = new ArrayInitialiser();
    arrayInit.location = tstream.peek.location;
    
    match(tstream, TokenType.OpenBracket);
    while (true) {
        arrayInit.arrayMemberInitialisations ~= parseArrayMemberInitialisation(tstream);
        if (tstream.peek.type != TokenType.CloseBracket) {
            match(tstream, TokenType.CloseBracket);
            break;
        } else {
            match(tstream, TokenType.Comma);
            continue;
        }
    }
    
    return arrayInit;
}

ArrayMemberInitialisation parseArrayMemberInitialisation(TokenStream tstream)
{
    auto memberInit = new ArrayMemberInitialisation();
    memberInit.location = tstream.peek.location;
    
    memberInit.left = parseNonVoidInitialiser(tstream);
    if (tstream.peek.type == TokenType.Colon) {
        match(tstream, TokenType.Colon);
        memberInit.right = parseNonVoidInitialiser(tstream);
    }
    
    return memberInit;
}

bool startsLikeDeclaratorSuffix(TokenStream tstream)
{
    return tstream.peek.type == TokenType.OpenBracket;
    // TODO: template
}

DeclaratorSuffix parseDeclaratorSuffix(TokenStream tstream)
{
    auto declSuffix = new DeclaratorSuffix();
    declSuffix.location = tstream.peek.location;
    
    match(tstream, TokenType.OpenBracket);  // TODO: template
    if (tstream.peek.type == TokenType.CloseBracket) {
        declSuffix.suffixType = DeclaratorSuffixType.DynamicArray;
    } else if (startsLikeBasicType(tstream)) {
        declSuffix.suffixType = DeclaratorSuffixType.AssociativeArray;
        declSuffix.type = parseType(tstream);
    } else {
        declSuffix.suffixType = DeclaratorSuffixType.StaticArray;
        declSuffix.assignExpression = parseAssignExpression(tstream);
    }
    match(tstream, TokenType.CloseBracket);
    
    return declSuffix;
}

Type parseType(TokenStream tstream)
{
    auto type = new Type();
    type.location = tstream.peek.location;
    
    type.basicType = parseBasicType(tstream);
    if (startsLikeBasicType2(tstream)) {
        type.declarator2 = parseDeclarator2(tstream);
    }
    
    return type;
}

DefaultInitialiserExpression parseDefaultInitialiserExpression(TokenStream tstream)
{
    auto def = new DefaultInitialiserExpression();
    def.location = tstream.peek.location;
    
    if (tstream.peek.type == TokenType.__File__ || tstream.peek.type == TokenType.__Line__) {
        def.type = cast(DefaultInitialiserExpressionType) tstream.peek.type;
    } else {
        def.type = DefaultInitialiserExpressionType.Assign;
        def.assignExpression = parseAssignExpression(tstream);
    }
    
    return def;
}
