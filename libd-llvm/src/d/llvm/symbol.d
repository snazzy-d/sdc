module d.llvm.symbol;

import d.llvm.codegen;

import d.ast.adt;
import d.ast.declaration;
import d.ast.dfunction;
import d.ast.type;

import util.visitor;

import llvm.c.analysis;
import llvm.c.core;

import std.algorithm;
import std.array;
import std.string;

final class DeclarationGen {
	private CodeGenPass pass;
	alias pass this;
	
	private LLVMValueRef[ExpressionSymbol] exprSymbols;
	private LLVMTypeRef[TypeSymbol] typeSymbols;
	
	this(CodeGenPass pass) {
		this.pass = pass;
	}
	
	void visit(Declaration d) {
		if(auto es = cast(ExpressionSymbol) d) {
			visit(es);
		} else if(auto ts = cast(TypeSymbol) d) {
			visit(ts);
		} else if(auto cd = cast(ClassDeclaration) d) {
			visit(cd);
		}
		
		assert(cast(Symbol) d, "Can only generate symbols.");
	}
	
	LLVMValueRef visit(ExpressionSymbol s) {
		return exprSymbols.get(s, this.dispatch(s));
	}
	
	LLVMValueRef visit(FunctionDeclaration f) {
		auto funptrType = pass.visit(f.type);
		
		auto funType = LLVMGetElementType(funptrType);
		auto fun = LLVMAddFunction(dmodule, f.mangle.toStringz(), funType);
		
		// Register the function.
		exprSymbols[f] = fun;
		
		if(f.fbody) {
			genFunctionBody(f, fun);
		}
			
		return fun;
	}
	
	LLVMValueRef visit(MethodDeclaration m) {
		return visit(cast(FunctionDeclaration) m);
	}
	
	private void genFunctionBody(FunctionDeclaration f) {
		genFunctionBody(f, exprSymbols[f]);
	}
	
	private void genFunctionBody(FunctionDeclaration f, LLVMValueRef fun) {
		// Alloca and instruction block.
		auto allocaBB = LLVMAppendBasicBlockInContext(context, fun, "");
		auto bodyBB = LLVMAppendBasicBlockInContext(context, fun, "body");
		
		// Ensure we are rentrant.
		auto backupCurrentBlock = LLVMGetInsertBlock(builder);
		auto oldLabels = labels;
		
		scope(exit) {
			LLVMPositionBuilderAtEnd(builder, backupCurrentBlock);
			labels = oldLabels;
		}
		
		// XXX: what is the way to flush an AA ?
		labels = typeof(labels).init;
		
		// Handle parameters in the alloca block.
		LLVMPositionBuilderAtEnd(builder, allocaBB);
		
		auto funType = LLVMGetElementType(LLVMTypeOf(fun));
		
		LLVMValueRef[] params;
		LLVMTypeRef[] parameterTypes;
		params.length = parameterTypes.length = f.parameters.length;
		LLVMGetParams(fun, params.ptr);
		LLVMGetParamTypes(funType, parameterTypes.ptr);
		
		foreach(i, p; f.parameters) {
			auto value = params[i];
			
			if(p.isReference) {
				LLVMSetValueName(value, p.name.toStringz());
				
				exprSymbols[p] = value;
			} else {
				auto alloca = LLVMBuildAlloca(builder, parameterTypes[i], p.name.toStringz());
				
				LLVMSetValueName(value, ("arg." ~ p.name).toStringz());
				
				LLVMBuildStore(builder, value, alloca);
				exprSymbols[p] = alloca;
			}
		}
		
		// Generate function's body.
		LLVMPositionBuilderAtEnd(builder, bodyBB);
		pass.visit(f.fbody);
		
		// If the current block isn't concluded, it means that it is unreachable.
		if(!LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(builder))) {
			// FIXME: provide the right AST in case of void function.
			if(LLVMGetTypeKind(LLVMGetReturnType(funType)) == LLVMTypeKind.Void) {
				LLVMBuildRetVoid(builder);
			} else {
				LLVMBuildUnreachable(builder);
			}
		}
		
		// Branch from alloca block to function body.
		LLVMPositionBuilderAtEnd(builder, allocaBB);
		LLVMBuildBr(builder, bodyBB);
	}
	
	LLVMValueRef visit(VariableDeclaration var) {
		auto value = pass.visit(var.value);
		
		if(var.isEnum) {
			return exprSymbols[var] = value;
		}
		
		if(var.isStatic) {
			auto globalVar = LLVMAddGlobal(dmodule, pass.visit(var.type), var.mangle.toStringz());
			LLVMSetThreadLocal(globalVar, true);
			
			// Register the variable.
			exprSymbols[var] = globalVar;
			
			// Store the initial value into the global variable.
			LLVMSetInitializer(globalVar, value);
			
			return globalVar;
		} else {
			// Backup current block
			auto backupCurrentBlock = LLVMGetInsertBlock(builder);
			LLVMPositionBuilderAtEnd(builder, LLVMGetFirstBasicBlock(LLVMGetBasicBlockParent(backupCurrentBlock)));
			
			// Create an alloca for this variable.
			auto type = pass.visit(var.type);
			auto alloca = LLVMBuildAlloca(builder, type, var.mangle.toStringz());
			
			LLVMPositionBuilderAtEnd(builder, backupCurrentBlock);
			
			// Register the variable.
			exprSymbols[var] = alloca;
			
			// Store the initial value into the alloca.
			LLVMBuildStore(builder, value, alloca);
			
			return alloca;
		}
	}
	
	LLVMTypeRef visit(TypeSymbol s) {
		return typeSymbols.get(s, this.dispatch(s));
	}
	
	LLVMTypeRef visit(StructDefinition d) {
		auto llvmStruct = LLVMStructCreateNamed(context, cast(char*) d.mangle.toStringz());
		typeSymbols[d] = llvmStruct;
		
		LLVMTypeRef[] members;
		
		foreach(member; d.members) {
			if(auto f = cast(FieldDeclaration) member) {
				members ~= pass.visit(f.type);
			}
		}
		
		LLVMStructSetBody(llvmStruct, members.ptr, cast(uint) members.length, false);
		
		return llvmStruct;
	}
	
	LLVMTypeRef visit(ClassDeclaration c) {
		auto ret = pass.visit(new ClassType(c.location, c));
		
		foreach(member; c.members) {
			if (auto m = cast(MethodDeclaration) member) {
				genFunctionBody(m);
			}
		}
		
		return ret;
	}
	
	LLVMTypeRef visit(EnumDeclaration d) {
		auto type = typeSymbols[d] = pass.visit(d.type);
		
		foreach(e; d.enumEntries) {
			visit(e);
		}
		
		return type;
	}
	
	LLVMTypeRef visit(AliasDeclaration a) {
		auto llvmType = pass.visit(a.type);
		typeSymbols[a] = llvmType;
		
		return llvmType;
	}
}

