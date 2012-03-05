/**
 * Copyright 2010-2011 Bernard Helyer.
 * Copyright 2010-2011 Jakob Ovrum.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.expression;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.string;
import std.stdio;

import llvm.c.Core;

import sdc.aglobal;
import sdc.util;
import sdc.lexer;
import sdc.location;
import sdc.extract;
import sdc.compilererror;
import ast = sdc.ast.all;
import sdc.gen.sdcclass;
import sdc.gen.sdcmodule;
import sdc.gen.sdctemplate;
import sdc.gen.sdcfunction;
import sdc.gen.type;
import sdc.gen.value;
import sdc.parser.expression;


Value genExpression(ast.Expression expression, Module mod)
{
    auto v = genConditionalExpression(expression.conditionalExpression, mod);
    if (expression.expression !is null) {
        v = genExpression(expression.expression, mod);
    }
    return v;
}

private bool isPointerArithmetic(Value lhs, Value rhs, ast.BinaryOperation operation)
{
    return (operation == ast.BinaryOperation.AddAssign ||
        operation == ast.BinaryOperation.SubAssign) &&
        lhs.type.dtype == DType.Pointer &&
        isIntegerDType(rhs.type.dtype);
}

Value genConditionalExpression(ast.ConditionalExpression expression, Module mod)
{
    auto a = genBinaryExpression(expression.binaryExpression, mod);
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

Value performOperation(T)(Module mod, Location location, ast.BinaryOperation operation, T lhsex, T rhsex)
{
    if (operation == ast.BinaryOperation.LogicalAnd || operation == ast.BinaryOperation.LogicalOr) {
        return performLogical(mod, location, operation, lhsex, rhsex);
    }
    Value lhs = lhsex.gen(mod), rhs = rhsex.gen(mod);
    
    void integralPromotion(ref Value v)
    {
        if (isIntegerDType(v.type.dtype) && v.type.dtype < DType.Int) {
            v = v.performCast(location, new IntType(mod));
        }
    }
    if (ast.undergoesIntegralPromotion(operation)) {
        integralPromotion(lhs);
        integralPromotion(rhs);
    }
      
    Value result = lhs;
    if (operation == ast.BinaryOperation.Assign) {
        if (!isPointerArithmetic(lhs, rhs, operation)) {
            rhs = implicitCast(rhs.location, rhs, lhs.type);
        }
    } else if (operation != ast.BinaryOperation.None) {
        binaryOperatorImplicitCast(location, &lhs, &rhs);
    }
    final switch (operation) with (ast.BinaryOperation) {
    case None:
        break;
    case Assign:
        lhs.set(location, rhs);
        break;
    case AddAssign:
        lhs.initialise(location, lhs.add(location, rhs));
        break;
    case SubAssign:
        lhs.initialise(location, lhs.sub(location, rhs));
        break;
    case MulAssign:
        lhs.initialise(location, lhs.mul(location, rhs));
        break;
    case DivAssign:
        lhs.initialise(location, lhs.div(location, rhs));
        break;
    case ModAssign:
        lhs.initialise(location, lhs.mod(location, rhs));
        break;
    case AndAssign:
        lhs.initialise(location, lhs.and(location, rhs));
        break;
    case OrAssign:
        lhs.initialise(location, lhs.or(location, rhs));
        break;
    case XorAssign:
        lhs.initialise(location, lhs.xor(location, rhs));
        break;
    case CatAssign:
    case ShiftLeftAssign:
    case SignedShiftRightAssign:
    case UnsignedShiftRightAssign:
    case PowAssign:
        throw new CompilerPanic(location, "unimplemented short hand assign operator.");
    case LogicalOr:
        result = lhs.logicalOr(location, rhs);
        break;
    case LogicalAnd:
        result = lhs.logicalAnd(location, rhs);
        break;
    case BitwiseOr:
        result = lhs.or(location, rhs);
        break;
    case BitwiseXor:
        result = lhs.xor(location, rhs);
        break;
    case BitwiseAnd:
        result = lhs.and(location, rhs);
        break;
    case Equality:
        result = lhs.eq(location, rhs);
        break;
    case NotEquality:
        result = lhs.neq(location, rhs);
        break;
    case Is:
    case NotIs:
        throw new CompilerPanic(location, "is operator is unimplemented.");
    case In:
    case NotIn:
        throw new CompilerPanic(location, "in operator is unimplemented.");
    case Less:
        result = lhs.lt(location, rhs);
        break;
    case LessEqual:
        result = lhs.lte(location, rhs);
        break;
    case Greater:
        result = lhs.gt(location, rhs);
        break;
    case GreaterEqual:
    case Unordered:
    case UnorderedEqual:
    case LessGreater:
    case LessEqualGreater:
    case UnorderedLessEqual:
    case UnorderedLess:
    case UnorderedGreaterEqual:
    case UnorderedGreater:
        throw new CompilerPanic(location, "unimplemented comparison operator.");
    case LeftShift:
    case SignedRightShift:
    case UnsignedRightShift:
        throw new CompilerPanic(location, "shifts are unimplemented.");
    case Addition:
        result = lhs.add(location, rhs);
        break;
    case Subtraction:
        result = lhs.sub(location, rhs);
        break;
    case Concat:
        throw new CompilerPanic(location, "concat is unimplemented.");
    case Division:
        result = lhs.div(location, rhs);
        break;
    case Multiplication:
        result = lhs.mul(location, rhs);
        break;
    case Modulus:
        result = lhs.mod(location, rhs);
        break;
    case Pow:
        throw new CompilerPanic(location, "pow is unimplemented.");
    }
    return result;
}

Value performLogical(T)(Module mod, Location location, ast.BinaryOperation operation, T lhsex, T rhsex)
in
{
    assert(operation == ast.BinaryOperation.LogicalAnd || operation == ast.BinaryOperation.LogicalOr);
}
body
{
    auto lhs = lhsex.gen(mod);
    if (operation == ast.BinaryOperation.LogicalOr) {
        // If the lhs is true, don't evaluate the rhs.
        auto asBool = lhs.performCast(location, new BoolType(mod)).get();
        auto or   = LLVMAppendBasicBlock(mod.currentFunction.llvmValue, "or");
        auto exit = LLVMAppendBasicBlock(mod.currentFunction.llvmValue, "orexit");
        
        LLVMBuildCondBr(mod.builder, asBool, exit, or);
        LLVMPositionBuilderAtEnd(mod.builder, or);
        lhs.logicalOr(location, rhsex.gen(mod));
        LLVMBuildBr(mod.builder, exit);
        LLVMPositionBuilderAtEnd(mod.builder, exit);
    } else {
        // If the lhs is false, don't evaluate the rhs.
        auto asBool = lhs.performCast(location, new BoolType(mod)).get();
        auto and  = LLVMAppendBasicBlock(mod.currentFunction.llvmValue, "and");
        auto exit = LLVMAppendBasicBlock(mod.currentFunction.llvmValue, "andexit");
        
        LLVMBuildCondBr(mod.builder, asBool, and, exit);
        LLVMPositionBuilderAtEnd(mod.builder, and);
        lhs.logicalAnd(location, rhsex.gen(mod));
        LLVMBuildBr(mod.builder, exit);
        LLVMPositionBuilderAtEnd(mod.builder, exit);
    }
    return lhs;
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
        binaryOperatorImplicitCast(expression.location, cast(Value*) &zero, &val);
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
        val = genUnaryExpression(expression.unaryExpression, mod);
        val = val.logicalNot(expression.location);
        break;
    case ast.UnaryPrefix.BitwiseNot:
        val = genUnaryExpression(expression.unaryExpression, mod);
        val = val.not(expression.location);
        break;
    case ast.UnaryPrefix.None:
        val = genPostfixExpression(expression.postfixExpression, mod);
        break;
    }
    return val;
}

alias BinaryExpressionProcessor!(Value, Module, genUnaryExpression, performOperation) processor;
alias processor.genBinaryExpression genBinaryExpression;

Value genNewExpression(ast.NewExpression expression, Module mod)
{
    auto type = astTypeToBackendType(expression.type, mod, OnFailure.DieWithError); 
    if (type.dtype == DType.Class) {
        auto asClass = enforce(cast(ClassType) type);
        return newClass(mod, expression.location, asClass, expression.argumentList);
    }
    auto loc  = expression.type.location - expression.location;
    if (expression.conditionalExpression is null) {
        auto size = type.getValue(mod, loc).getSizeof(loc);
        return mod.gcAlloc(loc, size).performCast(loc, new PointerType(mod, type));
    } else {
        auto length = genConditionalExpression(expression.conditionalExpression, mod).performCast(loc, getSizeT(mod));
        auto size = type.getValue(mod, loc).getSizeof(loc).mul(loc, length);
        auto array = new ArrayValue(mod, loc, type);
        auto ptr = mod.gcAlloc(loc, size).performCast(loc, new PointerType(mod, type));
        array.suppressCallbacks = true;
        array.getMember(loc, "length").initialise(loc, length);
        array.getMember(loc, "ptr").initialise(loc, ptr);
        array.suppressCallbacks = false;
        return array;
    }
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
        
        FunctionType functionType;
        if (lhs.type.dtype == DType.Function) {
            functionType = enforce(cast(FunctionType) lhs.type);
        } else if (lhs.type.getBase().dtype == DType.Function) {
            functionType = enforce(cast(FunctionType) lhs.type.getBase());
        } else {
            throw new CompilerError(expression.location, format("cannot call value of type '%s'", lhs.type.name()));
        }
        
        foreach (i, expr; argList.expressions) {
            if (!functionType.varargs && i < functionType.parameterTypes.length) {
                auto parameter = functionType.parameterTypes[i];
                Value[] values;
                if (parameter.dtype == DType.Pointer && parameter.getBase().dtype == DType.Function) {
                    auto asFunction = enforce(cast(FunctionType) parameter.getBase());
                    values = array(map!((Type t){ return t.getValue(mod, expression.location); })(asFunction.parameterTypes));
                    mod.functionPointerArguments = &values;
                }
            }
            
            auto oldAggregate = mod.callingAggregate;
            mod.callingAggregate = null;       
            args ~= genConditionalExpression(expr, mod);
            argLocations ~= expr.location;
            mod.callingAggregate = oldAggregate;
            
            mod.functionPointerArguments = null;
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
            args ~= genConditionalExpression(expr, mod);
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
        auto from = genConditionalExpression(cast(ast.ConditionalExpression)expression.firstNode, mod);
        auto to = genConditionalExpression(cast(ast.ConditionalExpression)expression.secondNode, mod);
        lhs = lhs.slice(expression.location, from, to);
        if (expression.postfixExpression !is null) lhs = genPostfixExpression(expression.postfixExpression, mod, lhs);
        break;
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
        auto name = extractIdentifier(cast(ast.Identifier) expression.secondNode);
        auto member = v.getMember(expression.location, name);
        if (member is null) {
            throw new CompilerError(expression.location, format("type '%s' has no member '%s'.", v.type.name(), name));
        }
        return member;
    case ast.PrimaryType.MixinExpression:
        auto v = genConditionalExpression(enforce(cast(ast.ConditionalExpression) expression.node), mod);
        if (!v.isKnown || !isString(v.type)) {
            throw new CompilerError(expression.node.location, "a mixin expression must be a string known at compile time.");
        }

        auto tstream = lex(v.knownString, v.location);
        tstream.get();  // Skip BEGIN 

        auto expr = parseConditionalExpression(tstream);
        return genConditionalExpression(expr, mod);
    case ast.PrimaryType.AssertExpression:
        return genAssertExpression(cast(ast.AssertExpression) expression.node, mod);
    case ast.PrimaryType.TemplateInstance:
        return genTemplateInstance(cast(ast.TemplateInstance) expression.node, mod);
    case ast.PrimaryType.ComplexTypeDotIdentifier:
        return genComplexTypeDotIdentifier(expression, mod);
    default:
        throw new CompilerPanic(expression.location, format("unhandled primary expression type: '%s'", to!string(expression.type)));
    }
}

Value genComplexTypeDotIdentifier(ast.PrimaryExpression expression, Module mod)
{
    auto typeval  = astTypeToBackendType(cast(ast.Type) expression.node, mod, OnFailure.DieWithError).getValue(mod, expression.location);
    auto property = extractIdentifier(cast(ast.Identifier) expression.secondNode);
    return typeval.getProperty(expression.location, property);
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
        auto member = mod.base.getMember(identifier.location, name);
        if (member is null) {
            throw new CompilerError(identifier.location, format("type '%s' has no member '%s'.", mod.base.type.name,  name));
        }
        return member;
    } else {
        auto s = mod.search("this");
        if (s !is null) {
            if (s.storeType != StoreType.Value) {
                throw new CompilerPanic(identifier.location, "this reference not a value.");
            }
            implicitBase = s.value;
        }
    }
    
    Store store;
    if (implicitBase !is null) {
        auto member = implicitBase.getMember(identifier.location, name);
        if (member !is null) {
            store = new Store(member);
        }
    }
    
    if (store is null) {
        store = mod.search(name);
    }  
    
    if (store is null) {
        failure();
    }
 
    if (store.storeType == StoreType.Value) {
        return store.value();
    } else if (store.storeType == StoreType.Scope) {
        return new ScopeValue(mod, identifier.location, store.getScope());
    } else if (store.storeType == StoreType.Type) {
        return store.type().getValue(mod, identifier.location);
    } else if (store.storeType == StoreType.Function) {
        auto functions = store.getFunctions();
        return new Functions(mod, identifier.location, functions);
    } else {
        assert(false, "unhandled StoreType.");
    }
}

Value genAssertExpression(ast.AssertExpression assertExpr, Module mod)
{
    auto condition = genConditionalExpression(assertExpr.condition, mod);
    Value message;
    if (assertExpr.message !is null) {
        message = genConditionalExpression(assertExpr.message, mod);
    }
    
    mod.rtAssert(assertExpr.location, condition, message);
    return new VoidValue(mod, assertExpr.location);
}
