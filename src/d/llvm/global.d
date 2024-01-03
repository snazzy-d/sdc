module d.llvm.global;

import d.llvm.codegen;

import d.ir.symbol;

import llvm.c.core;

enum Mode {
	Lazy,
	Eager,
}

alias GlobalPass = GlobalGen*;

struct GlobalGen {
	CodeGen pass;
	alias pass this;

	LLVMValueRef[ValueSymbol] globals;

	import d.llvm.local;
	LocalData localData;

	import d.llvm.constant;
	ConstantData constantData;

	import d.llvm.runtime;
	RuntimeData runtimeData;

	import d.llvm.statement;
	StatementGenData statementGenData;

	import d.llvm.intrinsic;
	IntrinsicGenData intrinsicGenData;

	// TODO: Move whatever uses mode in LocalGen here.
	// private:
	Mode mode;

public:
	this(CodeGen pass, string name, Mode mode = Mode.Lazy) {
		this.pass = pass;
		this.mode = mode;

		// Make sure globals are initialized.
		globals[null] = null;
		globals.remove(null);
	}

	void define(Module m) {
		// Dump module content on failure (for debug purpose).
		scope(failure) LLVMDumpModule(dmodule);

		foreach (s; m.members) {
			define(s);
		}

		checkModule();
	}

	auto checkModule() {
		char* errorPtr;

		import llvm.c.analysis;
		if (!LLVMVerifyModule(dmodule, LLVMVerifierFailureAction.ReturnStatus,
		                      &errorPtr)) {
			return;
		}

		scope(exit) LLVMDisposeMessage(errorPtr);

		import core.stdc.string;
		auto error = errorPtr[0 .. strlen(errorPtr)].idup;
		throw new Exception(error);
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
		} else {
			// Some symbol just don't need to generate anything, suck as TypeAlias.
			import std.format;
			assert(true, format!"%s is not supported!"(typeid(s)));
		}
	}

	LLVMValueRef declare(Function f)
			in(!f.hasContext, "Function must not have context!") {
		import d.llvm.local;
		return LocalGen(&this).declare(f);
	}

	LLVMValueRef define(Function f)
			in(!f.hasContext, "Function must not have context!") {
		import d.llvm.local;
		return LocalGen(&this).define(f);
	}

	void define(Template t) {
		foreach (i; t.instances) {
			if (i.hasThis || i.hasContext) {
				continue;
			}

			foreach (m; i.members) {
				import d.llvm.local;
				LocalGen(&this).define(m);
			}
		}
	}

	LLVMTypeRef define(Aggregate a) in(a.step == Step.Processed) {
		import d.llvm.local;
		return LocalGen(&this).define(a);
	}

	LLVMValueRef declare(Variable v) in {
		assert(v.storage.isGlobal, "locals not supported");
		assert(!v.isFinal);
		assert(!v.isRef);
	} do {
		auto var = globals.get(v, {
			if (v.storage == Storage.Enum) {
				import d.llvm.constant;
				return ConstantGen(&this).visit(v.value);
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
			import std.format;
			assert(
				LLVMGetLinkage(var) == LLVMLinkage.LinkOnceODR,
				format!"Variable %s already defined!"(
					v.mangle.toString(context))
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
		auto value = ConstantGen(&this).visit(v.value);

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
}
