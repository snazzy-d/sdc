/**
 * Copyright 2011 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.interpreter.expression;

import sdc.compilererror;
import sdc.location;
import sdc.util;
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

i.Value performOperation(T)(Interpreter interpreter, Location location, BinaryOperation operation, T lhs, T rhs)
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
    return nullVal;
}
