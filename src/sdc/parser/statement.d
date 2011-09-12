/**
 * Copyright 2010 Bernard Helyer.
 * Copyright 2010-2011 Jakob Ovrum.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.parser.statement;

import sdc.util;
import sdc.tokenstream;
import sdc.compilererror;
import sdc.ast.statement;
import sdc.parser.base;
import sdc.parser.expression;
import sdc.parser.declaration;
import sdc.parser.conditional;
import sdc.parser.sdcpragma;

Statement parseStatement(TokenStream tstream, bool allowEmptyStatement = false)
{
    auto statement = new Statement();
    statement.location = tstream.peek.location;
    
    if (tstream.peek.type == TokenType.Semicolon) {
        if (!allowEmptyStatement) {
            auto error = new CompilerError(tstream.peek.location, "illegal empty statement.");
            error.fixHint = "{}";
            throw error;
        }
        statement.type = StatementType.EmptyStatement;
        tstream.get();
    } else if (tstream.peek.type == TokenType.OpenBrace) {
        statement.type = StatementType.BlockStatement;
        statement.node = parseBlockStatement(tstream);
    } else if (tstream.peek.type == TokenType.If) {
        statement.type = StatementType.IfStatement;
        statement.node = parseIfStatement(tstream);   
    } else if (tstream.peek.type == TokenType.While) {
        statement.type = StatementType.WhileStatement;
        statement.node = parseWhileStatement(tstream);
    } else if (tstream.peek.type == TokenType.Do) {
        statement.type = StatementType.DoStatement;
        statement.node = parseDoStatement(tstream);
    } else if (tstream.peek.type == TokenType.Return) {
        statement.type = StatementType.ReturnStatement;
        statement.node = parseReturnStatement(tstream);
    } else if (tstream.peek.type == TokenType.Pragma) {
        statement.type = StatementType.PragmaStatement;
        statement.node = parsePragmaStatement(tstream);
    } else if (tstream.peek.type == TokenType.Mixin) {
        statement.type = StatementType.MixinStatement;
        statement.node = parseMixinStatement(tstream);
    } else if (tstream.peek.type == TokenType.Asm) {
        statement.type = StatementType.AsmStatement;
        statement.node = parseAsmStatement(tstream);
    } else if (tstream.peek.type == TokenType.Throw) {
        statement.type = StatementType.ThrowStatement;
        statement.node = parseThrowStatement(tstream);
    } else if (tstream.peek.type == TokenType.Try) {
        statement.type = StatementType.TryStatement;
        statement.node = parseTryStatement(tstream);
    } else if (tstream.peek.type == TokenType.Goto) {
        statement.type = StatementType.GotoStatement;
        statement.node = parseGotoStatement(tstream);
    } else if (tstream.peek.type == TokenType.Foreach) {
        statement.type = StatementType.ForeachStatement;
        statement.node = parseForeachStatement(tstream);
    } else if (tstream.peek.type == TokenType.For) {
        statement.type = StatementType.ForStatement;
        statement.node = parseForStatement(tstream);
    } else if (tstream.peek.type == TokenType.Break) {
        statement.type = StatementType.BreakStatement;
        statement.node = parseBreakStatement(tstream);
    } else if (tstream.peek.type == TokenType.Continue) {
        statement.type = StatementType.ContinueStatement;
        statement.node = parseContinueStatement(tstream);
    } else if (tstream.peek.type == TokenType.Default) {
        statement.type = StatementType.DefaultStatement;
        statement.node = parseDefaultStatement(tstream);
    } else if (tstream.peek.type == TokenType.Case) {
        statement.node = parseCaseStatement(tstream, statement.type);
    } else if (tstream.peek.type == TokenType.Switch || tstream.peek.type == TokenType.Final) {
        statement.type = StatementType.SwitchStatement;
        statement.node = parseSwitchStatement(tstream);
    } else if (tstream.peek.type == TokenType.Identifier && tstream.lookahead(1).type == TokenType.Colon) {
        statement.type = StatementType.LabeledStatement;
        statement.node = parseLabeledStatement(tstream);
    } else if (tstream.peek.type == TokenType.Static && tstream.lookahead(1).type == TokenType.Assert) {
        statement.type = StatementType.StaticAssert;
        statement.node = parseStaticAssert(tstream);
    } else if (startsLikeConditional(tstream)) {
        statement.type = StatementType.ConditionalStatement;
        statement.node = parseConditionalStatement(tstream);
    } else if (tstream.lookahead(0).type == TokenType.Identifier &&
               tstream.lookahead(1).type == TokenType.Asterix &&
               tstream.lookahead(2).type == TokenType.Identifier) {
        // In D, this is always a declaration; unlike C.
        statement.type = StatementType.DeclarationStatement;
        statement.node = parseDeclarationStatement(tstream);
    } else if (startsLikeDeclaration(tstream)) {
        statement.type = StatementType.DeclarationStatement;
        statement.node = parseDeclarationStatement(tstream);
    } else {
        statement.type = StatementType.ExpressionStatement;
        statement.node = parseExpressionStatement(tstream);
    }
    
    return statement;
}

BlockStatement parseBlockStatement(TokenStream tstream)
{
    auto block = new BlockStatement();
    block.location = tstream.peek.location;
    
    if (tstream.peek.type == TokenType.OpenBrace) {
        match(tstream, TokenType.OpenBrace);
        while (tstream.peek.type != TokenType.CloseBrace) {
            block.statements ~= parseStatement(tstream, true);
        }
        match(tstream, TokenType.CloseBrace);
    } else {
        block.statements ~= parseStatement(tstream);
    }
    
    return block;
}

GotoStatement parseGotoStatement(TokenStream tstream)
{
    auto statement = new GotoStatement();
    statement.location = tstream.peek.location;
    
    match(tstream, TokenType.Goto);
    switch (tstream.peek.type) {
    case TokenType.Identifier:
        statement.type = GotoStatementType.Identifier;
        statement.target = parseIdentifier(tstream);
        break;
    case TokenType.Default:
        statement.type = GotoStatementType.Default;
        tstream.get();
        break;
    case TokenType.Case:
        statement.type = GotoStatementType.Case;
        tstream.get();
        if (tstream.peek.type != TokenType.Semicolon) {
            statement.caseTarget = parseExpression(tstream);
        }
        break;
    default:
        throw new CompilerError(tstream.peek.location, "expected identifier, case, or default.");
    }
    statement.location.spanTo(tstream.previous.location);
    
    if (tstream.peek.type != TokenType.Semicolon) {
        throw new MissingSemicolonError(tstream.previous.location, "goto statement");
    }
    tstream.get();
    
    return statement;
}

LabeledStatement parseLabeledStatement(TokenStream tstream)
{
    auto statement = new LabeledStatement();
    statement.location = tstream.lookahead(1).location - tstream.peek.location;
    
    statement.identifier = parseIdentifier(tstream);
    match(tstream, TokenType.Colon);
    statement.statement = parseStatement(tstream);
    return statement;
}

TryStatement parseTryStatement(TokenStream tstream)
{
    auto statement = new TryStatement();
    statement.location = tstream.peek.location;
    
    match(tstream, TokenType.Try);
    statement.statement = parseStatement(tstream);
    match(tstream, TokenType.Catch);
    statement.catchStatement = parseStatement(tstream);
    return statement;
}

ThrowStatement parseThrowStatement(TokenStream tstream)
{
    auto statement = new ThrowStatement();
    
    auto throwToken = match(tstream, TokenType.Throw);
    if (tstream.peek.type == TokenType.Semicolon) { // Unlike C++.
        throw new CompilerError(tstream.peek.location, "throw statement must specify an exception.");
    }
    
    statement.exception = parseExpression(tstream);
    
    if (tstream.peek.type != TokenType.Semicolon) {
        throw new MissingSemicolonError(tstream.previous.location, "throw statement");
    }
    tstream.get();
    
    statement.location = statement.exception.location - throwToken.location;
    return statement; 
}

IfStatement parseIfStatement(TokenStream tstream)
{
    auto statement = new IfStatement();
    
    auto startToken = match(tstream, TokenType.If);
    auto openToken = match(tstream, TokenType.OpenParen);
    statement.ifCondition = parseIfCondition(tstream);
    
    if (tstream.peek.type != TokenType.CloseParen) {
        throw new PairMismatchError(openToken.location, tstream.previous.location, "if condition", ")");
    }
    auto closeToken = tstream.get();
    
    statement.location = closeToken.location - startToken.location;
    statement.thenStatement = parseStatement(tstream);
    if (tstream.peek.type == TokenType.Else) {
        match(tstream, TokenType.Else);
        statement.elseStatement = parseStatement(tstream);
    }
    
    return statement;
}

IfCondition parseIfCondition(TokenStream tstream)
{
    auto condition = new IfCondition();
    condition.location = tstream.peek.location;
    
    if (tstream.peek.type == TokenType.Auto) {
        condition.type = IfConditionType.Identifier;
        match(tstream, TokenType.Auto);
        condition.node = parseIdentifier(tstream);
        match(tstream, TokenType.Assign);
    } else {
        condition.type = IfConditionType.ExpressionOnly;
    }
    condition.expression = parseExpression(tstream);
    
    return condition;
}

WhileStatement parseWhileStatement(TokenStream tstream)
{
    auto statement = new WhileStatement();
    match(tstream, TokenType.While);
    auto openToken = match(tstream, TokenType.OpenParen);
    statement.expression = parseExpression(tstream);
    
    if (tstream.peek.type != TokenType.CloseParen) {
        throw new PairMismatchError(openToken.location, tstream.previous.location, "while condition", ")");
    }
    auto closeToken = tstream.get();
    
    statement.location = closeToken.location - openToken.location;
    statement.statement = parseStatement(tstream);
    return statement;
}


DoStatement parseDoStatement(TokenStream tstream)
{
    auto statement = new DoStatement();
    statement.location = tstream.peek.location;
    match(tstream, TokenType.Do);
    statement.statement = parseStatement(tstream);
    match(tstream, TokenType.While);
    auto openToken = match(tstream, TokenType.OpenParen);
    statement.expression = parseExpression(tstream);
    
    if (tstream.peek.type != TokenType.CloseParen) {
        throw new PairMismatchError(openToken.location, tstream.previous.location, "while condition", ")");
    }
    tstream.get();
    
    if (tstream.peek.type != TokenType.Semicolon) {
        throw new MissingSemicolonError(tstream.previous.location, "do-while statement");
    }
    tstream.get();
    return statement;
}

ForStatement parseForStatement(TokenStream tstream)
{
    auto forToken = match(tstream, TokenType.For);
    auto openToken = match(tstream, TokenType.OpenParen);
    
    auto statement = new ForStatement;
    auto initialise = parseStatement(tstream, true);
    if (initialise.type != StatementType.EmptyStatement) {
        statement.initialise = initialise;
    }
    
    if (tstream.peek.type != TokenType.Semicolon) {
        statement.test = parseExpression(tstream);
    }
    match(tstream, TokenType.Semicolon);
    
    if (tstream.peek.type != TokenType.CloseParen) {
        statement.increment = parseExpression(tstream);
    }
    
    if (tstream.peek.type != TokenType.CloseParen) {
        throw new PairMismatchError(openToken.location, tstream.previous.location, "for loop", ")");
    }
    auto closeToken = tstream.get();
    statement.location = closeToken.location - openToken.location;
    
    statement.statement = parseStatement(tstream);
    
    return statement;
}

ForeachStatement parseForeachStatement(TokenStream tstream)
{
    auto statement = new ForeachStatement();
    statement.location = tstream.peek.location;
    
    match(tstream, TokenType.Foreach);
    auto openToken = match(tstream, TokenType.OpenParen);
    
    ForeachType parseForeachType()
    {
        auto type = new ForeachType();
        type.location = tstream.peek.location;
        
        if (tstream.peek.type == TokenType.Ref) {
            tstream.get();
            type.isRef = true;
        }
        
        if (tstream.peek.type == TokenType.Identifier &&
           (tstream.lookahead(1).type == TokenType.Comma ||
            tstream.lookahead(1).type == TokenType.Semicolon)) {
            type.type = ForeachTypeType.Implicit;
            type.identifier = parseIdentifier(tstream);
        } else {
            type.type = ForeachTypeType.Explicit;
            type.explicitType = parseType(tstream);
            type.identifier = parseIdentifier(tstream);
        }
        
        type.location.spanTo(tstream.previous.location);
        return type;
    }
    
    do {
        statement.foreachTypes ~= parseForeachType();
        
        if (tstream.peek.type == TokenType.Comma) {
            tstream.get();
        }
    } while(tstream.peek.type != TokenType.Semicolon);
    
    match(tstream, TokenType.Semicolon);
    
    statement.expression = parseExpression(tstream);
    
    if (tstream.peek.type == TokenType.DoubleDot) {
        tstream.get();
        statement.form = ForeachForm.Range;
        
        if (statement.foreachTypes.length > 1) {
            auto invalidArea = statement.foreachTypes[$-1].location - statement.foreachTypes[1].location;
            throw new CompilerError(invalidArea, "range foreach must only have one foreach variable.");
        }
        
        statement.rangeEnd = parseExpression(tstream);
    } else {
        statement.form = ForeachForm.Aggregate;
    }
    
    if (tstream.peek.type != TokenType.CloseParen) {
        throw new PairMismatchError(openToken.location, tstream.previous.location, "foreach statement", ")");
    }
    auto closeToken = tstream.get();
    
    statement.location = closeToken.location - openToken.location;
    statement.statement = parseStatement(tstream);
    
    return statement;
}

BreakStatement parseBreakStatement(TokenStream tstream)
{
    auto statement = new BreakStatement();
    statement.location = tstream.peek.location;
    match(tstream, TokenType.Break);
    
    if (tstream.peek.type == TokenType.Identifier) {
        statement.target = parseIdentifier(tstream);
        statement.location.spanTo(statement.target.location);
    }
    
    if (tstream.peek.type != TokenType.Semicolon) {
        throw new MissingSemicolonError(tstream.previous.location, "break statement");
    }
    tstream.get();

    return statement;
}

ContinueStatement parseContinueStatement(TokenStream tstream)
{
    auto statement = new ContinueStatement();
    statement.location = tstream.peek.location;
    match(tstream, TokenType.Continue);
    
    if (tstream.peek.type == TokenType.Identifier) {
        statement.target = parseIdentifier(tstream);
        statement.location.spanTo(statement.target.location);
    }
    
    if (tstream.peek.type != TokenType.Semicolon) {
        throw new MissingSemicolonError(tstream.previous.location, "continue statement");
    }
    tstream.get();

    return statement;
}

SwitchStatement parseSwitchStatement(TokenStream tstream)
{
    auto statement = new SwitchStatement();
    statement.location = tstream.peek.location;
    
    if (tstream.peek.type == TokenType.Final) {
        statement.isFinal = true;
        tstream.get();
    }
    
    auto startToken = match(tstream, TokenType.Switch);
    auto openToken = match(tstream, TokenType.OpenParen);
    
    statement.controlExpression = parseExpression(tstream);
    
    if (tstream.peek.type != TokenType.CloseParen) {
        throw new PairMismatchError(openToken.location, tstream.previous.location, "switch control expression", ")");
    }
    auto closeToken = tstream.get();
    statement.location.spanTo(closeToken.location);
    
    statement.statement = parseStatement(tstream);
    
    return statement;
}

// Statement lists in case and default statements.
Statement[] parseScopeStatementList(TokenStream tstream)
{
    Statement[] list;
    
    while (tstream.peek.type != TokenType.Case &&
           tstream.peek.type != TokenType.Default &&
           tstream.peek.type != TokenType.CloseBrace) {
        list ~= parseStatement(tstream, true);
    }
    
    return list;
}

SwitchSubStatement parseCaseStatement(TokenStream tstream, out StatementType type)
{
    auto startToken = match(tstream, TokenType.Case);
    auto firstExpression = parseConditionalExpression(tstream);
    
    SwitchSubStatement statement;
    
    if (tstream.peek.type == TokenType.DoubleDot) {
        tstream.get();
        
        auto caseRange = new CaseRangeStatement();
        caseRange.rangeBegin = firstExpression;
        caseRange.rangeEnd = parseConditionalExpression(tstream);
        
        if (tstream.peek.type != TokenType.Colon) {
            throw new MissingColonError(tstream.previous.location, "case range");
        }
        auto closeToken = tstream.get();
        
        caseRange.location = closeToken.location - startToken.location;
        statement = caseRange;
    } else {
        auto caseList = new CaseListStatement();
        caseList.cases ~= firstExpression;
        if (tstream.peek.type == TokenType.Comma) {
            tstream.get();
        
            while (tstream.peek.type != TokenType.Colon) {
                caseList.cases ~= parseConditionalExpression(tstream);
                if (tstream.peek.type != TokenType.Colon) {
                    if (tstream.peek.type != TokenType.Comma) {
                        throw new PairMismatchError(startToken.location, tstream.previous.location, "case list", ":");
                    }
                    tstream.get();
                }
            }
        } else {
            if (tstream.peek.type != TokenType.Colon) {
                throw new MissingColonError(tstream.previous.location, "case expression");
            }
        }
        auto closeToken = tstream.get();
        
        caseList.location = closeToken.location - startToken.location;
        statement = caseList;
    }
    
    statement.statementList = parseScopeStatementList(tstream);
    return statement;
}

SwitchSubStatement parseDefaultStatement(TokenStream tstream)
{
    auto startToken = match(tstream, TokenType.Default);
    
    if (tstream.peek.type != TokenType.Colon) {
        throw new MissingColonError(startToken.location, "switch default");
    }
    auto closeToken = tstream.get();
    
    auto statement = new SwitchSubStatement();
    statement.location = closeToken.location - startToken.location;
    statement.statementList = parseScopeStatementList(tstream);
    return statement;
}

ReturnStatement parseReturnStatement(TokenStream tstream)
{
    auto statement = new ReturnStatement();
    statement.location = tstream.peek.location;
    match(tstream, TokenType.Return);
    if (tstream.peek.type != TokenType.Semicolon) {
        statement.retval = parseExpression(tstream);
    }
    if (tstream.peek.type != TokenType.Semicolon) {
        throw new MissingSemicolonError(tstream.previous.location, "return statement");
    }
    tstream.get();
    return statement;
}

DeclarationStatement parseDeclarationStatement(TokenStream tstream)
{
    auto statement = new DeclarationStatement();
    statement.location = tstream.peek.location;
    statement.declaration = parseDeclaration(tstream);
    return statement;
}

ExpressionStatement parseExpressionStatement(TokenStream tstream)
{
    auto statement = new ExpressionStatement();
    statement.location = tstream.peek.location;
    statement.expression = parseExpression(tstream);
    if(tstream.peek.type != TokenType.Semicolon) {
        throw new MissingSemicolonError(tstream.lookbehind(1).location, "expression");
    }
    tstream.get();
    return statement;
}

PragmaStatement parsePragmaStatement(TokenStream tstream)
{
    auto statement = new PragmaStatement();
    statement.location = tstream.peek.location;
    
    statement.thePragma = parsePragma(tstream);
    
    if (tstream.peek.type == TokenType.Semicolon) {
        tstream.get();
    } else {
        statement.statement = parseStatement(tstream);
    }
    return statement;
}

MixinStatement parseMixinStatement(TokenStream tstream)
{
    auto statement = new MixinStatement();
    
    auto startToken = match(tstream, TokenType.Mixin);
    auto openToken = match(tstream, TokenType.OpenParen);
    statement.code = parseConditionalExpression(tstream);
    
    if (tstream.peek.type != TokenType.CloseParen) {
        throw new PairMismatchError(openToken.location, tstream.previous.location, "mixin statement", ")");
    }
    auto closeToken = tstream.get();
    
    if (tstream.peek.type != TokenType.Semicolon) {
        throw new MissingSemicolonError(closeToken.location, "mixin statement");
    }
    tstream.get();
    
    statement.location = closeToken.location - startToken.location;
    return statement;
}

AsmStatement parseAsmStatement(TokenStream tstream)
{
    auto statement = new AsmStatement();
    statement.location = tstream.peek.location;
    
    match(tstream, TokenType.Asm);
    match(tstream, TokenType.OpenBrace);
    while (tstream.peek.type != TokenType.CloseBrace) {
        if (tstream.peek.type == TokenType.End) {
            throw new CompilerError(tstream.peek.location, "unexpected EOF in asm statement.");
        }
        statement.tokens~=tstream.get();
    }
    match(tstream, TokenType.CloseBrace);
    return statement;
}
