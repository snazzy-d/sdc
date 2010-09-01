/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.extract.base;

import std.conv;

import sdc.ast.all;


string extractQualifiedName(QualifiedName qualifiedName)
{
    char[] buf = qualifiedName.leadingDot ? ".".dup : "".dup;
    foreach (identifier; qualifiedName.identifiers) {
        buf ~= identifier.value;
        buf ~= ".";
    }
    buf = buf[0 .. $ - 1];  // Chop off final '.'
    return buf.idup;
}

string extractIdentifier(Identifier identifier)
{
    return identifier.value;
}

int extractIntegerLiteral(IntegerLiteral literal)
{
    return to!int(literal.value);
}

double extractFloatLiteral(FloatLiteral literal)
{
    return to!double(literal.value);
}
