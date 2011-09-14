/**
 * Copyright 2011 Jakob Ovrum.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.sdcswitch;

import llvm.c.Core;
import std.string;
import ast = sdc.ast.all;
import sdc.compilererror;
import sdc.location;
import sdc.gen.cfg;
import sdc.gen.statement;
import sdc.gen.expression;
import sdc.gen.sdcmodule;
import sdc.gen.type;
import sdc.gen.value;
import sdc.gen.loop; // For BreakTarget.

struct SwitchCase
{
    ast.ConditionalExpression case_;
    LLVMBasicBlockRef target;
}

struct SwitchRangeCase
{
    ast.ConditionalExpression begin, end;
    LLVMBasicBlockRef target;
}

class IllegalFallThroughError : CompilerError
{
    this(ast.SwitchSubStatement statement)
    {
        super(statement.location, "implicit fall-through is illegal, use 'goto case' for explicit fall-through.");
    }
}

struct SwitchDefault
{
    Location location;
    LLVMBasicBlockRef target;
    BasicBlock block;
}

struct PendingGotoCase
{
    Location location;
    LLVMBasicBlockRef insertAt;
    BasicBlock block;
    Value explicitTarget; // Optional.
}

struct Switch
{
    bool isFinal;
    Type type; // Type of control expression.
    BasicBlock switchTop;
    BasicBlock postSwitch;
    LLVMBasicBlockRef postSwitchBB;
    
    SwitchDefault defaultClause;
    SwitchCase[] cases;
    SwitchRangeCase[] ranges;
    PendingGotoCase[] pendingGotoCases; // Dealt with at each clause.
    PendingGotoCase[] pendingTargetedGotoCases; // Dealt with at the end.
    PendingGotoCase[] pendingGotoDefaults; // Dealt with at the end.
    
    bool wasDefault = false; // Bah.
}

private class SwitchBreakTarget : BreakTarget
{
    private:
    LLVMBasicBlockRef breakTarget;
    
    this(BasicBlock postSwitch, LLVMBasicBlockRef postSwitchBB)
    {
        super(postSwitch);    
        this.breakTarget = postSwitchBB;
    }
    
    public override:
    void genBreak(Location location, Module mod)
    {
        LLVMBuildBr(mod.builder, breakTarget);
    }
    
    void genContinue(Location location, Module mod)
    {
        throw new CompilerError(location, "continue statement must be in a loop.");
    }
}

private void consumeFallThroughGotos(ref PendingGotoCase[] gotos, LLVMBasicBlockRef target, BasicBlock targetBlock, Module mod)
{
    auto bb = mod.currentFunction.currentBasicBlock;
    while (gotos.length) {
        auto gotoCase = gotos[$-1];
        LLVMPositionBuilderAtEnd(mod.builder, gotoCase.insertAt);
        LLVMBuildBr(mod.builder, target);
        gotoCase.block.children ~= targetBlock;
        gotos = gotos[0..$-1];
    }
    LLVMPositionBuilderAtEnd(mod.builder, bb);
}

void genSwitchStatement(ast.SwitchStatement statement, Module mod)
{
    if (statement.isFinal) {
        throw new CompilerPanic(statement.location, "final switch is unimplemented.");
    }

    auto controlExpression = genExpression(statement.controlExpression, mod);
    auto switchType = controlExpression.type;
    if (!isString(switchType) && !isIntegerDType(switchType.dtype)) {
        throw new CompilerError(controlExpression.location, format("switch control expression must be of string or integer type, not '%s'.", switchType.name()));
    }
    
    auto topBB = mod.currentFunction.currentBasicBlock;
    auto top = mod.currentFunction.cfgTail;
    
    auto switchBB = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.llvmValue, "switch");
    auto postSwitchBB = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.llvmValue, "postswitch");
    
    auto postSwitch = new BasicBlock("postswitch");
    
    auto switch_ = Switch(statement.isFinal, switchType, top, postSwitch, postSwitchBB);
    
    auto popSwitch = mod.currentSwitch;
    mod.currentSwitch = &switch_;
    
    // Code is allowed in the switch before any case or default clause.
    // TODO: This code should be in its own BasicBlock so that it can be
    // marked unreacable accordingly, but this doesn't work very well atm.
    LLVMPositionBuilderAtEnd(mod.builder, switchBB);
    mod.currentFunction.currentBasicBlock = switchBB;
    
    mod.pushScope();
    mod.pushBreakTarget(new SwitchBreakTarget(postSwitch, postSwitchBB));
    
    genStatement(statement.statement, mod);
    
    mod.popBreakTarget();
    mod.popScope();
    
    if (switch_.defaultClause.target is null) {
        throw new CompilerError(statement.location, "switch must have a default clause.");
    }
    
    if (!switch_.wasDefault) {
        LLVMBuildBr(mod.builder, postSwitchBB);
    }
    
    if (switch_.pendingGotoCases.length > 0) {
        auto msg = "no case statement following goto case.";
        auto error = new CompilerError(switch_.pendingGotoCases[0].location, msg);
        CompilerError next = error;
        foreach (gotoCase; switch_.pendingGotoCases[1..$]) {
            next = next.more = new CompilerError(gotoCase.location, msg);
        }
        throw error;
    }
    
    if (!switch_.isFinal) {
        consumeFallThroughGotos(switch_.pendingGotoDefaults, switch_.defaultClause.target, switch_.defaultClause.block, mod);
    }
    
    if (switch_.pendingTargetedGotoCases.length > 0) {
        throw new CompilerPanic(switch_.pendingTargetedGotoCases[0].location, "targeted goto case is unimplemented.");
    }
    
    LLVMMoveBasicBlockAfter(postSwitchBB, mod.currentFunction.currentBasicBlock);
    
    LLVMPositionBuilderAtEnd(mod.builder, topBB);
    mod.currentFunction.currentBasicBlock = topBB;
    mod.currentFunction.cfgTail = top;
    
    LLVMValueRef[] cases;
    foreach (switchCase; switch_.cases) {
        auto value = genConditionalExpression(switchCase.case_, mod);
        value = implicitCast(value.location, value, switchType);
        if (!value.isKnown) {
            throw new CompilerPanic(value.location, "runtime switch cases are unimplemented.");
        }
        cases ~= value.getConstant();
    }
    
    foreach (range; switch_.ranges) {
        auto begin = genConditionalExpression(range.begin, mod);
        begin = implicitCast(begin.location, begin, switchType);
        if (!begin.isKnown) {
            throw new CompilerPanic(begin.location, "runtime switch cases are unimplemented.");
        }
        
        auto end = genConditionalExpression(range.end, mod);
        end = implicitCast(end.location, end, switchType);
        if (!end.isKnown) {
            throw new CompilerPanic(end.location, "runtime switch cases are unimplemented.");
        }
        
        //cases ~= begin.getConstant();
        throw new CompilerPanic(end.location - begin.location, "range case is unimplemented.");
    }
    
    auto switchInst = LLVMBuildSwitch(mod.builder, controlExpression.get(), switch_.defaultClause.target, cast(uint)switch_.cases.length);
    foreach (i, value; cases) {
        LLVMAddCase(switchInst, value, switch_.cases[i].target);
    }
    
    LLVMPositionBuilderAtEnd(mod.builder, postSwitchBB);
    mod.currentFunction.currentBasicBlock = postSwitchBB;
    mod.currentFunction.cfgTail = postSwitch;
    
    mod.currentSwitch = popSwitch;
}

private struct SwitchSubStatement
{
    BasicBlock block;
    LLVMBasicBlockRef llvmBlock;
}

// Switch target, either a case or a default clause.
SwitchSubStatement genSwitchSubStatement(string name, ast.SwitchSubStatement statement, Module mod)
{
    auto switch_ = mod.currentSwitch;
    
    auto bb = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.llvmValue, toStringz(name));
    
    if (switch_.wasDefault) {
        switch_.wasDefault = false;
    } else {
        LLVMBuildBr(mod.builder, bb);
    }
    
    auto sub = new BasicBlock(name);
    switch_.switchTop.children ~= sub;
    
    consumeFallThroughGotos(switch_.pendingGotoCases, bb, sub, mod);
    
    LLVMPositionBuilderAtEnd(mod.builder, bb);
    mod.currentFunction.currentBasicBlock = bb;
    mod.currentFunction.cfgTail = sub;
    
    foreach(s; statement.statementList) {
        genStatement(s, mod);
    }
    
    return SwitchSubStatement(sub, bb);
}

void genDefaultStatement(ast.SwitchSubStatement statement, Module mod)
{
    auto switch_ = mod.currentSwitch;
    if (switch_ is null) {
        throw new CompilerError(statement.location, "default statement must be in a switch statement.");
    }
    
    if (switch_.defaultClause.target !is null) {
        throw new CompilerError(
            statement.location,
            "switch can only have one default clause.",
            new CompilerError(
                switch_.defaultClause.location,
                "previous definition here."
            )
        );
    }
    
    auto popTail = mod.currentFunction.cfgTail;
    
    auto result = genSwitchSubStatement("default", statement, mod);
    if (!mod.currentFunction.cfgTail.isUnreachableBlock) {
        mod.currentFunction.cfgTail.children ~= switch_.postSwitch;
    }
    
    LLVMBuildBr(mod.builder, switch_.postSwitchBB);
    switch_.wasDefault = true;
    
    mod.currentFunction.cfgTail = popTail;
    
    switch_.defaultClause = SwitchDefault(statement.location, result.llvmBlock, result.block);
}

void genCaseStatement(ast.CaseListStatement statement, Module mod)
{
    auto switch_ = mod.currentSwitch;
    if (switch_ is null) {
        throw new CompilerError(statement.location, "case statement must be in a switch statement.");
    }
    
    auto popTail = mod.currentFunction.cfgTail;
    
    auto result = genSwitchSubStatement("case", statement, mod);
    auto tail = mod.currentFunction.cfgTail;
    if (!tail.isUnreachableBlock) {
        throw new IllegalFallThroughError(statement);
    }
    
    mod.currentFunction.cfgTail = popTail;
    
    foreach (switchCase; statement.cases) {
        switch_.cases ~= SwitchCase(switchCase, result.llvmBlock);
    }
}

void genCaseRangeStatement(ast.CaseRangeStatement statement, Module mod)
{
    auto switch_ = mod.currentSwitch;
    if (switch_ is null) {
        throw new CompilerError(statement.location, "case range statement must be in a switch statement.");
    }
    
    auto popTail = mod.currentFunction.cfgTail;
    
    auto result = genSwitchSubStatement("caserange", statement, mod);
    auto tail = mod.currentFunction.cfgTail;
    if (!tail.isUnreachableBlock) {
        throw new IllegalFallThroughError(statement);
    }
    
    mod.currentFunction.cfgTail = popTail;
    
    switch_.ranges ~= SwitchRangeCase(statement.rangeBegin, statement.rangeEnd, result.llvmBlock);
}
