/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdl.d for more details.
 * 
 * lexer.d: split input source file into a list of tokens.
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

private:

void error(Location loc, string message)
{
    stderr.writeln(format("%s: error: %s.", loc, message));
    throw new CompilerError();
}

void warning(Location loc, string message)
{
    stderr.writeln(format("%s: warning: %s.", loc, message));
}

void match(Source src, dchar c)
{
    if (src.peek != c) {
        error(src.location, format("expected '%s' got '%s'", c, src.peek));
    }
    src.get();
}

Token currentLocationToken(TokenStream tstream)
{
    auto t = new Token();
    t.location = tstream.source.location;
    return t;
}

bool ishex(dchar c)
{
    return isdigit(c) || c >= 'A' && c <= 'F' || c >= 'a' && c <= 'f';
}

pure bool isoctal(dchar c)
{
    return c >= '0' && c <= '7';
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
    
    if (isdigit(tstream.source.peek)) {
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
    match(tstream.source, '/');
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
            match(tstream.source, '/');
            if (tstream.source.peek == '*') {
                warning(tstream.source.location, "'/*' inside of block comment");
            }
        }
        if (tstream.source.peek == '*') {
            match(tstream.source, '*');
            if (tstream.source.peek == '/') {
                match(tstream.source, '/');
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
            match(tstream.source, '+');
            if (tstream.source.peek == '/') {
                depth--;
            }
        }
        if (tstream.source.peek == '/') {
            match(tstream.source, '/');
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
    match(tstream.source, '/');
    
    switch (tstream.source.peek) {
    case '=':
        match(tstream.source, '=');
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
    match(tstream.source, '.');
    
    switch (tstream.source.peek) {
    case '.':
        match(tstream.source, '.');
        if (tstream.source.peek == '.') {
            match(tstream.source, '.');
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
    match(tstream.source, c);
    
    if (tstream.source.peek == '=') {
        match(tstream.source, '=');
        type = symbolAssign;
    } else if (tstream.source.peek == c) {
        match(tstream.source, c);
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
    match(tstream.source, c);
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
    match(tstream.source, c);
    
    if (tstream.source.peek == '=') {
        match(tstream.source, '=');
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
        match(tstream.source, '(');
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
    match(tstream.source, '<');
    
    if (tstream.source.peek == '=') {
        match(tstream.source, '=');
        token.type = TokenType.LessAssign;
    } else if (tstream.source.peek == '<') {
        match(tstream.source, '<');
        if (tstream.source.peek == '=') {
            match(tstream.source, '=');
            token.type = TokenType.DoubleLessAssign;
        } else {
            token.type = TokenType.DoubleLess;
        }
    } else if (tstream.source.peek == '>') {
        match(tstream.source, '>');
        if (tstream.source.peek == '=') {
            match(tstream.source, '=');
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
    match(tstream.source, '>');
    
    if (tstream.source.peek == '=') {
        match(tstream.source, '=');
        token.type = TokenType.GreaterAssign;
    } else if (tstream.source.peek == '>') {
        match(tstream.source, '>');
        if (tstream.source.peek == '=') {
            match(tstream.source, '=');
            token.type = TokenType.DoubleGreaterAssign;
        } else if (tstream.source.peek == '>') {
            match(tstream.source, '>');
            if (tstream.source.peek == '=') {
                match(tstream.source, '=');
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
    match(tstream.source, '!');
    
    if (tstream.source.peek == '=') {
        match(tstream.source, '=');
        token.type = TokenType.BangAssign;
    } else if (tstream.source.peek == '>') {
        match(tstream.source, '>');
        if (tstream.source.peek == '=') {
            token.type = TokenType.BangGreaterAssign;
        } else {
            token.type = TokenType.BangGreater;
        }
    } else if (tstream.source.peek == '<') {
        match(tstream.source, '<');
        if (tstream.source.peek == '>') {
            match(tstream.source, '>');
            if (tstream.source.peek == '=') {
                match(tstream.source, '=');
                token.type = TokenType.BangLessGreaterAssign;
            } else {
                token.type = TokenType.BangLessGreater;
            }
        } else if (tstream.source.peek == '=') {
            match(tstream.source, '=');
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
    match(tstream.source, '\'');
    while (tstream.source.peek != '\'') {
        if (tstream.source.eof) {
            error(token.location, "unterminated character literal");
        }
        if (tstream.source.peek == '\\') {
            match(tstream.source, '\\');
            tstream.source.get();
        } else {
            tstream.source.get();
        }
    }
    match(tstream.source, '\'');
    
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
        match(tstream.source, 'r');
        raw = true;
        terminator = '"';
    } else if (tstream.source.peek == 'q') {
        return lexQString(tstream);
    } else if (tstream.source.peek == 'x') {
        match(tstream.source, 'x');
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
    
    match(tstream.source, terminator);
    while (tstream.source.peek != terminator) {
        if (tstream.source.eof) {
            error(token.location, "unterminated string literal");
        }
        if (!raw && tstream.source.peek == '\\') {
            match(tstream.source, '\\');
            tstream.source.get();
        } else {
            tstream.source.get();
        }
    }
    match(tstream.source, terminator);
    dchar postfixc = tstream.source.peek;
    if ((postfixc == 'c' || postfixc == 'w' || postfixc == 'd') && postfix) {
        match(tstream.source, postfixc);
    }
    
    token.type = TokenType.StringLiteral;
    token.value = tstream.source.sliceFrom(mark);
    tstream.addToken(token);
    
    return true;
}

bool lexQString(TokenStream tstream)
{
    auto token = currentLocationToken(tstream);
    token.type = TokenType.StringLiteral;
    auto mark = tstream.source.save();
    bool leof;
    if (tstream.source.lookahead(1, leof) == '{') {
        return lexTokenString(tstream);
    }
    match(tstream.source, 'q');
    match(tstream.source, '"');
    
    dchar opendelimiter, closedelimiter;
    switch (tstream.source.peek) {
    case '[':
        opendelimiter = '[';
        closedelimiter = ']';
        break;
    case '(':
        opendelimiter = '(';
        closedelimiter = ')';
        break;
    case '<':
        opendelimiter = '<';
        closedelimiter = '>';
        break;
    case '{':
        opendelimiter = '{';
        closedelimiter = '}';
        break;
    default:
        assert(false);
    }
    
    match(tstream.source, opendelimiter);
    int nest = 1;
    while (nest > 0) {
        if (tstream.source.eof) {
            error(token.location, "unterminated string");
        }
        if (tstream.source.peek == opendelimiter) {
            match(tstream.source, opendelimiter);
            nest++;
        } else if (tstream.source.peek == closedelimiter) {
            match(tstream.source, closedelimiter);
            nest--;
            if (nest == 0) {
                match(tstream.source, '"');
            }
        } else {
            tstream.source.get();
        }
    }
    
    token.value = tstream.source.sliceFrom(mark);
    tstream.addToken(token);
    return true;
}

bool lexTokenString(TokenStream tstream)
{
    auto token = currentLocationToken(tstream);
    token.type = TokenType.StringLiteral;
    auto mark = tstream.source.save();
    match(tstream.source, 'q');
    match(tstream.source, '{');
    auto dummystream = new TokenStream(tstream.source);
    
    int nest = 1;
    while (nest > 0) {
        bool retval = lexNext(dummystream);
        if (!retval) {
            error(dummystream.source.location, format("expected token, got '%s'", tstream.source.peek));
            return false;
        }
        switch (dummystream.lastAdded.type) {
        case TokenType.OpenBrace:
            nest++;
            break;
        case TokenType.CloseBrace:
            nest--;
            break;
        case TokenType.End:
            error(dummystream.source.location, "unterminated token string");
            break;
        default:
            break;
        }
    }
    
    token.value = tstream.source.sliceFrom(mark);
    tstream.addToken(token);
    return true;
}

// This function was adapted from DMD.
bool lexNumber(TokenStream tstream)
{
    enum State { Initial, Zero, Decimal, Octal, Octale, 
                 Hex, Binary, HexZero, BinaryZero }
    
    auto token = currentLocationToken(tstream);
    auto mark = tstream.source.save();
    State state = State.Initial;
    int base = 0;
    bool leof;
    auto src = tstream.source.dup;
    
    LOOP: while (true) {
        switch (state) {
        case State.Initial:
            if (src.peek == '0') {
                state = State.Zero;
            } else {
                state = State.Decimal;
            }
            break;
        case State.Zero:
            switch (src.peek) {
            case 'x': case 'X':
                state = State.HexZero;
                break;
            case '.':
                if (src.lookahead(1, leof) == '.') {
                    break LOOP;  // '..' is a separate token.
                }
            // FALLTHROUGH
            case 'i': case 'f': case 'F':
                return lexReal(tstream);
            case 'b': case 'B':
                state = State.BinaryZero;
                break;
            case '0': case '1': case '2': case '3': 
            case '4': case '5': case '6': case '7':
                state = State.Octal;
                break;
            case '_':
                state = State.Octal;
                match(src, '_');
                continue;
            case 'L':
                if (src.lookahead(1, leof) == 'i') {
                    return lexReal(tstream);
                }
                break LOOP;
            default:
                break LOOP;
            }
            break;
        case State.Decimal:  // Reading a decimal number.
            if (!isdigit(src.peek)) {
                if (src.peek == '_') {
                    // Ignore embedded '_'.
                    match(src, '_');
                    continue;
                }
                if (src.peek == '.' && src.lookahead(1, leof) != '.') {
                    return lexReal(tstream);
                } else if (src.peek == 'i' || src.peek == 'f' ||
                           src.peek == 'F' || src.peek == 'e' ||
                           src.peek == 'E') {
                    return lexReal(tstream);
                } else if (src.peek == 'L' && src.lookahead(1, leof) == 'i') {
                    return lexReal(tstream);
                }
                break LOOP;
            }
            break;
        case State.Hex:  // Reading a hexadecimal number.
        case State.HexZero:
            if (!ishex(src.peek)) {
                if (src.peek == '_') {
                    match(src, '_');
                    continue;
                }
                if (src.peek == '.' && src.lookahead(1, leof) != '.') {
                    return lexReal(tstream);
                } 
                if (src.peek == 'p' || src.peek == 'P' || src.peek == 'i') {
                    return lexReal(tstream);
                }
                if (state == State.HexZero) {
                    error(src.location, format("hex digit expected, not '%s'", src.peek));
                }
                break LOOP;
            }
            state = State.Hex;
            break;
        case State.Octal:   // Reading an octal number.
        case State.Octale:  // Reading an octal number with non-octal digits.
            if (!isoctal(src.peek)) {
                if (src.peek == '_') {
                    match(src, '_');
                    continue;
                }
                if (src.peek == '.' && src.lookahead(1, leof) != '.') {
                    return lexReal(tstream);
                }
                if (src.peek == 'i') {
                    return lexReal(tstream);
                }
                if (isdigit(src.peek)) {
                    state = State.Octale;
                } else {
                    break LOOP;
                }
            }
            break;
        case State.BinaryZero:  // Reading the beginning of a binary number.
        case State.Binary:      // Reading a binary number.
            if (src.peek != '0' && src.peek != '1') {
                if (src.peek == '_') {
                    match(src, '_');
                    continue;
                }
                if (state == State.BinaryZero) {
                    error(src.location, format("binary digit expected, not '%s'", src.peek));
                } else {
                    break LOOP;
                }
            }
            state = State.Binary;
            break;
        default:
            assert(false);
        }
        src.get();
    }
    
    if (state == State.Octale) {
        error(src.location, format("octal digit expected, not '%s'", src.peek));
    }
    
    tstream.source.sync(src);
    
    // Parse trailing 'u', 'U', 'l' or 'L' in any combination.
    while (true) {
        switch (tstream.source.peek) {
        case 'U': case 'u':
            tstream.source.get();
            continue;
        case 'l':
            error(tstream.source.location, "'l' suffix is deprecated. Use 'L' instead");
            break;
        case 'L':
            match(tstream.source, 'L');
            continue;
        default:
            break;
        }
        break;
    }
    
    token.type = TokenType.IntegerLiteral;
    token.value = tstream.source.sliceFrom(mark);
    tstream.addToken(token);
    
    return true;
}

// This function was adapted from DMD.
bool lexReal(TokenStream tstream)
in
{
    assert(tstream.source.peek == '.' || isdigit(tstream.source.peek));
}
body
{
    auto token = currentLocationToken(tstream);
    token.type = TokenType.FloatLiteral;
    auto mark = tstream.source.save();
    
    int dblstate = 0;
    int hex = 0;
    bool first = true;
    OUTER: while (true) {
        if (first) {
            first = false;
        } else {
            tstream.source.get();
        }
        INNER: while (true) {
            switch (dblstate) {
            case 0:  // Opening state.
                if (tstream.source.peek == '0') {
                    dblstate = 9;
                } else if (tstream.source.peek == '.') {
                    dblstate = 3;
                } else {
                    dblstate = 1;
                }
                break;
            case 9:
                dblstate = 1;
                if (tstream.source.peek == 'x' || tstream.source.peek == 'X') {
                    hex++;
                    break;
                }
            case 1:  // Digits to the left of the decimal point.
            case 3:  // Digits to the right of the decimal point.
            case 7:  // Continuing exponent digits.
                if (!isdigit(tstream.source.peek) && !(hex && ishex(tstream.source.peek))) {
                    if (tstream.source.peek == '_') {
                        continue OUTER;
                    }
                    dblstate++;
                    continue INNER;
                }
                break;
            case 2:  // No more digits to the left of the decimal point.
                if (tstream.source.peek == '.') {
                    dblstate++;
                    break;
                }
                // FALLTHROUGH
            case 4:  // No more digits to the right of the decimal point.
                if ((tstream.source.peek == 'e' || tstream.source.peek == 'E') ||
                    hex && (tstream.source.peek == 'P' || tstream.source.peek == 'p')) {
                    dblstate = 5;
                    hex = 0;  // An exponent is always decimal.
                    break;
                }
                if (hex) {
                    error(tstream.source.location, "binary-exponent-part required");
                }
                break OUTER;
            case 5:  // Looking immediately to the right of E.
                dblstate++;
                if (tstream.source.peek == '-' || tstream.source.peek == '+') {
                    break;
                }
            case 6:  // First exponent digit expected.
                if (!isdigit(tstream.source.peek)) {
                    error(tstream.source.location, "exponent expected");
                } 
                dblstate++;
                break;
            case 8:  // Past end of exponent digits.
                break OUTER;
            default:
                assert(false);
            }
            break;
        }
    }
    
    switch (tstream.source.peek) {
    case 'f': case 'F': case 'L':
        tstream.source.get();
        break;
    case 'l':
        error(tstream.source.location, "'l' suffix is deprecated. Use 'L' instead");
    default:
        break;
    }
    
    if (tstream.source.peek == 'i' || tstream.source.peek == 'I') {
        if (tstream.source.peek == 'I') {
            error(tstream.source.location, "'I' suffix is deprecated. Use 'i' instead");
        }
        match(tstream.source, 'i');
    }
    
    token.value = tstream.source.sliceFrom(mark);
    tstream.addToken(token);
    return true;
}
