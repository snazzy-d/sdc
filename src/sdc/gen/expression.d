/**
 * Copyright 2010-2011 Bernard Helyer.
 * Copyright 2010 Jakob Ovrum.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.expression;

import std.conv;
import std.exception;
import std.string;
import std.stdio;

import llvm.c.Core;

import sdc.global;
import sdc.source;
import sdc.util;
import sdc.lexer;
import sdc.location;
import sdc.extract;
import sdc.compilererror;
import ast = sdc.ast.all;
import sdc.gen.sdcclass;
import sdc.gen.sdcmodule;
import sdc.gen.sdctemplate;
import sdc.gen.type;
import sdc.gen.value;
import sdc.parser.expression;


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
    rhs = implicitCast(rhs.location, rhs, lhs.type);
    switch (expression.assignType) with (ast.AssignType) {
    case None:
        assert(false);
    case Normal:
        lhs.set(expression.location, rhs);
        break;
    case AddAssign:
        lhs.set(expression.location, lhs.add(expression.location, rhs));
        break;
    case SubAssign:
        lhs.set(expression.location, lhs.sub(expression.location, rhs));
        break;
    case MulAssign:
        lhs.set(expression.location, lhs.mul(expression.location, rhs));
        break;
    case DivAssign:
        lhs.set(expression.location, lhs.div(expression.location, rhs));
        break;
    case ModAssign:
        throw new CompilerPanic(expression.location, "modulo assign is unimplemented.");
    case AndAssign:
        throw new CompilerPanic(expression.location, "and assign is unimplemented.");
    case OrAssign:
        throw new CompilerPanic(expression.location, "or assign is unimplemented.");
    case XorAssign:
        throw new CompilerPanic(expression.location, "xor assign is unimplemented.");
    case CatAssign:
        throw new CompilerPanic(expression.location, "cat assign is unimplemented.");
    case ShiftLeftAssign:
        throw new CompilerPanic(expression.location, "shift left assign is unimplemented.");
    case SignedShiftRightAssign:
        throw new CompilerPanic(expression.location, "signed shift assign is unimplemented.");
    case UnsignedShiftRightAssign:
        throw new CompilerPanic(expression.location, "unsigned shift assign is unimplemented.");
    case PowAssign:
        throw new CompilerPanic(expression.location, "pow assign is unimplemented.");
    default:
        throw new CompilerPanic(expression.location, "unimplemented assign expression type.");
    }
    return rhs;
}

Value genConditionalExpression(ast.ConditionalExpression expression, Module mod)
{
    auto a = genOrOrExpression(expression.orOrExpression, mod);
    if (expression.expression !is null) {
        auto e = genExpression(expression.expression, mod.dup);
        auto v = e.type.getValue(mod, expression.location);
        
        auto condTrueBB  = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.llvmValue, "condTrue");
        auto condFalseBB = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.llvmValue, "condFalse");
        auto condEndBB   = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.llvmValue, "condEnd");
        LLVMBuildCondBr(mod.builder, a.performCast(expression.location, new BoolType(mod)).get(), condTrueBB, condFalseBB);
        LLVMPositionBuilderAtEnd(mod.builder, condTrueBB);
        v.initialise(expression.location, genExpression(expression.expression, mod));
        LLVMBuildBr(mod.builder, condEndBB);
        LLVMPositionBuilderAtEnd(mod.builder, condFalseBB);
        v.initialise(expression.location, genConditionalExpression(expression.conditionalExpression, mod));
        LLVMBuildBr(mod.builder, condEndBB);
        LLVMPositionBuilderAtEnd(mod.builder, condEndBB);
        
        a = v;
    }
    return a;
}

Value genOrOrExpression(ast.OrOrExpression expression, Module mod)
{
    Value val;
    if (expression.orOrExpression !is null) {
        auto lhs = genOrOrExpression(expression.orOrExpression, mod);
        val = genAndAndExpression(expression.andAndExpression, mod);
        val = val.logicalOr(expression.location, lhs);
    } else {
        val = genAndAndExpression(expression.andAndExpression, mod);
    }
    return val;
}

Value genAndAndExpression(ast.AndAndExpression expression, Module mod)
{
    Value val;
    if (expression.andAndExpression !is null) {
        auto lhs = genAndAndExpression(expression.andAndExpression, mod);
        val = genOrExpression(expression.orExpression, mod);
        val = val.logicalAnd(expression.location, lhs);
    } else {
        val = genOrExpression(expression.orExpression, mod);
    }
    return val;
}

Value genOrExpression(ast.OrExpression expression, Module mod)
{
    Value val;
    if (expression.orExpression !is null) {
        auto lhs = genOrExpression(expression.orExpression, mod);
        val = genXorExpression(expression.xorExpression, mod);
        binaryOperatorImplicitCast(expression.location, &lhs, &val);
        val = lhs.or(expression.location, val);
    } else {
        val = genXorExpression(expression.xorExpression, mod);
    }
    return val;
}

Value genXorExpression(ast.XorExpression expression, Module mod)
{
    Value val;
    if (expression.xorExpression !is null) {
        auto lhs = genXorExpression(expression.xorExpression, mod);
        val = genAndExpression(expression.andExpression, mod);
        binaryOperatorImplicitCast(expression.location, &lhs, &val);
        val = lhs.xor(expression.location, val);
    } else {
        val = genAndExpression(expression.andExpression, mod);
    }
    return val;
}

Value genAndExpression(ast.AndExpression expression, Module mod)
{
    Value val;
    if (expression.andExpression !is null) {
        auto lhs = genAndExpression(expression.andExpression, mod);
        val = genCmpExpression(expression.cmpExpression, mod);
        binaryOperatorImplicitCast(expression.location, &lhs, &val);
        val = lhs.and(expression.location, val);
    } else {
        val = genCmpExpression(expression.cmpExpression, mod);
    }
    return val;
}

Value genCmpExpression(ast.CmpExpression expression, Module mod)
{
    auto lhs = genShiftExpression(expression.lhShiftExpression, mod);
    switch (expression.comparison) {
    case ast.Comparison.None:
        break;
    case ast.Comparison.Equality:
        auto rhs = genShiftExpression(expression.rhShiftExpression, mod);
        binaryOperatorImplicitCast(expression.location, &lhs, &rhs);
        lhs = lhs.eq(expression.location, rhs);
        break;
    case ast.Comparison.NotEquality:
        auto rhs = genShiftExpression(expression.rhShiftExpression, mod);
        binaryOperatorImplicitCast(expression.location, &lhs, &rhs);
        lhs = lhs.neq(expression.location, rhs);
        break;
    case ast.Comparison.Greater:
        auto rhs = genShiftExpression(expression.rhShiftExpression, mod);
        binaryOperatorImplicitCast(expression.location, &lhs, &rhs);
        lhs = lhs.gt(expression.location, rhs);
        break;
    case ast.Comparison.LessEqual:
        auto rhs = genShiftExpression(expression.rhShiftExpression, mod);
        binaryOperatorImplicitCast(expression.location, &lhs, &rhs);
        lhs = lhs.lte(expression.location, rhs);
        break;
    case ast.Comparison.Less:
        auto rhs = genShiftExpression(expression.rhShiftExpression, mod);
        binaryOperatorImplicitCast(expression.location, &lhs, &rhs);
        lhs = lhs.lt(expression.location, rhs);
        break;
    default:
        throw new CompilerPanic(expression.location, "unhandled comparison expression.");
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
        auto lhs = genMulExpression(expression.mulExpression, mod);
        val = genAddExpression(expression.addExpression, mod);
        binaryOperatorImplicitCast(expression.location, &lhs, &val);
        
        final switch (expression.addOperation) {
        case ast.AddOperation.Add:
            val = lhs.add(expression.location, val);
            break;
        case ast.AddOperation.Subtract:
            val = lhs.sub(expression.location, val);
            break;
        case ast.AddOperation.Concat:
            throw new CompilerPanic(expression.location, "unimplemented add operation.");
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
        auto lhs = genPowExpression(expression.powExpression, mod);
        val = genMulExpression(expression.mulExpression, mod);
        binaryOperatorImplicitCast(expression.location, &lhs, &val);
        
        final switch (expression.mulOperation) {
        case ast.MulOperation.Mul:
            val = lhs.mul(expression.location, val);
            break;
        case ast.MulOperation.Div:
            val = lhs.div(expression.location, val);
            break;
        case ast.MulOperation.Mod:
            throw new CompilerPanic(expression.location, "unimplemented mul operation.");
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
        val.set(expression.location, val.dec(expression.location));
        break;
    case ast.UnaryPrefix.PrefixInc:
        val = genUnaryExpression(expression.unaryExpression, mod);
        val.set(expression.location, val.inc(expression.location));
        break;
    case ast.UnaryPrefix.Cast:
        val = genUnaryExpression(expression.castExpression.unaryExpression, mod);
        val = val.performCast(expression.location, astTypeToBackendType(expression.castExpression.type, mod, OnFailure.DieWithError));
        break;
    case ast.UnaryPrefix.UnaryMinus:
        val = genUnaryExpression(expression.unaryExpression, mod);
        auto zero = new IntValue(mod, expression.location, 0);
        binaryOperatorImplicitCast(expression.location, &zero, &val);
        val = zero.sub(expression.location, val);
        break;
    case ast.UnaryPrefix.UnaryPlus:
        val = genUnaryExpression(expression.unaryExpression, mod);
        break;
    case ast.UnaryPrefix.AddressOf:
        val = genUnaryExpression(expression.unaryExpression, mod);
        val = val.addressOf(expression.location);
        break;
    case ast.UnaryPrefix.Dereference:
        val = genUnaryExpression(expression.unaryExpression, mod);
        val = val.dereference(expression.location);
        break;
    case ast.UnaryPrefix.New:
        val = genNewExpression(expression.newExpression, mod);
        break;
    case ast.UnaryPrefix.LogicalNot:
    case ast.UnaryPrefix.BitwiseNot:
        throw new CompilerPanic(expression.location, "unimplemented unary expression.");
    case ast.UnaryPrefix.None:
        val = genPostfixExpression(expression.postfixExpression, mod);
        break;
    }
    return val;
}

Value genNewExpression(ast.NewExpression expression, Module mod)
{
    auto type = astTypeToBackendType(expression.type, mod, OnFailure.DieWithError);    
    if (type.dtype == DType.Class) {
        auto asClass = enforce(cast(ClassType) type);
        return newClass(mod, expression.location, asClass, expression.argumentList);
    }
    auto loc  = expression.type.location - expression.location;
    auto size = type.getValue(mod, loc).getSizeof(loc);
    return mod.gcAlloc(loc, size).performCast(loc, new PointerType(mod, type));
}

Value genPostfixExpression(ast.PostfixExpression expression, Module mod, Value suppressPrimary = null)
{
    Value lhs = suppressPrimary;
        
    final switch (expression.type) {
    case ast.PostfixType.Primary:
        auto asPrimary = enforce(cast(ast.PrimaryExpression) expression.firstNode);
        lhs = genPrimaryExpression(asPrimary, mod);
        if (expression.postfixExpression !is null) lhs = genPostfixExpression(expression.postfixExpression, mod, lhs);
        break;
    case ast.PostfixType.PostfixInc:
        auto val = lhs;
        auto tmp = lhs.type.getValue(mod, lhs.location);
        tmp.initialise(expression.location, lhs);
        lhs = tmp;
        val.set(expression.location, val.inc(expression.location));
        if (expression.postfixExpression !is null) lhs = genPostfixExpression(expression.postfixExpression, mod, lhs);
        break;
    case ast.PostfixType.PostfixDec:
        auto val = lhs;
        auto tmp = lhs.type.getValue(mod, lhs.location);
        tmp.initialise(expression.location, lhs);
        lhs = tmp;
        val.set(expression.location, val.dec(expression.location));
        if (expression.postfixExpression !is null) lhs = genPostfixExpression(expression.postfixExpression, mod, lhs);
        break;
    case ast.PostfixType.Parens:
        Value[] args;
        Location[] argLocations;
        auto argList = cast(ast.ArgumentList) expression.firstNode;
        assert(argList);
        foreach (expr; argList.expressions) {
            auto oldAggregate = mod.callingAggregate;
            mod.callingAggregate = null;
            args ~= genAssignExpression(expr, mod);
            argLocations ~= expr.location;
            mod.callingAggregate = oldAggregate;
        }
        if (mod.callingAggregate !is null && mod.callingAggregate.type.dtype == DType.Struct) {
            auto p = new PointerValue(mod, expression.location, mod.callingAggregate.type);
            p.initialise(expression.location, mod.callingAggregate.addressOf(expression.location));
            args ~= p;
        } else if (mod.callingAggregate !is null) {
            args ~= mod.callingAggregate;
        }
        
        lhs = lhs.call(argList.location, argLocations, args);

        if (expression.postfixExpression !is null) lhs = genPostfixExpression(expression.postfixExpression, mod, lhs);
        break;
    case ast.PostfixType.Index:
        Value[] args;
        foreach (expr; (cast(ast.ArgumentList) expression.firstNode).expressions) {
            args ~= genAssignExpression(expr, mod);
        }
        if (args.length == 0 || args.length > 1) {
            throw new CompilerPanic(expression.location, "slice argument lists must contain only one argument.");
        }
        lhs = lhs.index(lhs.location, args[0]);
        if (expression.postfixExpression !is null) lhs = genPostfixExpression(expression.postfixExpression, mod, lhs);
        break;
    case ast.PostfixType.Dot:
        auto qname = enforce(cast(ast.QualifiedName) expression.firstNode);
        mod.base = lhs;
        foreach (identifier; qname.identifiers) {
            if (mod.base.type.dtype == DType.Struct || mod.base.type.dtype == DType.Class) {
                mod.callingAggregate = mod.base;
            }
            mod.base = genIdentifier(identifier, mod);
        }
        lhs = mod.base;
        if (expression.postfixExpression !is null) lhs = genPostfixExpression(expression.postfixExpression, mod, lhs);
        mod.callingAggregate = null;
        mod.base = null;
        break;
    case ast.PostfixType.Slice:
        throw new CompilerPanic(expression.location, "unimplemented postfix expression type.");
        assert(false);
    }
    return lhs;
}

Value genPrimaryExpression(ast.PrimaryExpression expression, Module mod)
{
    switch (expression.type) {
    case ast.PrimaryType.IntegerLiteral:
        return new IntValue(mod, expression.location, extractIntegerLiteral(cast(ast.IntegerLiteral) expression.node));
    case ast.PrimaryType.FloatLiteral:
        return new DoubleValue(mod, expression.location, extractFloatLiteral(cast(ast.FloatLiteral) expression.node));
    case ast.PrimaryType.True:
        return new BoolValue(mod, expression.location, true);
    case ast.PrimaryType.False:
        return new BoolValue(mod, expression.location, false);
    case ast.PrimaryType.CharacterLiteral: 
        return new CharValue(mod, expression.location, cast(char)extractCharacterLiteral(cast(ast.CharacterLiteral) expression.node));
    case ast.PrimaryType.StringLiteral:
        return new StringValue(mod, expression.location, extractStringLiteral(cast(ast.StringLiteral) expression.node));
    case ast.PrimaryType.Identifier:
        return genIdentifier(cast(ast.Identifier) expression.node, mod);
    case ast.PrimaryType.ParenExpression:
        return genExpression(cast(ast.Expression) expression.node, mod);
    case ast.PrimaryType.This:
        auto i = new ast.Identifier();
        i.location = expression.location;
        i.value = "this";
        return genIdentifier(i, mod);
    case ast.PrimaryType.Null:
        return new NullPointerValue(mod, expression.location);
    case ast.PrimaryType.BasicTypeDotIdentifier:
        auto v = primitiveTypeToBackendType(cast(ast.PrimitiveType) expression.node, mod).getValue(mod, expression.location);
        return v.getMember(expression.location, extractIdentifier(cast(ast.Identifier) expression.secondNode));
    case ast.PrimaryType.MixinExpression:
        auto v = genAssignExpression(enforce(cast(ast.AssignExpression) expression.node), mod);
        if (!v.isKnown || !isString(v.type)) {
            throw new CompilerError(expression.node.location, "a mixin expression must be a string known at compile time.");
        }
        auto source = new Source(v.knownString, v.location);
        auto tstream = lex(source);
        tstream.getToken();  // Skip BEGIN 
        auto expr = parseAssignExpression(tstream);
        return genAssignExpression(expr, mod);
    case ast.PrimaryType.TemplateInstance:
        return genTemplateInstance(cast(ast.TemplateInstance) expression.node, mod);
    default:
        throw new CompilerPanic(expression.location, "unhandled primary expression type.");
    }
}

Value genIdentifier(ast.Identifier identifier, Module mod)
{
    auto name = extractIdentifier(identifier);
    void failure() 
    { 
        throw new CompilerError(identifier.location, format("unknown identifier '%s'.", name));
    }
    
    
    Value implicitBase;
    if (mod.base !is null) {
        return mod.base.getMember(identifier.location, name);
    } else {
        auto s = mod.search("this");
        if (s !is null) {
            if (s.storeType != StoreType.Value) {
                throw new CompilerPanic(identifier.location, "this reference not a value.");
            }
            implicitBase = s.value;
        }
    }  
    auto store = mod.search(name);

    if (store is null) {
        if (implicitBase !is null) {
            store = new Store(implicitBase.getMember(identifier.location, name));
        }
        if (store is null) {
            failure();
        }
    }
    
 
    if (store.storeType == StoreType.Value) {
        return store.value();
    } else if (store.storeType == StoreType.Scope) {
        return new ScopeValue(mod, identifier.location, store.getScope());
    } else if (store.storeType == StoreType.Type) {
        return store.type().getValue(mod, identifier.location);
    } else if (store.storeType == StoreType.Function) {
        auto fn = store.getFunction();
        auto wrapper = new FunctionWrapperValue(mod, identifier.location, fn.type);
        wrapper.mValue = fn.llvmValue;
        return wrapper;
    } else {
        assert(false, "unhandled StoreType.");
    }
}
