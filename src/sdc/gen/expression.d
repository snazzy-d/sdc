/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.expression;

import std.conv;

import llvm.c.Core;

import sdc.compilererror;
import sdc.ast.base;
import sdc.ast.expression;
import sdc.gen.semantic;


LLVMValueRef genExpression(Expression expr, Semantic semantic)
{
    auto lhs = genAssignExpression(expr.assignExpression, semantic);
    return lhs;
}

LLVMValueRef genAssignExpression(AssignExpression expr, Semantic semantic)
{
    auto lhs = genConditionalExpression(expr.conditionalExpression, semantic);
    return lhs;
}

LLVMValueRef genConditionalExpression(ConditionalExpression expr, Semantic semantic)
{
    auto lhs = genOrOrExpression(expr.orOrExpression, semantic);
    return lhs;
}

LLVMValueRef genOrOrExpression(OrOrExpression expr, Semantic semantic)
{
    auto lhs = genAndAndExpression(expr.andAndExpression, semantic);
    return lhs;
}

LLVMValueRef genAndAndExpression(AndAndExpression expr, Semantic semantic)
{
    auto lhs = genOrExpression(expr.orExpression, semantic);
    return lhs;
}

LLVMValueRef genOrExpression(OrExpression expr, Semantic semantic)
{
    auto lhs = genXorExpression(expr.xorExpression, semantic);
    return lhs;
}

LLVMValueRef genXorExpression(XorExpression expr, Semantic semantic)
{
    auto lhs = genAndExpression(expr.andExpression, semantic);
    return lhs;
}

LLVMValueRef genAndExpression(AndExpression expr, Semantic semantic)
{
    auto lhs = genCmpExpression(expr.cmpExpression, semantic);
    return lhs;
}

LLVMValueRef genCmpExpression(CmpExpression expr, Semantic semantic)
{
    auto lhs = genShiftExpression(expr.lhShiftExpression, semantic);
    return lhs;
}

LLVMValueRef genShiftExpression(ShiftExpression expr, Semantic semantic)
{
    auto lhs = genAddExpression(expr.addExpression, semantic);
    return lhs;
}

LLVMValueRef genAddExpression(AddExpression expr, Semantic semantic)
{
    auto lhs = genMulExpression(expr.mulExpression, semantic);
    if (expr.addExpression !is null) {
        auto rhs = genAddExpression(expr.addExpression, semantic);
        final switch (expr.addOperation) {
        case AddOperation.Add:
            lhs = LLVMBuildAdd(semantic.builder, lhs, rhs, "add");
            break;
        case AddOperation.Subtract:
            break;
        case AddOperation.Concat:
            break;
        }
    }
    return lhs;
}

LLVMValueRef genMulExpression(MulExpression expr, Semantic semantic)
{
    auto lhs = genPowExpression(expr.powExpression, semantic);
    return lhs;
}

LLVMValueRef genPowExpression(PowExpression expr, Semantic semantic)
{
    auto lhs = genUnaryExpression(expr.unaryExpression, semantic);
    return lhs;
}

LLVMValueRef genUnaryExpression(UnaryExpression expr, Semantic semantic)
{
    auto lhs = genPostfixExpression(expr.postfixExpression, semantic);
    return lhs;
}

LLVMValueRef genPostfixExpression(PostfixExpression expr, Semantic semantic)
{
    auto lhs = genPrimaryExpression(expr.primaryExpression, semantic);
    return lhs;
}

LLVMValueRef genPrimaryExpression(PrimaryExpression expr, Semantic semantic)
{
    switch (expr.type) {
    case PrimaryType.IntegerLiteral:
        return LLVMConstInt(LLVMInt32TypeInContext(semantic.context), to!int((cast(IntegerLiteral)expr.node).value), false);
    default:
        error(expr.location, "ICE: unhandled primary expression type.");
    }
    assert(false);
}
