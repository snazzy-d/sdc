/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.llvm.base;

import std.stdio;


string genIndent(int indent)
{
    char[] buf;
    foreach (i; 0 .. indent) {
        buf ~= " ";
    }
    return buf.idup;
}

void moduleIdentifier(File file, int indent, string identifier)
{
    file.writeln(genIndent(indent), "; ", identifier);
    file.writeln();
}
