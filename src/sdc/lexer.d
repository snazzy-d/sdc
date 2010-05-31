/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdl.d for more details.
 * 
 * This code is pretty bad. I know. D=
 */ 

module sdc.lexer;

import std.stdio;
import std.string;
import std.conv;
import std.file;
import std.ctype;
import std.c.time;

import sdc.tokenstream;
import sdc.info;
import sdc.compilererror;


immutable string[12] months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
immutable string[7]  days   = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];


class Lexer
{
    string moduleSource;
    TokenStream tstream;
    
    this(string sdcmodule)
    {
        tstream = new TokenStream();
        tstream.filename = sdcmodule;
        moduleSource = cast(string) std.file.read(sdcmodule);
        getChar();
        mColumnNumber--;
        if (mChar == '#' && peek() == '!') {
            moduleSource = moduleSource[2 .. $];
            mIndex = 0;
            while (mChar != '\n' && mChar != 0) {
                getChar();
            }
        }
    }
    
    void error(string message)
    {
        stderr.writeln(format("%s(%d:%d): lexerror: %s", tstream.filename, mLineNumber, mColumnNumber, message));
        throw new CompilerError();
    }
    
    void warning(string message)
    {
        stderr.writeln(format("%s(%d:%d): lexwarning: %s", tstream.filename, mLineNumber, mColumnNumber, message));
    }
    
    void lex()
    {
        eatWhiteSpace();
        while (!mEOF) {
            next();
            eatWhiteSpace();
        }
    }
    
    /// Read in the next token, add it to the token list.
    protected void next()
    {
        auto start = mIndex - 1;  // The index is alwaysma one ahead.
        auto column = mColumnNumber;
        
        if (isalpha(mChar) || mChar == '_') {
            if (mChar == 'r' && peek() == '"') {
                match('r');
                readString('"', true);
            } else {
                readIdentifier();
            }
        } else if (isdigit(mChar)) {
            readInteger();
        } else {
            readOther();
        }
        
        if (mEOF || mType == TokenType.None) {
            return;
        }
        
        auto end = mIndex - 1;
        assert(end > start);
        auto token = new Token();
        token.value = moduleSource[start .. end];
        
        specialTokens(token);
        if (mEOF) {
            return;
        }
        
        token.type = mType;
        token.lineNumber = mLineNumber;
        token.columnNumber = column;
        tstream.addToken(token);
    }
    
    
    protected void specialTokens(Token token)
    {
        if (mType != TokenType.Identifier) {
            return;
        }
        mType = identifierType(token.value);
        if (token.value == "__DATE__") {
            auto tmptime = time(null);
            auto thetime = localtime(&tmptime);
            string datestr = format(`"%s %s %s"`,
                                    months[thetime.tm_mon],
                                    zfill(to!string(thetime.tm_mday), 2),
                                    to!string(1900 + thetime.tm_year));
            token.value = datestr;
            mType = TokenType.StringLiteral;
        } else if (token.value == "__TIME__") {
            auto tmptime = time(null);
            auto thetime = localtime(&tmptime);
            string timestr = format(`"%s:%s:%s"`, 
                                    zfill(to!string(thetime.tm_hour), 2),
                                    zfill(to!string(thetime.tm_min), 2),
                                    zfill(to!string(thetime.tm_sec), 2));
            token.value = timestr;
            mType = TokenType.StringLiteral;
        } else if (token.value == "__TIMESTAMP__") {
            auto tmptime = time(null);
            auto thetime = localtime(&tmptime);
            string datestr = format(`"%s %s %s %s:%s:%s %s"`,
                                    days[thetime.tm_wday],
                                    months[thetime.tm_mon],
                                    zfill(to!string(thetime.tm_mday), 2),
                                    zfill(to!string(thetime.tm_hour), 2),
                                    zfill(to!string(thetime.tm_min), 2),
                                    zfill(to!string(thetime.tm_sec), 2),
                                    to!string(1900 + thetime.tm_year));
            token.value = datestr;
            mType = TokenType.StringLiteral;
        } else if (token.value == "__EOF__") {
            mEOF = true;
        } else if (token.value == "__VENDOR__") {
            token.value = VENDOR;
            mType = TokenType.StringLiteral;
        } else if (token.value == "__VERSION__") {
            token.value = to!string(VERSION);
            token.type = TokenType.IntegerLiteral;
        }
    }
    
    protected void readIdentifier()
    {
        mType = TokenType.Identifier;
        while ((isalnum(mChar) || mChar == '_') && !mEOF) {
            getChar();
        }
    }
    
    protected void readInteger()
    {
        mType = TokenType.IntegerLiteral;
        while (isdigit(mChar) && !mEOF) {
            getChar();
        }
    }
    
    protected void readOther()
    {
        mType = TokenType.None;
        switch (mChar) {
        case '@':
            getChar();
            if (!isalpha(mChar)) {
                error("unknown @ property");
            }
            readIdentifier();
            break;
        case '`':
            readString('`', true);
            break;
        case '"':
            readString('"', false);
            break;
        case '\'':
            readCharacter();
            break;
        case '#':
            error("no special token sequences are currently implemented. Bug Bernard.");
            break;
        case '/':
            getChar();
            if (mChar == '=') {
                mType = TokenType.SlashAssign;
                getChar();
            } else if (mChar == '*') {
                cComment();
            } else if (mChar == '/') {
                cppComment();
            } else if (mChar == '+') {
                nestingComment();
            } else {
                mType = TokenType.Slash;
            }
            break;
        case '.':
            getChar();
            if (mChar == '.') {
                getChar();
                if (mChar == '.') {
                    mType = TokenType.TripleDot;
                    getChar();
                } else {
                    mType = TokenType.DoubleDot;
                }
            } else {
                mType = TokenType.Dot;
            }
            break;
        case '&':
            getChar();
            if (mChar == '=') {
                mType = TokenType.AmpersandAssign;
                getChar();
            } else if (mChar == '&') {
                mType = TokenType.DoubleAmpersand;
                getChar();
            } else {
                mType = TokenType.Ampersand;
            }
            break;
        case '|':
            getChar();
            if (mChar == '=') {
                mType = TokenType.PipeAssign;
                getChar();
            } else if (mChar == '|') {
                mType = TokenType.DoublePipe;
                getChar();
            } else {
                mType = TokenType.Pipe;
            }
            break;
        case '-':
            getChar();
            if (mChar == '=') {
                mType = TokenType.DashAssign;
                getChar();
            } else if (mChar == '-') {
                mType = TokenType.DoubleDash;
                getChar();
            } else {
                mType = TokenType.Dash;
            }
            break;
        case '+':
            getChar();
            if (mChar == '=') {
                mType = TokenType.PlusAssign;
                getChar();
            } else if (mChar == '+') {
                mType = TokenType.DoublePlus;
                getChar();
            } else {
                mType = TokenType.Plus;
            }
            break;
        case '<':
            getChar();
            if (mChar == '=') {
                mType = TokenType.LessAssign;
                getChar();
            } else if (mChar == '<') {
                getChar();
                if (mChar == '=') {
                    mType = TokenType.DoubleLessAssign;
                    getChar();
                } else {
                    mType = TokenType.DoubleLess;
                }
            } else if (mChar == '>') {
                getChar();
                if (mChar == '=') {
                    mType = TokenType.LessGreaterAssign;
                    getChar();
                } else {
                    mType = TokenType.LessGreater;
                }
            } else {
                mType = TokenType.Less;
            }
            break;
        case '>':
            getChar();
            if (mChar == '=') {
                mType = TokenType.GreaterAssign;
                getChar();
            } else if (mChar == '>') {
                getChar();
                if (mChar == '=') {
                    mType = TokenType.DoubleGreaterAssign;
                    getChar();
                } else if (mChar == '>') {
                    getChar();
                    if (mChar == '=') {
                        mType = TokenType.TripleGreaterAssign;
                        getChar();
                    } else {
                        mType = TokenType.TripleGreater;
                    }
                } else {
                    mType = TokenType.DoubleGreater;
                }
            } else {
                mType = TokenType.Greater;
            }
            break;
        case '!':
            getChar();
            if (mChar == '=') {
                mType = TokenType.BangAssign;
                getChar();
            } else if (mChar == '<') {
                getChar();
                if (mChar == '=') { 
                    mType = TokenType.BangLessAssign;
                    getChar();
                } else if (mChar == '>') {
                    getChar();
                    if (mChar == '=') {
                        mType = TokenType.BangLessGreaterAssign;
                        getChar();
                    } else {
                        mType = TokenType.BangLessGreater;
                    }
                } else {
                    mType = TokenType.BangLess;
                }
            } else if (mChar == '>') {
                getChar();
                if (mChar == '=') {
                    mType = TokenType.BangGreaterAssign;
                    getChar();
                } else {
                    mType = TokenType.BangGreater;
                }
            } else {
                mType = TokenType.Bang;
            }
            break;
        case '(':
            mType = TokenType.OpenParen;
            getChar();
            break;
        case ')':
            mType = TokenType.CloseParen;
            getChar();
            break;
        case '[':
            mType = TokenType.OpenBrace;
            getChar();
            break;
        case ']':
            mType = TokenType.CloseBrace;
            getChar();
            break;
        case '{':
            mType = TokenType.OpenBracket;
            getChar();
            break;
        case '}':
            mType = TokenType.CloseBracket;
            getChar();
            break;
        case '?':
            mType = TokenType.QuestionMark;
            getChar();
            break;
        case ',':
            mType = TokenType.Comma;
            getChar();
            break;
        case ';':
            mType = TokenType.Semicolon;
            getChar();
            break;
        case ':':
            mType = TokenType.Colon;
            getChar();
            break;
        case '$':
            mType = TokenType.Dollar;
            getChar();
            break;
        case '=':
            getChar();
            if (mChar == '=') {
                mType = TokenType.DoubleAssign;
                getChar();
            } else {
                mType = TokenType.Assign;
            }
            break;
        case '*':
            getChar();
            if (mChar == '=') {
                mType = TokenType.AsterixAssign;
                getChar();
            } else {
                mType = TokenType.Asterix;
            }
            break;
        case '%':
            getChar();
            if (mChar == '=') {
                mType = TokenType.PercentAssign;
                getChar();
            } else {
                mType = TokenType.Percent;
            }
            break;
        case '^':
            getChar();
            if (mChar == '=') {
                mType = TokenType.CaretAssign;
                getChar();
            } else {
                mType = TokenType.Caret;
            }
            break;
        case '~':
            getChar();
            if (mChar == '=') {
                mType = TokenType.TildeAssign;
                getChar();
            } else {
                mType = TokenType.Tilde;
            }
            break;
        default:
            error(format("don't know how to handle character '%s'", mChar));
            assert(false);
        }
    }
    
    // The *Comment functions eat characters until they deem the comment to be over.
    
    protected void cppComment()
    {
        mType = TokenType.None;
        match('/');
        while (mChar != '\n' && !mEOF) {
            getChar();
        }
        match('\n');
    }
    
    protected void cComment()
    {
        mType = TokenType.None;
        match('*');
        bool looping = true;
        while (looping) {
            if (mEOF) {
                error("unterminated c style comment");
            }
            if (mChar == '*') {
                getChar();
                if (mChar == '/') {
                    looping = false;
                    getChar();
                    continue;
                }
            } else if (mChar == '/') {
                getChar();
                if (mChar == '*') {
                    warning("'/*' within c style comment");
                }
            } else {
                getChar();
            }
        }
    }

    protected void nestingComment()
    {
        mType = TokenType.None;
        match('+');
        int commentDepth = 1;
        while (commentDepth >= 1) {
            if (mEOF) {
                error("unterminated nesting comment");
            }
            if (mChar == '/') {
                getChar();
                if (mChar == '+') {
                    commentDepth++;
                    getChar();
                }
            } else if (mChar == '+') {
                getChar();
                if (mChar == '/') {
                    commentDepth--;
                    getChar();
                }
            } else {
                getChar();
            }
        }
    }
    
    
    // Note that nothing is expanded in the lexer. That happens as late as possible.
    void readString(char terminator, bool raw, bool postfix = true)
    {
        mType = TokenType.StringLiteral;
        match(terminator);
        while (mChar != terminator) {
            if (mEOF) {
                error("unterminated string");
            }
            if (!raw && mChar == '\\') {
                getChar();
                if (mEOF) error("unterminated string");
                if (mChar == terminator) {
                    getChar();
                } else if (mChar == '\\') {
                    getChar();
                }
            } else {
                getChar();
            }
        }
        match(terminator);
        if (postfix && (mChar == 'c' || mChar == 'd' || mChar == 'w')) {
            getChar();
        }
    }
    
    void readCharacter()
    {
        readString('\'', false, false);
        mType = TokenType.CharacterLiteral;
    }
    
    protected void eatWhiteSpace()
    {
        while (mChar == ' ' || mChar == '\t' || mChar == '\r' || mChar == '\n') {
            if (mEOF) {
                break;
            }
            getChar();
        }
    }
    
    protected void match(char c)
    {
        if (mChar != c) {
            error(format("expected '%s' got '%s'", c, mChar));
        }
        getChar();
    }
    
    /// Read in the next input character.
    protected void getChar()
    {
        if (mIndex >= moduleSource.length) {
            mEOF = true;
            mChar = 0;
            return;
        }
        if (mChar == '\n') {
            mColumnNumber = 0;
            mLineNumber++;
        }
           
        mChar = moduleSource[mIndex];
        mColumnNumber++;
        
        mIndex++;
    }
        
    protected char peek()
    {
        if (mIndex >= moduleSource.length) {
            return 0;
        }
        return moduleSource[mIndex];
    }
    
    protected char mChar;
    protected size_t mIndex;
    protected TokenType mType = TokenType.None;
    protected bool mEOF = false;
    protected int mLineNumber = 1;
    protected int mColumnNumber = 1;
}
