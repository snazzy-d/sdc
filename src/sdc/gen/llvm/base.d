/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.llvm.base;

import std.stdio;
import std.conv;

import sdc.compilererror;
import sdc.ast.all;


int counter;

string genLocal()
{
    auto retval = "%" ~ to!string(counter);
    counter++;
    return retval;
}

string genIndent(int indent)
{
    char[] buf;
    foreach (i; 0 .. indent) {
        buf ~= " ";
    }
    return buf.idup;
}

string llvmType(BasicType type)
{
    if (type.type == BasicTypeType.Int) {
        return "i32";
    } else {
        error(type.location, "unsupported type");
    }
    assert(false);
}

void comment(File file, int indent, string identifier)
{
    file.writeln(genIndent(indent), "; ", identifier);
    file.writeln();
}


void functionDefinition(File file, int indent, BasicType retval, string name, Parameter[] parameters)
{
    file.write(genIndent(indent));
    file.write("define ", llvmType(retval), " @", name);
    file.write("(");
    foreach (i, parameter; parameters) {
        file.write(llvmType(parameter.basicType), " %", parameter.identifier.value);
        if (i < parameters.length - 1) {
            file.write(", ");
        }
    }
    file.writeln(") {");
}
