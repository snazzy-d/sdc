/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */ 
module sdc.tokenstream;

import std.stdio;
import std.string;

import sdc.source;
import sdc.compilererror;
public import sdc.token;


class TokenStream
{
    Source source;
    string filename;
    
    this(Source source)
    {
        filename = source.location.filename;
        this.source = source;
        auto start = new Token();
        start.type = TokenType.Begin;
        start.value = "START";
        mTokens ~= start;
    }
    
    this()
    {
    }
    
    void addToken(Token token)
    {
        mTokens ~= token;
        token.location.length = token.value.length;
    }
    
    Token lastAdded() @property
    {
        return mTokens[$ - 1];
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
    
    Token lookahead(size_t n)
    {
        if (n == 0) {
            return peek();
        }
        auto index = mIndex + n;
        if (index >= mTokens.length) {
            auto token = new Token();
            token.type = TokenType.End;
            token.value = "EOF";
            token.location = lastAdded.location;
            return token;
        }
        
        return mTokens[index];
    }
    
    void printTo(File file)
    {
        foreach (t; mTokens) {
            file.writefln("%s (%s @ %s)", t.value, tokenToString[t.type], t.location);
        }
    }
    
    private Token[] mTokens;
    private size_t mIndex;
}
