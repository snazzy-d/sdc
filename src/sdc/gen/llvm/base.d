/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.llvm.base;

import std.stdio;
import std.conv;

import sdc.primitive;
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

string llvmType(Primitive primitive)
{
    if (primitive.size == 0) {
        return "void";
    }
    
    char[] buf = "i".dup;
    buf ~= to!string(primitive.size);
    foreach (i; 0 .. primitive.pointer) {
        buf ~= "*";
    }
    return buf.idup;
}

string llvmString(Value value)
{
    if (value.type == ValueType.Variable) {
        auto var = cast(Variable) value;
        return (var.isGlobal ? "@" : "%") ~ var.name;
    } else {
        return (cast(Constant)value).value;
    }
}

/**
 * Comment 'msg' at the current indent level.
 */
void emitComment(File file, string msg)
{
    emitIndent(file);
    file.writeln("; ", msg);
}

/**
 * Allocate memory on the stack of the type of var, and
 * place in var. Note that this modifies the type of var
 * to a pointer to its previous type.
 */
void emitAlloca(File file, Variable var)
{
    emitIndent(file);
    file.writeln("%", var.name, " = alloca ", llvmType(var.primitive));
    var.primitive.pointer++;
}

void emitGlobal(File file, Variable var)
{
    emitIndent(file);
    file.writeln("@", var.name, " = common global ", llvmType(var.primitive), " 0");
    var.primitive.pointer++;  // Globals are always pointers.
    var.isGlobal = true;
}

/**
 * Store the value val in the specified variable.
 * Note that the type of var should be a pointer to the type of val.
 */
void emitStore(File file, Variable var, Value val)
{
    emitIndent(file);
    file.writefln("store %s %s, %s %s", llvmType(val.primitive), llvmString(val), llvmType(var.primitive), llvmString(var));
}

void emitLoad(File file, Variable to, Value from)
{
    emitIndent(file);
    file.writeln(llvmString(to), " = load ", llvmType(to.primitive), "* ", llvmString(from));
}

void emitOp(string OP)(File file, Variable to, Value a, Value b)
{
    emitIndent(file);
    file.writefln("%s = %s %s %s, %s", llvmString(to), mixin(OP), llvmType(to.primitive), llvmString(a), llvmString(b));
}

alias emitOp!(`"sub"`) emitSub;
alias emitOp!(`"xor"`) emitXor;
alias emitOp!(`"mul"`) emitMul;
alias emitOp!(`"add"`) emitAdd;
alias emitOp!(`"sdiv"`) emitDiv;


/**
 * Negate the value stored in var.
 * var is assumed to be a pointer to an integer.
 * The negated value is returned in a pointer to an integer.
 */
Variable emitNeg(File file, Variable var)
{
    auto minusOne = genVariable(Primitive(32, 0), "minusOne");
    auto tmp = genVariable(Primitive(32, 0), "tmp");
    emitLoad(file, tmp, var);
    emitSub(file, minusOne, tmp, new Constant("1", Primitive(32, 0)));
    auto negated = genVariable(Primitive(32, 0), "negated");
    emitXor(file, negated, minusOne, new Constant("-1", minusOne.primitive));
    auto retval = genVariable(Primitive(32, 0), "negated");
    emitAlloca(file, retval);
    emitStore(file, retval, negated);
    return retval;
}


Variable emitDuoOps(string OP)(File file, Variable a, Variable b)
{
    auto prim = a.primitive;
    prim.pointer--;
    auto op1 = genVariable(prim, "op");
    emitLoad(file, op1, a);
    auto op2 = genVariable(prim, "op");
    emitLoad(file, op2, b);
    auto result = genVariable(prim, "result");
    mixin(OP ~ "(file, result, op1, op2);");
    auto retval = genVariable(prim, "retval");
    emitAlloca(file, retval);
    emitStore(file, retval, result);
    return retval;
}

alias emitDuoOps!("emitMul") emitMulOps;
alias emitDuoOps!("emitAdd") emitAddOps;
alias emitDuoOps!("emitSub") emitSubOps;
alias emitDuoOps!("emitDiv") emitDivOps;

void emitFunctionName(File file, FunctionDeclaration declaration)
{
    emitIndent(file);
    file.write("define ", llvmType(fullTypeToPrimitive(declaration.retval)), " @", extractIdentifier(declaration.name));
    file.write("(");
}

void emitFunctionParameter(File file, Primitive primitive, string name, bool last)
{
    file.write(llvmType(primitive), " %", name, last ? "" : ", ");
}

void emitFunctionBeginEnd(File file)
{
    file.writeln(") {");
}

void emitCloseFunctionDeclaration(File file, FunctionDeclaration declaration)
{
    file.writeln("}\n");
}

void emitReturn(File file, Value val)
{
    emitIndent(file);
    file.writefln("ret %s %s", llvmType(val.primitive), llvmString(val));
}

void emitVoidReturn(File file)
{
    emitIndent(file);
    file.writeln("ret void");
}

/**
 * Generate code to call a function.
 * Params:
 *   file = the file to write the generated code to.
 *   name = the name of the function to call.
 *   args = arguments to the function, stored via a pointer.
 */
Variable emitFunctionCall(File file, Variable func, Variable[] args)
{
    Variable[] directargs;
    foreach (arg; args) {
        auto var = genVariable(removePointer(arg.primitive), "param");
        emitLoad(file, var, arg);
        directargs ~= var;
    }
    
    emitIndent(file);
    auto ret = genVariable(func.primitive, "ret");
    file.writef("%s = call %s @%s(", llvmString(ret), llvmType(func.primitive), func.name);
    foreach (i, arg; directargs) {
        file.write(llvmType(arg.primitive), " %", arg.name);
        if (i < directargs.length - 1) {
            file.write(", ");
        }
    }
    file.writeln(")");
    
    if (func.primitive.size != 0) {
        auto retval = genVariable(func.primitive, "retval");
        emitAlloca(file, retval);
        emitStore(file, retval, ret);
        return retval;
    } else {
        return voidVariable;
    }
    assert(false);
}
