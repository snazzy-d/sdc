/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.parser.expression;

import std.array;
import std.conv;
import std.exception;
import std.string;

import sdc.util;
import sdc.tokenstream;
import sdc.compilererror;
import sdc.ast.all;
import sdc.parser.base;
import sdc.parser.declaration;
import sdc.parser.sdctemplate;


Expression parseExpression(TokenStream tstream)
{
    auto expr = new Expression();
    expr.location = tstream.peek.location;
    expr.conditionalExpression = parseConditionalExpression(tstream);
    if (tstream.peek.type == TokenType.Comma) {
        match(tstream, TokenType.Comma);
        expr.expression = parseExpression(tstream);
    }
    expr.location.spanTo(tstream.previous.location);
    return expr;
}

ConditionalExpression parseConditionalExpression(TokenStream tstream)
{
    auto condExpr = new ConditionalExpression();
    condExpr.location = tstream.peek.location;
    condExpr.binaryExpression = parseBinaryExpression(tstream);
    if (tstream.peek.type == TokenType.QuestionMark) {
        match(tstream, TokenType.QuestionMark);
        condExpr.expression = parseExpression(tstream);
        match(tstream, TokenType.Colon);
        condExpr.conditionalExpression = parseConditionalExpression(tstream);
    }
    
    condExpr.location.spanTo(tstream.previous.location);
    return condExpr;
}

BinaryExpression parseBinaryExpression(TokenStream tstream)
{
    auto expression = new BinaryExpression();
    expression.location = tstream.peek.location;
    expression.lhs = parseUnaryExpression(tstream);
    
    switch (tstream.peek.type) {
    case TokenType.Bang:
        if (tstream.lookahead(1).type == TokenType.Is) {
            tstream.get();
            expression.operation = BinaryOperation.NotIs;
        } else if (tstream.lookahead(1).type == TokenType.In) {
            tstream.get();
            expression.operation = BinaryOperation.NotIn;
        } else {
            goto default; 
        }
        break;
    case TokenType.Assign:
        expression.operation = BinaryOperation.Assign; break;
    case TokenType.PlusAssign:
        expression.operation = BinaryOperation.AddAssign; break;
    case TokenType.DashAssign:
        expression.operation = BinaryOperation.SubAssign; break;
    case TokenType.AsterixAssign:
        expression.operation = BinaryOperation.MulAssign; break;
    case TokenType.SlashAssign:
        expression.operation = BinaryOperation.DivAssign; break;
    case TokenType.PercentAssign:
        expression.operation = BinaryOperation.ModAssign; break;
    case TokenType.AmpersandAssign:
        expression.operation = BinaryOperation.AndAssign; break;
    case TokenType.PipeAssign:
        expression.operation = BinaryOperation.OrAssign; break;
    case TokenType.CaretAssign:
        expression.operation = BinaryOperation.XorAssign; break;
    case TokenType.TildeAssign:
        expression.operation = BinaryOperation.CatAssign; break;
    case TokenType.DoubleLessAssign:
        expression.operation = BinaryOperation.ShiftLeftAssign; break;
    case TokenType.DoubleGreaterAssign:
        expression.operation = BinaryOperation.SignedShiftRightAssign; break; 
    case TokenType.TripleGreaterAssign:
        expression.operation = BinaryOperation.UnsignedShiftRightAssign; break;
//    case TokenType.DoubleCaretAssign:  TODO add to lexer
//        expression.operation = BinaryOperation.PowAssign; break;
    case TokenType.DoublePipe:
        expression.operation = BinaryOperation.LogicalOr; break;
    case TokenType.DoubleAmpersand:
        expression.operation = BinaryOperation.LogicalAnd; break;
    case TokenType.Pipe:
        expression.operation = BinaryOperation.BitwiseOr; break;
    case TokenType.Caret:
        expression.operation = BinaryOperation.BitwiseXor; break;
    case TokenType.Ampersand:
        expression.operation = BinaryOperation.BitwiseAnd; break;
    case TokenType.DoubleAssign:
        expression.operation = BinaryOperation.Equality; break;
    case TokenType.BangAssign:
        expression.operation = BinaryOperation.NotEquality; break;
    case TokenType.Is:
        expression.operation = BinaryOperation.Is; break;
    case TokenType.In:
        expression.operation = BinaryOperation.In; break;
    case TokenType.Less:
        expression.operation = BinaryOperation.Less; break;
    case TokenType.LessAssign:
        expression.operation = BinaryOperation.LessEqual; break;
    case TokenType.Greater:
        expression.operation = BinaryOperation.Greater; break;
    case TokenType.GreaterAssign:
        expression.operation = BinaryOperation.GreaterEqual; break;
    case TokenType.BangLessGreaterAssign:
        expression.operation = BinaryOperation.Unordered; break;
    case TokenType.BangLessGreater:
        expression.operation = BinaryOperation.UnorderedEqual; break;
    case TokenType.LessGreater:
        expression.operation = BinaryOperation.LessGreater; break;
    case TokenType.LessGreaterAssign:
        expression.operation = BinaryOperation.LessEqualGreater; break;
    case TokenType.BangGreater:
        expression.operation = BinaryOperation.UnorderedLessEqual; break;
    case TokenType.BangGreaterAssign:
        expression.operation = BinaryOperation.UnorderedLess; break;
    case TokenType.BangLess:
        expression.operation = BinaryOperation.UnorderedGreaterEqual; break;
    case TokenType.BangLessAssign:
        expression.operation = BinaryOperation.UnorderedGreater; break;
    case TokenType.DoubleLess:
        expression.operation = BinaryOperation.LeftShift; break;
    case TokenType.DoubleGreater:
        expression.operation = BinaryOperation.SignedRightShift; break;
    case TokenType.TripleGreater:
        expression.operation = BinaryOperation.UnsignedRightShift; break;
    case TokenType.Plus:
        expression.operation = BinaryOperation.Addition; break;
    case TokenType.Dash:
        expression.operation = BinaryOperation.Subtraction; break;
    case TokenType.Tilde:
        expression.operation = BinaryOperation.Concat; break;
    case TokenType.Slash:
        expression.operation = BinaryOperation.Division; break;
    case TokenType.Asterix:
        expression.operation = BinaryOperation.Multiplication; break;
    case TokenType.Percent:
        expression.operation = BinaryOperation.Modulus; break;
    case TokenType.DoubleCaret:
        expression.operation = BinaryOperation.Pow; break;
    default:
        expression.operation = BinaryOperation.None; break;
    }
    if (expression.operation != BinaryOperation.None) {
        tstream.get();
        expression.rhs = parseBinaryExpression(tstream);
    } 
    
    expression.location.spanTo(tstream.previous.location);
    return expression;
}

UnaryExpression parseUnaryExpression(TokenStream tstream)
{
    auto unaryExpr = new UnaryExpression();
    unaryExpr.location = tstream.peek.location;
    
    switch (tstream.peek.type) {
    case TokenType.Ampersand:
        match(tstream, TokenType.Ampersand);
        unaryExpr.unaryPrefix = UnaryPrefix.AddressOf;
        unaryExpr.unaryExpression = parseUnaryExpression(tstream);
        break;
    case TokenType.DoublePlus:
        match(tstream, TokenType.DoublePlus);
        unaryExpr.unaryPrefix = UnaryPrefix.PrefixInc;
        unaryExpr.unaryExpression = parseUnaryExpression(tstream);
        break;
    case TokenType.DoubleDash:
        match(tstream, TokenType.DoubleDash);
        unaryExpr.unaryPrefix = UnaryPrefix.PrefixDec;
        unaryExpr.unaryExpression = parseUnaryExpression(tstream);
        break;
    case TokenType.Asterix:
        match(tstream, TokenType.Asterix);
        unaryExpr.unaryPrefix = UnaryPrefix.Dereference;
        unaryExpr.unaryExpression = parseUnaryExpression(tstream);
        break;
    case TokenType.Dash:
        match(tstream, TokenType.Dash);
        unaryExpr.unaryPrefix = UnaryPrefix.UnaryMinus;
        unaryExpr.unaryExpression = parseUnaryExpression(tstream);
        break;
    case TokenType.Plus:
        match(tstream, TokenType.Plus);
        unaryExpr.unaryPrefix = UnaryPrefix.UnaryPlus;
        unaryExpr.unaryExpression = parseUnaryExpression(tstream);
        break;
    case TokenType.Bang:
        match(tstream, TokenType.Bang);
        unaryExpr.unaryPrefix = UnaryPrefix.LogicalNot;
        unaryExpr.unaryExpression = parseUnaryExpression(tstream);
        break;
    case TokenType.Tilde:
        match(tstream, TokenType.Tilde);
        unaryExpr.unaryPrefix = UnaryPrefix.BitwiseNot;
        unaryExpr.unaryExpression = parseUnaryExpression(tstream);
        break;
    case TokenType.Cast:
        unaryExpr.unaryPrefix = UnaryPrefix.Cast;
        unaryExpr.castExpression = parseCastExpression(tstream);
        break;
    case TokenType.New:
        unaryExpr.unaryPrefix = UnaryPrefix.New;
        unaryExpr.newExpression = parseNewExpression(tstream);
        break;
    default:
        unaryExpr.postfixExpression = parsePostfixExpression(tstream);
        break;
    }
    
    unaryExpr.location.spanTo(tstream.previous.location);
    return unaryExpr;
}

CastExpression parseCastExpression(TokenStream tstream)
{
    auto castExpr = new CastExpression();
    auto castToken = match(tstream, TokenType.Cast);
    match(tstream, TokenType.OpenParen);
    castExpr.type = parseType(tstream);
    match(tstream, TokenType.CloseParen);
    castExpr.unaryExpression = parseUnaryExpression(tstream);
    castExpr.location = castExpr.unaryExpression.location - castToken.location;
    return castExpr;
}

NewExpression parseNewExpression(TokenStream tstream)
{
    auto newExpr = new NewExpression();
    newExpr.location = tstream.peek.location;
    
    match(tstream, TokenType.New);
    if (tstream.peek.type == TokenType.OpenParen) {
        // new(
        match(tstream, TokenType.OpenParen);
        if (tstream.peek.type != TokenType.CloseParen) {
            parseConditionalExpression(tstream);
        }
        throw new CompilerError(tstream.peek.location - newExpr.location, "custom allocators are unsupported."); 
    }
    newExpr.type = parseType(tstream);
    
    if (tstream.peek.type == TokenType.OpenParen) {
        newExpr.argumentList = parseArgumentList(tstream);
    } else if (newExpr.type.suffixes.length > 0 && newExpr.type.suffixes[$ - 1].type == TypeSuffixType.Array) {
        if (newExpr.type.suffixes[$ - 1].node !is null && (cast(ConditionalExpression) newExpr.type.suffixes[$ - 1].node) !is null) {
            newExpr.conditionalExpression = cast(ConditionalExpression) newExpr.type.suffixes[$ - 1].node;
            newExpr.type.suffixes.popBack();
        }
    }
    
    newExpr.location.spanTo(tstream.previous.location);
    return newExpr;
}

PostfixExpression parsePostfixExpression(TokenStream tstream, int count = 0)
{
    auto postfixExpr = new PostfixExpression();
    postfixExpr.location = tstream.peek.location;
    
    switch (tstream.peek.type) {
    case TokenType.DoublePlus:
        postfixExpr.type = PostfixType.PostfixInc;
        match(tstream, TokenType.DoublePlus);
        postfixExpr.postfixExpression = parsePostfixExpression(tstream, count + 1);
        break;
    case TokenType.DoubleDash:
        postfixExpr.type = PostfixType.PostfixDec;
        match(tstream, TokenType.DoubleDash);
        postfixExpr.postfixExpression = parsePostfixExpression(tstream, count + 1);
        break;
    case TokenType.OpenParen:
        if (count == 0) {
            goto default;
        }
        postfixExpr.firstNode = parseArgumentList(tstream);
        postfixExpr.type = PostfixType.Parens;
        postfixExpr.postfixExpression = parsePostfixExpression(tstream, count + 1);
        break;
    case TokenType.OpenBracket:
        parseBracketPostfixExpression(tstream, postfixExpr);
        postfixExpr.postfixExpression = parsePostfixExpression(tstream, count + 1);
        break;
    case TokenType.Dot:
        postfixExpr.type = PostfixType.Dot;
        match(tstream, TokenType.Dot);
        postfixExpr.firstNode = parseQualifiedName(tstream);        
        postfixExpr.postfixExpression = parsePostfixExpression(tstream, count + 1);
        break;
    default:
        if (count == 0 && isPrimaryExpression(tstream)) {
            postfixExpr.firstNode = parsePrimaryExpression(tstream);
            postfixExpr.type = PostfixType.Primary;
            postfixExpr.postfixExpression = parsePostfixExpression(tstream, count + 1); 
        } else {
            postfixExpr = null;
        }
        break;
    }
    
    if (postfixExpr !is null) {
        postfixExpr.location.spanTo(tstream.previous.location);
    } else if (count == 0) {
        auto next = tstream.peek;
        throw new CompilerError(next.location, format("expected expression, not '%s'.", next));
    }
    return postfixExpr;
}

ArgumentList parseArgumentList(TokenStream tstream, TokenType open = TokenType.OpenParen, TokenType close = TokenType.CloseParen)
{
    auto list = new ArgumentList();
    
    auto openToken = match(tstream, open);
    while (tstream.peek.type != close) {
        list.expressions ~= parseConditionalExpression(tstream);
        if (tstream.peek.type != close) {
            if (tstream.peek.type != TokenType.Comma) {
                throw new PairMismatchError(openToken.location, tstream.previous.location, "argument list", tokenToString[close]);
            }
            match(tstream, TokenType.Comma);
        }
    }
    auto closeToken = match(tstream, close);
    
    list.location = closeToken.location - openToken.location;
    return list;
}

/// Parse either a slice expression or an index argument list.
void parseBracketPostfixExpression(TokenStream tstream, PostfixExpression expr)
{
    auto openToken = match(tstream, TokenType.OpenBracket);
    void mismatch(string type) {
        throw new PairMismatchError(openToken.location, tstream.previous.location, type, "]");
    }
    
    // slice whole
    if (tstream.peek.type == TokenType.CloseBracket) {
        tstream.get();
        expr.type = PostfixType.Slice;
        return;
    }
    
    auto firstExpr = parseConditionalExpression(tstream);
    
    // slice
    if (tstream.peek.type == TokenType.DoubleDot) {
        tstream.get();
        expr.type = PostfixType.Slice;
        expr.firstNode = firstExpr;
        expr.secondNode = parseConditionalExpression(tstream);
        if (tstream.peek.type != TokenType.CloseBracket) {
            mismatch("slice expression");
        }
        auto closeToken = tstream.get();
        expr.location = closeToken.location - openToken.location;
        return;
    }
    
    // index argument list
    auto list = new ArgumentList();
    list.expressions ~= firstExpr;
    
    while (tstream.peek.type != TokenType.CloseBracket) {
        list.expressions ~= parseConditionalExpression(tstream);
        if (tstream.peek.type != TokenType.CloseBracket) {
            if (tstream.peek.type != TokenType.Comma) {
                mismatch("index argument list");
            }
            match(tstream, TokenType.Comma);
        }
    }
    auto closeToken = match(tstream, TokenType.CloseBracket);
    list.location = closeToken.location - openToken.location;
    
    expr.type = PostfixType.Index;
    expr.firstNode = list;
}

bool isPrimaryExpression(TokenStream tstream)
{
    switch (tstream.peek.type) {
    case TokenType.Identifier:
        return true;
    case TokenType.Dot:
        return tstream.lookahead(1).type == TokenType.Identifier;
    case TokenType.This:
        return true;
    case TokenType.Super:
        return true;
    case TokenType.Null:
        return true;
    case TokenType.True:
        return true;
    case TokenType.False:
        return true;
    case TokenType.Dollar:
        return true;
    case TokenType.__File__:
        return true;
    case TokenType.__Line__:
        return true;
    case TokenType.IntegerLiteral:
        return true;
    case TokenType.FloatLiteral:
        return true;
    case TokenType.StringLiteral:
        return true;
    case TokenType.CharacterLiteral:
        return true;
    case TokenType.OpenParen:
        return true;
    case TokenType.Mixin:
        return true;
    case TokenType.Assert:
        return true;
    case TokenType.Is:
        return true;
    case TokenType.Typeid:
        return true;
    case TokenType.Import:
        return true;
    default:
        if (contains([__traits(allMembers, PrimitiveTypeType)], to!string(tstream.peek.type))) {
            return true;
        } else {
            return false;
        }
    }
}

PrimaryExpression parsePrimaryExpression(TokenStream tstream)
{
    auto primaryExpr = new PrimaryExpression();
    primaryExpr.location = tstream.peek.location;
    
    switch (tstream.peek.type) {
    case TokenType.Identifier:
        if (tstream.lookahead(1).type == TokenType.Bang) {
            primaryExpr.type = PrimaryType.TemplateInstance;
            primaryExpr.node = parseTemplateInstance(tstream);
        } else {
            primaryExpr.type = PrimaryType.Identifier;
            primaryExpr.node = parseIdentifier(tstream);
        }
        break;
    case TokenType.Dot:
        match(tstream, TokenType.Dot);
        primaryExpr.type = PrimaryType.GlobalIdentifier;
        primaryExpr.node = parseIdentifier(tstream);
        break;
    case TokenType.This:
        match(tstream, TokenType.This);
        primaryExpr.type = PrimaryType.This;
        break;
    case TokenType.Super:
        match(tstream, TokenType.Super);
        primaryExpr.type = PrimaryType.Super;
        break;
    case TokenType.Null:
        match(tstream, TokenType.Null);
        primaryExpr.type = PrimaryType.Null;
        break;
    case TokenType.True:
        match(tstream, TokenType.True);
        primaryExpr.type = PrimaryType.True;
        break;
    case TokenType.False:
        match(tstream, TokenType.False);
        primaryExpr.type = PrimaryType.False;
        break;
    case TokenType.Dollar:
        match(tstream, TokenType.Dollar);
        primaryExpr.type = PrimaryType.Dollar;
        break;
    case TokenType.__File__:
        match(tstream, TokenType.__File__);
        primaryExpr.type = PrimaryType.__File__;
        break;
    case TokenType.__Line__:
        match(tstream, TokenType.__Line__);
        primaryExpr.type = PrimaryType.__Line__;
        break;
    case TokenType.IntegerLiteral:
        primaryExpr.type = PrimaryType.IntegerLiteral;
        primaryExpr.node = parseIntegerLiteral(tstream);
        break;
    case TokenType.FloatLiteral:
        primaryExpr.type = PrimaryType.FloatLiteral;
        primaryExpr.node = parseFloatLiteral(tstream);
        break;
    case TokenType.StringLiteral:
        primaryExpr.type = PrimaryType.StringLiteral;
        primaryExpr.node = parseStringLiteral(tstream);
        break;
    case TokenType.CharacterLiteral:
        primaryExpr.type = PrimaryType.CharacterLiteral;
        primaryExpr.node = parseCharacterLiteral(tstream);
        break;
    case TokenType.OpenParen:
        auto openToken = match(tstream, TokenType.OpenParen);
        bool isTypeExpression = startsLikeTypeExpression(tstream);
        
        if (isTypeExpression) {
            primaryExpr.type = PrimaryType.ComplexTypeDotIdentifier;
            primaryExpr.node = parseType(tstream);
        } else {
            primaryExpr.type = PrimaryType.ParenExpression;
            primaryExpr.node = parseExpression(tstream);
        }
        
        if (tstream.peek.type != TokenType.CloseParen) {
            throw new PairMismatchError(openToken.location, tstream.previous.location, "primary expression", ")");
        }
        
        match(tstream, TokenType.CloseParen);
        
        if(isTypeExpression) {
            match(tstream, TokenType.Dot);
            primaryExpr.secondNode = parseIdentifier(tstream);
        }
        break;
    case TokenType.Mixin:
        primaryExpr.type = PrimaryType.MixinExpression;
        match(tstream, TokenType.Mixin);
        match(tstream, TokenType.OpenParen);
        primaryExpr.node = parseConditionalExpression(tstream);
        match(tstream, TokenType.CloseParen);
        break;
    case TokenType.Assert:
        primaryExpr.type = PrimaryType.AssertExpression;
        primaryExpr.node = parseAssertExpression(tstream);
        break;
    case TokenType.Is:
        primaryExpr.type = PrimaryType.IsExpression;
        primaryExpr.node = parseIsExpression(tstream);
        break;
    default:
        if (contains([__traits(allMembers, PrimitiveTypeType)], to!string(tstream.peek.type))) {
            primaryExpr.type = PrimaryType.BasicTypeDotIdentifier;
            primaryExpr.node = parsePrimitiveType(tstream);
            match(tstream, TokenType.Dot);
            primaryExpr.secondNode = parseIdentifier(tstream);
        } else {
            throw new CompilerPanic(tstream.peek.location, "unhandled primary expression.");
        }
    }
    
    primaryExpr.location.spanTo(tstream.previous.location);
    return primaryExpr;
}

AssertExpression parseAssertExpression(TokenStream tstream)
{
    auto assertExpr = new AssertExpression();
    auto firstToken = match(tstream, TokenType.Assert);
    auto openToken = match(tstream, TokenType.OpenParen);
    
    assertExpr.condition = parseConditionalExpression(tstream);
    
    if (tstream.peek.type == TokenType.Comma) {
        tstream.get();
        assertExpr.message = parseConditionalExpression(tstream);
    }
    
    if (tstream.peek.type != TokenType.CloseParen) {
        throw new PairMismatchError(openToken.location, tstream.previous.location, "assert", ")");
    }
    auto lastToken = tstream.get();
    assertExpr.location = lastToken.location - firstToken.location;
    
    return assertExpr;
}

// This is rather hacky.
bool startsLikeTypeExpression(TokenStream tstream)
{
    // type qualifier?
    if (contains(PAREN_TYPES, tstream.peek.type) && tstream.lookahead(1).type == TokenType.OpenParen) {
        return true;
    }
    
    if (contains(PRIMITIVE_TYPES, tstream.peek.type)) {
        // pointer?
        if (tstream.lookahead(1).type == TokenType.Asterix) {
            return true;
        }
        
        // array?
        if (tstream.lookahead(1).type == TokenType.OpenBracket) {
            return true;
        }
        
        // TODO: template instantiations?
    }
    
    if (tstream.peek.type == TokenType.Typeof) {
        return true;
    }
    
    return false;
}

IsExpression parseIsExpression(TokenStream tstream)
{
    auto expr = new IsExpression();
    
    match(tstream, TokenType.Is);
    auto openToken = match(tstream, TokenType.OpenParen);
    
    expr.type = parseType(tstream);
    
    if (tstream.peek.type == TokenType.CloseParen) {
        auto closeToken = tstream.get();
        expr.operation = IsOperation.SemanticCheck;
        expr.location = closeToken.location - openToken.location;
        return expr;
    }
    
    if (tstream.peek.type == TokenType.Identifier) {
        expr.identifier = parseIdentifier(tstream);
        
        if (tstream.peek.type == TokenType.CloseParen) {
            auto closeToken = tstream.get();
            expr.operation = IsOperation.SemanticCheck;
            expr.location = closeToken.location - openToken.location;
            return expr;
        }
    }
    
    if (tstream.peek.type == TokenType.DoubleAssign) {
        expr.operation = IsOperation.ExplicitType;
    } else if (tstream.peek.type == TokenType.Colon) {
        expr.operation = IsOperation.ImplicitType;
    } else {
        throw new CompilerError(tstream.peek.location, format("expected '==' or ':', not '%s'.", tstream.peek));
    }
    tstream.get();
    
    switch(tstream.peek.type) with(TokenType) {
        case Struct, Union, Class, Interface, Enum, Function, Delegate, Super, Return:
            expr.specialisation = cast(IsSpecialisation)tstream.get().type;
            break;
        case Const, Immutable, Shared, Inout:
            if (tstream.lookahead(1).type == TokenType.OpenParen) {
                goto default;
            }
            goto case Struct;
        default:
            expr.specialisation = IsSpecialisation.Type;
            expr.specialisationType = parseType(tstream);
    }
    
    if (tstream.peek.type != TokenType.CloseParen) {
        throw new PairMismatchError(openToken.location, tstream.previous.location, "is expression", ")");
    }
    
    auto closeToken = tstream.get();
    expr.location = closeToken.location - openToken.location;
    return expr;
}