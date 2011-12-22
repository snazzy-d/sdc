/**
 * Copyright 2010-2011 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.util;

import core.runtime;
import std.array;
import std.conv;
import std.file;
import std.random;
import std.stdio;
import std.string;
import std.process;

import sdc.compilererror;
import sdc.ast.expression;
import sdc.gen.sdcmodule;

bool contains(T)(const(T)[] l, const T a)
{
    foreach (e; l) {
        if (e == a) {
            return true;
        }
    }
    return false;
}

void debugPrint(T...)(lazy string msg, T vs) 
{
    debug {
        write("DEBUG: ");
        writefln(msg, vs);
    }
}

void debugPrint(T)(T arg)
{
    debugPrint("%s", to!string(arg));
}

void debugPrintMany(T...)(T args)
{
    foreach (arg; args) {
        debugPrint("%s", to!string(arg));
    }
}

void dbga() { debugPrint("A"); }
void dbgb() { debugPrint("B"); }

enum Status : bool
{
    Failure,
    Success,
}

unittest
{
    auto fail = Status.Failure;
    auto success = Status.Success;
    assert(!fail);
    assert(success);
}

template MultiMixin(alias A, T...)
{
    static if (T.length) {
        mixin A!(T[0]);
        mixin MultiMixin!(A, T[1 .. $]);
    }
}

// My lord, this has got to go.
mixin template ImportToModule(T, string ARGS)
{
    override T importToModule(Module mod)
    {
        static typeof(this) cache = null;
        if (cache !is null) {
            return cache;
        }
        mixin("auto imprtd = new typeof(this)(" ~ ARGS ~ ");");
        cache = imprtd;
        foreach (member; __traits(allMembers, typeof(this))) { 
            enum m = "imprtd." ~ member; 
            static if (__traits(compiles, mixin(m ~ ".keys && " ~ m ~ ".values"))) {
                foreach (k, v; mixin(member)) {
                    static if (__traits(compiles, mixin(member ~ "[k].importToModule(mod)"))) {
                        mixin(m ~ "[k] = " ~ member ~ "[k].importToModule(mod);");
                    } else {
                        mixin(m ~ "[k] = " ~ member ~ "[k];");
                    }
                }
            } else static if (__traits(compiles, mixin(member ~ ".length && " ~ member ~ ".ptr")) && __traits(isScalar, mixin(member))) {
                static if (__traits(compiles, mixin(member ~ "[0].importToModule(mod)"))) {
                    mixin(m ~ " = new typeof(" ~ member ~ ")[" ~ member ~ ".length];");
                    foreach (i, e; mixin(member)) {
                        mixin(m ~ "[i] = " ~ member ~ "[i].importToModule(mod);");
                    }  
                } else {
                    mixin(m ~ " = " ~ member ~ ".dup;");
                } 
            } else static if (__traits(compiles, mixin(m ~ " = " ~ member ~ ".importToModule(mod)"))) {
                mixin("if (" ~ m ~ "!is null) " ~ m ~ " = " ~ member ~ ".importToModule(mod);");
            } else static if (__traits(compiles, mixin(m ~ " = " ~ member))) {
                mixin(m ~ " = " ~ member ~ ";");
            } 
        }
        static if (__traits(compiles, imprtd.declare())) {
            imprtd.declare();
        }
        static if (__traits(compiles, imprtd.add(mod, this.mangledName))) {
            imprtd.mod = null;
            imprtd.add(mod, this.mangledName);
        }
        return imprtd;
    }
}

T[] importList(T)(T[] list, Module mod)
{
    auto output = new T[list.length];
    foreach (i, e; list) {
        output[i] = e.importToModule(mod);
    }
    return output;
}

class ImportDummy(T)
{
    T importToModule(Module mod)
    {
        return T.init;
    }
}

Throwable.TraceInfo nullTraceHandler(void*)
{
    return null;
}

void disableStackTraces()
{
    Runtime.traceHandler = &nullTraceHandler;
}

void enableStackTraces()
{
    Runtime.traceHandler = &defaultTraceHandler;
}

/**
 * Generate a filename in a temporary directory that doesn't exist.
 *
 * Params:
 *   extension = a string to be appended to the filename. Defaults to an empty string.
 *
 * Returns: an absolute path to a unique (as far as we can tell) filename. 
 */
string temporaryFilename(string extension = "")
{
    version (Windows) {
        string prefix = getenv("TEMP") ~ '/';
    } else {
        string prefix = "/tmp/";
    }
    string filename;
    do {
        filename = randomString(32);
        filename = prefix ~ filename ~ extension;
    } while (exists(filename));
    return filename;
}

/// Generate a random string `length` characters long.
string randomString(size_t length)
{
    auto str = new char[length];
    foreach (i; 0 .. length) {
        char c;
        switch (uniform(0, 3)) {
        case 0:
            c = cast(char) uniform('0', '9' + 1);
            break;
        case 1:
            c = cast(char) uniform('a', 'z' + 1);
            break;
        case 2:
            c = cast(char) uniform('A', 'Z' + 1);
            break;
        default:
            assert(false);
        }
        str[i] = c;
    }
    return str.idup;    
}

/**
 * Contains a function, genBinaryExpression.
 * 
 * The function handles converting the AST's infix representation
 * to postfix and handles fixity, calls a function F to create each
 * side of an expression and calls a function G to handle the whole
 * expression.
 * 
 * Params:
 *   V - the Value type that represents a single node in an expression.
 *       see gen.Value and interpreter.i.Value.
 *   M - a manager object that is passed to both F and G.
 *       see gen.Module and interpreter.Interpreter.
 *   F - a function of the form V function(UnaryExpression, M).
 *       called on each terminal of an expression to get its value.
 *   G - a function of the form V function(T)(M, Location, BinaryOperation, T, T),
 *       where T is an ExpressionOrOperation that are Expressions, and thus
 *       contain a V. They don't take a V, because the terminals cannot
 *       be eagerly evaluated in all cases.
 */
template BinaryExpressionProcessor(V, M, alias F, alias G)
{
    struct ExpressionOrOperation
    {
        UnaryExpression expression;
        BinaryOperation operation;
        V userdata;
        
        this(BinaryOperation operation)
        {
            this.operation = operation;
        }
        
        this(UnaryExpression expression)
        {
            this.expression = expression;
        }
        
        this(V userdata)
        {
            this.userdata = userdata;
        }
        
        bool isExpression() @property
        {
            return expression !is null;
        }
        
        V gen(M manager)
        in { assert(isExpression || userdata !is null); }
        body
        {
            if (userdata !is null) {
                return userdata;
            }
            return F(expression, manager);
        }
    }
    
    /// Gather all expressions and operations into a single list without evaluating them.
    ExpressionOrOperation[] gatherExpressions(BinaryExpression expression)
    {
        ExpressionOrOperation[] list;
        while (expression.operation != BinaryOperation.None) {
            list ~= ExpressionOrOperation(expression.lhs);
            list ~= ExpressionOrOperation(expression.operation);
            expression = expression.rhs;
        }
        list ~= ExpressionOrOperation(expression.lhs);
        return list;
    }
    
    ExpressionOrOperation[] expressionsAsPostfix(BinaryExpression expression)
    {
        // Ladies and gentlemen, Mr. Edsger Dijkstra's shunting-yard algorithm! (polite applause)
        ExpressionOrOperation[] infix = gatherExpressions(expression);
        ExpressionOrOperation[] postfix;
        BinaryOperation[] operationStack;
        
        foreach (element; infix) {
            if (element.isExpression) {
                postfix ~= element;
                continue;
            }
            while (!operationStack.empty) {
                if ((isLeftAssociative(element.operation) && element.operation <= operationStack.front) ||
                    (!isLeftAssociative(element.operation) && element.operation < operationStack.front)) {
                    postfix ~= ExpressionOrOperation(operationStack.front);
                    operationStack.popFront;
                } else {
                    break;
                }
            }
            operationStack = element.operation ~ operationStack;    
        }
        
        foreach (operation; operationStack) {
            postfix ~= ExpressionOrOperation(operation);
        }
        
        return postfix;
    }
    
    V genBinaryExpression(BinaryExpression expression, M mod)
    {
        auto postfix = expressionsAsPostfix(expression);
        ExpressionOrOperation[] valueStack;
        foreach (element; postfix) {
            if (element.isExpression) {
                valueStack = element ~ valueStack;
            } else {
                if (valueStack.length < 2) {
                    throw new CompilerPanic(expression.location, "invalid expression made it to backend.");
                }
                auto rhs = valueStack.front;
                valueStack.popFront;
                auto lhs = valueStack.front;
                valueStack.popFront;
                
                valueStack = ExpressionOrOperation(G(mod, expression.location, element.operation, lhs, rhs)) ~ valueStack;
            }
        } 
        
        return valueStack.front.gen(mod);
    }
}
