/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.expression;

import std.string;

import sdc.compilererror;
import sdc.extract.base;
import ast = sdc.ast.all;
import sdc.gen.sdcmodule;
import sdc.gen.value;


Value genExpression(ast.Expression expression, Module mod)
{
    return genAssignExpression(expression.assignExpression, mod);
}

Value genAssignExpression(ast.AssignExpression expression, Module mod)
{
    return genConditionalExpression(expression.conditionalExpression, mod);
}

Value genConditionalExpression(ast.ConditionalExpression expression, Module mod)
{
    return genOrOrExpression(expression.orOrExpression, mod);
}

Value genOrOrExpression(ast.OrOrExpression expression, Module mod)
{
    return genAndAndExpression(expression.andAndExpression, mod);
}

Value genAndAndExpression(ast.AndAndExpression expression, Module mod)
{
    return genOrExpression(expression.orExpression, mod);
}

Value genOrExpression(ast.OrExpression expression, Module mod)
{
    return genXorExpression(expression.xorExpression, mod);
}

Value genXorExpression(ast.XorExpression expression, Module mod)
{
    return genAndExpression(expression.andExpression, mod);
}

Value genAndExpression(ast.AndExpression expression, Module mod)
{
    return genCmpExpression(expression.cmpExpression, mod);
}

Value genCmpExpression(ast.CmpExpression expression, Module mod)
{
    return genShiftExpression(expression.lhShiftExpression, mod);
}

Value genShiftExpression(ast.ShiftExpression expression, Module mod)
{
    return genAddExpression(expression.addExpression, mod);
}

Value genAddExpression(ast.AddExpression expression, Module mod)
{
    return genMulExpression(expression.mulExpression, mod);
}

Value genMulExpression(ast.MulExpression expression, Module mod)
{
    return genPowExpression(expression.powExpression, mod);
}

Value genPowExpression(ast.PowExpression expression, Module mod)
{
    return genUnaryExpression(expression.unaryExpression, mod);
}

Value genUnaryExpression(ast.UnaryExpression expression, Module mod)
{
    return genPostfixExpression(expression.postfixExpression, mod);
}

Value genPostfixExpression(ast.PostfixExpression expression, Module mod)
{
    auto lhs = genPrimaryExpression(expression.primaryExpression, mod);
    final switch (expression.type) {
    case ast.PostfixType.None:
        break;
    case ast.PostfixType.Dot:
    case ast.PostfixType.PostfixInc:
        auto val = lhs;
        lhs = new IntValue(mod, lhs);
        val.add(new IntValue(mod, expression.location, 1));
        break;
    case ast.PostfixType.PostfixDec:
    case ast.PostfixType.Parens:
    case ast.PostfixType.Index:
    case ast.PostfixType.Slice:
        panic(expression.location, "unimplemented postfix expression type.");
        assert(false);
    }
    return lhs;
}

Value genPrimaryExpression(ast.PrimaryExpression expression, Module mod)
{
    Value val;
    switch (expression.type) {
    case ast.PrimaryType.IntegerLiteral:
        return new IntValue(mod, expression.location, extractIntegerLiteral(cast(ast.IntegerLiteral) expression.node));
    case ast.PrimaryType.True:
        return new BoolValue(mod, expression.location, true);
    case ast.PrimaryType.False:
        return new BoolValue(mod, expression.location, false);
    case ast.PrimaryType.Identifier:
        return genIdentifier(cast(ast.Identifier) expression.node, mod);
    default:
        panic(expression.location, "unhandled primary expression type.");
    }
    return val;
}

Value genIdentifier(ast.Identifier identifier, Module mod)
{
    auto name = extractIdentifier(identifier);
    auto val = mod.currentScope.get(name);
    if (val is null) {
        error(identifier.location, format("unknown identifier '%s'.", name));
    }
    return val;
}
