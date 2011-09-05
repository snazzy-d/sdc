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
    expr.assignExpression = parseAssignExpression(tstream);
    if (tstream.peek.type == TokenType.Comma) {
        match(tstream, TokenType.Comma);
        expr.expression = parseExpression(tstream);
    }
    expr.location.spanTo(tstream.previous.location);
    return expr;
}

AssignExpression parseAssignExpression(TokenStream tstream)
{
    auto assignExpr = new AssignExpression();
    assignExpr.conditionalExpression = parseConditionalExpression(tstream);
    assignExpr.location = assignExpr.conditionalExpression.location;
    switch (tstream.peek.type) {
    case TokenType.Assign:
        assignExpr.assignType = AssignType.Normal;
        break;
    case TokenType.PlusAssign:
        assignExpr.assignType = AssignType.AddAssign;
        break;
    case TokenType.DashAssign:
        assignExpr.assignType = AssignType.SubAssign;
        break;
    case TokenType.AsterixAssign:
        assignExpr.assignType = AssignType.MulAssign;
        break;
    case TokenType.SlashAssign:
        assignExpr.assignType = AssignType.DivAssign;
        break;
    case TokenType.PercentAssign:
        assignExpr.assignType = AssignType.ModAssign;
        break;
    case TokenType.AmpersandAssign:
        assignExpr.assignType = AssignType.AndAssign;
        break;
    case TokenType.PipeAssign:
        assignExpr.assignType = AssignType.OrAssign;
        break;
    case TokenType.CaretAssign:
        assignExpr.assignType = AssignType.XorAssign;
        break;
    case TokenType.TildeAssign:
        assignExpr.assignType = AssignType.CatAssign;
        break;
    case TokenType.DoubleLessAssign:
        assignExpr.assignType = AssignType.ShiftLeftAssign;
        break;
    case TokenType.DoubleGreaterAssign:
        assignExpr.assignType = AssignType.SignedShiftRightAssign;
        break;
    case TokenType.TripleGreaterAssign:
        assignExpr.assignType = AssignType.UnsignedShiftRightAssign;
        break;
        // TODO: Double caret assign.
    default:
        return assignExpr;
    }
    tstream.get();
    assignExpr.assignExpression = parseAssignExpression(tstream);
    assignExpr.location.spanTo(tstream.previous.location);
    return assignExpr;
}

ConditionalExpression parseConditionalExpression(TokenStream tstream)
{
    auto condExpr = new ConditionalExpression();
    condExpr.location = tstream.peek.location;
    condExpr.orOrExpression = parseOrOrExpression(tstream);
    if (tstream.peek.type == TokenType.QuestionMark) {
        match(tstream, TokenType.QuestionMark);
        condExpr.expression = parseExpression(tstream);
        match(tstream, TokenType.Colon);
        condExpr.conditionalExpression = parseConditionalExpression(tstream);
    }
    
    condExpr.location.spanTo(tstream.previous.location);
    return condExpr;
}

OrOrExpression parseOrOrExpression(TokenStream tstream)
{
    auto orOrExpr = new OrOrExpression();
    orOrExpr.location = tstream.peek.location;
    
    orOrExpr.andAndExpression = parseAndAndExpression(tstream);
    if (tstream.peek.type == TokenType.DoublePipe) {
        match(tstream, TokenType.DoublePipe);
        orOrExpr.orOrExpression = parseOrOrExpression(tstream);
    }
    
    orOrExpr.location.spanTo(tstream.previous.location);
    return orOrExpr;
}

AndAndExpression parseAndAndExpression(TokenStream tstream)
{
    auto andAndExpr = new AndAndExpression();
    andAndExpr.location = tstream.peek.location;
    
    andAndExpr.orExpression = parseOrExpression(tstream);
    if (tstream.peek.type == TokenType.DoubleAmpersand) {
        match(tstream, TokenType.DoubleAmpersand);
        andAndExpr.andAndExpression = parseAndAndExpression(tstream);
    }
    
    andAndExpr.location.spanTo(tstream.previous.location);
    return andAndExpr;
}

OrExpression parseOrExpression(TokenStream tstream)
{
    auto orExpr = new OrExpression();
    orExpr.location = tstream.peek.location;
    
    orExpr.xorExpression = parseXorExpression(tstream);
    if (tstream.peek.type == TokenType.Pipe) {
        match(tstream, TokenType.Pipe);
        orExpr.orExpression = parseOrExpression(tstream);
    }
    
    orExpr.location.spanTo(tstream.previous.location);
    return orExpr;
}

XorExpression parseXorExpression(TokenStream tstream)
{
    auto xorExpr = new XorExpression();
    xorExpr.location = tstream.peek.location;
    
    xorExpr.andExpression = parseAndExpression(tstream);
    if (tstream.peek.type == TokenType.Caret) {
        match(tstream, TokenType.Caret);
        xorExpr.xorExpression = parseXorExpression(tstream);
    }
    
    xorExpr.location.spanTo(tstream.previous.location);
    return xorExpr;
}

AndExpression parseAndExpression(TokenStream tstream)
{
    auto andExpr = new AndExpression();
    andExpr.location = tstream.peek.location;
    
    andExpr.cmpExpression = parseCmpExpression(tstream);
    if (tstream.peek.type == TokenType.Ampersand) {
        match(tstream, TokenType.Ampersand);
        andExpr.andExpression = parseAndExpression(tstream);
    }
    
    andExpr.location.spanTo(tstream.previous.location);
    return andExpr;
}

CmpExpression parseCmpExpression(TokenStream tstream)
{
    auto cmpExpr = new CmpExpression();
    cmpExpr.location = tstream.peek.location;
    
    cmpExpr.lhShiftExpression = parseShiftExpression(tstream);
    switch (tstream.peek.type) {
    case TokenType.Bang:
        match(tstream, TokenType.Bang);
        if (tstream.peek.type == TokenType.Is) {
            cmpExpr.comparison = Comparison.NotIs;
        } else if (tstream.peek.type == TokenType.In) {
            cmpExpr.comparison = Comparison.NotIn;
        } else {
            throw new CompilerError(tstream.peek.location, format("expected 'is' or 'in', not '%s'.", tstream.peek.value));
        }
        break;
    case TokenType.DoubleAssign:
        cmpExpr.comparison = Comparison.Equality;
        break;
    case TokenType.BangAssign:
        cmpExpr.comparison = Comparison.NotEquality;
        break;
    case TokenType.Is:
        cmpExpr.comparison = Comparison.Is;
        break;
    case TokenType.In:
        cmpExpr.comparison = Comparison.In;
        break;
    case TokenType.Less:
        cmpExpr.comparison = Comparison.Less;
        break;
    case TokenType.LessAssign:
        cmpExpr.comparison = Comparison.LessEqual;
        break;
    case TokenType.Greater:
        cmpExpr.comparison = Comparison.Greater;
        break;
    case TokenType.GreaterAssign:
        cmpExpr.comparison = Comparison.GreaterEqual;
        break;
    case TokenType.BangLessGreaterAssign:
        cmpExpr.comparison = Comparison.Unordered;
        break;
    case TokenType.BangLessGreater:
        cmpExpr.comparison = Comparison.UnorderedEqual;
        break;
    case TokenType.LessGreater:
        cmpExpr.comparison = Comparison.LessGreater;
        break;
    case TokenType.LessGreaterAssign:
        cmpExpr.comparison = Comparison.LessEqualGreater;
        break;
    case TokenType.BangGreater:
        cmpExpr.comparison = Comparison.UnorderedLessEqual;
        break;
    case TokenType.BangGreaterAssign:
        cmpExpr.comparison = Comparison.UnorderedLess;
        break;
    case TokenType.BangLess:
        cmpExpr.comparison = Comparison.UnorderedGreaterEqual;
        break;
    case TokenType.BangLessAssign:
        cmpExpr.comparison = Comparison.UnorderedGreater;
        break;
    default:
        return cmpExpr;
    }
    tstream.get();
    cmpExpr.rhShiftExpression = parseShiftExpression(tstream);
    cmpExpr.location.spanTo(tstream.previous.location);
    return cmpExpr;
}

ShiftExpression parseShiftExpression(TokenStream tstream)
{
    auto shiftExpr = new ShiftExpression();
    shiftExpr.location = tstream.peek.location;
    
    shiftExpr.addExpression = parseAddExpression(tstream);
    switch (tstream.peek.type) {
    case TokenType.DoubleLess:
        shiftExpr.shift = Shift.Left;
        break;
    case TokenType.DoubleGreater:
        shiftExpr.shift = Shift.SignedRight;
        break;
    case TokenType.TripleGreater:
        shiftExpr.shift = Shift.UnsignedRight;
        break;
    default:
        return shiftExpr;
    }
    tstream.get();
    shiftExpr.shiftExpression = parseShiftExpression(tstream);
    shiftExpr.location.spanTo(tstream.previous.location);
    return shiftExpr;
}

AddExpression parseAddExpression(TokenStream tstream)
{
    auto addExpr = new AddExpression();
    addExpr.location = tstream.peek.location;
    
    addExpr.mulExpression = parseMulExpression(tstream);
    switch (tstream.peek.type) {
    case TokenType.Plus:
        addExpr.addOperation = AddOperation.Add;
        break;
    case TokenType.Dash:
        addExpr.addOperation = AddOperation.Subtract;
        break;
    case TokenType.Tilde:
        addExpr.addOperation = AddOperation.Concat;
        break;
    default:
        return addExpr;
    }
    tstream.get();
    addExpr.addExpression = parseAddExpression(tstream);
    addExpr.location.spanTo(tstream.previous.location);
    return addExpr;
}

MulExpression parseMulExpression(TokenStream tstream)
{
    auto mulExpr = new MulExpression();
    mulExpr.location = tstream.peek.location;
    
    mulExpr.powExpression = parsePowExpression(tstream);
    switch (tstream.peek.type) {
    case TokenType.Asterix:
        mulExpr.mulOperation = MulOperation.Mul;
        break;
    case TokenType.Slash:
        mulExpr.mulOperation = MulOperation.Div;
        break;
    case TokenType.Percent:
        mulExpr.mulOperation = MulOperation.Mod;
        break;
    default:
        return mulExpr;
    }
    tstream.get();    
    mulExpr.mulExpression = parseMulExpression(tstream);
    
    mulExpr.location.spanTo(tstream.previous.location);
    return mulExpr;
}

PowExpression parsePowExpression(TokenStream tstream)
{
    auto powExpr = new PowExpression();
    powExpr.location = tstream.peek.location;
    
    powExpr.unaryExpression = parseUnaryExpression(tstream);
    if (tstream.peek.type == TokenType.DoubleCaret) {
        match(tstream, TokenType.DoubleCaret);
        powExpr.powExpression = parsePowExpression(tstream);
    }
    
    powExpr.location.spanTo(tstream.previous.location);
    return powExpr;
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
            parseAssignExpression(tstream);
        }
        throw new CompilerError(tstream.peek.location - newExpr.location, "custom allocators are unsupported."); 
    }
    newExpr.type = parseType(tstream);
    
    if (tstream.peek.type == TokenType.OpenParen) {
        newExpr.argumentList = parseArgumentList(tstream);
    } else if (newExpr.type.suffixes.length > 0 && newExpr.type.suffixes[$ - 1].type == TypeSuffixType.Array) {
        if (newExpr.type.suffixes[$ - 1].node !is null && (cast(AssignExpression) newExpr.type.suffixes[$ - 1].node) !is null) {
            newExpr.assignExpression = cast(AssignExpression) newExpr.type.suffixes[$ - 1].node;
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
        list.expressions ~= parseAssignExpression(tstream);
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
    
    auto firstExpr = parseAssignExpression(tstream);
    
    // slice
    if (tstream.peek.type == TokenType.DoubleDot) {
        tstream.get();
        expr.type = PostfixType.Slice;
        expr.firstNode = firstExpr;
        expr.secondNode = parseAssignExpression(tstream);
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
        list.expressions ~= parseAssignExpression(tstream);
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
        primaryExpr.node = parseAssignExpression(tstream);
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
    match(tstream, TokenType.OpenParen);
    
    assertExpr.condition = parseAssignExpression(tstream);
    
    if (tstream.peek.type == TokenType.Comma) {
        tstream.get();
        assertExpr.message = parseAssignExpression(tstream);
    }
    
    auto lastToken = match(tstream, TokenType.CloseParen);
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