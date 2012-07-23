module d.backend.codegen;

import d.ast.dmodule;

import util.visitor;

import llvm.c.Analysis;
import llvm.c.Core;

import std.string;

auto codeGen(Module m) {
	auto builder = LLVMCreateBuilder();
	auto dmodule = LLVMModuleCreateWithName(m.location.filename.toStringz());
	
	// Dump module content on exit (for debug purpose).
	scope(exit) LLVMDumpModule(dmodule);
	
	auto cg = new DeclarationGen(dmodule, builder);
	foreach(decl; m.declarations) {
		cg.visit(decl);
	}
	
	return dmodule;
}

import d.ast.declaration;
import d.ast.dfunction;

class DeclarationGen {
	private LLVMBuilderRef builder;
	private LLVMModuleRef dmodule;
	
	private ExpressionGen expressionGen;
	private TypeGen typeGen;
	
	LLVMValueRef[string] variables;
	
	this(LLVMModuleRef dmodule, LLVMBuilderRef builder) {
		this.builder = builder;
		this.dmodule = dmodule;
		
		typeGen = new TypeGen();
		expressionGen = new ExpressionGen(builder, this, typeGen);
	}
	
final:
	void visit(Declaration d) {
		this.dispatch(d);
	}
	
	void visit(FunctionDefinition f) {
		assert(f.name == "main", "Only main can be compiled !");
		
		auto funType = LLVMFunctionType(LLVMInt32Type(), null, 0, false);
		auto fun = LLVMAddFunction(dmodule, toStringz(f.name), funType);
		
		// Instruction block.
		auto basicBlock = LLVMAppendBasicBlock(fun, "");
		LLVMPositionBuilderAtEnd(builder, basicBlock);
		
		(new StatementGen(builder, this, expressionGen)).visit(f.fbody);
		
		LLVMVerifyFunction(fun, LLVMVerifierFailureAction.PrintMessage);
	}
	
	void visit(VariablesDeclaration decls) {
		foreach(var; decls.variables) {
			visit(var);
		}
	}
	
	void visit(VariableDeclaration var) {
		// Backup current block
		auto backupCurrentBlock = LLVMGetInsertBlock(builder);
		LLVMPositionBuilderAtEnd(builder, LLVMGetFirstBasicBlock(LLVMGetBasicBlockParent(backupCurrentBlock)));
		
		// Create an alloca for this variable.
		auto alloca = LLVMBuildAlloca(builder, typeGen.visit(var.type), "");
		
		LLVMPositionBuilderAtEnd(builder, backupCurrentBlock);
		
		// Store the initial value into the alloca.
		auto value = expressionGen.visit(var.value);
		LLVMBuildStore(builder, value, alloca);
		
		//*
		variables[var.name] = value;
		/*/
		variables[var.name] = alloca;
		//*/
	}
}

import d.ast.statement;

class StatementGen {
	private LLVMBuilderRef builder;
	
	private DeclarationGen declarationGen;
	private ExpressionGen expressionGen;
	
	this(LLVMBuilderRef builder, DeclarationGen declarationGen, ExpressionGen expressionGen){
		this.builder = builder;
		this.declarationGen = declarationGen;
		this.expressionGen = expressionGen;
	}
	
final:
	void visit(Statement s) {
		this.dispatch(s);
	}
	
	void visit(DeclarationStatement d) {
		declarationGen.visit(d.declaration);
	}
	
	void visit(BlockStatement b) {
		foreach(s; b.statements) {
			visit(s);
		}
	}
	
	void visit(IfStatement ifs) {
		auto fun = LLVMGetBasicBlockParent(LLVMGetInsertBlock(builder));
		
		auto thenBB = LLVMAppendBasicBlock(fun, "then");
		auto elseBB = LLVMAppendBasicBlock(fun, "else");
		auto mergeBB = LLVMAppendBasicBlock(fun, "merge");
		
		LLVMBuildCondBr(builder, expressionGen.visit(ifs.condition), thenBB, elseBB);
		
		// Emit then value
		LLVMPositionBuilderAtEnd(builder, thenBB);
		
		visit(ifs.then);
		
		// Conclude that block.
		LLVMBuildBr(builder, mergeBB);
		
		// Codegen of else can change the current block, so we put everything in order.
		thenBB = LLVMGetInsertBlock(builder);
		LLVMMoveBasicBlockAfter(elseBB, thenBB);
		LLVMPositionBuilderAtEnd(builder, elseBB);
		
		// TODO: Codegen for else.
		
		// Conclude that block.
		LLVMBuildBr(builder, mergeBB);
		
		// Codegen of else can change the current block, so we put everything in order.
		elseBB = LLVMGetInsertBlock(builder);
		LLVMMoveBasicBlockAfter(mergeBB, elseBB);
		LLVMPositionBuilderAtEnd(builder, mergeBB);
		
		// TODO: generate phi to merge everything back.
	}
	
	void visit(ReturnStatement f) {
		LLVMBuildRet(builder, expressionGen.visit(f.value));
	}
}

import d.ast.expression;

class ExpressionGen {
	private LLVMBuilderRef builder;
	
	private DeclarationGen declarationGen;
	private TypeGen typeGen;
	
	this(LLVMBuilderRef builder, DeclarationGen declarationGen, TypeGen typeGen) {
		this.builder = builder;
		this.declarationGen = declarationGen;
		this.typeGen = typeGen;
	}
	
final:
	LLVMValueRef visit(Expression e) {
		return this.dispatch(e);
	}
	
	LLVMValueRef visit(IntegerLiteral!true il) {
		return LLVMConstInt(typeGen.visit(il.type), il.value, true);
	}
	
	LLVMValueRef visit(IntegerLiteral!false il) {
		return LLVMConstInt(typeGen.visit(il.type), il.value, false);
	}
	
	private auto handleBinaryOp(alias LLVMBuildOp, BinaryExpression)(BinaryExpression e) {
		return LLVMBuildOp(builder, visit(e.lhs), visit(e.rhs), "");
	}
	
	LLVMValueRef visit(AddExpression add) {
		return handleBinaryOp!LLVMBuildAdd(add);
	}
	
	LLVMValueRef visit(SubExpression sub) {
		return handleBinaryOp!LLVMBuildSub(sub);
	}
	
	LLVMValueRef visit(MulExpression mul) {
		return handleBinaryOp!LLVMBuildMul(mul);
	}
	
	LLVMValueRef visit(DivExpression div) {
		// Check signed/unsigned.
		return handleBinaryOp!LLVMBuildSDiv(div);
	}
	
	LLVMValueRef visit(ModExpression mod) {
		// Check signed/unsigned.
		return handleBinaryOp!LLVMBuildSRem(mod);
	}
	
	LLVMValueRef visit(IdentifierExpression e) {
		//*
		return declarationGen.variables[e.identifier.name];
		/*/
		return LLVMBuildLoad(builder, declarationGen.variables[e.identifier.name], "");
		//*/
	}
	
	auto handleComparaison(LLVMIntPredicate predicate, BinaryExpression)(BinaryExpression e) {
		return handleBinaryOp!(function(LLVMBuilderRef builder, LLVMValueRef lhs, LLVMValueRef rhs, const char* name) {
			return LLVMBuildICmp(builder, predicate, lhs, rhs, name);
		})(e);
	}
	
	// TODO: handled signed and unsigned !
	LLVMValueRef visit(LessExpression e) {
		return handleComparaison!(LLVMIntPredicate.ULT)(e);
	}
	
	LLVMValueRef visit(LessEqualExpression e) {
		return handleComparaison!(LLVMIntPredicate.ULE)(e);
	}
	
	LLVMValueRef visit(GreaterExpression e) {
		return handleComparaison!(LLVMIntPredicate.UGT)(e);
	}
	
	LLVMValueRef visit(GreaterEqualExpression e) {
		return handleComparaison!(LLVMIntPredicate.UGE)(e);
	}
}

import d.ast.type;

class TypeGen {
	LLVMTypeRef visit(Type t) {
		return this.dispatch(t);
	}
	
	LLVMTypeRef visit(BuiltinType!int) {
		return LLVMInt32Type();
	}
	
	LLVMTypeRef visit(BuiltinType!uint) {
		return LLVMInt32Type();
	}
	
	LLVMTypeRef visit(BuiltinType!long) {
		return LLVMInt64Type();
	}
	
	LLVMTypeRef visit(BuiltinType!ulong) {
		return LLVMInt64Type();
	}
}

