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
import sdc.extract.base;
import sdc.extract.expression;

int indent;

void incrementIndent()
{
    indent++;
}

void decrementIndent()
{
    if (indent > 0) {
        indent--;
    }
}

void emitIndent(File file)
{
    foreach (i; 0 .. indent) {
        file.write("  ");
    }
}

string llvmType(Type type)
{
    return "i32";
}


void emitComment(File file, string msg)
{
    emitIndent(file);
    file.writeln("; ", msg);
}

void emitAlloca(File file, string variable, Type type)
{
    emitIndent(file);
    file.writeln("%", variable, " = alloca ", llvmType(type));
}

void emitStoreValue(File file, string variable, Type type, string value)
{
    emitIndent(file);
    file.writeln("store ", llvmType(type), " ", value, ", ", llvmType(type), "* %", variable);
}

void emitStoreVariable(File file, string variable, Type type, string value)
{
    emitIndent(file);
    file.writeln("store ", llvmType(type), " %", value, ", ", llvmType(type), "* %", variable);
}


void emitLoad(File file, string tovariable, string fromvariable, Type type)
{
    emitIndent(file);
    file.writeln("%", tovariable, " = load ", llvmType(type), "* %", fromvariable);
}

void emitAdd(File file, string tovariable, string a, string b, Type type)
{
    emitIndent(file);
    file.writeln("%", tovariable, " = add ", llvmType(type), " %", a, ", %", b);
}

void emitSub(File file, string tovariable, string a, string b, Type type)
{
    emitIndent(file);
    file.writeln("%", tovariable, " = sub ", llvmType(type), " %", a, ", %", b);
}


void emitMul(File file, string tovariable, string a, string b, Type type)
{
    emitIndent(file);
    file.writeln("%", tovariable, " = mul ", llvmType(type), " %", a, ", %", b);
}

void emitDiv(File file, string tovariable, string a, string b, Type type)
{
    emitIndent(file);
    file.writeln("%", tovariable, " = sdiv ", llvmType(type), " %", a, ", %", b);
}

void emitFunctionDeclaration(File file, FunctionDeclaration declaration)
{
    emitIndent(file);
    file.write("define ", llvmType(declaration.retval), " @", extractIdentifier(declaration.name));
    file.write("(");
    foreach (i, parameter; declaration.parameters) {
        file.write(llvmType(parameter.type), extractIdentifier(parameter.identifier));
        if (i < declaration.parameters.length - 1) {
            file.write(", ");
        }
    }
    file.writeln(") {");
}

void emitCloseFunctionDeclaration(File file, FunctionDeclaration declaration)
{
    file.writeln("}");
}

void emitReturnExpression(File file, string variable, Type type)
{
    emitIndent(file);
    file.writeln("ret ", llvmType(type), " %", variable);
}


