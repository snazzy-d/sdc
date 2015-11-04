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
	
	import d.llvm.local : Mode;
	Mode mode;
	
	this(CodeGenPass pass, Mode mode = Mode.Lazy) {
		this.pass = pass;
		this.mode = mode;
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
		assert(!v.isFinal);
		assert(!v.isRef);
	} body {
		auto var = globals.get(v, {
			if (v.storage == Storage.Enum) {
				import d.llvm.constant;
				return ConstantGen(pass).visit(v.value);
			}
			
			return createVariableStorage(v);
		}());
		
		// Register the variable.
		globals[v] = var;
		if (!v.value || v.storage == Storage.Enum) {
			return var;
		}
		
		if (v.inTemplate || mode == Mode.Eager) {
			if (maybeDefine(v, var)) {
				LLVMSetLinkage(var, LLVMLinkage.LinkOnceODR);
			}
		}
		
		return var;
	}
	
	LLVMValueRef define(Variable v) in {
		assert(v.storage.isGlobal, "locals not supported");
		assert(!v.isFinal);
		assert(!v.isRef);
	} body {
		auto var = declare(v);
		if (!v.value || v.storage == Storage.Enum) {
			return var;
		}
		
		if (!maybeDefine(v, var)) {
			auto linkage = LLVMGetLinkage(var);
			assert(linkage == LLVMLinkage.LinkOnceODR, "variable " ~ v.mangle.toString(context) ~ " already defined");
			LLVMSetLinkage(var, LLVMLinkage.External);
		}
		
		return var;
	}
	
	bool maybeDefine(Variable v, LLVMValueRef var) in {
		assert(v.storage.isGlobal, "locals not supported");
		assert(v.storage != Storage.Enum, "enum do not have a storage");
		assert(!v.isFinal);
		assert(!v.isRef);
	} body {
		if (LLVMGetInitializer(var)) {
			return false;
		}
		
		import d.llvm.constant;
		auto value = ConstantGen(pass).visit(v.value);
		
		// Store the initial value into the global variable.
		LLVMSetInitializer(var, value);
		return true;
	}
	
	private LLVMValueRef createVariableStorage(Variable v) in {
		assert(v.storage.isGlobal, "locals not supported");
		assert(v.storage != Storage.Enum, "enum do not have a storage");
	} body {
		auto qualifier = v.type.qualifier;
		auto type = pass.visit(v.type);
		
		// If it is not enum, it must be static.
		assert(v.storage == Storage.Static);
		auto var = LLVMAddGlobal(dmodule, type, v.mangle.toStringz(context));
		
		// Depending on the type qualifier,
		// make it thread local/ constant or nothing.
		final switch(qualifier) with(TypeQualifier) {
			case Mutable, Inout, Const:
				LLVMSetThreadLocal(var, true);
				break;
			
			case Shared, ConstShared:
				break;
			
			case Immutable:
				LLVMSetGlobalConstant(var, true);
				break;
		}
		
		return var;
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
