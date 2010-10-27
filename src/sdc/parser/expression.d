/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.parser.expression;

import std.conv;
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
    return expr;
}

AssignExpression parseAssignExpression(TokenStream tstream)
{
    auto assignExpr = new AssignExpression();
    assignExpr.location = tstream.peek.location;
    assignExpr.conditionalExpression = parseConditionalExpression(tstream);
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
    tstream.getToken();
    assignExpr.assignExpression = parseAssignExpression(tstream);
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
    tstream.getToken();
    cmpExpr.rhShiftExpression = parseShiftExpression(tstream);
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
    tstream.getToken();
    shiftExpr.shiftExpression = parseShiftExpression(tstream);
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
    tstream.getToken();
    addExpr.addExpression = parseAddExpression(tstream);
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
    tstream.getToken();    
    mulExpr.mulExpression = parseMulExpression(tstream);
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
    // TODO: The rest.
    case TokenType.New:
        unaryExpr.newExpression = parseNewExpression(tstream);
        break;
    case TokenType.Delete:
        unaryExpr.deleteExpression = parseDeleteExpression(tstream);
        break;
    default:
        unaryExpr.postfixExpression = parsePostfixExpression(tstream);
        break;
    }
    
    return unaryExpr;
}

CastExpression parseCastExpression(TokenStream tstream)
{
    auto castExpr = new CastExpression();
    castExpr.location = tstream.peek.location;
    match(tstream, TokenType.Cast);
    match(tstream, TokenType.OpenParen);
    castExpr.type = parseType(tstream);
    match(tstream, TokenType.CloseParen);
    castExpr.unaryExpression = parseUnaryExpression(tstream);
    return castExpr;
}

NewExpression parseNewExpression(TokenStream tstream)
{
    auto newExpr = new NewExpression();
    newExpr.location = tstream.peek.location;
    
    return newExpr;
}

DeleteExpression parseDeleteExpression(TokenStream tstream)
{
    auto deleteExpr = new DeleteExpression();
    deleteExpr.location = tstream.peek.location;
    match(tstream, TokenType.Delete);
    deleteExpr.unaryExpression = parseUnaryExpression(tstream);
    return deleteExpr;
}

PostfixExpression parsePostfixExpression(TokenStream tstream, bool second = false)
{
    auto postfixExpr = new PostfixExpression();
    postfixExpr.location = tstream.peek.location;
    
    if (!second) {
        postfixExpr.primaryExpression = parsePrimaryExpression(tstream);
    }
    switch (tstream.peek.type) {
    case TokenType.DoublePlus:
        postfixExpr.type = PostfixType.PostfixInc;
        match(tstream, TokenType.DoublePlus);
        break;
    case TokenType.DoubleDash:
        postfixExpr.type = PostfixType.PostfixDec;
        match(tstream, TokenType.DoubleDash);
        break;
    case TokenType.OpenParen:
        postfixExpr.firstNode = parseArgumentList(tstream);
        postfixExpr.type = PostfixType.Parens;
        break;
    case TokenType.OpenBracket:
        postfixExpr.firstNode = parseArgumentList(tstream, TokenType.OpenBracket, TokenType.CloseBracket);
        postfixExpr.type = PostfixType.Index;
        break;
    case TokenType.Dot:
        postfixExpr.type = PostfixType.Dot;
        match(tstream, TokenType.Dot);
        postfixExpr.firstNode = parseQualifiedName(tstream);
        postfixExpr.secondNode = parsePostfixExpression(tstream, true);
        break;
    default:
        break;
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
            match(tstream, TokenType.Comma);
        }
    }
    auto closeToken = match(tstream, close);
    
    list.location = closeToken.location - openToken.location;
    return list;
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
        primaryExpr.type = PrimaryType.ParenExpression;
        match(tstream, TokenType.OpenParen);
        primaryExpr.node = parseExpression(tstream);
        match(tstream, TokenType.CloseParen);
        break;
    default:
        if (contains([__traits(allMembers, PrimitiveTypeType)], to!string(tstream.peek.type))) {
            primaryExpr.type = PrimaryType.BasicTypeDotIdentifier;
            primaryExpr.node = parsePrimitiveType(tstream);
            match(tstream, TokenType.Dot);
            primaryExpr.secondNode = parseIdentifier(tstream);
        } else {
            throw new CompilerError(tstream.peek.location, "expected a primary expression.");
        }
    }
    
    return primaryExpr;
}

