module d.backend.codegen;

import d.ast.dmodule;

import util.visitor;

import llvm.c.Analysis;
import llvm.c.Core;

import std.algorithm;
import std.array;
import std.string;

auto codeGen(Module m) {
	auto cg = new CodeGenPass();
	
	cg.visit(m);
	
	return cg.dmodule;
}

class CodeGenPass {
	private DeclarationGen declarationGen;
	private StatementGen statementGen;
	private ExpressionGen expressionGen;
	private AddressOfGen addressOfGen;
	private TypeGen typeGen;
	
	private LLVMBuilderRef builder;
	private LLVMModuleRef dmodule;
	
	private LLVMValueRef[ExpressionSymbol] exprSymbols;
	private LLVMTypeRef[TypeSymbol] typeSymbols;
	
	bool isSigned;
	
	this() {
		declarationGen	= new DeclarationGen(this);
		statementGen	= new StatementGen(this);
		expressionGen	= new ExpressionGen(this);
		addressOfGen	= new AddressOfGen(this);
		typeGen			= new TypeGen(this);
		
		builder = LLVMCreateBuilder();
	}
	
final:
	Module visit(Module m) {
		dmodule = LLVMModuleCreateWithName(m.location.filename.toStringz());
		
		// Dump module content on failure (for debug purpose).
		scope(failure) LLVMDumpModule(dmodule);
		
		foreach(decl; m.declarations) {
			visit(decl);
		}
		
		return m;
	}
	
	auto visit(Declaration decl) {
		return declarationGen.visit(decl);
	}
	
	auto visit(ExpressionSymbol s) {
		return declarationGen.visit(s);
	}
	
	auto visit(TypeSymbol s) {
		return declarationGen.visit(s);
	}
	
	auto visit(Statement stmt) {
		return statementGen.visit(stmt);
	}
	
	auto visit(Expression e) {
		return expressionGen.visit(e);
	}
	
	auto visit(Type t) {
		return typeGen.visit(t);
	}
}

import d.ast.adt;
import d.ast.declaration;
import d.ast.dfunction;

class DeclarationGen {
	private CodeGenPass pass;
	alias pass this;
	
	this(CodeGenPass pass) {
		this.pass = pass;
	}
	
final:
	void visit(Declaration d) {
		if(auto es = cast(ExpressionSymbol) d) {
			visit(es);
		} else if(auto ts = cast(TypeSymbol) d) {
			visit(ts);
		}
	}
	
	LLVMValueRef visit(ExpressionSymbol s) {
		return exprSymbols.get(s, this.dispatch(s));
	}
	
	LLVMValueRef visit(FunctionDefinition f) {
		// Ensure we are rentrant.
		auto backupCurrentBlock = LLVMGetInsertBlock(builder);
		scope(exit) LLVMPositionBuilderAtEnd(builder, backupCurrentBlock);
		
		auto parameterTypes = f.parameters.map!(p => pass.visit(p.type)).array();
		
		auto funType = LLVMFunctionType(pass.visit(f.returnType), parameterTypes.ptr, cast(uint) parameterTypes.length, false);
		auto fun = LLVMAddFunction(dmodule, f.mangling.toStringz(), funType);
		
		// Register the function.
		exprSymbols[f] = fun;
		
		// Alloca and instruction block.
		auto allocaBB = LLVMAppendBasicBlock(fun, "");
		auto bodyBB = LLVMAppendBasicBlock(fun, "body");
		
		// Handle parameters in the alloca block.
		LLVMPositionBuilderAtEnd(builder, allocaBB);
		
		LLVMValueRef[] params;
		params.length = f.parameters.length;
		LLVMGetParams(fun, params.ptr);
		
		foreach(i, p; f.parameters) {
			auto value = params[i];
			
			// XXX: avoid to test every iterations.
			if(f.isStatic || i > 0) {
				auto alloca = LLVMBuildAlloca(builder, parameterTypes[i], p.name.toStringz());
				
				LLVMSetValueName(value, ("arg." ~ p.name).toStringz());
				
				LLVMBuildStore(builder, value, alloca);
				exprSymbols[p] = alloca;
			} else {
				LLVMSetValueName(value, p.name.toStringz());
			}
		}
		
		// Generate function's body.
		LLVMPositionBuilderAtEnd(builder, bodyBB);
		pass.visit(f.fbody);
		
		// If the current block isn' concluded, it means that it is unreachable.
		if(!LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(builder))) {
			LLVMBuildUnreachable(builder);
		}
		
		// Branch from alloca block to function body.
		LLVMPositionBuilderAtEnd(builder, allocaBB);
		LLVMBuildBr(builder, bodyBB);
		
		LLVMVerifyFunction(fun, LLVMVerifierFailureAction.PrintMessage);
		
		return fun;
	}
	
	LLVMValueRef visit(VariableDeclaration var) {
		if(var.isStatic) {
			auto globalVar = LLVMAddGlobal(dmodule, pass.visit(var.type), var.mangling.toStringz());
			// FIXME: interpreter don't support TLS for now.
			// LLVMSetThreadLocal(globalVar, true);
			
			// Register the variable.
			exprSymbols[var] = globalVar;
			
			// Store the initial value into the alloca.
			auto value = pass.visit(var.value);
			LLVMSetInitializer(globalVar, value);
			
			return globalVar;
		} else {
			// Backup current block
			auto backupCurrentBlock = LLVMGetInsertBlock(builder);
			LLVMPositionBuilderAtEnd(builder, LLVMGetFirstBasicBlock(LLVMGetBasicBlockParent(backupCurrentBlock)));
			
			// Create an alloca for this variable.
			auto alloca = LLVMBuildAlloca(builder, pass.visit(var.type), var.mangling.toStringz());
			
			LLVMPositionBuilderAtEnd(builder, backupCurrentBlock);
			
			// Register the variable.
			exprSymbols[var] = alloca;
			
			// Store the initial value into the alloca.
			auto value = pass.visit(var.value);
			LLVMBuildStore(builder, value, alloca);
			
			return alloca;
		}
	}
	
	LLVMTypeRef visit(TypeSymbol s) {
		return typeSymbols.get(s, this.dispatch(s));
	}
	
	LLVMTypeRef visit(StructDefinition sd) {
		auto llvmStruct = LLVMStructCreateNamed(LLVMGetGlobalContext(), cast(char*) sd.name.toStringz());
		typeSymbols[sd] = llvmStruct;
		
		LLVMTypeRef[] members;
		
		foreach(member; sd.members) {
			if(auto f = cast(FieldDeclaration) member) {
				members ~= pass.visit(f.type);
			}
		}
		
		LLVMStructSetBody(llvmStruct, members.ptr, cast(uint) members.length, false);
		
		return llvmStruct;
	}
	
	LLVMTypeRef visit(AliasDeclaration a) {
		auto llvmType = pass.visit(a.type);
		typeSymbols[a] = llvmType;
		
		return llvmType;
	}
}

import d.ast.statement;

class StatementGen {
	private CodeGenPass pass;
	alias pass this;
	
	this(CodeGenPass pass) {
		this.pass = pass;
	}
		
final:
	void visit(Statement s) {
		this.dispatch(s);
	}
	
	void visit(DeclarationStatement d) {
		pass.visit(d.declaration);
	}
	
	void visit(ExpressionStatement e) {
		pass.visit(e.expression);
	}
	
	void visit(BlockStatement b) {
		foreach(s; b.statements) {
			visit(s);
		}
	}
	
	void visit(IfElseStatement ifs) {
		auto condition = pass.visit(ifs.condition);
		
		auto fun = LLVMGetBasicBlockParent(LLVMGetInsertBlock(builder));
		
		auto thenBB = LLVMAppendBasicBlock(fun, "then");
		auto elseBB = LLVMAppendBasicBlock(fun, "else");
		auto mergeBB = LLVMAppendBasicBlock(fun, "merge");
		
		LLVMBuildCondBr(builder, condition, thenBB, elseBB);
		
		// Emit then
		LLVMPositionBuilderAtEnd(builder, thenBB);
		
		visit(ifs.then);
		
		// Codegen of then can change the current block, so we put everything in order.
		thenBB = LLVMGetInsertBlock(builder);
		
		// Conclude that block if it isn't already.
		if(!LLVMGetBasicBlockTerminator(thenBB)) {
			LLVMBuildBr(builder, mergeBB);
		}
		
		// Put the else block after the generated stuff.
		LLVMMoveBasicBlockAfter(elseBB, thenBB);
		LLVMPositionBuilderAtEnd(builder, elseBB);
		
		// Emit else
		visit(ifs.elseStatement);
		
		// Codegen of else can change the current block, so we put everything in order.
		elseBB = LLVMGetInsertBlock(builder);
		
		// Conclude that block if it isn't already.
		if(!LLVMGetBasicBlockTerminator(elseBB)) {
			LLVMBuildBr(builder, mergeBB);
		}
		
		LLVMMoveBasicBlockAfter(mergeBB, elseBB);
		LLVMPositionBuilderAtEnd(builder, mergeBB);
	}
	
	private void handleLoop(LoopStatement)(LoopStatement l) {
		auto fun = LLVMGetBasicBlockParent(LLVMGetInsertBlock(builder));
		
		enum isFor = is(LoopStatement : ForStatement);
		enum isDoWhile = is(LoopStatement : DoWhileStatement);
		
		static if(isFor) {
			auto testBB = LLVMAppendBasicBlock(fun, "for");
			auto continueBB = LLVMAppendBasicBlock(fun, "increment");
		} else {
			auto testBB = LLVMAppendBasicBlock(fun, "while");
			alias testBB continueBB;
		}
		
		auto doBB = LLVMAppendBasicBlock(fun, "do");
		auto doneBB = LLVMAppendBasicBlock(fun, "done");
		
		static if(isDoWhile) {
			alias doBB startBB;
		} else {
			alias testBB startBB;
		}
		
		// Generate initialization if appropriate
		static if(isFor) {
			visit(l.initialize);
		}
		
		// Jump into the loop.
		LLVMBuildBr(builder, startBB);
		LLVMPositionBuilderAtEnd(builder, testBB);
		
		// Test and do or jump to done.
		auto condition = pass.visit(l.condition);
		LLVMBuildCondBr(builder, condition, doBB, doneBB);
		
		// Build continue block or alias it to the test.
		static if(isFor) {
			LLVMPositionBuilderAtEnd(builder, continueBB);
			pass.visit(l.increment);
			
			LLVMBuildBr(builder, testBB);
		}
		
		// Emit do
		LLVMPositionBuilderAtEnd(builder, doBB);
		
		visit(l.statement);
		
		// Codegen of then can change the current block, so we put everything in order.
		doBB = LLVMGetInsertBlock(builder);
		
		// Conclude that block if it isn't already.
		if(!LLVMGetBasicBlockTerminator(doBB)) {
			LLVMBuildBr(builder, continueBB);
		}
		
		LLVMMoveBasicBlockAfter(doneBB, doBB);
		LLVMPositionBuilderAtEnd(builder, doneBB);
	}
	
	void visit(WhileStatement w) {
		handleLoop(w);
	}
	
	void visit(DoWhileStatement w) {
		handleLoop(w);
	}
	
	void visit(ForStatement f) {
		handleLoop(f);
	}
	
	void visit(ReturnStatement r) {
		LLVMBuildRet(builder, pass.visit(r.value));
	}
}

import d.ast.expression;

class ExpressionGen {
	private CodeGenPass pass;
	alias pass this;
	
	this(CodeGenPass pass) {
		this.pass = pass;
	}
		
final:
	LLVMValueRef visit(Expression e) {
		return this.dispatch!(function LLVMValueRef(Expression e) {
			auto msg = typeid(e).toString() ~ " is not supported.";
			
			import sdc.terminal;
			outputCaretDiagnostics(e.location, msg);
			
			assert(0, msg);
		})(e);
	}
	
	LLVMValueRef visit(BooleanLiteral bl) {
		return LLVMConstInt(pass.visit(bl.type), bl.value, false);
	}
	
	LLVMValueRef visit(IntegerLiteral!true il) {
		return LLVMConstInt(pass.visit(il.type), il.value, true);
	}
	
	LLVMValueRef visit(IntegerLiteral!false il) {
		return LLVMConstInt(pass.visit(il.type), il.value, false);
	}
	
	LLVMValueRef visit(FloatLiteral fl) {
		return LLVMConstReal(pass.visit(fl.type), fl.value);
	}
	
	// XXX: character types in backend ?
	LLVMValueRef visit(CharacterLiteral cl) {
		return LLVMConstInt(pass.visit(cl.type), cl.value[0], false);
	}
	
	LLVMValueRef visit(CommaExpression ce) {
		visit(ce.lhs);
		
		return visit(ce.rhs);
	}
	
	LLVMValueRef visit(ThisExpression e) {
		return LLVMBuildLoad(builder, addressOfGen.visit(e), "");
	}
	
	private void updateVariableValue(Expression e, LLVMValueRef value) {
		LLVMBuildStore(builder, value, addressOfGen.visit(e));
	}
	
	LLVMValueRef visit(AssignExpression e) {
		auto value = visit(e.rhs);
		
		updateVariableValue(e.lhs, value);
		
		return value;
	}
	
	LLVMValueRef visit(AddressOfExpression e) {
		return addressOfGen.visit(e.expression);
	}
	
	LLVMValueRef visit(ReferenceOfExpression e) {
		return addressOfGen.visit(e.expression);
	}
	
	LLVMValueRef visit(DereferenceExpression e) {
		return LLVMBuildLoad(builder, visit(e.expression), "");
	}
	
	private auto handleIncrement(alias LLVMIncrementOp, bool pre, IncrementExpression)(IncrementExpression e) {
		auto preValue = visit(e.expression);
		auto lvalue = e.expression;
		
		auto postValue = LLVMIncrementOp(builder, preValue, LLVMConstInt(pass.visit(lvalue.type), 1, false), "");
		
		updateVariableValue(lvalue, postValue);
		
		// PreIncrement return the value after it is incremented.
		static if(pre) {
			return postValue;
		} else {
			return preValue;
		}
	}
	
	LLVMValueRef visit(PreIncrementExpression e) {
		return handleIncrement!(LLVMBuildAdd, true)(e);
	}
	
	LLVMValueRef visit(PreDecrementExpression e) {
		return handleIncrement!(LLVMBuildSub, true)(e);
	}
	
	LLVMValueRef visit(PostIncrementExpression e) {
		return handleIncrement!(LLVMBuildAdd, false)(e);
	}
	
	LLVMValueRef visit(PostDecrementExpression e) {
		return handleIncrement!(LLVMBuildSub, false)(e);
	}
	
	private auto handleBinaryOp(alias LLVMBuildOp, BinaryExpression)(BinaryExpression e) {
		return LLVMBuildOp(builder, visit(e.lhs), visit(e.rhs), "");
	}
	
	private auto handleBinaryOp(alias LLVMSignedBuildOp, alias LLVMUnsignedBuildOp, BinaryExpression)(BinaryExpression e) {
		pass.visit(e.type);
		
		if(isSigned) {
			return handleBinaryOp!LLVMSignedBuildOp(e);
		} else {
			return handleBinaryOp!LLVMUnsignedBuildOp(e);
		}
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
		return handleBinaryOp!(LLVMBuildSDiv, LLVMBuildUDiv)(div);
	}
	
	LLVMValueRef visit(ModExpression mod) {
		return handleBinaryOp!(LLVMBuildSRem, LLVMBuildURem)(mod);
	}
	
	private auto handleLogicalBinary(string operation)(BinaryExpression!operation e) if(operation == "&&" || operation == "||") {
		auto lhs = visit(e.lhs);
		
		auto lhsBB = LLVMGetInsertBlock(builder);
		auto fun = LLVMGetBasicBlockParent(lhsBB);
		
		static if(operation == "&&") {
			auto rhsBB = LLVMAppendBasicBlock(fun, "and_short_circuit");
			auto mergeBB = LLVMAppendBasicBlock(fun, "and_merge");
			LLVMBuildCondBr(builder, lhs, rhsBB, mergeBB);
		} else {
			auto rhsBB = LLVMAppendBasicBlock(fun, "or_short_circuit");
			auto mergeBB = LLVMAppendBasicBlock(fun, "or_merge");
			LLVMBuildCondBr(builder, lhs, mergeBB, rhsBB);
		}
		
		// Emit then
		LLVMPositionBuilderAtEnd(builder, rhsBB);
		
		auto rhs = visit(e.rhs);
		
		// Conclude that block.
		LLVMBuildBr(builder, mergeBB);
		
		// Codegen of then can change the current block, so we put everything in order.
		rhsBB = LLVMGetInsertBlock(builder);
		LLVMMoveBasicBlockAfter(mergeBB, rhsBB);
		LLVMPositionBuilderAtEnd(builder, mergeBB);
		
		//Generate phi to get the result.
		auto phiNode = LLVMBuildPhi(builder, pass.visit(e.type), "");
		
		LLVMValueRef[2] incomingValues;
		incomingValues[0] = lhs;
		incomingValues[1] = rhs;
		LLVMBasicBlockRef[2] incomingBlocks;
		incomingBlocks[0] = lhsBB;
		incomingBlocks[1] = rhsBB;
		LLVMAddIncoming(phiNode, incomingValues.ptr, incomingBlocks.ptr, incomingValues.length);
		
		return phiNode;
	}
	
	LLVMValueRef visit(LogicalAndExpression e) {
		return handleLogicalBinary(e);
	}
	
	LLVMValueRef visit(LogicalOrExpression e) {
		return handleLogicalBinary(e);
	}
	
	LLVMValueRef visit(SymbolExpression e) {
		return LLVMBuildLoad(builder, addressOfGen.visit(e), "");
	}
	
	LLVMValueRef visit(FieldExpression e) {
		return LLVMBuildLoad(builder, addressOfGen.visit(e), "");
	}
	
	private auto handleComparaison(LLVMIntPredicate predicate, BinaryExpression)(BinaryExpression e) {
		return handleBinaryOp!(function(LLVMBuilderRef builder, LLVMValueRef lhs, LLVMValueRef rhs, const char* name) {
			return LLVMBuildICmp(builder, predicate, lhs, rhs, name);
		})(e);
	}
	
	private auto handleComparaison(LLVMIntPredicate signedPredicate, LLVMIntPredicate unsignedPredicate, BinaryExpression)(BinaryExpression e) {
		// TODO: implement type comparaison.
		// assert(e.lhs.type == e.rhs.type);
		
		pass.visit(e.lhs.type);
		
		if(isSigned) {
			return handleComparaison!signedPredicate(e);
		} else {
			return handleComparaison!unsignedPredicate(e);
		}
	}
	
	LLVMValueRef visit(EqualityExpression e) {
		return handleComparaison!(LLVMIntPredicate.EQ)(e);
	}
	
	LLVMValueRef visit(NotEqualityExpression e) {
		return handleComparaison!(LLVMIntPredicate.NE)(e);
	}
	
	LLVMValueRef visit(LessExpression e) {
		return handleComparaison!(LLVMIntPredicate.SLT, LLVMIntPredicate.ULT)(e);
	}
	
	LLVMValueRef visit(LessEqualExpression e) {
		return handleComparaison!(LLVMIntPredicate.SLE, LLVMIntPredicate.ULE)(e);
	}
	
	LLVMValueRef visit(GreaterExpression e) {
		return handleComparaison!(LLVMIntPredicate.SGT, LLVMIntPredicate.UGT)(e);
	}
	
	LLVMValueRef visit(GreaterEqualExpression e) {
		return handleComparaison!(LLVMIntPredicate.SGE, LLVMIntPredicate.UGE)(e);
	}
	
	LLVMValueRef visit(PadExpression e) {
		auto type = pass.visit(e.type);
		
		pass.visit(e.expression.type);
		if(isSigned) {
			return LLVMBuildSExt(builder, visit(e.expression), type, "");
		} else {
			return LLVMBuildZExt(builder, visit(e.expression), type, "");
		}
	}
	
	LLVMValueRef visit(TruncateExpression e) {
		return LLVMBuildTrunc(builder, visit(e.expression), pass.visit(e.type), "");
	}
	
	LLVMValueRef visit(BitCastExpression e) {
		return LLVMBuildBitCast(builder, visit(e.expression), pass.visit(e.type), "");
	}
	
	LLVMValueRef visit(CallExpression c) {
		LLVMValueRef[] arguments;
		arguments.length = c.arguments.length;
		
		foreach(i, arg; c.arguments) {
			arguments[i] = visit(arg);
		}
		
		return LLVMBuildCall(builder, addressOfGen.visit(c.callee), arguments.ptr, cast(uint) arguments.length, "");
	}
	
	LLVMValueRef visit(VoidInitializer v) {
		return LLVMGetUndef(pass.visit(v.type));
	}
}

class AddressOfGen {
	private CodeGenPass pass;
	alias pass this;
	
	this(CodeGenPass pass) {
		this.pass = pass;
	}
	
final:
	LLVMValueRef visit(Expression e) {
		return this.dispatch(e);
	}
	
	LLVMValueRef visit(SymbolExpression e) {
		return pass.visit(e.symbol);
	}
	
	LLVMValueRef visit(FieldExpression e) {
		auto ptr = visit(e.expression);
		
		return LLVMBuildStructGEP(builder, ptr, e.field.index, "");
	}
	
	LLVMValueRef visit(ThisExpression e) {
		return LLVMGetFirstParam(LLVMGetBasicBlockParent(LLVMGetInsertBlock(builder)));
	}
}

import d.ast.type;

class TypeGen {
	private CodeGenPass pass;
	alias pass this;
	
	this(CodeGenPass pass) {
		this.pass = pass;
	}
	
final:
	LLVMTypeRef visit(Type t) {
		return this.dispatch!(function LLVMTypeRef(Type t) {
			auto msg = typeid(t).toString() ~ " is not supported.";
			
			import sdc.terminal;
			outputCaretDiagnostics(t.location, msg);
			
			assert(0, msg);
		})(t);
	}
	
	LLVMTypeRef visit(SymbolType t) {
		return pass.visit(t.symbol);
	}
	
	LLVMTypeRef visit(BooleanType t) {
		isSigned = false;
		
		return LLVMInt1Type();
	}
	
	LLVMTypeRef visit(IntegerType t) {
		isSigned = !(t.type % 2);
		
		final switch(t.type) {
				case Integer.Byte, Integer.Ubyte :
					return LLVMInt8Type();
				
				case Integer.Short, Integer.Ushort :
					return LLVMInt16Type();
				
				case Integer.Int, Integer.Uint :
					return LLVMInt32Type();
				
				case Integer.Long, Integer.Ulong :
					return LLVMInt64Type();
		}
	}
	
	LLVMTypeRef visit(FloatType t) {
		isSigned = true;
		
		final switch(t.type) {
				case Float.Float :
					return LLVMFloatType();
				
				case Float.Double :
					return LLVMDoubleType();
				
				case Float.Real :
					return LLVMX86FP80Type();
		}
	}
	
	// XXX: character type in the backend ?
	LLVMTypeRef visit(CharacterType t) {
		isSigned = false;
		
		final switch(t.type) {
				case Character.Char :
					return LLVMInt8Type();
				
				case Character.Wchar :
					return LLVMInt16Type();
				
				case Character.Dchar :
					return LLVMInt32Type();
		}
	}
	
	LLVMTypeRef visit(VoidType t) {
		return LLVMVoidType();
	}
	
	LLVMTypeRef visit(PointerType t) {
		auto pointed = visit(t.type);
		
		isSigned = false;
		
		return LLVMPointerType(pointed, 0);
	}
	
	LLVMTypeRef visit(ReferenceType t) {
		auto pointed = visit(t.type);
		
		return LLVMPointerType(pointed, 0);
	}
}

