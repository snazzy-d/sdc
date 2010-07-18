/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.expression;

import std.conv;
import std.string;
import core.memory;

import llvm.c.Core;

import sdc.compilererror;
import sdc.ast.base;
import sdc.ast.expression;
import sdc.ast.declaration;
import sdc.gen.semantic;
import sdc.gen.extract;
import sdc.gen.type;


LLVMValueRef genExpression(Expression expr, Semantic semantic)
{
    auto lhs = genAssignExpression(expr.assignExpression, semantic);
    return lhs;
}

LLVMValueRef genAssignExpression(AssignExpression expr, Semantic semantic)
{
    auto lhs = genConditionalExpression(expr.conditionalExpression, semantic);
    if (expr.assignType != AssignType.None) {
        auto rhs = genAssignExpression(expr.assignExpression, semantic);
        auto r   = LLVMBuildLoad(semantic.builder, rhs, "assign");
        LLVMBuildStore(semantic.builder, r, lhs);
    }
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
        auto l   = LLVMBuildLoad(semantic.builder, lhs, "addlhs");
        auto r   = LLVMBuildLoad(semantic.builder, rhs, "addrhs");
        LLVMValueRef result;
        final switch (expr.addOperation) {
        case AddOperation.Add:
            result = LLVMBuildAdd(semantic.builder, l, r, "add");
            break;
        case AddOperation.Subtract:
            result = LLVMBuildSub(semantic.builder, l, r, "sub");
            break;
        case AddOperation.Concat:
            error(expr.location, "ICE: concatenation is unimplemented.");
            assert(false);
        }
        LLVMBuildStore(semantic.builder, result, lhs);
    }
    return lhs;
}

LLVMValueRef genMulExpression(MulExpression expr, Semantic semantic)
{
    auto lhs = genPowExpression(expr.powExpression, semantic);
    if (expr.mulExpression !is null) {
        auto rhs = genMulExpression(expr.mulExpression, semantic);
        auto l   = LLVMBuildLoad(semantic.builder, lhs, "mullhs");
        auto r   = LLVMBuildLoad(semantic.builder, rhs, "mulrhs");
        LLVMValueRef result;
        final switch (expr.mulOperation) {
        case MulOperation.Mul:
            result = LLVMBuildMul(semantic.builder, l, r, "mul");
            break;
        case MulOperation.Div:
            error(expr.location, "ICE: division is unimplemented.");
            break;
        case MulOperation.Mod:
            error(expr.location, "ICE: modulo is unimplemented.");
            break;
        }
        LLVMBuildStore(semantic.builder, result, lhs);
    }
    return lhs;
}

LLVMValueRef genPowExpression(PowExpression expr, Semantic semantic)
{
    auto lhs = genUnaryExpression(expr.unaryExpression, semantic);
    return lhs;
}

LLVMValueRef genUnaryExpression(UnaryExpression expr, Semantic semantic)
{
    LLVMValueRef lhs;
    if (expr.castExpression !is null) {
        lhs = genCastExpression(expr.castExpression, semantic);
    } else {
        lhs = genPostfixExpression(expr.postfixExpression, semantic);
    }
    return lhs;
}

LLVMValueRef genCastExpression(CastExpression expr, Semantic semantic)
{
    auto toType = typeToLLVM(expr.type, semantic);
    auto e = genUnaryExpression(expr.unaryExpression, semantic);
    auto val = LLVMBuildLoad(semantic.builder, e, "tmp");
    
    switch (LLVMGetTypeKind(toType)) {
    case LLVMTypeKind.Integer:
        val = LLVMBuildIntCast(semantic.builder, val, toType, "cast");
        break;
    default:
        error(expr.location, "invalid explicit cast.");
    }
    
    auto ex = LLVMBuildAlloca(semantic.builder, LLVMTypeOf(val), "ex");
    LLVMBuildStore(semantic.builder, val, ex);
    return ex;
}
0
LLVMValueRef genPostfixExpression(PostfixExpression expr, Semantic semantic)
{
    auto lhs = genPrimaryExpression(expr.primaryExpression, semantic);
    final switch (expr.postfixOperation) {
    case PostfixOperation.None:
        auto ident = cast(Identifier) expr.primaryExpression.node;
        if (ident is null) break;
        auto name = extractIdentifier(ident);
        auto d = semantic.getDeclaration(name);
        assert(d);  // It should've been looked up in genIdentifier.
        if (d.declarationType == DeclarationType.Function) {
            lhs = genFunctionCall(expr, semantic, lhs);
        }
        break;
    case PostfixOperation.Dot:
    case PostfixOperation.PostfixInc:
    case PostfixOperation.PostfixDec:
    case PostfixOperation.Index:
    case PostfixOperation.Slice:
        error(expr.location, "ICE: unsupported postfix operation.");
        assert(false);
    case PostfixOperation.Parens:
        lhs = genFunctionCall(expr, semantic, lhs);
        break;
    }
    return lhs;
}

LLVMValueRef genFunctionCall(PostfixExpression expr, Semantic semantic, LLVMValueRef fn)
{
    LLVMValueRef[] args;
    if (expr.argumentList !is null) foreach (arg; expr.argumentList.expressions) {
        auto exp   = genAssignExpression(arg, semantic);
        auto param = LLVMBuildLoad(semantic.builder, exp, "param");
        args ~= param;
    }
    verifyArgs(expr, args, fn);
    auto ret = LLVMBuildCall(semantic.builder, fn, args.ptr, args.length, "fn");
    auto retval = LLVMBuildAlloca(semantic.builder, LLVMTypeOf(ret), "retval");
    LLVMBuildStore(semantic.builder, ret, retval);
    return retval;
}


void verifyArgs(PostfixExpression expr, LLVMValueRef[] callerArgs, LLVMValueRef fn)
{
    
    auto argsLength = LLVMCountParams(fn);
    LLVMValueRef* functionArgs = cast(LLVMValueRef*) GC.malloc(LLVMValueRef.sizeof * argsLength);
    if (argsLength != callerArgs.length) goto err;
    LLVMGetParams(fn, functionArgs);
    foreach (i; 0 .. argsLength) {
        if (LLVMTypeOf(callerArgs[i]) != LLVMTypeOf(*(functionArgs + i))) {
            goto err;
        }
    }
    return;  // It all seems to check out.
    
err:
    error(expr.location, "function call does not match function signature.");    
}

LLVMValueRef genPrimaryExpression(PrimaryExpression expr, Semantic semantic)
{
    switch (expr.type) {
    case PrimaryType.Identifier:
        return genIdentifier(cast(Identifier) expr.node, semantic);
    case PrimaryType.IntegerLiteral:
        auto val = LLVMConstInt(LLVMInt32TypeInContext(semantic.context), to!int((cast(IntegerLiteral) expr.node).value), false);
        auto var = LLVMBuildAlloca(semantic.builder, LLVMTypeOf(val), "literalvar");
        LLVMBuildStore(semantic.builder, val, var);
        return var;
    default:
        error(expr.location, "ICE: unhandled primary expression type.");
    }
    assert(false);
}

LLVMValueRef genIdentifier(Identifier identifier, Semantic semantic)
{
    auto name = extractIdentifier(identifier);
    auto d    = semantic.getDeclaration(name);
    if (d is null) {
        error(identifier.location, format("undefined identifier '%s'.", name));
    }
    if (d.value is null) {
        error(identifier.location, format("identifier '%s' has no value.", name));
    }
    return d.value;
}
