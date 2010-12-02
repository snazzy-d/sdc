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
import sdc.gen.expression;
import sdc.gen.sdcmodule;
import sdc.gen.type;


void genPragma(ast.Pragma thePragma, Module mod)
{
    switch (thePragma.identifier.value) {
    case "msg":
        if (thePragma.argumentList is null || thePragma.argumentList.expressions.length == 0) {
            throw new CompilerError(thePragma.location, "pragma 'msg' requires at least one argument.");
        }
        foreach (assignExpression; thePragma.argumentList.expressions) {
            auto val = genAssignExpression(assignExpression, mod);
            if (!val.isKnown) {
                throw new CompilerError(assignExpression.location, "argument is not known at compile time.");
            }
            if (!isString(val.type)) {
                throw new CompilerError(assignExpression.location, "arguments to pragma 'msg' must be a string known at compile time.");
            }
            write(val.knownString);
        }
        writeln();
        break;
    case "SDC_is_known_at_compile_time":
        if (thePragma.argumentList is null || thePragma.argumentList.expressions.length == 0) {
            throw new CompilerError(thePragma.location, "pragma 'SDC_const' requires at least one argument.");
        }
        foreach (assignExpression; thePragma.argumentList.expressions) {
            auto val = genAssignExpression(assignExpression, mod);
            if (!val.isKnown) {
                writefln("SDC_is_known_at_compile_time: %s: value not known at compile time.", val.location);
            } else {
                writefln("SDC_is_known_at_compile_time: %s: value is known at compile time.", val.location);
            }
        }
        break;
    default:
        throw new CompilerError(thePragma.identifier.location, format("unrecognised pragma identifier '%s'.", thePragma.identifier.value));
    }
}
