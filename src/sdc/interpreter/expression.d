/**
 * Copyright 2011 Bernard Helyer.
 * This file is part of SDC.
 * See LICENCE or sdc.d for more details.
 */
module sdc.interpreter.expression;

import std.conv;

import sdc.compilererror;
import sdc.extract;
import sdc.location;
import sdc.util;
import sdc.ast.base;
import sdc.ast.expression;
import sdc.gen.type;
import sdc.interpreter.base;

i.Value nullVal;

i.Value interpretExpression(Expression e, Interpreter interpreter)
{
    i.Value val = interpretConditionalExpression(e.conditionalExpression, interpreter);
    if (e.expression !is null) {
        return interpretExpression(e.expression, interpreter);
    }
    return val;
}

i.Value interpretConditionalExpression(ConditionalExpression e, Interpreter interpreter)
{
    i.Value val = interpretBinaryExpression(e.binaryExpression, interpreter);
    if (e.expression !is null) {
        i.Value asBool = val.toBool();
        if (asBool.val.Bool) {
            return interpretExpression(e.expression, interpreter);
        } else {
            return interpretConditionalExpression(e.conditionalExpression, interpreter);
        }
        assert(false);
    }
    return val;
}

i.Value interpretUnaryExpression(UnaryExpression e, Interpreter interpreter)
{
    switch (e.unaryPrefix) with (UnaryPrefix) {
    case None:
        return interpretPostfixExpression(e.postfixExpression, interpreter);
    default:
        throw new CompilerPanic(e.location, "unimplemented unary expression type.");
    }
}

i.Value performOperation(T)(Interpreter interpreter, Location location, BinaryOperation operation, T v, T rhs)
{
    return nullVal;
}

alias BinaryExpressionProcessor!(i.Value, Interpreter, interpretUnaryExpression, performOperation) processor;
alias processor.genBinaryExpression interpretBinaryExpression;

i.Value interpretPostfixExpression(PostfixExpression e, Interpreter interpreter)
{
    switch (e.type) with (PostfixType) {
    case Primary:
        return interpretPrimaryExpression(cast(PrimaryExpression) e.firstNode, interpreter);
    default:
        throw new CompilerPanic(e.location, "unimplemented postfix expression type.");
    }
}

i.Value interpretPrimaryExpression(PrimaryExpression e, Interpreter interpreter)
{
    i.Value val;
    switch (e.type) {
    case PrimaryType.IntegerLiteral:
        auto asLiteral = cast(IntegerLiteral) e.node;
        assert(asLiteral !is null);
        val = new i.IntValue(extractIntegerLiteral(asLiteral));
        break;
    case PrimaryType.Identifier:
        interpreter.addTopLevels(e.location);
        auto ident = cast(Identifier) e.node;
        assert(ident !is null);
        string id = extractIdentifier(ident);
        val = interpreter.store.get(id);
        if (val is null) {
            throw new CompilerError(e.location, "unknown identifier used in expression.");
        }
        break;
    default:
        throw new CompilerPanic(e.location, "unsupport CTFE expression type: " ~ to!string(e.type));
    }
    return val;
}
