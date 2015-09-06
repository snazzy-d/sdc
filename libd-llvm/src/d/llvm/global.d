module d.llvm.global;

import d.llvm.codegen;

import d.ir.symbol;
import d.ir.type;

import util.visitor;

import llvm.c.analysis;
import llvm.c.core;

// Conflict with Interface in object.di
alias Interface = d.ir.symbol.Interface;

struct GlobalGen {
	private CodeGenPass pass;
	alias pass this;
	
	this(CodeGenPass pass) {
		this.pass = pass;
	}
	
	void define(Symbol s) {
		if (auto t = cast(TypeSymbol) s) {
			define(t);
		} else if (auto v = cast(Variable) s) {
			define(v);
		} else if (auto f = cast(Function) s) {
			define(f);
		} else if (auto t = cast(Template) s) {
			define(t);
		}
	}
	
	LLVMValueRef declare(Function f) in {
		assert(f.storage.isGlobal, "locals not supported");
		assert(!f.hasContext, "function must not have context");
	} body {
		import d.llvm.local;
		return LocalGen(pass).declare(f);
	}
	
	LLVMValueRef define(Function f) in {
		assert(f.storage.isGlobal, "locals not supported");
		assert(!f.hasContext, "function must not have context");
	} body {
		import d.llvm.local;
		return LocalGen(pass).define(f);
	}
	
	LLVMValueRef declare(Variable v) in {
		assert(v.storage.isGlobal, "locals not supported");
	} body {
		// TODO: Actually just declare here :)
		return globals.get(v, define(v));
	}
	
	LLVMValueRef define(Variable v) in {
		assert(v.storage.isGlobal, "locals not supported");
		assert(!v.isFinal);
		assert(!v.isRef);
	} body {
		return globals.get(v, {
			import d.llvm.local;
			auto lg = LocalGen(pass);

			// FIXME: This should only generate const using the const API.
			// That way no need for a builder and/or LocalGen.
			import d.llvm.expression;
			auto value = ExpressionGen(&lg).visit(v.value);
			
			return createVariableStorage(v, value);
		}());
	}
	
	private LLVMValueRef createVariableStorage(Variable v, LLVMValueRef value) in {
		assert(v.storage.isGlobal, "locals not supported");
	} body {
		if (v.storage == Storage.Enum) {
			return globals[v] = value;
		}
		
		auto qualifier = v.type.qualifier;
		auto type = pass.visit(v.type);

		// If it is not enum, it must be static.
		assert(v.storage == Storage.Static);

		import std.string;
		auto globalVar = LLVMAddGlobal(dmodule, type, v.mangle.toStringz());
		
		// Symbolgenerated from templates and for JITing should linkonce.
		// Other should not, but we lack a good way to make the different ATM.
		LLVMSetLinkage(globalVar, LLVMLinkage.LinkOnceODR);
		
		// Depending on the type qualifier,
		// make it thread local/ constant or nothing.
		final switch(qualifier) with(TypeQualifier) {
			case Mutable, Inout, Const:
				LLVMSetThreadLocal(globalVar, true);
				break;

			case Shared, ConstShared:
				break;

			case Immutable:
				LLVMSetGlobalConstant(globalVar, true);
				break;
		}
		
		// Store the initial value into the global variable.
		LLVMSetInitializer(globalVar, value);

		// Register the variable.
		return globals[v] = globalVar;
	}
	
	LLVMTypeRef define(TypeSymbol s) in {
		assert(s.step == Step.Processed);
		assert(!s.hasContext || s in embededContexts, "context is not set properly");
	} body {
		return this.dispatch(s);
	}
	
	LLVMTypeRef visit(TypeAlias a) in {
		assert(a.step == Step.Processed);
	} body {
		return pass.visit(a.type);
	}
	
	LLVMTypeRef visit(Struct s) in {
		assert(s.step == Step.Processed);
	} body {
		auto ret = buildStructType(s);
		
		foreach(m; s.members) {
			if (typeid(m) !is typeid(Field)) {
				define(m);
			}
		}
		
		return ret;
	}
	
	LLVMTypeRef visit(Union u) in {
		assert(u.step == Step.Processed);
	} body {
		auto ret = buildUnionType(u);
		
		foreach(m; u.members) {
			if (typeid(m) !is typeid(Field)) {
				define(m);
			}
		}
		
		return ret;
	}
	
	LLVMTypeRef visit(Class c) in {
		assert(c.step == Step.Processed);
	} body {
		auto ret = buildClassType(c);
		
		foreach(m; c.members) {
			if (auto f = cast(Method) m) {
				// We don't want to define inherited methods in childs.
				if (!f.hasThis || f.type.parameters[0].getType().dclass is c) {
					define(f);
				}
				
				continue;
			}
			
			if (typeid(m) !is typeid(Field)) {
				define(m);
			}
		}
		
		return ret;
	}
	
	LLVMTypeRef visit(Interface i) in {
		assert(i.step == Step.Processed);
	} body {
		return buildInterfaceType(i); 
	}
	
	LLVMTypeRef visit(Enum e) {
		auto type = buildEnumType(e);
		/+
		foreach(entry; e.entries) {
			visit(entry);
		}
		+/
		return type;
	}

	void define(Template t) {
		import d.llvm.local;
		foreach(i; t.instances) {
			if (i.storage.isLocal) {
				continue;
			}
			
			foreach(m; i.members) {
				LocalGen(pass).define(m);
			}
		}
	}
}
