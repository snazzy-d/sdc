module d.llvm.global;

import d.llvm.codegen;

import d.ir.symbol;
import d.ir.type;

import util.visitor;

import llvm.c.analysis;
import llvm.c.core;

struct GlobalGen {
	private CodeGen pass;
	alias pass this;

	import d.llvm.local : Mode;
	Mode mode;

	this(CodeGen pass, Mode mode = Mode.Lazy) {
		this.pass = pass;
		this.mode = mode;
	}

	void define(Symbol s) in(s.step == Step.Processed) {
		if (auto f = cast(Function) s) {
			define(f);
		} else if (auto t = cast(Template) s) {
			define(t);
		} else if (auto a = cast(Aggregate) s) {
			define(a);
		} else if (auto v = cast(Variable) s) {
			define(v);
		}
	}

	LLVMValueRef declare(Function f)
			in(!f.hasContext, "function must not have context") {
		import d.llvm.local;
		return LocalGen(pass).declare(f);
	}

	LLVMValueRef define(Function f)
			in(!f.hasContext, "function must not have context") {
		import d.llvm.local;
		return LocalGen(pass).define(f);
	}

	LLVMValueRef declare(Variable v) in {
		assert(v.storage.isGlobal, "locals not supported");
		assert(!v.isFinal);
		assert(!v.isRef);
	} do {
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
	} do {
		auto var = declare(v);
		if (!v.value || v.storage == Storage.Enum) {
			return var;
		}

		if (!maybeDefine(v, var)) {
			auto linkage = LLVMGetLinkage(var);
			assert(
				linkage == LLVMLinkage.LinkOnceODR,
				"variable " ~ v.mangle.toString(context) ~ " already defined"
			);
			LLVMSetLinkage(var, LLVMLinkage.External);
		}

		return var;
	}

	bool maybeDefine(Variable v, LLVMValueRef var) in {
		assert(v.storage.isGlobal, "locals not supported");
		assert(v.storage != Storage.Enum, "enum do not have a storage");
		assert(!v.isFinal);
		assert(!v.isRef);
	} do {
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
	} do {
		auto qualifier = v.type.qualifier;

		import d.llvm.type;
		auto type = TypeGen(pass).visit(v.type);

		// If it is not enum, it must be static.
		assert(v.storage == Storage.Static);
		auto var = LLVMAddGlobal(dmodule, type, v.mangle.toStringz(context));

		// Depending on the type qualifier,
		// make it thread local/ constant or nothing.
		final switch (qualifier) with (TypeQualifier) {
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

	LLVMTypeRef define(Aggregate a) in(a.step == Step.Processed) {
		import d.llvm.local;
		return LocalGen(pass).define(a);
	}

	void define(Template t) {
		foreach (i; t.instances) {
			if (i.hasThis || i.hasContext) {
				continue;
			}

			foreach (m; i.members) {
				import d.llvm.local;
				LocalGen(pass).define(m);
			}
		}
	}
}
