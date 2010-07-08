/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.expression;

import std.stdio;
import std.string;

import sdc.util;
import sdc.compilererror;
import sdc.ast.all;
import sdc.extract.base;
import sdc.extract.expression;
import sdc.gen.base;
import sdc.gen.semantic;
import sdc.gen.type;
import sdc.gen.primitive;

enum VoidExpression
{
    Permitted,
    Forbidden
}

Variable genExpression(Expression expression, File file, Semantic semantic)
{
    auto var = genAssignExpression(expression.assignExpression, file, semantic);
    /+if (var is voidVariable) {
        error(expression.location, "void expression has no value");
    }+/
    return var;
}

Variable genAssignExpression(AssignExpression expression, File file, Semantic semantic)
{
    auto lvalue = genConditionalExpression(expression.conditionalExpression, file, semantic);
    
    switch (expression.assignType) {
    case AssignType.Normal:
        auto rvalue = genAssignExpression(expression.assignExpression, file, semantic);
        auto rvar = genVariable(removePointer(rvalue.primitive), "rvalue");
        asmgen.emitLoad(file, rvar, rvalue);
        asmgen.emitStore(file, lvalue, rvar);
        break;
    case AssignType.None:
    default:
        break;
    }
    
    return lvalue;
}

Variable genConditionalExpression(ConditionalExpression expression, File file, Semantic semantic)
{
    return genOrOrExpression(expression.orOrExpression, file, semantic);
}

Variable genOrOrExpression(OrOrExpression expression, File file, Semantic semantic)
{
    return genAndAndExpression(expression.andAndExpression, file, semantic);
}

Variable genAndAndExpression(AndAndExpression expression, File file, Semantic semantic)
{
    return genOrExpression(expression.orExpression, file, semantic);
}

Variable genOrExpression(OrExpression expression, File file, Semantic semantic)
{
    return genXorExpression(expression.xorExpression, file, semantic);
}

Variable genXorExpression(XorExpression expression, File file, Semantic semantic)
{
    return genAndExpression(expression.andExpression, file, semantic);
}

Variable genAndExpression(AndExpression expression, File file, Semantic semantic)
{
    return genCmpExpression(expression.cmpExpression, file, semantic);
}

Variable genCmpExpression(CmpExpression expression, File file, Semantic semantic)
{
    auto var = genShiftExpression(expression.lhShiftExpression, file, semantic);
    switch (expression.comparison) {
    case Comparison.Equality:
        auto rhs = genShiftExpression(expression.rhShiftExpression, file, semantic);
        var = asmgen.emitIcmpEqOps(file, var, rhs);
        break;
    case Comparison.NotEquality:
        auto rhs = genShiftExpression(expression.rhShiftExpression, file, semantic);
        var = asmgen.emitIcmpNeOps(file, var, rhs);
        break;
    default:
        break;
    }
    
    return var;
}

Variable genShiftExpression(ShiftExpression expression, File file, Semantic semantic)
{
    return genAddExpression(expression.addExpression, file, semantic);
}

Variable genAddExpression(AddExpression expression, File file, Semantic semantic)
{
    auto var = genMulExpression(expression.mulExpression, file, semantic);
    if (expression.addExpression !is null) {
        auto var2 = genAddExpression(expression.addExpression, file, semantic);
        
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

Variable genMulExpression(MulExpression expression, File file, Semantic semantic)
{
    auto var = genPowExpression(expression.powExpression, file, semantic);
    if (expression.mulExpression !is null) {
        auto var2 = genMulExpression(expression.mulExpression, file, semantic);
        
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

Variable genPowExpression(PowExpression expression, File file, Semantic semantic)
{
    return genUnaryExpression(expression.unaryExpression, file, semantic);
}

Variable genUnaryExpression(UnaryExpression expression, File file, Semantic semantic)
{
    if (expression.unaryPrefix != UnaryPrefix.None) {
        auto var = genUnaryExpression(expression.unaryExpression, file, semantic);
        if (expression.unaryPrefix == UnaryPrefix.UnaryMinus) {
            var = asmgen.emitNeg(file, var);
        }
        return var;
    }
    return genPostfixExpression(expression.postfixExpression, file, semantic);
}

Variable genPostfixExpression(PostfixExpression expression, File file, Semantic semantic)
{
    auto var = genPrimaryExpression(expression.primaryExpression, file, semantic);
    
    if (expression.postfixOperation == PostfixOperation.Parens || var.isFunction) {
        Variable[] args;
        if (expression.argumentList !is null) foreach (argument; expression.argumentList.expressions) {
            args ~= genAssignExpression(argument, file, semantic);
        }
        return asmgen.emitFunctionCall(file, var, args);
    }
    
    return var;
}

Variable genPrimaryExpression(PrimaryExpression expression, File file, Semantic semantic)
{
    Variable var;
    
    bool globalLookup = false;
    switch (expression.type) {
    case PrimaryType.GlobalIdentifier:
        globalLookup = true;
        // Fallthrough.
    case PrimaryType.Identifier:
        return genIdentifierExpression(cast(Identifier) expression.node, file, semantic, globalLookup);
    case PrimaryType.IntegerLiteral:
        var = genVariable(Primitive(32, 0), "primitive");
        var.dtype = new IntType();
        asmgen.emitAlloca(file, var);
        asmgen.emitStore(file, var, new Constant((cast(IntegerLiteral)expression.node).value, Primitive(32, 0)));
        break;
    case PrimaryType.True:
        var = genVariable(Primitive(8, 0), "true");
        var.dtype = new BoolType();
        asmgen.emitAlloca(file, var);
        asmgen.emitStore(file, var, new Constant("1", Primitive(8, 0)));
        break;
    case PrimaryType.False:
        var = genVariable(Primitive(8, 0), "false");
        var.dtype = new BoolType();
        asmgen.emitAlloca(file, var);
        asmgen.emitStore(file, var, new Constant("0", Primitive(8, 0)));
        break;
    default:
        break;
    }
    
    return var;
}


Variable genIdentifierExpression(Identifier identifier, File file, Semantic semantic, bool globalLookup = false)
{
        string ident = extractIdentifier(identifier);
        auto decl = semantic.findDeclaration(ident, globalLookup);
        if (decl is null) {
            error(identifier.location, format("undefined identifier '%s'", ident));
        }
        
        Variable var;
        switch (decl.dectype) {
        case DeclType.SyntheticVariable:
            auto syn = cast(SyntheticVariableDeclaration) decl;
            var = genVariable(Primitive(32, 0), extractIdentifier(syn.identifier));  // !!!
            var.dtype = new IntType();  // !!!
            if (syn.isParameter) {
                asmgen.emitAlloca(file, var);
                asmgen.emitStore(file, var, new Variable(extractIdentifier(syn.identifier), Primitive(32, 0)));  // !!!
            } else {
                return syn.variable;
                //return new Variable(extractIdentifier(syn.identifier), addPointer(fullTypeToPrimitive(syn.type)));
            }
            break;
        case DeclType.Function:
            auto fun = cast(FunctionDeclaration) decl;
            auto prim = Primitive(32, 0);  // !!!
            auto name = extractIdentifier(fun.name);
            var = new Variable(name, prim);
            var.isFunction = true;
            break;
        default:
            error(identifier.location, "unknown declaration type");
        }
        
        return var;
}

