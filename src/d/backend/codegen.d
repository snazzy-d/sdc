module d.backend.codegen;

import d.ast.visitor;
import d.ast.dmodule;

import llvm.c.Core;

import std.string;

auto codeGen(Module m) {
	auto builder = LLVMCreateBuilder();
	auto dmodule = LLVMModuleCreateWithName(toStringz(m.moduleDeclaration.packages.join(".") ~ "." ~ m.moduleDeclaration.name));
	
	// Dump module content on exit (for debug purpose).
	scope(exit) LLVMDumpModule(dmodule);
	
	auto cg = new DeclarationGen(dmodule, builder);
	foreach(decl; m.declarations) {
		decl.accept(cg);
	}
	
	return dmodule;
}

import d.ast.declaration;
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
		
		f.fbody.accept(new StatementGen(builder, this));
		
		import llvm.c.Analysis;
		LLVMVerifyFunction(fun, LLVMVerifierFailureAction.PrintMessage);
	}
	
	void visit(VariablesDeclaration decls) {
		foreach(var; decls.variables) {
			var.accept(this);
		}
	}
	
	void visit(VariableDeclaration var) {
		auto expression = new ExpressiontGen(builder);
		var.value.accept(expression);
		
		// Create an alloca for this variable.
		auto alloca = LLVMBuildAlloca(builder, LLVMInt32Type(), var.name.toStringz());
		
		// Store the initial value into the alloca.
		LLVMBuildStore(builder, expression.value, alloca);
	}
}

import d.ast.statement;

class StatementGen : StatementVisitor {
	private LLVMBuilderRef builder;
	private DeclarationGen declarationGen;
	
	this(LLVMBuilderRef builder, DeclarationGen declarationGen){
		this.builder = builder;
		this.declarationGen = declarationGen;
	}
	
	void visit(Declaration d) {
		d.accept(declarationGen);
	}
	
	void visit(BlockStatement b) {
		foreach(s; b.statements) {
			s.accept(this);
		}
	}
	
	void visit(ReturnStatement f) {
		auto expression = new ExpressiontGen(builder);
		f.value.accept(expression);
		
		LLVMBuildRet(builder, expression.value);
	}
}

import d.ast.expression;

class ExpressiontGen : ExpressionVisitor {
	private LLVMBuilderRef builder;
	LLVMValueRef value;
	
	this(LLVMBuilderRef builder) {
		this.builder = builder;
	}
	
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
	
	private final void handleBinaryOp(alias LLVMBuildOp)(BinaryExpression e) {
		e.lhs.accept(this);
		auto lhs = value;
		
		e.rhs.accept(this);
		
		value = LLVMBuildOp(builder, lhs, value, "tmp");
	}
	
	void visit(AdditionExpression add) {
		handleBinaryOp!LLVMBuildAdd(add);
	}
	
	void visit(SubstractionExpression sub) {
		handleBinaryOp!LLVMBuildSub(sub);
	}
	
	void visit(ConcatExpression concat) {
		assert(0, "concat is not implemented.");
	}
	
	void visit(MultiplicationExpression mul) {
		handleBinaryOp!LLVMBuildMul(mul);
	}
	
	void visit(DivisionExpression div) {
		// Check signed/unsigned.
		handleBinaryOp!LLVMBuildSDiv(div);
	}
	
	void visit(ModulusExpression mod) {
		// Check signed/unsigned.
		handleBinaryOp!LLVMBuildSRem(mod);
	}
	
	void visit(PowExpression pow) {
		assert(0, "pow is not implemented.");
	}
}

