module d.llvm.debuginfo;

import d.ir.dscope;
import d.ir.symbol;
import d.ir.type;

import d.llvm.codegen;
import d.llvm.global;
import d.llvm.type;

import source.location;
import source.manager;

import util.visitor;

import llvm.c.core;
import llvm.c.debugInfo;
import llvm.c.target;

// Conflict with Interface in object.di
alias Interface = d.ir.symbol.Interface;

struct DebugInfoData {
	LLVMDIBuilderRef builder;
	LLVMMetadataRef compileUnit;

	LLVMMetadataRef[Symbol] symbolScopes;

	LLVMMetadataRef[] files;
	LLVMMetadataRef[] mixins;

	void create(LLVMModuleRef dmodule, Source main) {
		builder = LLVMCreateDIBuilderDisallowUnresolved(dmodule);

		auto file = getFile(main);

		enum Producer = "The Snazzy D compiler.";
		enum Flags = "";
		enum DebugFile = "";
		enum SysRoot = "";
		enum SDK = "";

		compileUnit = LLVMDIBuilderCreateCompileUnit(
			builder,
			LLVMDWARFSourceLanguage.D,
			file,
			Producer.ptr,
			Producer.length,
			false, // LLVMBool isOptimized
			Flags.ptr,
			Flags.length,
			0, // uint RuntimeVer
			DebugFile.ptr,
			DebugFile.length,
			LLVMDWARFEmissionKind.Full,
			0, // uint DWOId
			false, // LLVMBool SplitDebugInlining
			false, // LLVMBool DebugInfoForProfiling
			SysRoot.ptr,
			SysRoot.length,
			SDK.ptr,
			SDK.length,
		);
	}

	void finalize() {
		if (builder) {
			LLVMDIBuilderFinalize(builder);
		}
	}

	void dispose() {
		if (builder) {
			LLVMDisposeDIBuilder(builder);
		}
	}

	/**
	 * FIXME: We need to generate files from DebugLocation instead of Source.
	 *        This ensures that no in contract is required and ensure line
	 *        directives works as expected.
	 */
	auto getFile(Source source) in(source.isFile()) {
		if (files.length <= source) {
			/**
			 * We might waste a few entries for things such as config file
			 * parsed during startup, but the direct lookup we get out of it
			 * is very much worth it.
			 */
			files.length = source + 1;
		}

		if (files[source] !is null) {
			return files[source];
		}

		auto filename = source.getFileName().toString();
		auto directory = source.getDirectory().toString();
		auto file =
			LLVMDIBuilderCreateFile(builder, filename.ptr, filename.length,
			                        directory.ptr, directory.length);

		return files[source] = file;
	}
}

struct DebugInfoScopeGen {
	GlobalPass pass;
	alias pass this;

	this(GlobalPass pass) {
		this.pass = pass;
	}

	@property
	auto builder() {
		return debugInfoData.builder;
	}

	@property
	ref symbolScopes() {
		return debugInfoData.symbolScopes;
	}

	struct FileLine {
		LLVMMetadataRef file;
		uint line;
	}

	auto getFile(Location location) {
		auto source = location.getFullLocation(context).getSource();
		return debugInfoData.getFile(source);
	}

	auto getFileAndLine(Location location) {
		auto floc = location.getFullLocation(context);
		auto file = debugInfoData.getFile(floc.getSource());
		auto line = floc.start.getDebugLocation().line;

		return FileLine(file, line);
	}

	LLVMMetadataRef define(S)(S s) if (is(S : Scope) && is(S : Symbol)) {
		if (builder is null) {
			return null;
		}

		return visit(s);
	}

	LLVMMetadataRef visit(Scope s) {
		if (auto sym = cast(Symbol) s) {
			return visit(sym);
		}

		if (auto ns = cast(NestedScope) s) {
			assert(0, "Nested scopes are not supported!");
		}

		import std.format;
		assert(0, format!"Unknown scope: %s."(typeid(cast(Object) s)));
	}

	LLVMMetadataRef visit(Symbol s) {
		return this.dispatch(s);
	}

	LLVMMetadataRef visit(Module m) {
		if (auto mPtr = m in symbolScopes) {
			return *mPtr;
		}

		auto file = getFile(m.location);
		auto name = m.name.toString(context);

		enum Macros = "";
		enum IncludePath = "";
		enum APINotesFile = "";

		return symbolScopes[m] = LLVMDIBuilderCreateModule(
			builder,
			file,
			name.ptr,
			name.length,
			Macros.ptr,
			Macros.length,
			IncludePath.ptr,
			IncludePath.length,
			APINotesFile.ptr,
			APINotesFile.length,
		);
	}

	LLVMMetadataRef visit(Function f) {
		if (auto fPtr = f in symbolScopes) {
			return *fPtr;
		}

		auto type = DebugInfoTypeGen(pass).visit(f.type);

		auto fl = getFileAndLine(f.location);
		auto name = f.name.toString(context);
		auto link = f.mangle.toString(context);

		return symbolScopes[f] = LLVMDIBuilderCreateFunction(
			builder,
			visit(f.getParentScope()),
			name.ptr,
			name.length,
			link.ptr,
			link.length,
			fl.file,
			fl.line,
			type,
			false, // LLVMBool IsLocalToUnit
			true, // LLVMBool IsDefinition
			0, // uint ScopeLine
			LLVMDIFlags.Zero, // LLVMDIFlags Flags
			false, // LLVMBool IsOptimized
		);
	}

	LLVMMetadataRef getField(Field f, LLVMMetadataRef tmp, ref ulong offset) {
		auto fl = getFileAndLine(f.location);
		auto name = f.name.toString(context);

		auto t = f.type;
		auto type = DebugInfoTypeGen(pass).visit(t);
		auto size = LLVMDITypeGetSizeInBits(type);
		auto dalign = LLVMDITypeGetAlignInBits(type);

		// Bump the offset to ensure proper alignment.
		offset += dalign - 1;
		offset &= -dalign;

		scope(success) offset += size;
		return LLVMDIBuilderCreateMemberType(
			builder, tmp, name.ptr, name.length, fl.file, fl.line, size, dalign,
			offset, LLVMDIFlags.Zero, type);
	}

	LLVMMetadataRef visit(Struct s) {
		if (auto sPtr = s in symbolScopes) {
			return *sPtr;
		}

		// Generating the parent scope might trigger this struct's generation.
		auto parentScope = visit(s.getParentScope());
		if (auto sPtr = s in symbolScopes) {
			return *sPtr;
		}

		auto fl = getFileAndLine(s.location);
		auto name = s.name.toString(context);
		auto mangle = s.mangle.toString(context);

		auto type = typeGen.visit(s);
		auto size = 8 * LLVMABISizeOfType(targetData, type);
		auto dalign = 8 * LLVMABIAlignmentOfType(targetData, type);

		// Make sure we have a temporary composite to refer to in case we need it.
		auto tmp = symbolScopes[s] = LLVMTemporaryMDNode(llvmCtx, null, 0);

		LLVMMetadataRef[] elements;
		elements.length = s.fields.length;

		ulong offset = 0;
		foreach (i, f; s.fields) {
			elements[i] = getField(f, tmp, offset);
		}

		auto ret = symbolScopes[s] = LLVMDIBuilderCreateStructType(
			builder,
			parentScope,
			name.ptr,
			name.length,
			fl.file,
			fl.line,
			size,
			dalign,
			LLVMDIFlags.Zero,
			null, // LLVMMetadataRef DerivedFrom
			elements.ptr,
			cast(uint) elements.length,
			0, // uint RunTimeLang
			null, // LLVMMetadataRef VTableHolder
			mangle.ptr,
			mangle.length,
		);

		// Now we swap our temporary for the real thing.
		LLVMMetadataReplaceAllUsesWith(tmp, ret);
		return ret;
	}

	LLVMMetadataRef visit(Class c) {
		if (auto cPtr = c in symbolScopes) {
			return *cPtr;
		}

		// Generating the parent scope might trigger this class's generation.
		auto parentScope = visit(c.getParentScope());
		if (auto cPtr = c in symbolScopes) {
			return *cPtr;
		}

		auto fl = getFileAndLine(c.location);
		auto name = c.name.toString(context);
		auto mangle = c.mangle.toString(context);

		auto type = typeGen.getClassStructure(c);
		auto size = 8 * LLVMABISizeOfType(targetData, type);
		auto dalign = 8 * LLVMABIAlignmentOfType(targetData, type);

		// Make sure we have a temporary composite to refer to in case we need it.
		auto tmp = symbolScopes[c] = LLVMTemporaryMDNode(llvmCtx, null, 0);

		auto baseFieldCount = c.base.fields.length;
		auto base = visit(c.base);

		LLVMMetadataRef[] elements;
		elements.length = c.fields.length - baseFieldCount + 1;

		if (c is c.base) {
			assert(elements.length == 1);

			ulong offset = 0;
			elements[0] = getField(c.fields[0], tmp, offset);
		} else {
			elements[0] = LLVMDIBuilderCreateInheritance(
				builder,
				tmp,
				base,
				0, // ulong BaseOffset
				0, // uint VBPtrOffset
				LLVMDIFlags.Zero,
			);

			ulong offset = LLVMDITypeGetSizeInBits(base);
			foreach (i; 1 .. elements.length) {
				auto f = c.fields[baseFieldCount + i - 1];
				elements[i] = getField(f, tmp, offset);
			}
		}

		auto ret = symbolScopes[c] = LLVMDIBuilderCreateClassType(
			builder,
			parentScope,
			name.ptr,
			name.length,
			fl.file,
			fl.line,
			size,
			dalign,
			0, // ulong OffsetInBits
			LLVMDIFlags.Zero,
			base, // LLVMMetadataRef DerivedFrom
			elements.ptr,
			cast(uint) elements.length,
			base, // LLVMMetadataRef VTableHolder
			null, // LLVMMetadataRef TemplateParamsNode
			mangle.ptr,
			mangle.length,
		);

		// Now we swap our temporary for the real thing.
		LLVMMetadataReplaceAllUsesWith(tmp, ret);
		return ret;
	}

	LLVMMetadataRef visit(Enum e) {
		if (auto ePtr = e in symbolScopes) {
			return *ePtr;
		}

		// Generating the parent scope might trigger this class's generation.
		auto parentScope = visit(e.getParentScope());
		if (auto ePtr = e in symbolScopes) {
			return *ePtr;
		}

		auto fl = getFileAndLine(e.location);
		auto name = e.name.toString(context);
		auto mangle = e.mangle.toString(context);

		auto t = e.type.getCanonical();
		auto type = typeGen.visit(t);
		auto size = 8 * LLVMABISizeOfType(targetData, type);
		auto dalign = 8 * LLVMABIAlignmentOfType(targetData, type);

		LLVMMetadataRef[] entries;

		if (t.kind == TypeKind.Builtin && t.builtin.canConvertToIntegral()) {
			entries.length = e.entries.length;

			foreach (i, ee; e.entries) {
				auto ename = ee.name.toString(context);

				import d.llvm.constant;
				auto cst = ConstantGen(pass).visit(ee.value);

				// FIXME: We generated that int to begin with, so we shouldn't
				//        have to extract it in this way.
				auto value = LLVMConstIntGetZExtValue(cst);

				entries[i] = LLVMDIBuilderCreateEnumerator(
					builder, ename.ptr, ename.length, value,
					!t.builtin.isIntegral() || !t.builtin.isSigned());
			}
		}

		auto base = DebugInfoTypeGen(pass).visit(e.type);
		return LLVMDIBuilderCreateEnumerationType(
			builder, parentScope, name.ptr, name.length, fl.file, fl.line, size,
			dalign, entries.ptr, cast(uint) entries.length, base);
	}

	/**
	 * FIXME: Various placeholder for symbols that are not implemented.
	 */
	LLVMMetadataRef visit(Template t) {
		// FIXME: Generate debug infos for the template.
		//        At the moment, ldc doesn't generate anything,
		//        so it is fine not to.
		return visit(t.getParentScope());
	}

	LLVMMetadataRef visit(TemplateInstance i) {
		// FIXME: Generate debug infos for the template instance.
		//        At the moment, ldc doesn't generate anything,
		//        so it is fine not to.
		return visit(i.getParentScope());
	}
}

struct DebugInfoTypeGen {
	private GlobalPass pass;
	alias pass this;

	this(GlobalPass pass) {
		this.pass = pass;
	}

	@property
	auto builder() {
		return debugInfoData.builder;
	}

	LLVMMetadataRef visit(Type t) {
		return t.accept(this);
	}

	private auto getReference(LLVMMetadataRef type) {
		enum DW_TAG_reference_type = 0x0010;
		return LLVMDIBuilderCreateReferenceType(builder, DW_TAG_reference_type,
		                                        type);
	}

	auto visit(ParamType pt) {
		auto t = visit(pt.getType());
		return pt.isRef ? getReference(t) : t;
	}

	LLVMMetadataRef visit(BuiltinType t) {
		if (t == BuiltinType.Null) {
			return LLVMDIBuilderCreateNullPtrType(builder);
		}

		static struct TypeDef {
			string name;
			uint size;
			LLVMDWARFTypeEncoding encoding;
		}

		static immutable TypeDef[] BasicTypeDefinitions = [
			TypeDef("", 0, LLVMDWARFTypeEncoding.None),
			TypeDef("void", 0, LLVMDWARFTypeEncoding.None),
			TypeDef("bool", 8, LLVMDWARFTypeEncoding.Boolean),
			TypeDef("char", 8, LLVMDWARFTypeEncoding.UnsignedChar),
			TypeDef("wchar", 16, LLVMDWARFTypeEncoding.UnsignedChar),
			TypeDef("dchar", 32, LLVMDWARFTypeEncoding.UnsignedChar),
			TypeDef("byte", 8, LLVMDWARFTypeEncoding.Signed),
			TypeDef("ubyte", 8, LLVMDWARFTypeEncoding.Unsigned),
			TypeDef("short", 16, LLVMDWARFTypeEncoding.Signed),
			TypeDef("ushort", 16, LLVMDWARFTypeEncoding.Unsigned),
			TypeDef("int", 32, LLVMDWARFTypeEncoding.Signed),
			TypeDef("uint", 32, LLVMDWARFTypeEncoding.Unsigned),
			TypeDef("long", 64, LLVMDWARFTypeEncoding.Signed),
			TypeDef("ulong", 64, LLVMDWARFTypeEncoding.Unsigned),
			TypeDef("cent", 128, LLVMDWARFTypeEncoding.Signed),
			TypeDef("ucent", 128, LLVMDWARFTypeEncoding.Unsigned),
			TypeDef("float", 32, LLVMDWARFTypeEncoding.Float),
			TypeDef("double", 64, LLVMDWARFTypeEncoding.Float),
			TypeDef("real", 64, LLVMDWARFTypeEncoding.Float),
		];

		auto td = BasicTypeDefinitions[t];
		return LLVMDIBuilderCreateBasicType(
			builder, td.name.ptr, td.name.length, td.size, td.encoding,
			LLVMDIFlags.Zero);
	}

	LLVMMetadataRef visitPointerOf(Type t) {
		auto dt = visit(t);

		size_t len;
		auto cname = LLVMDITypeGetName(dt, &len);

		auto name = cname[0 .. len] ~ '*';
		return LLVMDIBuilderCreatePointerType(builder, dt, 64, 64, 0, name.ptr,
		                                      name.length);
	}

	LLVMMetadataRef visitSliceOf(Type t) {
		assert(0, "Slice type can't be generated.");
	}

	LLVMMetadataRef visitArrayOf(uint size, Type t) {
		assert(0, "Array type can't be generated.");
	}

	LLVMMetadataRef visit(Struct s) in(s.step >= Step.Signed) {
		return DebugInfoScopeGen(pass).visit(s);
	}

	LLVMMetadataRef visit(Union u) in(u.step >= Step.Signed) {
		assert(0, "Union type can't be generated.");
	}

	LLVMMetadataRef visit(Class c) in(c.step >= Step.Signed) {
		auto s = DebugInfoScopeGen(pass).visit(c);
		return getReference(s);
	}

	LLVMMetadataRef visit(Enum e) in(e.step >= Step.Signed) {
		return DebugInfoScopeGen(pass).visit(e);
	}

	LLVMMetadataRef visit(TypeAlias a) {
		assert(0, "Alias type can't be generated.");
	}

	LLVMMetadataRef visit(Interface i) {
		assert(0, "Interface type can't be generated.");
	}

	LLVMMetadataRef visit(Function f) in(f.step >= Step.Signed) {
		assert(0, "Context type can't be generated.");
	}

	LLVMMetadataRef visit(FunctionType f) {
		if (f.contexts.length) {
			enum Name = "delegate()";
			return LLVMDIBuilderCreateUnspecifiedType(builder, Name.ptr,
			                                          Name.length);
		}

		import std.algorithm, std.array;
		auto params = f.parameters.map!(p => visit(p)).array();
		auto ret = visit(f.returnType);

		// The return type is expected to be at index 0.
		// Not the most elegant way to get this done, but so be it.
		auto elements = ret ~ params;

		return LLVMDIBuilderCreateSubroutineType(
			builder, null, elements.ptr, cast(uint) elements.length,
			LLVMDIFlags.Zero);
	}

	LLVMMetadataRef visit(Type[] splat) {
		assert(0, "Sequence type can't be generated.");
	}

	LLVMMetadataRef visit(Pattern p) {
		assert(0, "Pattern type can't be generated.");
	}

	import d.ir.error;
	LLVMMetadataRef visit(CompileError e) {
		assert(0, "Error type can't be generated.");
	}
}
