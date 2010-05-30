/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdl.d for more details.
 */ 
module sdc.tokenstream;

import std.stdio;
import std.string;

import sdc.lexer : CompilerError;
public import sdc.token;


class TokenStream
{
    string filename;
    
    void addToken(Token token)
    {
        mTokens ~= token;
    }
    
    void error(string message)
    {
        stderr.writeln(format("%s(%d): parseerror: %s", filename, peek.lineNumber, message));
        throw new CompilerError();
    }
    
    Token getToken()
    {
        if (mIndex >= mTokens.length) {
            return EOFToken;
        }
        auto retval = mTokens[mIndex];
        mIndex++;
        return retval;
    }
    
    Token peek() @property
    {
        if (mIndex >= mTokens.length) {
            return EOFToken;
        }
        return mTokens[mIndex];
    }
    
    Token match(TokenType type)
    {
        if (peek.type != type) {
            error("match error " ~ peek.value);
        }
        return getToken();
    }
    
    
    protected Token[] mTokens;
    protected size_t mIndex;
}
