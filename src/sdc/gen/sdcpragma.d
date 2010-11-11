/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.sdcpragma;

import std.stdio;
import std.string;

import sdc.compilererror;
import ast=sdc.ast.all;
import sdc.gen.sdcmodule;


void genPragma(ast.Pragma thePragma, Module mod)
{
    switch (thePragma.identifier.value) {
    case "msg":
        writeln("Hello, world.");
        break;
    default:
        throw new CompilerError(thePragma.identifier.location, format("unrecognised pragma identifier '%s'.", thePragma.identifier.value));
    }
}
