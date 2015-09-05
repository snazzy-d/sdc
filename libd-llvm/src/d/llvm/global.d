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
	
	void visit(Symbol s) {
		if (auto t = cast(TypeSymbol) s) {
			visit(t);
		} else if (auto v = cast(Variable) s) {
			visit(v);
		} else if (auto f = cast(Function) s) {
			visit(f);
		}
	}
	
	LLVMValueRef visit(Function f) in {
		assert(f.storage.isGlobal, "locals not supported");
		assert(!f.hasContext, "function must not have context");
	} body {
		return globals.get(f, define(f));
	}
	
	LLVMValueRef define(Function f) in {
		assert(f.storage.isGlobal, "locals not supported");
	} body {
		import d.llvm.local;
		auto lg = LocalGen(pass);
		auto fun = lg.declare(f);
		
		// Register the function.
		globals[f] = fun;
		
		// We always generate the body for now, but it is very undesirable.
		// FIXME: Separate symbol declaration from symbol definition.
		if (f.fbody) {
			lg.define(f, fun);
		}
		
		return fun;
	}
	
	LLVMValueRef visit(Variable v) in {
		assert(v.storage.isGlobal, "locals not supported");
	} body {
		return globals.get(v, define(v));
	}
	
	LLVMValueRef define(Variable v) in {
		assert(v.storage.isGlobal, "locals not supported");
		assert(!v.isFinal);
		assert(!v.isRef);
	} body {
		import d.llvm.local;
		auto lg = LocalGen(pass);

		// FIXME: This should only generate const using the const API.
		// That way no need for a builder and/or LocalGen.
		import d.llvm.expression;
		auto value = ExpressionGen(&lg).visit(v.value);
		
		return createVariableStorage(v, value);
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
	
	LLVMTypeRef visit(TypeSymbol s) in {
		assert(s.step == Step.Processed);
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
		
		foreach(member; s.members) {
			if (typeid(member) !is typeid(Field)) {
				visit(member);
			}
		}
		
		return ret;
	}
	
	LLVMTypeRef visit(Union u) in {
		assert(u.step == Step.Processed);
	} body {
		auto ret = buildUnionType(u);
		
		foreach(member; u.members) {
			if (typeid(member) !is typeid(Field)) {
				visit(member);
			}
		}
		
		return ret;
	}
	
	LLVMTypeRef visit(Class c) in {
		assert(c.step == Step.Processed);
	} body {
		auto ret = buildClassType(c);
		
		foreach(member; c.members) {
			if (auto m = cast(Method) member) {
				// FIXME: separate declaration and definition.
				auto fun = visit(m);
				if (LLVMCountBasicBlocks(fun) == 0) {
					import d.llvm.local;
					LocalGen(pass).define(m, fun);
				}
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
}

