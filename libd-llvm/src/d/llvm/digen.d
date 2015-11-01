module d.llvm.digen;

import d.llvm.codegen;
import d.llvm.local;

import d.context.source;

import d.ir.dscope;
import d.ir.symbol;
import d.ir.type;

import d.exception;

import util.visitor;

import llvm.c.core;

// Conflict with Interface in object.di
alias Interface = d.ir.symbol.Interface;

struct DIData {
private:
	LLVMDIBuilderRef diBuilder;
	LLVMMetadataRef compileUnit;
	
	LLVMMetadataRef[Scope] scopes;
	
	DIFiles files;
	DIFiles mixins;
	
public:
	void enableDebug(LLVMModuleRef dmodule) in {
		assert(diBuilder is null);
	} body {
		diBuilder = LLVMCreateDIBuilder(dmodule);
		compileUnit = LLVMDICreateCompileUnit(
			diBuilder,
			0x0013, // DW_LANG_D
			"merde",
			"/fuck",
			"SDC",
			false, // isOptimized
			"", // Flags
			0, // RV ??? Runtime Version ?!??
			"", // SplitName ???
		);
	}
	
	void finalize() {
		if (diBuilder is null) {
			return;
		}
		
		LLVMFinalizeDIBuilder(diBuilder);
		LLVMDisposeDIBuilder(diBuilder);
		diBuilder = null;
	}
	
	~this() {
		assert(diBuilder is null, "Debug infos aren't finalized");
	}
	
	LLVMMetadataRef createDIFile(Source source) {
		return source.isFile()
			? files.createDIFile(diBuilder, source)
			: mixins.createDIFile(diBuilder, source);
	}
}

struct DIFiles {
	LLVMMetadataRef[] diFiles;
	
	LLVMMetadataRef createDIFile(LLVMDIBuilderRef diBuilder, Source source) {
		if (diFiles.length <= source) {
			diFiles.length = source + 1;
		}
		
		if (diFiles[source] !is null) {
			return diFiles[source];
		}
		
		return diFiles[source] = LLVMDICreateFile(
			diBuilder,
			source.getFileName().toStringz(),
			source.getDirectory().toStringz(),
		);
	}
}

struct DIGlobalGen {
	private CodeGen pass;
	alias pass this;
	
	LLVMMetadataRef diScope;
	
	this(CodeGen pass, LLVMMetadataRef diScope) {
		this.pass = pass;
		this.diScope = diScope;
	}
	
	@property diBuilder() {
		return diData.diBuilder;
	}
	
	void declare(Variable v, LLVMValueRef var) in {
		assert(v.storage == Storage.Static);
	} body {
		auto location = v.getFullLocation(context);
		LLVMDICreateGlobalVariable(
			diBuilder,
			diScope,
			v.name.toStringz(context),
			v.mangle.toStringz(context),
			diData.createDIFile(location.getSource()),
			location.getStartLineNumber(),
			DITypeGen(pass).visit(v.type),
			true, // isLocalToUnit
			var,
			null, // Decl
		);
	}
}

struct DIVariableGen {
	private LocalPass pass;
	alias pass this;
	
	this(LocalPass pass) {
		this.pass = pass;
	}
	
	@property diBuilder() {
		return diData.diBuilder;
	}
	
	void declare(Variable v, LLVMValueRef storage) in {
		assert(v.storage == Storage.Local);
	} body {
		auto location = v.location.getFullLocation(context);
		auto startLine = location.getStartLineNumber();
		auto diVariable = LLVMDICreateAutoVariable(
			diBuilder,
			diScope,
			v.name.toStringz(context),
			diData.createDIFile(location.getSource()),
			startLine,
			DITypeGen(pass.pass).visit(v.type),
			false, // alwaysPreserve
			0, // Flags
		);
		
		LLVMDIInsertDeclareAtEnd(
			diBuilder,
			storage,
			diVariable,
			LLVMDICreateExpression(diBuilder),
			LLVMGetDILocationInContext(llvmCtx, startLine, 0, diScope),
			LLVMGetInsertBlock(builder),
		);
	}
	
	void declare(Variable p, uint index, LLVMValueRef storage) in {
		assert(p.storage.isLocal);
	} body {
		auto location = p.location.getFullLocation(context);
		auto startLine = location.getStartLineNumber();
		
		auto diParam = LLVMDICreateParameterVariable(
			diBuilder,
			diScope,
			p.name.toStringz(context),
			index,
			diData.createDIFile(location.getSource()),
			startLine,
			DITypeGen(pass.pass).visit(p.type),
			false, // AlwaysPreserve
			0, // Flags
		);
		
		LLVMDIInsertDeclareAtEnd(
			diBuilder,
			storage,
			diParam,
			LLVMDICreateExpression(diBuilder),
			LLVMGetDILocationInContext(llvmCtx, startLine, 0, diScope),
			LLVMGetInsertBlock(builder),
		);
	}
}

struct DIScopeGen {
	private CodeGen pass;
	alias pass this;
	
	this(CodeGen pass) {
		this.pass = pass;
	}
	
	@property diBuilder() {
		return diData.diBuilder;
	}
	
	@property
	ref scopes() {
		return diData.scopes;
	}
	
	LLVMMetadataRef visit(Scope s) {
		if (auto sym = cast(Symbol) s) {
			return visit(sym);
		}
		
		if (auto ns = cast(NestedScope) s) {
			return visit(ns);
		}
		
		auto o = cast(Object) s;
		assert(0, "Unknown scope: " ~ typeid(o).toString());
	}
	
	LLVMMetadataRef define(S)(S s) if (is(S : Scope) && is(S : Symbol)) {
		if (diBuilder is null) {
			return null;
		}
		
		return visit(s);
	}
	
	LLVMMetadataRef visit(NestedScope ns) {
		/+
		return LLVMDICreateLexicalBlock(
			diBuilder,
			visit(ns.getParentScope()),
			diData.getFile(),
		);
		// +/
		return visit(ns.getParentScope());
	}
	
	LLVMMetadataRef visit(Symbol s) {
		return this.dispatch(s);
	}
	
	LLVMMetadataRef visit(Module m) {
		auto source = m.location.getFullLocation(context).getSource();
		return diData.createDIFile(source);
	}
	
	LLVMMetadataRef visit(Function f) in {
		assert(f.step >= Step.Signed);
	} body {
		if (auto sPtr = f in scopes) {
			return *sPtr;
		}
		
		auto location = f.getFullLocation(context);
		return scopes[f] = LLVMDICreateFunction(
			diBuilder,
			DIScopeGen(pass).visit(f.getParentScope()),
			f.name.toStringz(context),
			f.mangle.toStringz(context),
			diData.createDIFile(location.getSource()),
			location.getStartLineNumber(),
			DITypeGen(pass).visit(f.type),
			true, // isLocalToUnit
			true, // isDefinition
			location.getStartLineNumber(), // ScopeLine ???
			0, // Flags
			false, // isOptimized
			null, // Template parameters
			null, // No idea
		);
	}
	
	LLVMMetadataRef visit(Struct s) in {
		assert(s.step >= Step.Signed);
	} body {
		if (auto sPtr = s in scopes) {
			return *sPtr;
		}
		
		auto location = s.getFullLocation(context);
		return scopes[s] = LLVMDICreateStructType(
			diBuilder,
			visit(s.getParentScope()),
			s.name.toStringz(context),
			diData.createDIFile(location.getSource()),
			location.getStartLineNumber(),
			0, // Size
			0, // Align
			0, // Flags
			null, // Derived from
			LLVMMDNodeInContext(llvmCtx, null, 0), // Elements
			0x0013, // DW_LANG_D
			null, // VTableHolder
			s.mangle.toStringz(context),
		);
	}
	
	LLVMMetadataRef visit(Union u) in {
		assert(u.step >= Step.Signed);
	} body {
		if (auto sPtr = u in scopes) {
			return *sPtr;
		}
		
		auto location = u.getFullLocation(context);
		return scopes[u] = LLVMDICreateUnionType(
			diBuilder,
			visit(u.getParentScope()),
			u.name.toStringz(context),
			diData.createDIFile(location.getSource()),
			location.getStartLineNumber(),
			0, // Size
			0, // Align
			0, // Flags
			LLVMMDNodeInContext(llvmCtx, null, 0), // Elements
			0x0013, // DW_LANG_D
			u.mangle.toStringz(context),
		);
	}
	
	LLVMMetadataRef visit(Class c) {
		if (auto sPtr = c in scopes) {
			return *sPtr;
		}
		
		LLVMMetadataRef base;
		if (c !is c.base) {
			base = visit(c.base);
		}
		
		auto location = c.getFullLocation(context);
		return scopes[c] = LLVMDICreateClassType(
			diBuilder,
			visit(c.getParentScope()),
			c.name.toStringz(context),
			diData.createDIFile(location.getSource()),
			location.getStartLineNumber(),
			0, // Size
			0, // Align
			0, // Offset
			0, // Flags
			base, // Derived from
			LLVMMDNodeInContext(llvmCtx, null, 0), // Elements
			null, // VTableHolder
			null, // TemplateParms
			c.mangle.toStringz(context),
		);
	}
	
	LLVMMetadataRef visit(TemplateInstance ti) {
		// FIXME: do :)
		return visit(ti.getParentScope());
	}
	
	LLVMMetadataRef visit(Template t) {
		// FIXME: do :)
		return visit(t.getParentScope());
	}
	
}

struct DITypeGen {
	private CodeGen pass;
	alias pass this;
	
	this(CodeGen pass) {
		this.pass = pass;
	}
	
	@property diBuilder() {
		return diData.diBuilder;
	}
	
	LLVMMetadataRef visit(Type t) {
		return t.accept(this);
	}
	
	auto visit(ParamType pt) {
		auto t = visit(pt.getType());
		if (pt.isRef) {
			t = LLVMDICreateReferenceType(diBuilder, 0, t);
		}
		
		return t;
	}
	
	LLVMMetadataRef visit(BuiltinType t) {
		final switch(t) with(BuiltinType) {
			case None :
				assert(0, "Not Implemented");
			
			case Void :
				return LLVMDICreateBasicType(diBuilder, "void", 0, 0, 0);
			
			case Bool :
				return LLVMDICreateBasicType(diBuilder, "bool", 8, 8, 0);
			
			case Char :
				return LLVMDICreateBasicType(diBuilder, "char", 8, 8, 0);
			
			case Ubyte :
				return LLVMDICreateBasicType(diBuilder, "ubyte", 8, 8, 0);
			
			case Byte :
				return LLVMDICreateBasicType(diBuilder, "byte", 8, 8, 0);
			
			case Wchar :
				return LLVMDICreateBasicType(diBuilder, "wchar", 16, 16, 0);
			
			case Ushort :
				return LLVMDICreateBasicType(diBuilder, "ushort", 16, 16, 0);
			
			case Short :
				return LLVMDICreateBasicType(diBuilder, "short", 16, 16, 0);
			
			case Dchar :
				return LLVMDICreateBasicType(diBuilder, "dchar", 32, 32, 0);
			
			case Uint :
				return LLVMDICreateBasicType(diBuilder, "uint", 32, 32, 0);
			
			case Int :
				return LLVMDICreateBasicType(diBuilder, "int", 32, 32, 0);
			
			case Ulong :
				return LLVMDICreateBasicType(diBuilder, "ulong", 64, 64, 0);
			
			case Long :
				return LLVMDICreateBasicType(diBuilder, "long", 64, 64, 0);
			
			case Ucent :
				return LLVMDICreateBasicType(diBuilder, "ucent", 128, 64, 0);
			
			case Cent :
				return LLVMDICreateBasicType(diBuilder, "cent", 128, 64, 0);
			
			case Float :
				return LLVMDICreateBasicType(diBuilder, "float", 32, 32, 0);
			
			case Double :
				return LLVMDICreateBasicType(diBuilder, "double", 64, 64, 0);
			
			case Real :
				assert(0, "Not Implemented");
			
			case Null :
				return LLVMDICreateNullPtrType(diBuilder);
		}
	}
	
	LLVMMetadataRef visitPointerOf(Type t) {
		return LLVMDICreatePointerType(diBuilder, visit(t), 0, 0, "");
	}
	
	LLVMMetadataRef visitSliceOf(Type t) {
		return LLVMDICreateUnspecifiedType(diBuilder, "slice[]");
	}
	
	LLVMMetadataRef visitArrayOf(uint size, Type t) {
		return LLVMDICreateArrayType(
			diBuilder,
			size,
			0,
			visit(t),
			LLVMMDNodeInContext(llvmCtx, null, 0),
		); // Subscript ??!?
	}
	
	LLVMMetadataRef visit(Struct s) in {
		assert(s.step >= Step.Signed);
	} body {
		return DIScopeGen(pass).visit(s);
	}
	
	LLVMMetadataRef visit(Union u) in {
		assert(u.step >= Step.Signed);
	} body {
		return DIScopeGen(pass).visit(u);
	}
	
	LLVMMetadataRef visit(Class c) in {
		assert(c.step >= Step.Signed);
	} body {
		auto diClassPtr = LLVMDICreatePointerType(
			diBuilder,
			DIScopeGen(pass).visit(c),
			0,
			0,
			"",
		);
		
		return LLVMDICreateObjectPointerType(diBuilder, diClassPtr);
	}
	
	LLVMMetadataRef visit(Enum e) {
		auto location = e.getFullLocation(context);
		return LLVMDICreateEnumerationType(
			diBuilder,
			DIScopeGen(pass).visit(e.getParentScope()),
			e.name.toStringz(context),
			diData.createDIFile(location.getSource()),
			location.getStartLineNumber(),
			0, // Size
			0, // Align
			LLVMMDNodeInContext(llvmCtx, null, 0), // Elements
			visit(e.type),
			e.mangle.toStringz(context),
		);
	}
	
	LLVMMetadataRef visit(TypeAlias a) {
		// FIXME: This shoudl be a temp node, maybe ?
		auto location = a.getFullLocation(context);
		return LLVMDICreateTypedef(
			diBuilder,
			visit(a.type),
			a.name.toStringz(context),
			diData.createDIFile(location.getSource()),
			location.getStartLineNumber(),
			// FIXME: This scope is obviously incorrect.
			diData.createDIFile(location.getSource()),
		);
	}
	
	LLVMMetadataRef visit(Interface i) {
		return LLVMDICreateUnspecifiedType(diBuilder, "interface");
	}
	
	LLVMMetadataRef visit(Function f) in {
		assert(f.step >= Step.Signed);
	} body {
		return LLVMDICreateUnspecifiedType(diBuilder, "__ctxType");
	}
	
	LLVMMetadataRef visit(FunctionType f) {
		if (f.contexts.length) {
			return LLVMDICreateUnspecifiedType(
				diBuilder,
				"delegate()",
			);
		}
		
		import std.algorithm, std.array;
		auto params = f.parameters.map!(p => visit(p)).array();
		
		return LLVMDICreateSubroutineType(
			diBuilder,
			LLVMMDNodeInContext(llvmCtx, params.ptr, cast(uint) params.length),
			0, // Flags
		);
	}
	
	LLVMMetadataRef visit(Type[] seq) {
		assert(0, "Sequence type can't be generated.");
	}
	
	LLVMMetadataRef visit(TypeTemplateParameter p) {
		assert(0, "Template type can't be generated.");
	}
	
	import d.ir.error;
	LLVMMetadataRef visit(CompileError e) {
		assert(0, "Error type can't be generated.");
	}
}
