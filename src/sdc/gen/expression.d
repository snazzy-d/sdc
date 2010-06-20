module sdc.gen.expression;

import std.stdio;

import sdc.compilererror;
import sdc.ast.all;
import sdc.extract.base;
import sdc.extract.expression;
import sdc.gen.base;

string genExpression(Expression expression, File file)
{
    return genAssignExpression(expression.assignExpression, file);
}

string genAssignExpression(AssignExpression expression, File file)
{
    return genConditionalExpression(expression.conditionalExpression, file);
}

string genConditionalExpression(ConditionalExpression expression, File file)
{
    return genOrOrExpression(expression.orOrExpression, file);
}

string genOrOrExpression(OrOrExpression expression, File file)
{
    return genAndAndExpression(expression.andAndExpression, file);
}

string genAndAndExpression(AndAndExpression expression, File file)
{
    return genOrExpression(expression.orExpression, file);
}

string genOrExpression(OrExpression expression, File file)
{
    return genXorExpression(expression.xorExpression, file);
}

string genXorExpression(XorExpression expression, File file)
{
    return genAndExpression(expression.andExpression, file);
}

string genAndExpression(AndExpression expression, File file)
{
    return genCmpExpression(expression.cmpExpression, file);
}

string genCmpExpression(CmpExpression expression, File file)
{
    return genShiftExpression(expression.lhShiftExpression, file);
}

string genShiftExpression(ShiftExpression expression, File file)
{
    return genAddExpression(expression.addExpression, file);
}

string genAddExpression(AddExpression expression, File file)
{
    auto var = genMulExpression(expression.mulExpression, file);
    if (expression.addExpression !is null) {
        auto var2 = genAddExpression(expression.addExpression, file);
        auto tmpresult = genVariable("addtmp");
        auto v = genVariable("op");
        asmgen.emitLoad(file, v, var, null);
        auto v2 = genVariable("op");
        asmgen.emitLoad(file, v2, var2, null);
        
        if (expression.addOperation == AddOperation.Add) {
            asmgen.emitAdd(file, tmpresult, v, v2, null);
        } else if (expression.addOperation == AddOperation.Subtract) {
            asmgen.emitSub(file, tmpresult, v, v2, null);
        }
        
        auto result = genVariable("addresult");
        asmgen.emitAlloca(file, result, null);
        asmgen.emitStoreVariable(file, result, null, tmpresult);
        return result;
    }
    return var;
}

string genMulExpression(MulExpression expression, File file)
{
    auto var = genPowExpression(expression.powExpression, file);
    if (expression.mulExpression !is null) {
        auto var2 = genMulExpression(expression.mulExpression, file);
        auto tmpresult = genVariable("multmp");
        auto v = genVariable("op");
        asmgen.emitLoad(file, v, var, null);
        auto v2 = genVariable("op");
        asmgen.emitLoad(file, v2, var2, null);
        
        if (expression.mulOperation == MulOperation.Mul) {
            asmgen.emitMul(file, tmpresult, v, v2, null);
        } else if (expression.mulOperation == MulOperation.Div) {
            asmgen.emitDiv(file, tmpresult, v, v2, null);
        }
        
        auto result = genVariable("mulresult");
        asmgen.emitAlloca(file, result, null);
        asmgen.emitStoreVariable(file, result, null, tmpresult);
        return result;
    }
    return var;
}

string genPowExpression(PowExpression expression, File file)
{
    return genUnaryExpression(expression.unaryExpression, file);
}

string genUnaryExpression(UnaryExpression expression, File file)
{
    return genPostfixExpression(expression.postfixExpression, file);
}

string genPostfixExpression(PostfixExpression expression, File file)
{
    return genPrimaryExpression(expression.primaryExpression, file);
}

string genPrimaryExpression(PrimaryExpression expression, File file)
{
    auto var = genVariable("primary");
    
    switch (expression.type) {
    case PrimaryType.IntegerLiteral:
        asmgen.emitAlloca(file, var, null);
        asmgen.emitStoreValue(file, var, null, (cast(IntegerLiteral)expression.node).value);
        break;
    default:
        break;
    }
    
    return var;
}
