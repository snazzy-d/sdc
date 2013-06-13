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
	
	this(CodeGenPass pass) {
		this.pass = pass;
	}
	
	void visit(Declaration d) {
		if(auto es = cast(ExpressionSymbol) d) {
			visit(es);
		} else if(auto ts = cast(TypeSymbol) d) {
			visit(ts);
		}
		
		assert(cast(Symbol) d, "Can only generate symbols.");
	}
	
	LLVMValueRef visit(ExpressionSymbol s) {
		return exprSymbols.get(s, this.dispatch(s));
	}
	
	LLVMValueRef visit(FunctionDeclaration f) {
		auto type = pass.visit(f.type);
		
		LLVMValueRef ret, fun;
		if(LLVMGetTypeKind(type) == LLVMTypeKind.Struct) {
			assert(LLVMCountStructElementTypes(type) == 2, "delegate must have 2 fields");
			
			LLVMTypeRef[2] types;
			LLVMGetStructElementTypes(type, types.ptr);
			
			auto funType = LLVMGetElementType(types[0]);
			ret = fun = LLVMAddFunction(dmodule, f.mangle.toStringz(), funType);
			
			if(typeid(f) !is typeid(MethodDeclaration)) {
				ret = LLVMGetUndef(type);
				ret = LLVMBuildInsertValue(builder, ret, fun, 0, "");
			}
		} else {
			auto funType = LLVMGetElementType(type);
			ret = fun = LLVMAddFunction(dmodule, f.mangle.toStringz(), funType);
		}
		
		// Register the function.
		exprSymbols[f] = ret;
		
		if(f.fbody) {
			genFunctionBody(f, fun);
		}
			
		return ret;
	}
	
	LLVMValueRef visit(MethodDeclaration m) {
		return visit(cast(FunctionDeclaration) m);
	}
	
	private void genFunctionBody(FunctionDeclaration f) {
		auto fun = exprSymbols[f];
		if(LLVMGetTypeKind(LLVMTypeOf(fun)) == LLVMTypeKind.Struct) {
			fun = LLVMBuildExtractValue(builder, fun, 0, "");
		}
		
		genFunctionBody(f, fun);
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
		params.length = parameterTypes.length = LLVMCountParamTypes(funType);
		LLVMGetParams(fun, params.ptr);
		LLVMGetParamTypes(funType, parameterTypes.ptr);
		
		// XXX: This is kind of hacky, better can surely be done.
		auto parameters = f.parameters;
		if(auto dg = cast(DelegateType) f.type) {
			parameters = dg.context ~ parameters;
		}
		
		foreach(i, p; parameters) {
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
		return this.dispatch(s);
	}
	
	LLVMTypeRef visit(AliasDeclaration a) {
		return pass.visit(a.type);
	}
	
	LLVMTypeRef visit(StructDeclaration s) {
		auto ret = pass.visit(new StructType(s));
		
		foreach(member; s.members) {
			if(typeid(member) !is typeid(FieldDeclaration)) {
				visit(member);
			}
		}
		
		return ret;
	}
	
	LLVMTypeRef visit(ClassDeclaration c) {
		auto ret = pass.visit(new ClassType(c));
		
		foreach(member; c.members) {
			if (auto m = cast(MethodDeclaration) member) {
				genFunctionBody(m);
			}
		}
		
		return ret;
	}
	
	LLVMTypeRef visit(EnumDeclaration e) {
		auto type = pass.visit(new EnumType(e));
		
		foreach(entry; e.enumEntries) {
			visit(entry);
		}
		
		return type;
	}
}

