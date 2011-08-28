/**
 * Copyright 2010-2011 Bernard Helyer.
 * Copyright 2010 Jakob Ovrum.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */ 
module sdc.tokenstream;

import std.stdio;
import std.string;

import sdc.compilererror;
public import sdc.token;


class TokenStream
{
    string filename;
    
    private Token[] mTokens;
    private size_t mIndex;

    this(string filename, Token[] tokens)
    {
        if (tokens.length < 3)
            throw new CompilerPanic("Token stream too short.");
        if (tokens[$-1].type != TokenType.End)
            throw new CompilerPanic("Token stream not terminated correctly.");

        this.filename = filename;
        this.mTokens = tokens;
    }
    
    Token getToken()
    {
        auto retval = mTokens[mIndex];
        if (mIndex < mTokens.length - 1) {
            mIndex++;
        }
        return retval;
    }
    
    Token peek() @property
    {
        return mTokens[mIndex];
    }
    
    Token previous() @property
    {
        return mTokens[mIndex - 1];
    }
    
    Token lookahead(size_t n)
    {
        if (n == 0) {
            return peek();
        }
        auto index = mIndex + n;
        if (index >= mTokens.length) {
            return mTokens[$-1];
        }
        
        return mTokens[index];
    }
    
    Token lookbehind(size_t n)
    {
        auto index = mIndex - n;
        if (index < 0)
            throw new CompilerPanic("Token array out of bounds access.");
        return mTokens[mIndex - n];
    }
    
    void printTo(File file)
    {
        foreach (t; mTokens) {
            file.writefln("%s (%s @ %s)", t.value, tokenToString[t.type], t.location);
        }
    }
}
