/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.expression;

import std.stdio;

import sdc.primitive;
import sdc.compilererror;
import sdc.ast.all;
import sdc.extract.base;
import sdc.extract.expression;
import sdc.gen.base;

Variable genExpression(Expression expression, File file)
{
    return genAssignExpression(expression.assignExpression, file);
}

Variable genAssignExpression(AssignExpression expression, File file)
{
    return genConditionalExpression(expression.conditionalExpression, file);
}

Variable genConditionalExpression(ConditionalExpression expression, File file)
{
    return genOrOrExpression(expression.orOrExpression, file);
}

Variable genOrOrExpression(OrOrExpression expression, File file)
{
    return genAndAndExpression(expression.andAndExpression, file);
}

Variable genAndAndExpression(AndAndExpression expression, File file)
{
    return genOrExpression(expression.orExpression, file);
}

Variable genOrExpression(OrExpression expression, File file)
{
    return genXorExpression(expression.xorExpression, file);
}

Variable genXorExpression(XorExpression expression, File file)
{
    return genAndExpression(expression.andExpression, file);
}

Variable genAndExpression(AndExpression expression, File file)
{
    return genCmpExpression(expression.cmpExpression, file);
}

Variable genCmpExpression(CmpExpression expression, File file)
{
    return genShiftExpression(expression.lhShiftExpression, file);
}

Variable genShiftExpression(ShiftExpression expression, File file)
{
    return genAddExpression(expression.addExpression, file);
}

Variable genAddExpression(AddExpression expression, File file)
{
    auto var = genMulExpression(expression.mulExpression, file);
    if (expression.addExpression !is null) {
        auto var2 = genAddExpression(expression.addExpression, file);
        
        Variable result;
        if (expression.addOperation == AddOperation.Add) {
            result = asmgen.emitAddOps(file, var, var2);
        } else {
            result = asmgen.emitSubOps(file, var, var2);
        }
        return result;
    }
    return var;
}

Variable genMulExpression(MulExpression expression, File file)
{
    auto var = genPowExpression(expression.powExpression, file);
    if (expression.mulExpression !is null) {
        auto var2 = genMulExpression(expression.mulExpression, file);
        
        Variable result;
        if (expression.mulOperation == MulOperation.Mul) {
            result = asmgen.emitMulOps(file, var, var2);
        } else {
            result = asmgen.emitDivOps(file, var, var2);
        }
        return result;
    }
    return var;
}

Variable genPowExpression(PowExpression expression, File file)
{
    return genUnaryExpression(expression.unaryExpression, file);
}

Variable genUnaryExpression(UnaryExpression expression, File file)
{
    if (expression.unaryPrefix != UnaryPrefix.None) {
        auto var = genUnaryExpression(expression.unaryExpression, file);
        if (expression.unaryPrefix == UnaryPrefix.UnaryMinus) {
            var = asmgen.emitNeg(file, var);
        }
        return var;
    }
    return genPostfixExpression(expression.postfixExpression, file);
}

Variable genPostfixExpression(PostfixExpression expression, File file)
{
    return genPrimaryExpression(expression.primaryExpression, file);
}

Variable genPrimaryExpression(PrimaryExpression expression, File file)
{
    Variable var;
    Primitive primitive;
    
    switch (expression.type) {
    case PrimaryType.IntegerLiteral:
        var = genVariable(Primitive(32, 0), "primitive");
        var.dType = PrimitiveTypeType.Int;
        asmgen.emitAlloca(file, var);
        asmgen.emitStore(file, var, new Constant((cast(IntegerLiteral)expression.node).value, Primitive(32, 0)));
        break;
    case PrimaryType.True:
        var = genVariable(Primitive(8, 0), "true");
        var.dType = PrimitiveTypeType.Bool;
        asmgen.emitAlloca(file, var);
        asmgen.emitStore(file, var, new Constant("1", Primitive(8, 0)));
        break;
    case PrimaryType.False:
        var = genVariable(Primitive(8, 0), "false");
        var.dType = PrimitiveTypeType.Bool;
        asmgen.emitAlloca(file, var);
        asmgen.emitStore(file, var, new Constant("0", Primitive(8, 0)));
        break;
    default:
        break;
    }
    
    return var;
}
