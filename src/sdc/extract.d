/**
 * Copyright 2010 Bernard Helyer.
 * Copyright 2010 Jakob Ovrum.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.extract;

import std.conv;
import std.utf;
import std.string;
import path = std.path;

import sdc.compilererror;
import sdc.location;
import sdc.ast.all;


string extractQualifiedName(QualifiedName qualifiedName)
{
    string buf = qualifiedName.leadingDot ? "." : "";
    foreach (identifier; qualifiedName.identifiers) {
        buf ~= identifier.value;
        buf ~= ".";
    }
    buf = buf[0 .. $ - 1];  // Chop off final '.'
    return buf;
}

string extractModulePath(QualifiedName qualifiedName)
{
    string buf;
    foreach (identifier; qualifiedName.identifiers) {
        buf ~= identifier.value ~ path.sep;
    }
    return buf[0 .. $ - 1] ~ ".d";
}

string extractIdentifier(Identifier identifier)
{
    return identifier.value;
}

int extractIntegerLiteral(IntegerLiteral literal)
{
    auto copy = literal.value.idup;  // parse advances the string
    
    if (copy.length < 2) {
        return parse!int(copy);
    }
    switch (copy[0 .. 2]) {
    case "0x":
        return parse!int(copy[2 .. $], 16);
    case "0b":
        return parse!int(copy[2 .. $], 2);
    default:
        return parse!int(copy);
    }
}

double extractFloatLiteral(FloatLiteral literal)
{
    return to!double(literal.value);
}

//TODO: support wstring and dstring
string extractStringLiteral(StringLiteral literal)
{   
    auto value = literal.value;
    
    switch(value[0]){
    case 'r', 'q':
        return extractRawString(value[1..$]);
    case '`':
        return extractRawString(value);
    case '"':
        return extractString(literal.location, value[1..$]);
    case 'x':
        throw new CompilerPanic(literal.location, "hex literals are unimplemented.");
    default:
        throw new CompilerError(literal.location, format("unrecognised string prefix '%s'.", value[0]));
    }
}

dchar extractCharacterLiteral(CharacterLiteral literal)
{
    auto value = literal.value[1..$-1];
    if(value.length == 0) {
        throw new CompilerError(literal.location, "character literals can't be empty.");
    }
    
    size_t index = 0;
    auto c = extractCharacter(literal.location, value, index);
    if(index < value.length) {
        throw new CompilerError(literal.location, "character literals must be a single character.");
    }
    return c;
}

private:
string extractRawString(string s)
{
    char terminator = s[0];
    s = s[1..$-1];
    if(s[$-1] == terminator) {
        s = s[0..$-1];
    }
    return s;
}

dchar[dchar] escapeChars;

static this()
{
    escapeChars = [
        'a': '\a',
        'b': '\b',
        'f': '\f',
        'n': '\n',
        'r': '\r',
        't': '\t',
        'v': '\v'
    ];
}

string extractString(Location loc, string s)
{
    auto suffix = s[$-1];
    switch(suffix) {
    case 'c', 'w', 'd':
        s = s[0..$-2];
        break;
    case '"', '`':
        s = s[0..$-1];
        break;
    default:
        throw new CompilerError(loc, format("unrecognized string suffix '%s'.", suffix)); 
    }
    
    dstring parsed;
    
    size_t index = 0;
    while(index < s.length) {
        parsed ~= extractCharacter(loc, s, index);
    }
    
    return to!string(parsed);
}

dchar extractCharacter(Location loc, string s, ref size_t index)
{
    dchar c = decode(s, index);
    
    if(c == '\\') {
        dchar escapeChar = decode(s, index);
        switch(escapeChar) {
        case 'x': // One byte hexadecimal
            c = parse!uint(s[index..index+2], 16);
            index += 2;
            break;
        case 'u': // Two byte code point
            c = parse!ushort(s[index..index+4], 16);
            index += 4;
            break;
        case 'U': // Four byte code point
            c = parse!uint(s[index..index+8], 16);
            index += 8;
            break;
        case '&': // Named entity
            break;
        case '0': .. case '9': // Octal
            size_t octalLength = 1;
            foreach(i; 0..2) {
                if(index + octalLength >= s.length) {
                    break;
                } else {
                    dchar next = s[index + octalLength];
                    if(next > '0' && next < '9') {
                        octalLength++;
                    }
                 }
            }
            c = parse!uint(s[index - 1 .. index + octalLength - 1], 8);
            index += octalLength;
            break;
        case '\\', '"', '\'', '\?':
            c = escapeChar;
            break;
        default:
            if(auto pchar = escapeChar in escapeChars) {
                c = *pchar;
                break;
            }
            throw new CompilerError(loc, format("unrecognised escape character '%s'.", escapeChar));
        }
    }
    
    return c;
}
