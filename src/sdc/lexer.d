/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdl.d for more details.
 */ 
module sdc.lexer;

import std.stdio;
import std.string;
import std.conv;
import std.ctype;
import std.uni;
import std.c.time;

import sdc.source;
import sdc.location;
import sdc.tokenstream;
import sdc.compilererror;
import sdc.info;


TokenStream lex(Source source)
{
    auto tstream = new TokenStream(source);
    
    lexNext(tstream);
    while (tstream.lastAdded.type != TokenType.End) {
        bool retval = lexNext(tstream);
        if (!retval) {
            error(tstream.source.location, 
                  format("unexpected character: '%s'", tstream.source.peek)); 
        }
    }
    
    return tstream;
}

void error(Location loc, string message)
{
    stderr.writeln(format("%s: error: %s.", loc, message));
    throw new CompilerError();
}

void warning(Location loc, string message)
{
    stderr.writeln(format("%s: warning: %s.", loc, message));
}

void match(TokenStream tstream, dchar c)
{
    if (tstream.source.peek != c) {
        error(tstream.source.location, format("expected '%s' got '%s'", c, tstream.source.peek));
    }
    tstream.source.get();
}

Token currentLocationToken(TokenStream tstream)
{
    auto t = new Token();
    t.location = tstream.source.location;
    return t;
}

bool lexNext(TokenStream tstream)
{
    TokenType type = nextLex(tstream);
    
    switch (type) {
    case TokenType.End:
        return lexEOF(tstream);
    case TokenType.Identifier:
        return lexIdentifier(tstream);
    case TokenType.CharacterLiteral:
        return lexCharacter(tstream);
    case TokenType.StringLiteral:
        return lexString(tstream);
    case TokenType.Symbol:
        return lexSymbol(tstream);
    case TokenType.Number:
        return lexNumber(tstream);
    default:
        break;
    }
    
    return false;
}

/// Return which TokenType to try an lex next. 
TokenType nextLex(TokenStream tstream)
{
    skipWhitespace(tstream);
    if (tstream.source.eof) {
        return TokenType.End;
    }
    
    if (isUniAlpha(tstream.source.peek) || tstream.source.peek == '_' || tstream.source.peek == '@') {
        bool lookaheadEOF;
        if (tstream.source.peek == 'r' || tstream.source.peek == 'q' || tstream.source.peek == 'x') {
            dchar oneAhead = tstream.source.lookahead(1, lookaheadEOF);
            if (oneAhead == '"') {
                return TokenType.StringLiteral;
            } else if (tstream.source.peek == 'q' && oneAhead == '{') {
                return TokenType.StringLiteral;
            }
        }
        return TokenType.Identifier;
    }
    
    if (tstream.source.peek == '\'') {
        return TokenType.CharacterLiteral;
    }
    
    if (tstream.source.peek == '"' || tstream.source.peek == '`') {
        return TokenType.StringLiteral;
    }
    
    if (isdigit(tstream.source.peek) || tstream.source.peek == '.') {
        return TokenType.Number;
    }
    
    return TokenType.Symbol;
}


void skipWhitespace(TokenStream tstream)
{
    while (isspace(tstream.source.peek)) {
        tstream.source.get();
        if (tstream.source.eof) break;
    }
}

void skipLineComment(TokenStream tstream)
{
    match(tstream, '/');
    while (tstream.source.peek != '\n') {
        tstream.source.get();
        if (tstream.source.eof) return;
    }
}

void skipBlockComment(TokenStream tstream)
{
    bool looping = true;
    while (looping) {
        tstream.source.get();
        if (tstream.source.eof) {
            error(tstream.source.location, "unterminated block comment");
        }
        if (tstream.source.peek == '/') {
            match(tstream, '/');
            if (tstream.source.peek == '*') {
                warning(tstream.source.location, "'/*' inside of block comment");
            }
        }
        if (tstream.source.peek == '*') {
            match(tstream, '*');
            if (tstream.source.peek == '/') {
                match(tstream, '/');
                looping = false;
            }
        } 
    }
}

void skipNestingComment(TokenStream tstream)
{
    int depth = 1;
    while (depth > 0) {
        tstream.source.get();
        if (tstream.source.eof) {
            error(tstream.source.location, "unterminated nesting comment");
        }
        if (tstream.source.peek == '+') {
            match(tstream, '+');
            if (tstream.source.peek == '/') {
                depth--;
            }
        }
        if (tstream.source.peek == '/') {
            match(tstream, '/');
            if (tstream.source.peek == '+') {
                depth++;
            }
        }
    }
}

bool lexEOF(TokenStream tstream)
{
    if (!tstream.source.eof) {
        return false;
    }
    
    auto eof = currentLocationToken(tstream);
    eof.type = TokenType.End;
    eof.value = "END";
    tstream.addToken(eof);
    return true;
}

// This is a bit of a dog's breakfast.
bool lexIdentifier(TokenStream tstream)
{
    assert(isUniAlpha(tstream.source.peek) || tstream.source.peek == '_' || tstream.source.peek == '@');
    
    auto identToken = currentLocationToken(tstream);
    Mark m = tstream.source.save();
    tstream.source.get();
    
    while (isUniAlpha(tstream.source.peek) || isdigit(tstream.source.peek) || tstream.source.peek == '_') {
        tstream.source.get();
        if (tstream.source.eof) break;
    }
    
    identToken.value = tstream.source.sliceFrom(m);
    if (identToken.value[0] == '@') {
        auto i = identifierType(identToken.value);
        if (i == TokenType.Identifier) {
            auto err = format("invalid @ attribute '%s'", identToken.value);
            error(identToken.location, err);
        }
    }
    
    
    bool retval = lexSpecialToken(tstream, identToken);
    if (retval) return true;
    identToken.type = identifierType(identToken.value);
    tstream.addToken(identToken);
    
    return true;
}

bool lexSpecialToken(TokenStream tstream, Token token)
{
    immutable string[12] months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    immutable string[7] days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
    
    if (token.value == "__DATE__") {
        auto thetime = time(null);
        auto tm = localtime(&thetime);
        token.type = TokenType.StringLiteral;
        token.value = format(`"%s %02s %s"`,
                             months[tm.tm_mon], 
                             tm.tm_mday,
                             1900 + tm.tm_year);
        tstream.addToken(token);
        return true;
    } else if (token.value == "__EOF__") {
        tstream.source.eof = true;
        return true;
    } else if (token.value == "__TIME__") {
        auto thetime = time(null);
        auto tm = localtime(&thetime);
        token.type = TokenType.StringLiteral;
        token.value = format(`"%02s:%02s:%02s"`, tm.tm_hour, tm.tm_min,
                             tm.tm_sec);
        tstream.addToken(token);
        return true;
    } else if (token.value == "__TIMESTAMP__") {
        auto thetime = time(null);
        auto tm = localtime(&thetime);
        token.type = TokenType.StringLiteral;
        token.value = format(`"%s %s %02s %02s:%02s:%02s %s"`,
                             days[tm.tm_wday], months[tm.tm_mon],
                             tm.tm_mday, tm.tm_hour, tm.tm_min, tm.tm_sec,
                             1900 + tm.tm_year);
        tstream.addToken(token);
        return true;
    } else if (token.value == "__VENDOR__") {
        token.type = TokenType.StringLiteral;
        token.value = sdc.info.VENDOR;
        tstream.addToken(token);
        return true;
    } else if (token.value == "__VERSION__") {
        token.type = TokenType.IntegerLiteral;
        token.value = to!string(sdc.info.VERSION);
        tstream.addToken(token);
        return true;
    }
    return false;
}

bool lexSymbol(TokenStream tstream)
{
    switch (tstream.source.peek) {
    case '/':
        return lexSlash(tstream);
    case '.':
        return lexDot(tstream);
    case '&':
        return lexSymbolOrSymbolAssignOrDoubleSymbol(tstream, '&', 
               TokenType.Ampersand, TokenType.AmpersandAssign, TokenType.DoubleAmpersand);
    case '|':
        return lexSymbolOrSymbolAssignOrDoubleSymbol(tstream, '|',
               TokenType.Pipe, TokenType.PipeAssign, TokenType.DoublePipe);
    case '-':
        return lexSymbolOrSymbolAssignOrDoubleSymbol(tstream, '-',
               TokenType.Dash, TokenType.DashAssign, TokenType.DoubleDash);
    case '+':
        return lexSymbolOrSymbolAssignOrDoubleSymbol(tstream, '+',
               TokenType.Plus, TokenType.PlusAssign, TokenType.DoublePlus);
    case '<':
        return lexLess(tstream);
    case '>':
        return lexGreater(tstream);
    case '!':
        return lexBang(tstream);
    case '(':
        return lexOpenParen(tstream);
    case ')':
        return lexSingleSymbol(tstream, ')', TokenType.CloseParen);
    case '[':
        return lexSingleSymbol(tstream, '[', TokenType.OpenBracket);
    case ']':
        return lexSingleSymbol(tstream, ']', TokenType.CloseBracket);
    case '{':
        return lexSingleSymbol(tstream, '{', TokenType.OpenBrace);
    case '}':
        return lexSingleSymbol(tstream, '}', TokenType.CloseBrace);
    case '?':
        return lexSingleSymbol(tstream, '?', TokenType.QuestionMark);
    case ',':
        return lexSingleSymbol(tstream, ',', TokenType.Comma);
    case ';':
        return lexSingleSymbol(tstream, ';', TokenType.Semicolon);
    case ':':
        return lexSingleSymbol(tstream, ':', TokenType.Colon);
    case '$':
        return lexSingleSymbol(tstream, '$', TokenType.Dollar);
    case '=':
        return lexSymbolOrSymbolAssign(tstream, '=', TokenType.Assign, TokenType.DoubleAssign);
    case '*':
        return lexSymbolOrSymbolAssignOrDoubleSymbol(tstream, '*', 
               TokenType.Asterix, TokenType.AsterixAssign, TokenType.DoubleAsterix);
    case '%':
        return lexSymbolOrSymbolAssign(tstream, '%', TokenType.Percent, TokenType.PercentAssign);
    case '^':
        return lexSymbolOrSymbolAssign(tstream, '^', TokenType.Caret, TokenType.CaretAssign);
    case '~':
        return lexSymbolOrSymbolAssign(tstream, '~', TokenType.Tilde, TokenType.TildeAssign);
    default:
        break;
    }
    return false;
    
}

bool lexSlash(TokenStream tstream)
{
    auto token = currentLocationToken(tstream);
    auto mark = tstream.source.save();
    auto type = TokenType.Slash;
    match(tstream, '/');
    
    switch (tstream.source.peek) {
    case '=':
        match(tstream, '=');
        type = TokenType.SlashAssign;
        break;
    case '/':
        skipLineComment(tstream);
        return true;
    case '*':
        skipBlockComment(tstream);
        return true;
    case '+':
        skipNestingComment(tstream);
        return true;
    default:
        break;
    }
    
    token.type = type;
    token.value = tstream.source.sliceFrom(mark);
    tstream.addToken(token);
    
    return true;
}

bool lexDot(TokenStream tstream)
{
    auto token = currentLocationToken(tstream);
    auto mark = tstream.source.save();
    auto type = TokenType.Dot;
    match(tstream, '.');
    
    switch (tstream.source.peek) {
    case '.':
        match(tstream, '.');
        if (tstream.source.peek == '.') {
            match(tstream, '.');
            type = TokenType.TripleDot;
        } else {
            type = TokenType.DoubleDot;
        }
    default:
        break;
    }
    
    token.type = type;
    token.value = tstream.source.sliceFrom(mark);
    tstream.addToken(token);
    
    return true;
}


bool lexSymbolOrSymbolAssignOrDoubleSymbol(TokenStream tstream, dchar c, TokenType symbol, TokenType symbolAssign, TokenType doubleSymbol)
{
    auto token = currentLocationToken(tstream);
    auto mark = tstream.source.save();
    auto type = symbol;
    match(tstream, c);
    
    if (tstream.source.peek == '=') {
        match(tstream, '=');
        type = symbolAssign;
    } else if (tstream.source.peek == c) {
        match(tstream, c);
        type = doubleSymbol;
    }
    
    token.type = type;
    token.value = tstream.source.sliceFrom(mark);
    tstream.addToken(token);
    
    return true;
}

bool lexSingleSymbol(TokenStream tstream, dchar c, TokenType symbol)
{
    auto token = currentLocationToken(tstream);
    auto mark = tstream.source.save();
    match(tstream, c);
    token.type = symbol;
    token.value = tstream.source.sliceFrom(mark);
    tstream.addToken(token);
    return true;
}

bool lexSymbolOrSymbolAssign(TokenStream tstream, dchar c, TokenType symbol, TokenType symbolAssign)
{
    auto token = currentLocationToken(tstream);
    auto mark = tstream.source.save();
    auto type = symbol;
    match(tstream, c);
    
    if (tstream.source.peek == '=') {
        match(tstream, '=');
        type = symbolAssign;
    }
    
    token.type = type;
    token.value = tstream.source.sliceFrom(mark);
    tstream.addToken(token);
    
    return true;
}
    

bool lexOpenParen(TokenStream tstream)
{
    if (!lexOpKirbyRape(tstream)) {
        Mark m = tstream.source.save();
        auto token = currentLocationToken(tstream);
        match(tstream, '(');
        token.type = TokenType.OpenParen;
        token.value = tstream.source.sliceFrom(m);
        tstream.addToken(token);
    }
    
    return true;
}

bool lexOpKirbyRape(TokenStream tstream)
{
    bool eof = false;
    dchar one = tstream.source.lookahead(1, eof);
    if (eof || one != '>') return false;
    
    dchar two = tstream.source.lookahead(2, eof);
    if (eof || two != '^') return false;
    
    dchar three = tstream.source.lookahead(3, eof);
    if (eof || three != '(') return false;
    
    dchar four = tstream.source.lookahead(4, eof);
    if (eof || four != '>') return false;
    
    dchar five = tstream.source.lookahead(5, eof);
    if (eof || five != 'O') return false;

    dchar six = tstream.source.lookahead(6, eof);
    if (eof || six != '_') return false;
    
    dchar seven = tstream.source.lookahead(7, eof);
    if (eof || seven != 'O') return false;
    
    dchar eight = tstream.source.lookahead(8, eof);
    if (eof || eight != ')') return false;
    
    dchar nine = tstream.source.lookahead(9, eof);
    if (eof || nine != '>') return false;
    
    error(tstream.source.location, "no means no");
    
    assert(false);
}

bool lexLess(TokenStream tstream)
{
    auto token = currentLocationToken(tstream);
    auto mark = tstream.source.save();
    token.type = TokenType.Less;
    match(tstream, '<');
    
    if (tstream.source.peek == '=') {
        match(tstream, '=');
        token.type = TokenType.LessAssign;
    } else if (tstream.source.peek == '<') {
        match(tstream, '<');
        if (tstream.source.peek == '=') {
            match(tstream, '=');
            token.type = TokenType.DoubleLessAssign;
        } else {
            token.type = TokenType.DoubleLess;
        }
    } else if (tstream.source.peek == '>') {
        match(tstream, '>');
        if (tstream.source.peek == '=') {
            match(tstream, '=');
            token.type = TokenType.LessGreaterAssign;
        } else {
            token.type = TokenType.LessGreater;
        }
    }
    
    token.value = tstream.source.sliceFrom(mark);
    tstream.addToken(token);
    return true;
}

bool lexGreater(TokenStream tstream)
{
    auto token = currentLocationToken(tstream);
    auto mark = tstream.source.save();
    token.type = TokenType.Greater;
    match(tstream, '>');
    
    if (tstream.source.peek == '=') {
        match(tstream, '=');
        token.type = TokenType.GreaterAssign;
    } else if (tstream.source.peek == '>') {
        match(tstream, '>');
        if (tstream.source.peek == '=') {
            match(tstream, '=');
            token.type = TokenType.DoubleGreaterAssign;
        } else if (tstream.source.peek == '>') {
            match(tstream, '>');
            if (tstream.source.peek == '=') {
                match(tstream, '=');
                token.type = TokenType.TripleGreaterAssign;
            } else {
                token.type = TokenType.TripleGreater;
            }
        } else {
            token.type = TokenType.DoubleGreater;
        }
    } 
    
    token.value = tstream.source.sliceFrom(mark);
    tstream.addToken(token);
    return true;
}

bool lexBang(TokenStream tstream)
{
    auto token = currentLocationToken(tstream);
    auto mark = tstream.source.save();
    token.type = TokenType.Bang;
    match(tstream, '!');
    
    if (tstream.source.peek == '=') {
        match(tstream, '=');
        token.type = TokenType.BangAssign;
    } else if (tstream.source.peek == '>') {
        match(tstream, '>');
        if (tstream.source.peek == '=') {
            token.type = TokenType.BangGreaterAssign;
        } else {
            token.type = TokenType.BangGreater;
        }
    } else if (tstream.source.peek == '<') {
        match(tstream, '<');
        if (tstream.source.peek == '>') {
            match(tstream, '>');
            if (tstream.source.peek == '=') {
                match(tstream, '=');
                token.type = TokenType.BangLessGreaterAssign;
            } else {
                token.type = TokenType.BangLessGreater;
            }
        } else if (tstream.source.peek == '=') {
            match(tstream, '=');
            token.type = TokenType.BangLessAssign;
        } else {
            token.type = TokenType.BangLess;
        }
    }
    
    token.value = tstream.source.sliceFrom(mark);
    tstream.addToken(token);
    return true;
}

// Escape sequences are not expanded inside of the lexer.

bool lexCharacter(TokenStream tstream)
{
    auto token = currentLocationToken(tstream);
    auto mark = tstream.source.save();
    match(tstream, '\'');
    while (tstream.source.peek != '\'') {
        if (tstream.source.eof) {
            error(token.location, "unterminated character literal");
        }
        if (tstream.source.peek == '\\') {
            match(tstream, '\\');
            if (tstream.source.peek == '\'') {
                match(tstream, '\'');
            }
        } else {
            tstream.source.get();
        }
    }
    match(tstream, '\'');
    
    token.type = TokenType.CharacterLiteral;
    token.value = tstream.source.sliceFrom(mark);
    tstream.addToken(token);
    return true;
}

bool lexString(TokenStream tstream)
{
    auto token = currentLocationToken(tstream);
    auto mark = tstream.source.save();
    dchar terminator;
    bool raw;
    bool postfix = true;
    
    if (tstream.source.peek == 'r') {
        match(tstream, 'r');
        raw = true;
        terminator = '"';
    } else if (tstream.source.peek == 'q') {
        error(token.location, "strings that start with q are unimplemented");
    } else if (tstream.source.peek == 'x') {
        match(tstream, 'x');
        raw = false;
        terminator = '"';
    } else if (tstream.source.peek == '`') {
        raw = true;
        terminator = '`';
    } else if (tstream.source.peek == '"') {
        raw = false;
        terminator = '"';
    } else {
        return false;
    }
    
    match(tstream, terminator);
    while (tstream.source.peek != terminator) {
        if (tstream.source.eof) {
            error(token.location, "unterminated string literal");
        }
        if (!raw && tstream.source.peek == '\\') {
            match(tstream, '\\');
            if (tstream.source.peek == terminator) {
                match(tstream, terminator);
            }
        } else {
            tstream.source.get();
        }
    }
    match(tstream, terminator);
    dchar postfixc = tstream.source.peek;
    if ((postfixc == 'c' || postfixc == 'w' || postfixc == 'd') && postfix) {
        match(tstream, postfixc);
    }
    
    token.type = TokenType.StringLiteral;
    token.value = tstream.source.sliceFrom(mark);
    tstream.addToken(token);
    
    return true;
}


bool lexNumber(TokenStream tstream)
{
    bool floatingLiteral;
    bool hex;
    bool lookEOF;
    dchar first = tstream.source.peek;
    dchar second = tstream.source.lookahead(1, lookEOF);
    
    if (first == '0') {
        if (second == 'b' || second == 'B') {
            floatingLiteral = false;     
            goto _eval;
        } else if (second == 'x' || second == 'X') {
        } else {
            floatingLiteral = false; 
            goto _eval;
        }
    }
    
    dchar c;
    size_t lookIndex = 2;
    LOOP: while (true) {
        c = tstream.source.lookahead(lookIndex, lookEOF);
        if (lookEOF) break;
        
        switch (c) {
        case '0': case '1': case '2': case '3': case '4': case '5':
        case '6': case '7': case '8': case '9': case 'a': case 'b':
        case 'c': case 'd': case 'e': case 'f': case 'A': case 'B':
        case 'C': case 'D': case 'E': case 'F': case '+': case '-':
        case '_':
            break;
        case '.': case 'p': case 'P': case 'i':
            floatingLiteral = true;
            break LOOP;
        default:
            break LOOP;
        }
    }
    
    _eval:
    
    if (floatingLiteral) {
        return lexFloat(tstream);
    } else {
        return lexInteger(tstream);
    }
}

bool lexInteger(TokenStream tstream)
{
    auto token = currentLocationToken(tstream);
    auto mark = tstream.source.save();
    
    tstream.source.get();
    while (isdigit(tstream.source.peek)) {
        if (tstream.source.eof) break;
        tstream.source.get();
    }
    
    token.type = TokenType.IntegerLiteral;
    token.value = tstream.source.sliceFrom(mark);
    tstream.addToken(token);
    return true;
}

bool lexFloat(TokenStream tstream)
{
    return false;
}
