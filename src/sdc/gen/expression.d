/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.expression;

import std.conv;
import std.string;

import llvm.c.Core;

import sdc.util;
import sdc.compilererror;
import sdc.extract.base;
import ast = sdc.ast.all;
import sdc.gen.sdcmodule;
import sdc.gen.type;
import sdc.gen.value;


Value genExpression(ast.Expression expression, Module mod)
{
    auto v = genAssignExpression(expression.assignExpression, mod);
    if (expression.expression !is null) {
        return genExpression(expression.expression, mod);
    }
    return v;
}

Value genAssignExpression(ast.AssignExpression expression, Module mod)
{
    auto lhs = genConditionalExpression(expression.conditionalExpression, mod);
    if (expression.assignType == ast.AssignType.None) {
        return lhs;
    }
    auto rhs = genAssignExpression(expression.assignExpression, mod);
    rhs = implicitCast(rhs, lhs.type);
    switch (expression.assignType) with (ast.AssignType) {
    case None:
        assert(false);
    case Normal:
        lhs.set(rhs);
        break;
    case AddAssign:
        lhs.set(lhs.add(rhs));
        break;
    case SubAssign:
        lhs.set(lhs.sub(rhs));
        break;
    case MulAssign:
        lhs.set(lhs.mul(rhs));
        break;
    case DivAssign:
        lhs.set(lhs.div(rhs));
        break;
    case ModAssign:
        panic(expression.location, "modulo assign is unimplemented.");
        break;
    case AndAssign:
        panic(expression.location, "and assign is unimplemented.");
        break;
    case OrAssign:
        panic(expression.location, "or assign is unimplemented.");
        break;
    case XorAssign:
        panic(expression.location, "xor assign is unimplemented.");
        break;
    case CatAssign:
        panic(expression.location, "cat assign is unimplemented.");
        break;
    case ShiftLeftAssign:
        panic(expression.location, "shift left assign is unimplemented.");
        break;
    case SignedShiftRightAssign:
        panic(expression.location, "signed shift assign is unimplemented.");
        break;
    case UnsignedShiftRightAssign:
        panic(expression.location, "unsigned shift assign is unimplemented.");
        break;
    case PowAssign:
        panic(expression.location, "pow assign is unimplemented.");
        break;
    default:
        panic(expression.location, "unimplemented assign expression type.");
        assert(false);
    }
    return rhs;
}

Value genConditionalExpression(ast.ConditionalExpression expression, Module mod)
{
    auto a = genOrOrExpression(expression.orOrExpression, mod);
    return a;
}

Value genOrOrExpression(ast.OrOrExpression expression, Module mod)
{
    Value val;
    if (expression.orOrExpression !is null) {
        auto lhs = genOrOrExpression(expression.orOrExpression, mod);
        val = genAndAndExpression(expression.andAndExpression, mod);
        val.or(lhs);
    } else {
        val = genAndAndExpression(expression.andAndExpression, mod);
    }
    return val;
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
    auto lhs = genShiftExpression(expression.lhShiftExpression, mod);
    switch (expression.comparison) {
    case ast.Comparison.None:
        break;
    case ast.Comparison.Equality:
        auto rhs = genShiftExpression(expression.rhShiftExpression, mod);
        lhs = lhs.eq(rhs);
        break;
    case ast.Comparison.NotEquality:
        auto rhs = genShiftExpression(expression.rhShiftExpression, mod);
        lhs = lhs.neq(rhs);
        break;
    case ast.Comparison.Greater:
        auto rhs = genShiftExpression(expression.rhShiftExpression, mod);
        lhs = lhs.gt(rhs);
        break;
    case ast.Comparison.LessEqual:
        auto rhs = genShiftExpression(expression.rhShiftExpression, mod);
        lhs = lhs.lte(rhs);
        break;
    default:
        panic(expression.location, "unhandled comparison expression.");
        assert(false);
    }
    return lhs;
}

Value genShiftExpression(ast.ShiftExpression expression, Module mod)
{
    return genAddExpression(expression.addExpression, mod);
}

Value genAddExpression(ast.AddExpression expression, Module mod)
{
    Value val;
    if (expression.addExpression !is null) {
        auto lhs = genAddExpression(expression.addExpression, mod);
        val = genMulExpression(expression.mulExpression, mod);
        binaryOperatorImplicitCast(&lhs, &val);
        
        final switch (expression.addOperation) {
        case ast.AddOperation.Add:
            val = lhs.add(val);
            break;
        case ast.AddOperation.Subtract:
            val = lhs.sub(val);
            break;
        case ast.AddOperation.Concat:
            panic(expression.location, "unimplemented add operation.");
            assert(false);
        }
    } else {
        val = genMulExpression(expression.mulExpression, mod);
    }
    
    return val;
}

Value genMulExpression(ast.MulExpression expression, Module mod)
{
    Value val;
    if (expression.mulExpression !is null) {
        auto lhs = genMulExpression(expression.mulExpression, mod);
        val = genPowExpression(expression.powExpression, mod);
        binaryOperatorImplicitCast(&lhs, &val);
        
        final switch (expression.mulOperation) {
        case ast.MulOperation.Mul:
            val = lhs.mul(val);
            break;
        case ast.MulOperation.Div:
            val = lhs.div(val);
            break;
        case ast.MulOperation.Mod:
            panic(expression.location, "unimplemented mul operation.");
            assert(false);
        }
    } else {
        val = genPowExpression(expression.powExpression, mod);
    }
    return val;
}

Value genPowExpression(ast.PowExpression expression, Module mod)
{
    return genUnaryExpression(expression.unaryExpression, mod);
}

Value genUnaryExpression(ast.UnaryExpression expression, Module mod)
{
    Value val;
    final switch (expression.unaryPrefix) {
    case ast.UnaryPrefix.PrefixDec:
        val = genUnaryExpression(expression.unaryExpression, mod);
        auto rhs = new IntValue(mod, expression.location, 1);
        binaryOperatorImplicitCast(&val, &rhs);
        val.set(val.sub(rhs));
        break;
    case ast.UnaryPrefix.PrefixInc:
        val = genUnaryExpression(expression.unaryExpression, mod);
        auto rhs = new IntValue(mod, expression.location, 1);
        binaryOperatorImplicitCast(&val, &rhs);
        val.set(val.add(rhs));
        break;
    case ast.UnaryPrefix.Cast:
        val = genUnaryExpression(expression.castExpression.unaryExpression, mod);
        val = val.performCast(astTypeToBackendType(expression.castExpression.type, mod, OnFailure.DieWithError));
        break;
    case ast.UnaryPrefix.UnaryMinus:
        val = genUnaryExpression(expression.unaryExpression, mod);
        auto zero = new IntValue(mod, expression.location, 0);
        binaryOperatorImplicitCast(&zero, &val);
        val = zero.sub(val);
        break;
    case ast.UnaryPrefix.UnaryPlus:
        val = genUnaryExpression(expression.unaryExpression, mod);
        break;
    case ast.UnaryPrefix.AddressOf:
        val = genUnaryExpression(expression.unaryExpression, mod);
        val = val.addressOf();
        break;
    case ast.UnaryPrefix.Dereference:
        val = genUnaryExpression(expression.unaryExpression, mod);
        val = val.dereference();
        break;
    case ast.UnaryPrefix.LogicalNot:
    case ast.UnaryPrefix.BitwiseNot:
        panic(expression.location, "unimplemented unary expression.");
        assert(false);
    case ast.UnaryPrefix.None:
        val = genPostfixExpression(expression.postfixExpression, mod);
        break;
    }
    return val;
}

Value genPostfixExpression(ast.PostfixExpression expression, Module mod)
{
    auto lhs = genPrimaryExpression(expression.primaryExpression, mod);
    final switch (expression.type) {
    case ast.PostfixType.None:
        break;
    case ast.PostfixType.Dot:
        auto base = lhs;
        foreach (i, dotExpression; expression.dotExpressions) {
            mod.base = base;
            base = genPrimaryExpression(dotExpression, mod);
        }
        lhs = base;
        mod.base = null;
        break;
    case ast.PostfixType.PostfixInc:
        auto val = lhs;
        lhs = new IntValue(mod, lhs);
        auto rhs = new IntValue(mod, expression.location, 1);
        binaryOperatorImplicitCast(&lhs, &rhs);
        val.set(lhs.add(rhs));
        break;
    case ast.PostfixType.PostfixDec:
        auto val = lhs;
        lhs = new IntValue(mod, lhs);
        auto rhs = new IntValue(mod, expression.location, 1);
        binaryOperatorImplicitCast(&lhs, &rhs);
        val.set(lhs.sub(rhs));
        break;
    case ast.PostfixType.Parens:
        if (lhs.type.dtype == DType.Function) {
            Value[] args;
            auto argList = cast(ast.ArgumentList) expression.firstNode;
            assert(argList);
            foreach (expr; argList.expressions) {
                args ~= genAssignExpression(expr, mod);
            }
            lhs = lhs.call(args);
        } else {
            error(expression.location, "can only call functions.");
        }
        break;
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
    case ast.PrimaryType.FloatLiteral:
        return new DoubleValue(mod, expression.location, extractFloatLiteral(cast(ast.FloatLiteral) expression.node));
    case ast.PrimaryType.True:
        return new BoolValue(mod, expression.location, true);
    case ast.PrimaryType.False:
        return new BoolValue(mod, expression.location, false);
    case ast.PrimaryType.Identifier:
        return genIdentifier(cast(ast.Identifier) expression.node, mod);
    case ast.PrimaryType.ParenExpression:
        return genExpression(cast(ast.Expression) expression.node, mod);
    default:
        panic(expression.location, "unhandled primary expression type.");
    }
    return val;
}

Value genIdentifier(ast.Identifier identifier, Module mod)
{
    auto name = extractIdentifier(identifier);
    void failure() { error(identifier.location, format("unknown identifier '%s'.", name)); }
    
    if (mod.base !is null) {
        return mod.base.getMember(name);
    }
    auto store = mod.search(name);
    if (store is null) {
        failure();
    }
    
    return store.value();
}
