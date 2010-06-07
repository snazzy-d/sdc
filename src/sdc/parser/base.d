/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdl.d for more details.
 * 
 * parse.d: translate a TokenStream into a parse tree.
 */ 
module sdc.parser.base;

import std.string;
import std.path;

import sdc.compilererror;
import sdc.tokenstream;
import sdc.ast.all;


Module parse(TokenStream tstream)
{
    return parseModule(tstream);
}

private:

void match(TokenStream tstream, TokenType type)
{
    if (tstream.peek.type != type) {
        error(tstream.peek.location, format("expected '%s', got '%s'",
                                            tokenToString[type],
                                            tokenToString[tstream.peek.type]));
    }
    tstream.getToken();
}

Module parseModule(TokenStream tstream)
{
    auto mod = new Module();
    mod.location = tstream.peek.location;
    match(tstream, TokenType.Begin);
    mod.moduleDeclaration = parseModuleDeclaration(tstream);
    return mod;
}                                        

ModuleDeclaration parseModuleDeclaration(TokenStream tstream)
{
    auto modDec = new ModuleDeclaration();
    if (tstream.peek.type == TokenType.Module) {
        // Explicit module declaration.
        modDec.location = tstream.peek.location;
        match(tstream, TokenType.Module);
        modDec.name = parseQualifiedName(tstream);
        match(tstream, TokenType.Semicolon);
    } else {
        // Implicit module declaration.
        modDec.name = new QualifiedName();
        auto ident = new Identifier();
        ident.value = basename(tstream.filename, "." ~ getExt(tstream.filename));
        modDec.name.identifiers ~= ident;
    }
    return modDec;
}

QualifiedName parseQualifiedName(TokenStream tstream)
{
    auto name = new QualifiedName();
    name.location = tstream.peek.location;
    while (true) {
        name.identifiers ~= parseIdentifier(tstream);
        if (tstream.peek.type == TokenType.Dot) {
            match(tstream, TokenType.Dot);
        } else {
            break;
        }
    }
    return name;
}

Identifier parseIdentifier(TokenStream tstream)
{
    auto ident = new Identifier();
    ident.value = tstream.peek.value;
    ident.location = tstream.peek.location;
    match(tstream, TokenType.Identifier);
    return ident;
}

/*****************************************************************
 * Expressions
 *****************************************************************/

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
            error(tstream.peek.location, format("expected 'is' or 'in', not '%s'", tokenToString[tstream.peek.type]));
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
        unaryExpr.unaryPrefix = UnaryPrefix.AddressOf;
        unaryExpr.unaryExpression = parseUnaryExpression(tstream);
        break;
    case TokenType.DoublePlus:
        unaryExpr.unaryPrefix = UnaryPrefix.PrefixInc;
        unaryExpr.unaryExpression = parseUnaryExpression(tstream);
        break;
    case TokenType.DoubleDash:
        unaryExpr.unaryPrefix = UnaryPrefix.PrefixDec;
        unaryExpr.unaryExpression = parseUnaryExpression(tstream);
        break;
    case TokenType.Asterix:
        unaryExpr.unaryPrefix = UnaryPrefix.Dereference;
        unaryExpr.unaryExpression = parseUnaryExpression(tstream);
    case TokenType.Dash:
        unaryExpr.unaryPrefix = UnaryPrefix.UnaryMinus;
        unaryExpr.unaryExpression = parseUnaryExpression(tstream);
        break;
    case TokenType.Plus:
        unaryExpr.unaryPrefix = UnaryPrefix.UnaryPlus;
        unaryExpr.unaryExpression = parseUnaryExpression(tstream);
        break;
    case TokenType.Bang:
        unaryExpr.unaryPrefix = UnaryPrefix.LogicalNot;
        unaryExpr.unaryExpression = parseUnaryExpression(tstream);
        break;
    case TokenType.Tilde:
        unaryExpr.unaryPrefix = UnaryPrefix.BitwiseNot;
        unaryExpr.unaryExpression = parseUnaryExpression(tstream);
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

PostfixExpression parsePostfixExpression(TokenStream tstream)
{
    auto postfixExpr = new PostfixExpression();
    postfixExpr.location = tstream.peek.location;
    
    postfixExpr.primaryExpression = parsePrimaryExpression(tstream);
    switch (tstream.peek.type) {
    default:
        break;
    }
    
    return postfixExpr;
}

PrimaryExpression parsePrimaryExpression(TokenStream tstream)
{
    auto primaryExpr = new PrimaryExpression();
    primaryExpr.location = tstream.peek.location;
    
    
    return primaryExpr;
}
