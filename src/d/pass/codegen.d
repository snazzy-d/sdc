module d.pass.codegen;

import d.ast.visitor;
import d.ast.dmodule;

import llvm.c.Core;

import std.string;

auto codeGen(Module m) {
	auto builder = LLVMCreateBuilder();
	auto dmodule = LLVMModuleCreateWithName(toStringz(m.moduleDeclaration.packages.join(".") ~ "." ~ m.moduleDeclaration.name));
	
	auto cg = new DeclarationGen(dmodule, builder);
	foreach(decl; m.declarations) {
		decl.accept(cg);
	}
	
	return dmodule;
}

import d.ast.dfunction;

class DeclarationGen : DeclarationVisitor {
	private LLVMBuilderRef builder;
	private LLVMModuleRef dmodule;
	
	this(LLVMModuleRef dmodule, LLVMBuilderRef builder) {
		this.builder = builder;
		this.dmodule = dmodule;
	}
	
	void visit(FunctionDefinition f) {
		assert(f.name == "main", "Only main can be compiled !");
		
		auto funType = LLVMFunctionType(LLVMInt32Type(), null, 0, false);
		auto fun = LLVMAddFunction(dmodule, toStringz(f.name), funType);
		
		auto basicBlock = LLVMAppendBasicBlock(fun, "entry");
		LLVMPositionBuilderAtEnd(builder, basicBlock);
		
		f.fbody.accept(new StatementGen(builder));
		
		import llvm.c.Analysis;
		LLVMVerifyFunction(fun, LLVMVerifierFailureAction.PrintMessage);
		
		LLVMDumpModule(dmodule);
		
		
		// Let's run it !
		import llvm.c.ExecutionEngine;
		import std.stdio;
		LLVMLinkInInterpreter();
		
		LLVMExecutionEngineRef ee;
		char* errorPtr;
		int creationResult = LLVMCreateExecutionEngineForModule(&ee, dmodule, &errorPtr);
		if(creationResult == 1) {
			import std.c.string;
			writeln(errorPtr[0 .. strlen(errorPtr)]);
			writeln("Cannot create execution engine ! Exiting...");
			return;
		}
		
		auto executionResult = LLVMRunFunction(ee, fun, 0, null);
		auto returned = LLVMGenericValueToInt(executionResult, false);
		
		writeln("returned : ", returned);
	}
}

import d.ast.statement;

class StatementGen : StatementVisitor {
	private LLVMBuilderRef builder;
	
	this(LLVMBuilderRef builder){
		this.builder = builder;
	}
	
	void visit(BlockStatement b) {
		foreach(s; b.statements) {
			s.accept(new StatementGen(builder));
		}
	}
	
	void visit(ReturnStatement f) {
		auto expression = new ExpressiontGen();
		f.value.accept(expression);
		
		LLVMBuildRet(builder, expression.value);
	}
}

import d.ast.expression;

class ExpressiontGen : ExpressionVisitor {
	LLVMValueRef value;
	
	void visit(IntegerLiteral!int i32) {
		value = LLVMConstInt(LLVMInt32Type(), i32.value, true);
	}
	
	void visit(IntegerLiteral!uint i32) {
		value = LLVMConstInt(LLVMInt32Type(), i32.value, false);
	}
	
	void visit(IntegerLiteral!long i64) {
		value = LLVMConstInt(LLVMInt64Type(), i64.value, true);
	}
	
	void visit(IntegerLiteral!ulong i64) {
		value = LLVMConstInt(LLVMInt64Type(), i64.value, false);
	}
}

