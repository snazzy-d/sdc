/**
 * Copyright 2010-2011 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */ 
module sdc.lexer;

import std.algorithm;
import std.array;
import std.ascii;
import std.conv;
import std.stdio;
import std.string;
import std.utf;
import std.uni;
import std.c.time;

import sdc.source;
import sdc.location;
import sdc.tokenstream;
import sdc.tokenwriter;
import sdc.compilererror;

alias std.ascii.isWhite isWhite;

static import sdc.info;

/**
 * Tokenizes a string pretending to be at the given location.
 *
 * Throws:
 *   CompilerError on errors.
 *
 * Returns:
 *   A TokenStream filled with tokens.
 */
TokenStream lex(string src, Location loc)
{
    return lex(new Source(src, loc));
}

/**
 * Tokenizes a source file.
 *
 * Side-effects:
 *   Will advance the source location, on success this will be EOF.
 *
 * Throws:
 *   CompilerError on errors.
 *
 * Returns:
 *   A TokenStream filled with tokens.
 */
TokenStream lex(Source source)
{
    auto tw = new TokenWriter(source);

    do {
        if (lexNext(tw))
            continue;

        auto s = format("unexpected character: '%s'.", tw.source.peek);
        throw new CompilerError(tw.source.location, s);
    } while (tw.lastAdded.type != TokenType.End);

    return tw.getStream();
}


private:


pure bool isHexLex(dchar c)
{
    return isDigit(c) || c >= 'A' && c <= 'F' || c >= 'a' && c <= 'f';
}

pure bool isOctalLex(dchar c)
{
    return c >= '0' && c <= '7';
}

enum Position {
	Start,
	MiddleOrEnd
}

pure bool isAlphaLex(dchar c, Position position)
{
    if (position == Position.Start) {
        return isUniAlpha(c) || c == '_';
    } else {
        return isUniAlpha(c) || c == '_' || isDigit(c);
    }
}

/**
 * Match and advance if matched.
 *
 * Side-effects:
 *   If @src.peek and @c matches, advances source to next character.
 *
 * Throws:
 *   CompilerError if @src.peek did not match @c.
 */
void match(Source src, dchar c)
{
    auto cur = src.peek;
    if (cur != c) {
        auto s = format("expected '%s' got '%s'.", c, cur);
        throw new CompilerError(src.location, s);
    }
    // Advance to the next character.
    src.get();
}

Token currentLocationToken(TokenWriter tw)
{
    auto t = new Token();
    t.location = tw.source.location;
    return t;
}

bool lexNext(TokenWriter tw)
{
    TokenType type = nextLex(tw);
    
    switch (type) {
    case TokenType.End:
        return lexEOF(tw);
    case TokenType.Identifier:
        return lexIdentifier(tw);
    case TokenType.CharacterLiteral:
        return lexCharacter(tw);
    case TokenType.StringLiteral:
        return lexString(tw);
    case TokenType.Symbol:
        return lexSymbol(tw);
    case TokenType.Number:
        return lexNumber(tw);
    default:
        break;
    }
    
    return false;
}

/// Return which TokenType to try and lex next. 
TokenType nextLex(TokenWriter tw)
{
    skipWhitespace(tw);
    if (tw.source.eof) {
        return TokenType.End;
    }
    
    if (isUniAlpha(tw.source.peek) || tw.source.peek == '_') {
        bool lookaheadEOF;
        if (tw.source.peek == 'r' || tw.source.peek == 'q' || tw.source.peek == 'x') {
            dchar oneAhead = tw.source.lookahead(1, lookaheadEOF);
            if (oneAhead == '"') {
                return TokenType.StringLiteral;
            } else if (tw.source.peek == 'q' && oneAhead == '{') {
                return TokenType.StringLiteral;
            }
        }
        return TokenType.Identifier;
    }
    
    if (tw.source.peek == '\'') {
        return TokenType.CharacterLiteral;
    }
    
    if (tw.source.peek == '"' || tw.source.peek == '`') {
        return TokenType.StringLiteral;
    }
    
    if (isDigit(tw.source.peek)) {
        return TokenType.Number;
    }
    
    return TokenType.Symbol;
}


void skipWhitespace(TokenWriter tw)
{
    while (isWhite(tw.source.peek)) {
        tw.source.get();
        if (tw.source.eof) break;
    }
}

void skipLineComment(TokenWriter tw)
{
    match(tw.source, '/');
    while (tw.source.peek != '\n') {
        tw.source.get();
        if (tw.source.eof) return;
    }
}

void skipBlockComment(TokenWriter tw)
{
    bool looping = true;
    while (looping) {
        if (tw.source.eof) {
            throw new CompilerError(tw.source.location, "unterminated block comment.");
        }
        if (tw.source.peek == '/') {
            match(tw.source, '/');
            if (tw.source.peek == '*') {
                warning(tw.source.location, "'/*' inside of block comment.");
            }
        } else if (tw.source.peek == '*') {
            match(tw.source, '*');
            if (tw.source.peek == '/') {
                match(tw.source, '/');
                looping = false;
            }
        } else {
            tw.source.get();
        }
    }
}

void skipNestingComment(TokenWriter tw)
{
    int depth = 1;
    while (depth > 0) {
        if (tw.source.eof) {
            throw new CompilerError(tw.source.location, "unterminated nesting comment.");
        }
        if (tw.source.peek == '+') {
            match(tw.source, '+');
            if (tw.source.peek == '/') {
                match(tw.source, '/');
                depth--;
            }
        } else if (tw.source.peek == '/') {
            match(tw.source, '/');
            if (tw.source.peek == '+') {
                depth++;
            }
        } else {
            tw.source.get();
        }
    }
}

bool lexEOF(TokenWriter tw)
{
    if (!tw.source.eof) {
        return false;
    }
    
    auto eof = currentLocationToken(tw);
    eof.type = TokenType.End;
    eof.value = "EOF";
    tw.addToken(eof);
    return true;
}

// This is a bit of a dog's breakfast.
bool lexIdentifier(TokenWriter tw)
{
    assert(isUniAlpha(tw.source.peek) || tw.source.peek == '_' || tw.source.peek == '@');
    
    auto identToken = currentLocationToken(tw);
    Mark m = tw.source.save();
    tw.source.get();
    
    while (isUniAlpha(tw.source.peek) || isDigit(tw.source.peek) || tw.source.peek == '_') {
        tw.source.get();
        if (tw.source.eof) break;
    }
    
    identToken.value = tw.source.sliceFrom(m);
    if (identToken.value.length == 0) {
        throw new CompilerPanic(identToken.location, "empty identifier string.");
    }
    if (identToken.value[0] == '@') {
        auto i = identifierType(identToken.value);
        if (i == TokenType.Identifier) {
            auto err = format("invalid @ attribute '%s'.", identToken.value);
            throw new CompilerError(identToken.location, err);
        }
    }
    
    
    bool retval = lexSpecialToken(tw, identToken);
    if (retval) return true;
    identToken.type = identifierType(identToken.value);
    tw.addToken(identToken);
    
    return true;
}

bool lexSpecialToken(TokenWriter tw, Token token)
{
    immutable string[12] months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    immutable string[7] days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
 
    switch(token.value) {
    case "__DATE__":
        auto thetime = time(null);
        auto tm = localtime(&thetime);
        token.type = TokenType.StringLiteral;
        token.value = format(`"%s %02s %s"`,
                             months[tm.tm_mon], 
                             tm.tm_mday,
                             1900 + tm.tm_year);
        tw.addToken(token);
        return true;

    case "__EOF__":
        tw.source.eof = true;
        return true;

    case "__TIME__":
        auto thetime = time(null);
        auto tm = localtime(&thetime);
        token.type = TokenType.StringLiteral;
        token.value = format(`"%02s:%02s:%02s"`, tm.tm_hour, tm.tm_min,
                             tm.tm_sec);
        tw.addToken(token);
        return true;

    case "__TIMESTAMP__":
        auto thetime = time(null);
        auto tm = localtime(&thetime);
        token.type = TokenType.StringLiteral;
        token.value = format(`"%s %s %02s %02s:%02s:%02s %s"`,
                             days[tm.tm_wday], months[tm.tm_mon],
                             tm.tm_mday, tm.tm_hour, tm.tm_min, tm.tm_sec,
                             1900 + tm.tm_year);
        tw.addToken(token);
        return true;

    case "__VENDOR__":
        token.type = TokenType.StringLiteral;
        token.value = sdc.info.VENDOR;
        tw.addToken(token);
        return true;

    case "__VERSION__":
        token.type = TokenType.IntegerLiteral;
        token.value = to!string(sdc.info.VERSION);
        tw.addToken(token);
        return true;

    default:
        return false;
    }
}

bool lexSymbol(TokenWriter tw)
{
    switch (tw.source.peek) {
    case '/':
        return lexSlash(tw);
    case '.':
        return lexDot(tw);
    case '&':
        return lexSymbolOrSymbolAssignOrDoubleSymbol(tw, '&', 
               TokenType.Ampersand, TokenType.AmpersandAssign, TokenType.DoubleAmpersand);
    case '|':
        return lexSymbolOrSymbolAssignOrDoubleSymbol(tw, '|',
               TokenType.Pipe, TokenType.PipeAssign, TokenType.DoublePipe);
    case '-':
        return lexSymbolOrSymbolAssignOrDoubleSymbol(tw, '-',
               TokenType.Dash, TokenType.DashAssign, TokenType.DoubleDash);
    case '+':
        return lexSymbolOrSymbolAssignOrDoubleSymbol(tw, '+',
               TokenType.Plus, TokenType.PlusAssign, TokenType.DoublePlus);
    case '<':
        return lexLess(tw);
    case '>':
        return lexGreater(tw);
    case '!':
        return lexBang(tw);
    case '(':
        return lexOpenParen(tw);
    case ')':
        return lexSingleSymbol(tw, ')', TokenType.CloseParen);
    case '[':
        return lexSingleSymbol(tw, '[', TokenType.OpenBracket);
    case ']':
        return lexSingleSymbol(tw, ']', TokenType.CloseBracket);
    case '{':
        return lexSingleSymbol(tw, '{', TokenType.OpenBrace);
    case '}':
        return lexSingleSymbol(tw, '}', TokenType.CloseBrace);
    case '?':
        return lexSingleSymbol(tw, '?', TokenType.QuestionMark);
    case ',':
        return lexSingleSymbol(tw, ',', TokenType.Comma);
    case ';':
        return lexSingleSymbol(tw, ';', TokenType.Semicolon);
    case ':':
        return lexSingleSymbol(tw, ':', TokenType.Colon);
    case '$':
        return lexSingleSymbol(tw, '$', TokenType.Dollar);
    case '@':
        return lexSingleSymbol(tw, '@', TokenType.At);
    case '=':
        return lexSymbolOrSymbolAssign(tw, '=', TokenType.Assign, TokenType.DoubleAssign);
    case '*':
        return lexSymbolOrSymbolAssign(tw, '*', TokenType.Asterix, TokenType.AsterixAssign);
    case '%':
        return lexSymbolOrSymbolAssign(tw, '%', TokenType.Percent, TokenType.PercentAssign);
    case '^':
        return lexSymbolOrSymbolAssignOrDoubleSymbol(tw, '^', 
               TokenType.Caret, TokenType.CaretAssign, TokenType.DoubleCaret);
    case '~':
        return lexSymbolOrSymbolAssign(tw, '~', TokenType.Tilde, TokenType.TildeAssign);
    case '#':
        return lexPragma(tw);
    default:
        break;
    }
    return false;
    
}

bool lexSlash(TokenWriter tw)
{
    auto token = currentLocationToken(tw);
    auto mark = tw.source.save();
    auto type = TokenType.Slash;
    match(tw.source, '/');
    
    switch (tw.source.peek) {
    case '=':
        match(tw.source, '=');
        type = TokenType.SlashAssign;
        break;
    case '/':
        skipLineComment(tw);
        return true;
    case '*':
        skipBlockComment(tw);
        return true;
    case '+':
        skipNestingComment(tw);
        return true;
    default:
        break;
    }
    
    token.type = type;
    token.value = tw.source.sliceFrom(mark);
    tw.addToken(token);
    
    return true;
}

/* Help! I'm trapped in a code factory. Send food! */

bool lexDot(TokenWriter tw)
{
    auto token = currentLocationToken(tw);
    auto mark = tw.source.save();
    auto type = TokenType.Dot;
    match(tw.source, '.');
    
    switch (tw.source.peek) {
    case '.':
        match(tw.source, '.');
        if (tw.source.peek == '.') {
            match(tw.source, '.');
            type = TokenType.TripleDot;
        } else {
            type = TokenType.DoubleDot;
        }
        break;
    default:
        break;
    }
    
    token.type = type;
    token.value = tw.source.sliceFrom(mark);
    tw.addToken(token);
    
    return true;
}


bool lexSymbolOrSymbolAssignOrDoubleSymbol(TokenWriter tw, dchar c, TokenType symbol, TokenType symbolAssign, TokenType doubleSymbol)
{
    auto token = currentLocationToken(tw);
    auto mark = tw.source.save();
    auto type = symbol;
    match(tw.source, c);
    
    if (tw.source.peek == '=') {
        match(tw.source, '=');
        type = symbolAssign;
    } else if (tw.source.peek == c) {
        match(tw.source, c);
        type = doubleSymbol;
    }
    
    token.type = type;
    token.value = tw.source.sliceFrom(mark);
    tw.addToken(token);
    
    return true;
}

bool lexSingleSymbol(TokenWriter tw, dchar c, TokenType symbol)
{
    auto token = currentLocationToken(tw);
    auto mark = tw.source.save();
    match(tw.source, c);
    token.type = symbol;
    token.value = tw.source.sliceFrom(mark);
    tw.addToken(token);
    return true;
}

bool lexSymbolOrSymbolAssign(TokenWriter tw, dchar c, TokenType symbol, TokenType symbolAssign)
{
    auto token = currentLocationToken(tw);
    auto mark = tw.source.save();
    auto type = symbol;
    match(tw.source, c);
    
    if (tw.source.peek == '=') {
        match(tw.source, '=');
        type = symbolAssign;
    }
    
    token.type = type;
    token.value = tw.source.sliceFrom(mark);
    tw.addToken(token);
    
    return true;
}
    

bool lexOpenParen(TokenWriter tw)
{
    if (!lexOpKirbyRape(tw)) {
        Mark m = tw.source.save();
        auto token = currentLocationToken(tw);
        match(tw.source, '(');
        token.type = TokenType.OpenParen;
        token.value = tw.source.sliceFrom(m);
        tw.addToken(token);
    }
    
    return true;
}

bool lexOpKirbyRape(TokenWriter tw)
{
    bool eof = false;
    dchar one = tw.source.lookahead(1, eof);
    if (eof || one != '>') return false;
    
    dchar two = tw.source.lookahead(2, eof);
    if (eof || two != '^') return false;
    
    dchar three = tw.source.lookahead(3, eof);
    if (eof || three != '(') return false;
    
    dchar four = tw.source.lookahead(4, eof);
    if (eof || four != '>') return false;
    
    dchar five = tw.source.lookahead(5, eof);
    if (eof || five != 'O') return false;

    dchar six = tw.source.lookahead(6, eof);
    if (eof || six != '_') return false;
    
    dchar seven = tw.source.lookahead(7, eof);
    if (eof || seven != 'O') return false;
    
    dchar eight = tw.source.lookahead(8, eof);
    if (eof || eight != ')') return false;
    
    dchar nine = tw.source.lookahead(9, eof);
    if (eof || nine != '>') return false;
    
    throw new CompilerError(tw.source.location, "no means no!");
}

bool lexLess(TokenWriter tw)
{
    auto token = currentLocationToken(tw);
    auto mark = tw.source.save();
    token.type = TokenType.Less;
    match(tw.source, '<');
    
    if (tw.source.peek == '=') {
        match(tw.source, '=');
        token.type = TokenType.LessAssign;
    } else if (tw.source.peek == '<') {
        match(tw.source, '<');
        if (tw.source.peek == '=') {
            match(tw.source, '=');
            token.type = TokenType.DoubleLessAssign;
        } else {
            token.type = TokenType.DoubleLess;
        }
    } else if (tw.source.peek == '>') {
        match(tw.source, '>');
        if (tw.source.peek == '=') {
            match(tw.source, '=');
            token.type = TokenType.LessGreaterAssign;
        } else {
            token.type = TokenType.LessGreater;
        }
    }
    
    token.value = tw.source.sliceFrom(mark);
    tw.addToken(token);
    return true;
}

bool lexGreater(TokenWriter tw)
{
    auto token = currentLocationToken(tw);
    auto mark = tw.source.save();
    token.type = TokenType.Greater;
    match(tw.source, '>');
    
    if (tw.source.peek == '=') {
        match(tw.source, '=');
        token.type = TokenType.GreaterAssign;
    } else if (tw.source.peek == '>') {
        match(tw.source, '>');
        if (tw.source.peek == '=') {
            match(tw.source, '=');
            token.type = TokenType.DoubleGreaterAssign;
        } else if (tw.source.peek == '>') {
            match(tw.source, '>');
            if (tw.source.peek == '=') {
                match(tw.source, '=');
                token.type = TokenType.TripleGreaterAssign;
            } else {
                token.type = TokenType.TripleGreater;
            }
        } else {
            token.type = TokenType.DoubleGreater;
        }
    } 
    
    token.value = tw.source.sliceFrom(mark);
    tw.addToken(token);
    return true;
}

bool lexBang(TokenWriter tw)
{
    auto token = currentLocationToken(tw);
    auto mark = tw.source.save();
    token.type = TokenType.Bang;
    match(tw.source, '!');
    
    if (tw.source.peek == '=') {
        match(tw.source, '=');
        token.type = TokenType.BangAssign;
    } else if (tw.source.peek == '>') {
        match(tw.source, '>');
        if (tw.source.peek == '=') {
            token.type = TokenType.BangGreaterAssign;
        } else {
            token.type = TokenType.BangGreater;
        }
    } else if (tw.source.peek == '<') {
        match(tw.source, '<');
        if (tw.source.peek == '>') {
            match(tw.source, '>');
            if (tw.source.peek == '=') {
                match(tw.source, '=');
                token.type = TokenType.BangLessGreaterAssign;
            } else {
                token.type = TokenType.BangLessGreater;
            }
        } else if (tw.source.peek == '=') {
            match(tw.source, '=');
            token.type = TokenType.BangLessAssign;
        } else {
            token.type = TokenType.BangLess;
        }
    }
    
    token.value = tw.source.sliceFrom(mark);
    tw.addToken(token);
    return true;
}

// Escape sequences are not expanded inside of the lexer.

bool lexCharacter(TokenWriter tw)
{
    auto token = currentLocationToken(tw);
    auto mark = tw.source.save();
    match(tw.source, '\'');
    while (tw.source.peek != '\'') {
        if (tw.source.eof) {
            throw new CompilerError(token.location, "unterminated character literal.");
        }
        if (tw.source.peek == '\\') {
            match(tw.source, '\\');
            tw.source.get();
        } else {
            tw.source.get();
        }
    }
    match(tw.source, '\'');
    
    token.type = TokenType.CharacterLiteral;
    token.value = tw.source.sliceFrom(mark);
    tw.addToken(token);
    return true;
}

bool lexString(TokenWriter tw)
{
    auto token = currentLocationToken(tw);
    auto mark = tw.source.save();
    dchar terminator;
    bool raw;
    bool postfix = true;
    
    if (tw.source.peek == 'r') {
        match(tw.source, 'r');
        raw = true;
        terminator = '"';
    } else if (tw.source.peek == 'q') {
        return lexQString(tw);
    } else if (tw.source.peek == 'x') {
        match(tw.source, 'x');
        raw = false;
        terminator = '"';
    } else if (tw.source.peek == '`') {
        raw = true;
        terminator = '`';
    } else if (tw.source.peek == '"') {
        raw = false;
        terminator = '"';
    } else {
        return false;
    }
    
    match(tw.source, terminator);
    while (tw.source.peek != terminator) {
        if (tw.source.eof) {
            throw new CompilerError(token.location, "unterminated string literal.");
        }
        if (!raw && tw.source.peek == '\\') {
            match(tw.source, '\\');
            tw.source.get();
        } else {
            tw.source.get();
        }
    }
    match(tw.source, terminator);
    dchar postfixc = tw.source.peek;
    if ((postfixc == 'c' || postfixc == 'w' || postfixc == 'd') && postfix) {
        match(tw.source, postfixc);
    }
    
    token.type = TokenType.StringLiteral;
    token.value = tw.source.sliceFrom(mark);
    tw.addToken(token);
    
    return true;
}

bool lexQString(TokenWriter tw)
{
    auto token = currentLocationToken(tw);
    token.type = TokenType.StringLiteral;
    auto mark = tw.source.save();
    bool leof;
    if (tw.source.lookahead(1, leof) == '{') {
        return lexTokenString(tw);
    }
    match(tw.source, 'q');
    match(tw.source, '"');
    
    dchar opendelimiter, closedelimiter;
    bool nesting = true;
    string identdelim = null;
    switch (tw.source.peek) {
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
        nesting = false;
        if (isAlphaLex(tw.source.peek, Position.Start)) {
            char[] buf;
            buf ~= tw.source.peek;
            tw.source.get();
            while (isAlphaLex(tw.source.peek, Position.MiddleOrEnd)) {
                buf ~= tw.source.peek;
                tw.source.get();
            }
            match(tw.source, '\n');
            identdelim = buf.idup;
        } else {
            opendelimiter = tw.source.peek;
            closedelimiter = tw.source.peek;
        }
    }
    
    if (identdelim is null) match(tw.source, opendelimiter);
    int nest = 1;
    LOOP: while (true) {
        if (tw.source.eof) {
            throw new CompilerError(token.location, "unterminated string.");
        }
        if (tw.source.peek == opendelimiter) {
            match(tw.source, opendelimiter);
            nest++;
        } else if (tw.source.peek == closedelimiter) {
            match(tw.source, closedelimiter);
            nest--;
            if (nest == 0) {
                match(tw.source, '"');
            }
        } else {
            tw.source.get();
        }
        
        // Time to quit?
        if (nesting && nest <= 0) {
            break;
        } else if (identdelim !is null && tw.source.peek == '\n') {
            size_t look = 1;
            while (look - 1 < identdelim.length) {
                dchar c = tw.source.lookahead(look, leof);
                if (leof) {
                    throw new CompilerError(token.location, "unterminated string.");
                }
                if (c != identdelim[look - 1]) {
                    continue LOOP;
                }
                look++;
            }
            foreach (i; 0 .. look) {
                tw.source.get();
            }
            match(tw.source, '"');
            break;
        } else if (tw.source.peek == closedelimiter) {
            match(tw.source, closedelimiter);
            match(tw.source, '"');
            break;
        }
    }
    
    token.value = tw.source.sliceFrom(mark);
    tw.addToken(token);
    return true;
}

bool lexTokenString(TokenWriter tw)
{
    auto token = currentLocationToken(tw);
    token.type = TokenType.StringLiteral;
    auto mark = tw.source.save();
    match(tw.source, 'q');
    match(tw.source, '{');
    auto dummystream = new TokenWriter(tw.source);
    
    int nest = 1;
    while (nest > 0) {
        bool retval = lexNext(dummystream);
        if (!retval) {
            throw new CompilerError(dummystream.source.location, format("expected token, got '%s'.", tw.source.peek));
        }
        switch (dummystream.lastAdded.type) {
        case TokenType.OpenBrace:
            nest++;
            break;
        case TokenType.CloseBrace:
            nest--;
            break;
        case TokenType.End:
            throw new CompilerError(dummystream.source.location, "unterminated token string.");
        default:
            break;
        }
    }
    
    token.value = tw.source.sliceFrom(mark);
    tw.addToken(token);
    return true;
}

/* 
 * Consume characters from the source from the characters array until you can't.
 * Returns: the number of characters consumed, not counting underscores.
 */
size_t consume(Source src, dchar[] characters...)
{
    size_t consumed;
    while (characters.count(src.peek) > 0) {
        if (src.peek != '_') consumed++;
        src.get();
    }
    return consumed;
}

/**
 * Lex an integer literal and add the resulting token to tw.
 * If it detects the number is floating point, it will call lexReal directly.
 */ 
bool lexNumber(TokenWriter tw)
{   
    auto token = currentLocationToken(tw);
    auto src = new Source(tw.source);
    auto mark = src.save();
    
    if (src.peek == '0') {
        src.get();
        if (src.peek == 'b' || src.peek == 'B') {
            // Binary literal.
            src.get();
            auto consumed = consume(src, '0', '1', '_');
            if (consumed == 0) {
                throw new CompilerError(src.location, "expected binary digit.");
            }
        } else if (src.peek == 'x' || src.peek == 'X') {
            // Hexadecimal literal.
            src.get();
            if (src.peek == '.' || src.peek == 'p' || src.peek == 'P') return lexReal(tw);
            auto consumed = consume(src, '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
                    'a', 'b', 'c', 'd', 'e', 'f',
                    'A', 'B', 'C', 'D', 'E', 'F', '_');
            if (src.peek == '.' || src.peek == 'p' || src.peek == 'P') return lexReal(tw);
            if (consumed == 0) {
                throw new CompilerError(src.location, "expected hexadecimal digit.");
            }
        } else if (src.peek == '1' || src.peek == '2' || src.peek == '3' || src.peek == '4' || src.peek == '5' ||
               src.peek == '6' || src.peek == '7') {
            /* This used to be an octal literal, which are gone.
             * DMD treats this as an error, so we do too.
             */
            throw new CompilerError(src.location, "octal literals are unsupported.");
        } else if (src.peek == 'f' || src.peek == 'F') {
            return lexReal(tw);
        }
    } else if (src.peek == '1' || src.peek == '2' || src.peek == '3' || src.peek == '4' || src.peek == '5' ||
               src.peek == '6' || src.peek == '7' || src.peek == '8' || src.peek == '9') {
        src.get();
        if (src.peek == '.') return lexReal(tw);
        consume(src, '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '_');
        if (src.peek == '.') return lexReal(tw);
    } else {
        throw new CompilerError(src.location, "expected integer literal.");
    }
    
    if (src.peek == 'f' || src.peek == 'F' || src.peek == 'e' || src.peek == 'E') {
        return lexReal(tw);
    }
    
    tw.source.sync(src);
    if (tw.source.peek == 'U' || tw.source.peek == 'u') {
        tw.source.get();
        if (tw.source.peek == 'L') tw.source.get();
    } else if (tw.source.peek == 'L') {
        tw.source.get();
        if (tw.source.peek == 'U' || tw.source.peek == 'u') {
            tw.source.get();
        }
    }
    
    token.type = TokenType.IntegerLiteral;
    token.value = tw.source.sliceFrom(mark);
    token.value = toUTF8(array(filter!"a != '_'"(token.value)));
    tw.addToken(token);
    
    return true;
}

/// Lex a floating literal and add the resulting token to tw. 
bool lexReal(TokenWriter tw)
{
    auto token = currentLocationToken(tw);
    auto mark = tw.source.save();
    
    if (tw.source.peek == '.') {
        // .n 
        tw.source.get();
        if (!isDigit(tw.source.peek)) {
            throw new CompilerError(tw.source.location, "expected digit after decimal point.");
        }
        tw.source.get();
        consume(tw.source, '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '_');
        if (tw.source.peek == 'L' || tw.source.peek == 'f' || tw.source.peek == 'F') {
            tw.source.get();
            goto _lex_real_out;
        }
    } else if (tw.source.peek == '0') {
        tw.source.get();
        if (tw.source.peek == 'x' || tw.source.peek == 'X') {
            // 0xnP+
            tw.source.get();
            auto consumed = consume(tw.source, '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
                                    'a', 'b', 'c', 'd', 'e', 'f',
                                    'A', 'B', 'C', 'D', 'E', 'F', '_');
            if (consumed == 0) {
                throw new CompilerError(tw.source.location, "expected at least one hexadecimal digit.");
            }
            if (tw.source.peek == 'p' || tw.source.peek == 'P') {
                tw.source.get();
                if (tw.source.peek == '+' || tw.source.peek == '-') {
                    tw.source.get();
                }
                goto _lex_real_after_exp;
            } else {
                throw new CompilerError(tw.source.location, "expected exponent.");
            }
        } else {
            // 0.n
            if (tw.source.peek == '.') goto _lex_real_decimal;
            if (tw.source.peek != '0' && (isDigit(tw.source.peek) || tw.source.peek == '_')) {
                tw.source.get();
                consume(tw.source, '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '_');
                _lex_real_decimal:
                match(tw.source, '.');
                consume(tw.source, '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '_');
                if (tw.source.peek == 'L' || tw.source.peek == 'f' || tw.source.peek == 'F') {
                    tw.source.get();
                    goto _lex_real_out;
                }
            } else {
                throw new CompilerError(tw.source.location, "expected non-zero digit, underscore, or decimal point.");
            }
        }
    } else if (isDigit(tw.source.peek)) {
        // n.n
        consume(tw.source, '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '_');
        match(tw.source, '.');
        consume(tw.source, '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '_');
        if (tw.source.peek == 'L' || tw.source.peek == 'f' || tw.source.peek == 'F') {
            tw.source.get();
            goto _lex_real_out;
        }
    } else {
        throw new CompilerError(tw.source.location, "expected floating point literal.");
    }
    
    if (tw.source.peek == 'e' || tw.source.peek == 'E') {
        tw.source.get();
        if (tw.source.peek == '+' || tw.source.peek == '-') {
            tw.source.get();
        }
    } else {
        throw new CompilerError(tw.source.location, "expected exponent.");
    }
    
    if (!isDigit(tw.source.peek)) {
        throw new CompilerError(tw.source.location, "expected digit.");
    }
    _lex_real_after_exp:
    consume(tw.source, '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '_');
    if (tw.source.peek == 'L' || tw.source.peek == 'f' || tw.source.peek == 'F') {
        tw.source.get();
    }
    
    _lex_real_out:
    token.type = TokenType.FloatLiteral;
    token.value = tw.source.sliceFrom(mark);
    token.value = toUTF8(array(filter!"a != '_'"(token.value)));
    tw.addToken(token);
    return true;
}

bool lexPragma(TokenWriter tw)
{
    /* Can't do this yet because the code for getting values out of
     * literals hasn't been written.
     */
    throw new CompilerError(tw.source.location, "# pragma is not implemented.");
}
