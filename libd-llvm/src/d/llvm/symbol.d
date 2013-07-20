module d.llvm.symbol;

import d.llvm.codegen;

import d.ir.symbol;
import d.ir.type;

import util.visitor;

import llvm.c.analysis;
import llvm.c.core;

import std.algorithm;
import std.array;
import std.string;

final class SymbolGen {
	private CodeGenPass pass;
	alias pass this;
	
	private LLVMValueRef[ValueSymbol] valueSymbols;
	
	this(CodeGenPass pass) {
		this.pass = pass;
	}
	
	void visit(Symbol s) {
		if(auto v = cast(ValueSymbol) s) {
			visit(v);
		} else if(auto t = cast(TypeSymbol) s) {
			visit(t);
		}
	}
	
	LLVMValueRef visit(ValueSymbol s) {
		return valueSymbols.get(s, this.dispatch(s));
	}
	
	LLVMValueRef visit(Function f) {
		auto type = pass.visit(f.type);
		
		LLVMValueRef ret, fun;
		if(LLVMGetTypeKind(type) == LLVMTypeKind.Struct) {
			assert(LLVMCountStructElementTypes(type) == 2, "delegate must have 2 fields");
			
			LLVMTypeRef[2] types;
			LLVMGetStructElementTypes(type, types.ptr);
			
			auto funType = LLVMGetElementType(types[0]);
			ret = fun = LLVMAddFunction(dmodule, f.mangle.toStringz(), funType);
			
			if(typeid(f) !is typeid(Method)) {
				ret = LLVMGetUndef(type);
				ret = LLVMBuildInsertValue(builder, ret, fun, 0, "");
			}
		} else {
			auto funType = LLVMGetElementType(type);
			ret = fun = LLVMAddFunction(dmodule, f.mangle.toStringz(), funType);
		}
		
		// Register the function.
		valueSymbols[f] = ret;
		
		if(f.fbody) {
			genFunctionBody(f, fun);
		}
		
		return ret;
	}
	
	LLVMValueRef visit(Method m) {
		return visit(cast(Function) m);
	}
	
	private void genFunctionBody(Function f) {
		auto fun = valueSymbols[f];
		if(LLVMGetTypeKind(LLVMTypeOf(fun)) == LLVMTypeKind.Struct) {
			fun = LLVMBuildExtractValue(builder, fun, 0, "");
		}
		
		genFunctionBody(f, fun);
	}
	
	private void genFunctionBody(Function f, LLVMValueRef fun) {
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
		LLVMTypeRef[] paramTypes;
		params.length = paramTypes.length = LLVMCountParamTypes(funType);
		LLVMGetParams(fun, params.ptr);
		LLVMGetParamTypes(funType, paramTypes.ptr);
		
		auto parameters = f.params;
		/+
		// XXX: This is kind of hacky, better can surely be done.
		if(auto dg = cast(DelegateType) f.type) {
			parameters = dg.context ~ parameters;
		}
		+/
		foreach(i, p; parameters) {
			auto value = params[i];
			
			if(p.pt.isRef) {
				LLVMSetValueName(value, p.name.toStringz());
				
				valueSymbols[p] = value;
			} else {
				auto alloca = LLVMBuildAlloca(builder, paramTypes[i], p.name.toStringz());
				
				LLVMSetValueName(value, ("arg." ~ p.name).toStringz());
				
				LLVMBuildStore(builder, value, alloca);
				valueSymbols[p] = alloca;
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
	
	LLVMValueRef visit(Variable var) {
		auto value = pass.visit(var.value);
		
		if(var.isEnum) {
			return valueSymbols[var] = value;
		}
		
		if(var.isStatic) {
			auto globalVar = LLVMAddGlobal(dmodule, pass.visit(var.type), var.mangle.toStringz());
			LLVMSetThreadLocal(globalVar, true);
			
			// Register the variable.
			valueSymbols[var] = globalVar;
			
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
			valueSymbols[var] = alloca;
			
			// Store the initial value into the alloca.
			LLVMBuildStore(builder, value, alloca);
			
			return alloca;
		}
	}
	
	LLVMTypeRef visit(TypeSymbol s) {
		return this.dispatch(s);
	}
	
	LLVMTypeRef visit(TypeAlias a) {
		return pass.visit(a.type);
	}
	
	LLVMTypeRef visit(Struct s) {
		auto ret = pass.visit(new StructType(s));
		
		foreach(member; s.members) {
			if(typeid(member) !is typeid(Field)) {
				visit(member);
			}
		}
		
		return ret;
	}
	
	LLVMTypeRef visit(Class c) {
		auto ret = pass.visit(new ClassType(c));
		
		foreach(member; c.members) {
			if (auto m = cast(Method) member) {
				/+
				genFunctionBody(m);
				+/
			}
		}
		
		return ret;
	}
	
	LLVMTypeRef visit(Enum e) {
		auto type = pass.visit(new EnumType(e));
		/+
		foreach(entry; e.entries) {
			visit(entry);
		}
		+/
		return type;
	}
}

