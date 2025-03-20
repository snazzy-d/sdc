module d.semantic.symbol;

import d.semantic.caster;
import d.semantic.declaration;
import d.semantic.semantic;

import d.ast.declaration;
import d.ast.expression;
import d.ast.identifier;

import d.ir.constant;
import d.ir.expression;
import d.ir.symbol;
import d.ir.type;

alias AstModule = d.ast.declaration.Module;
alias Module = d.ir.symbol.Module;

// Conflict with Interface in object.di
alias Interface = d.ir.symbol.Interface;

enum isSchedulable(D, S) =
	is(D : Declaration) && is(S : Symbol) && !__traits(isAbstractClass, S);

struct SymbolVisitor {
	private SemanticPass pass;
	alias pass this;

	this(SemanticPass pass) {
		this.pass = pass;
	}

	void visit(Declaration d, Symbol s) {
		auto tid = typeid(s);

		import std.traits, std.typetuple;
		alias Members =
			TypeTuple!(__traits(getOverloads, SymbolAnalyzer, "analyze"));
		foreach (visit; Members) {
			alias parameters = ParameterTypeTuple!visit;
			static assert(parameters.length == 2);

			static if (isSchedulable!parameters) {
				alias DeclType = parameters[0];
				alias SymType = parameters[1];

				if (tid is typeid(SymType)) {
					auto decl = cast(DeclType) d;

					import std.format;
					assert(
						decl,
						format!"Unexpected declaration type %s."(
							typeid(DeclType))
					);

					scheduler.schedule(decl, () @trusted {
						// Fast cast can be trusted in this case,
						// we already did the check.
						import util.fastcast;
						return fastCast!SymType(s);
					}());
					return;
				}
			}
		}

		import std.format;
		assert(0, format!"Can't process %s."(tid));
	}
}

struct SymbolAnalyzer {
	private SemanticPass pass;
	alias pass this;

	alias Step = SemanticPass.Step;

	this(SemanticPass pass) {
		this.pass = pass;
	}

	void analyze(AstModule astm, Module m) {
		auto oldManglePrefix = manglePrefix;
		scope(exit) manglePrefix = oldManglePrefix;

		manglePrefix = "";

		import std.conv;
		foreach (name; astm.packages) {
			auto p = name.toString(context);
			manglePrefix ~= p.length.to!string() ~ p;
		}

		auto name = astm.name.toString(context);
		manglePrefix ~= name.length.to!string() ~ name;

		auto mangle = m.mangle = context.getName(manglePrefix);

		import source.name;
		// All modules implicitly import object.
		auto obj = importModule([BuiltinName!"object"]);
		m.addImport(obj);

		import d.semantic.declaration;
		m.members = DeclarationVisitor(pass).flatten(astm.declarations, m);

		// sdc.intrinsics is a magic module !
		if (mangle == BuiltinName!"3sdc10intrinsics") {
			fillIntrinsics(m);
		}

		scheduler.require(m.members);
		m.step = Step.Processed;
	}

	private void fillIntrinsics(Module m) {
		void setInstrinsic(Function f, Intrinsic i)
				in(f, "intrinsic not defined") {
			pass.scheduler.require(f);
			f.intrinsicID = i;
		}

		import source.name;
		void set(Name name, Intrinsic i) {
			import source.location;
			auto s = m.resolve(Location.init, name);
			if (s is null) {
				return;
			}

			if (auto f = cast(Function) s) {
				return setInstrinsic(f, i);
			}

			auto os = cast(OverloadSet) s;
			assert(os);
			foreach (c; os.set) {
				if (auto f = cast(Function) c) {
					setInstrinsic(f, i);
				}
			}
		}

		// Ideally we'd use UDA, but as they are not implemented,
		// we just bake the magic in the compiler.
		set(BuiltinName!"expect", Intrinsic.Expect);
		set(BuiltinName!"likely", Intrinsic.Likely);
		set(BuiltinName!"unlikely", Intrinsic.Unlikely);
		set(BuiltinName!"alloca", Intrinsic.Alloca);
		set(BuiltinName!"popCount", Intrinsic.PopCount);
		set(BuiltinName!"countLeadingZeros", Intrinsic.CountLeadingZeros);
		set(BuiltinName!"countTrailingZeros", Intrinsic.CountTrailingZeros);
		set(BuiltinName!"bswap", Intrinsic.ByteSwap);
		set(BuiltinName!"fetchAdd", Intrinsic.FetchAdd);
		set(BuiltinName!"fetchSub", Intrinsic.FetchSub);
		set(BuiltinName!"fetchAnd", Intrinsic.FetchAnd);
		set(BuiltinName!"fetchOr", Intrinsic.FetchOr);
		set(BuiltinName!"fetchXor", Intrinsic.FetchXor);
		set(BuiltinName!"cas", Intrinsic.CompareAndSwap);
		set(BuiltinName!"casWeak", Intrinsic.CompareAndSwapWeak);
		set(BuiltinName!"readCycleCounter", Intrinsic.ReadCycleCounter);
		set(BuiltinName!"readFramePointer", Intrinsic.ReadFramePointer);
	}

	void analyze(FunctionDeclaration fd, Function f) {
		import std.algorithm, std.array;
		auto params = fd.params.map!((p) {
			import d.semantic.type;
			auto t = TypeVisitor(pass).visit(p.type);

			Expression value;
			if (p.value) {
				import d.semantic.expression;
				value = ExpressionVisitor(pass).visit(p.value);
			}

			return new Variable(p.location, t, p.name, value);
		}).array();

		// Functions are always populated as resolution is order dependent.
		f.step = Step.Populated;

		// Prepare statement visitor for return type.
		auto oldThisType = thisType;
		auto oldReturnType = returnType;
		auto oldManglePrefix = manglePrefix;
		scope(exit) {
			thisType = oldThisType;
			returnType = oldReturnType;
			manglePrefix = oldManglePrefix;
		}

		import std.conv;
		auto name = f.name.toString(context);
		manglePrefix = manglePrefix ~ to!string(name.length) ~ name;

		auto fbody = fd.fbody;
		bool isAuto = false;

		import source.name;
		immutable isCtor = f.name == BuiltinName!"__ctor";
		immutable isDtor = f.name == BuiltinName!"__dtor";

		// Make sure we take the type qualifier into account
		if (f.hasThis) {
			// XXX: Maybe we should offer a way to requalify ParamType.
			thisType = thisType.getType().qualify(fd.storageClass.qualifier)
			                   .getParamType(oldThisType.paramKind);
		} else {
			assert(fd.storageClass.qualifier == TypeQualifier.Mutable,
			       "Unexpected qualifier for a function without this!");
		}

		void buildType() {
			f.type = FunctionType(
				f.linkage, pass.returnType,
				params.map!(p => p.paramType).array(), fd.isVariadic);

			assert(!isCtor || !isDtor || f.linkage == Linkage.D,
			       "Only D linkage is supported for ctors and dtors!");

			switch (f.linkage) with (Linkage) {
				case D:
					import d.semantic.mangler;
					auto mangle = TypeMangler(pass).visit(f.type);
					mangle = f.hasThis ? mangle : ("FM" ~ mangle[1 .. $]);
					f.mangle =
						pass.context.getName("_D" ~ pass.manglePrefix ~ mangle);
					break;

				case C:
					f.mangle = f.name;
					break;

				default:
					import std.format;
					assert(0, format!"Linkage %s is not supported."(f.linkage));
			}

			f.step = Step.Signed;
		}

		if (isCtor || isDtor) {
			assert(f.hasThis, "Constructor must have a this pointer!");

			// However, we don't want usual hasThis behavior to kick in
			// as constructor are kind of magic.
			f.hasThis = false;

			returnType =
				Type.get(BuiltinType.Void).getParamType(ParamKind.Regular);

			auto xtorType = thisType;

			// For small struct, we construct by value.
			if (isCtor && xtorType.kind == TypeKind.Struct) {
				auto s = xtorType.getType().dstruct;
				scheduler.require(s, Step.Signed);

				if (s.isSmall) {
					xtorType = xtorType.getParamType(ParamKind.Regular);
					returnType = xtorType;

					if (fbody) {
						import d.ast.statement;
						fbody = new BlockStatement(
							fbody.location,
							[
								fbody,
								new ReturnStatement(
									f.location, new ThisExpression(f.location))
							]
						);
					}
				}
			}

			auto thisParameter =
				new Variable(f.location, xtorType, BuiltinName!"this", null);

			params = thisParameter ~ params;

			// If we have a dtor body, we need to tweak it.
			if (isDtor && fbody) {
				auto a = xtorType.getType().getCanonical().aggregate;
				scheduler.require(a, Step.Signed);

				import d.ast.statement;
				Statement[] fieldDtors;

				foreach (field; a.fields) {
					auto t = field.type.getCanonical();
					if (t.kind != TypeKind.Struct) {
						continue;
					}

					auto s = t.dstruct;
					scheduler.require(s, Step.Signed);
					if (s.isPod) {
						continue;
					}

					import d.ast.expression;
					auto fieldDtor = new IdentifierDotIdentifier(
						fbody.location,
						BuiltinName!"__dtor",
						new ExpressionDotIdentifier(
							fbody.location, field.name,
							new ThisExpression(fbody.location))
					);

					fieldDtors ~= new ScopeStatement(
						f.location,
						ScopeKind.Exit,
						new ExpressionStatement(
							new IdentifierCallExpression(fbody.location,
							                             fieldDtor, []))
					);
				}

				// Ok, we have fields to destroy, let's do it !
				if (fieldDtors.length > 0) {
					import std.algorithm;
					foreach (i; 0 .. fieldDtors.length / 2) {
						swap(fieldDtors[i], fieldDtors[$ - i - 1]);
					}

					fieldDtors ~= fbody;
					fbody = new BlockStatement(fbody.location, fieldDtors);
				}
			}
		} else {
			// If it has a this pointer, add it as parameter.
			if (f.hasThis) {
				assert(
					thisType.getType().isAggregate(),
					"thisType must be defined if function has a this pointer."
				);

				auto thisParameter = new Variable(f.location, thisType,
				                                  BuiltinName!"this", null);

				params = thisParameter ~ params;
			}

			isAuto = fd.returnType.getType().isAuto;

			import d.semantic.type;
			returnType = isAuto
				? Type.get(BuiltinType.None).getParamType(ParamKind.Regular)
				: TypeVisitor(pass).visit(fd.returnType);
		}

		// Add this as a parameter, but not context.
		// Why ? Because bullshit !
		f.params = params;

		// If this is a closure, we add the context parameter.
		if (f.hasContext) {
			assert(ctxSym,
			       "ctxSym must be defined if function has a context pointer.");

			import source.name;
			auto contextParameter = new Variable(
				f.location,
				Type.getContextType(ctxSym).getParamType(ParamKind.Ref),
				BuiltinName!"__ctx",
				null,
			);

			params = contextParameter ~ params;
		}

		if (!isAuto) {
			buildType();
		}

		if (fbody) {
			auto oldCtxSym = ctxSym;
			scope(exit) ctxSym = oldCtxSym;

			ctxSym = f;

			// Register parameters.
			foreach (p; params) {
				p.mangle = p.name;
				p.step = Step.Processed;

				if (!p.name.isEmpty()) {
					f.addSymbol(p);
				}
			}

			// And flatten.
			import d.semantic.statement;
			StatementVisitor(pass).getBody(f, fbody);

			import d.semantic.flow;
			f.closure = FlowAnalyzer(pass, f).getClosure();
		}

		if (isAuto) {
			// If nothing has been set, the function returns void.
			auto t = returnType.getType();
			if (t.kind == TypeKind.Builtin && t.builtin == BuiltinType.None) {
				returnType = Type.get(BuiltinType.Void)
				                 .getParamType(returnType.paramKind);
			}

			buildType();
		}

		assert(f.fbody || !isAuto, "Auto functions must have a body!");
		f.step = Step.Processed;
	}

	void analyze(FunctionDeclaration d, Method m) {
		analyze(d, cast(Function) m);
	}

	private auto getValue(VariableDeclaration d) {
		auto stc = d.storageClass;

		if (d.type.isAuto) {
			// XXX: remove selective import when dmd is sane.
			import d.semantic.expression : ExpressionVisitor;
			return ExpressionVisitor(pass).visit(d.value);
		}

		import d.semantic.type : TypeVisitor;
		auto type = TypeVisitor(pass).withStorageClass(stc).visit(d.type);
		if (auto vi = cast(AstVoidInitializer) d.value) {
			return new ConstantExpression(vi.location, new VoidConstant(type));
		}

		// XXX: remove selective import when dmd is sane.
		import d.semantic.expression : ExpressionVisitor;
		import d.semantic.defaultinitializer : InitBuilder;
		auto value = d.value
			? ExpressionVisitor(pass).visit(d.value)
			: InitBuilder(pass, d.location).asExpression(type);

		return buildImplicitCast(pass, d.location, type, value);
	}

	void analyze(VariableDeclaration d, Variable v) {
		auto value = getValue(d);
		assert(value);

		// We peel alias for auto variable as it can lead to
		// very confusing results, like a template parameter.
		v.type = d.type.isAuto ? value.type.getCanonical() : value.type;

		value = v.value = v.storage.isGlobal
			? new ConstantExpression(value.location, evaluate(value))
			: value;

		v.mangle = v.name;

		assert(
			v.storage != Storage.Static,
			"Static variable are not supported anymore, use GlobalVariable."
		);

		// XXX: Make sure type is at least signed.
		import d.semantic.sizeof;
		SizeofVisitor(pass).visit(value.type);

		v.step = Step.Processed;
	}

	void analyze(VariableDeclaration d, GlobalVariable g) {
		auto value = getValue(d);
		assert(value);

		// We peel alias for auto variable as it can lead to
		// very confusing results, like a template parameter.
		g.type = d.type.isAuto ? value.type.getCanonical() : value.type;

		assert(g.linkage == Linkage.D, "Only D mangling is implemented.");

		import d.semantic.mangler;
		auto mangle = TypeMangler(pass).visit(g.type);
		auto name = g.name.toString(context);

		import std.conv;
		mangle = "_D" ~ manglePrefix ~ to!string(name.length) ~ name ~ mangle;
		g.mangle = context.getName(mangle);

		g.value = evaluate(value);
		g.step = Step.Processed;
	}

	void analyze(VariableDeclaration d, ManifestConstant m) {
		auto value = getValue(d);
		assert(value);

		// We peel alias for auto variable as it can lead to
		// very confusing results, like a template parameter.
		m.type = d.type.isAuto ? value.type.getCanonical() : value.type;

		m.mangle = m.name;
		m.value = evaluate(value);

		m.step = Step.Processed;
	}

	void analyze(VariableDeclaration d, Field f) {
		auto value = getValue(d);
		assert(value);

		// We peel alias for auto variable as it can lead to
		// very confusing results, like a template parameter.
		f.type = d.type.isAuto ? value.type.getCanonical() : value.type;

		f.mangle = f.name;
		f.value = evaluate(value);

		// XXX: Make sure type is at least signed.
		import d.semantic.sizeof;
		SizeofVisitor(pass).visit(value.type);

		f.step = Step.Processed;
	}

	void analyze(IdentifierAliasDeclaration iad, SymbolAlias a) {
		import d.semantic.identifier;
		a.symbol = IdentifierResolver(
			pass
		).resolve(iad.identifier).apply!(delegate Symbol(identified) {
			alias T = typeof(identified);
			static if (is(T : Symbol)) {
				return identified;
			} else static if (is(T : Type)) {
				/**
				 * Its not ideal to turn the alias into an alias to an alias,
				 * but it's hard to figure out whether the identifier will
				 * resolve to a symbol or something else.
				 * 
				 * This will do for now.
				 */
				return process(new TypeAlias(a.location, a.name, identified));
			} else {
				import std.format;
				assert(0, format!"Not implemented for %s."(typeid(identified)));
			}
		})();

		process(a);
	}

	void process(SymbolAlias a) {
		assert(a.symbol, "SymbolAlias must alias to something!");
		a.step = Step.Populated;

		scheduler.require(a.symbol, Step.Signed);
		a.hasContext = a.symbol.hasContext;
		a.hasThis = a.symbol.hasThis;
		a.mangle = a.symbol.mangle;
		a.step = Step.Processed;
	}

	void analyze(TypeAliasDeclaration d, TypeAlias a) {
		import d.semantic.type : TypeVisitor;
		a.type = TypeVisitor(pass).visit(d.type);

		// If it is a function or delegate type, we need to apply the linkage.
		if (a.type.kind == TypeKind.Function) {
			auto f = a.type.asFunctionType();
			a.type = f.withLinkage(a.linkage).getType(a.type.qualifier);
		}

		process(a);
	}

	auto process(TypeAlias a) {
		import d.semantic.mangler;
		a.mangle = context.getName(TypeMangler(pass).visit(a.type));

		a.step = Step.Processed;
		return a;
	}

	void analyze(ValueAliasDeclaration d, ValueAlias a) {
		// XXX: remove selective import when dmd is sane.
		import d.semantic.expression : ExpressionVisitor;
		a.value = evaluate(ExpressionVisitor(pass).visit(d.value));

		import d.semantic.mangler;
		auto typeMangle = TypeMangler(pass).visit(a.value.type);
		auto valueMangle = ConstantMangler().visit(a.value);
		a.mangle = context.getName(typeMangle ~ valueMangle);

		a.step = Step.Processed;
	}

	void analyze(StructDeclaration d, Struct s) {
		auto oldManglePrefix = manglePrefix;
		auto oldThisType = thisType;

		scope(exit) {
			manglePrefix = oldManglePrefix;
			thisType = oldThisType;
		}

		auto type = Type.get(s);
		thisType = type.getParamType(ParamKind.Ref);

		// Update mangle prefix.
		import std.conv;
		auto name = s.name.toString(context);
		manglePrefix = manglePrefix ~ name.length.to!string() ~ name;

		assert(s.linkage == Linkage.D || s.linkage == Linkage.C);
		auto mangle = "S" ~ manglePrefix;
		s.mangle = context.getName(mangle);

		// XXX: d is hijacked without explicit import
		import source.name : BuiltinName;
		if (s.hasContext) {
			auto ctxPtr = Type.getContextType(ctxSym).getPointer();
			auto ctx = new Field(s.location, 0, ctxPtr, BuiltinName!"__ctx",
			                     new NullConstant(ctxPtr));

			ctx.step = Step.Processed;
			s.fields = [ctx];
		}

		auto members = DeclarationVisitor(pass).flatten(d.members, s);
		foreach (m; members) {
			if (auto f = cast(Field) m) {
				s.fields ~= f;
			} else {
				s.members ~= m;
			}
		}

		auto init = new ManifestConstant(d.location, BuiltinName!"init");
		init.step = Step.Signed;
		init.mangle = context.getName(
			"_D" ~ manglePrefix ~ to!string("init".length) ~ "init" ~ mangle);

		s.members ~= init;
		s.addSymbol(init);

		s.step = Step.Populated;

		import d.semantic.defaultinitializer;
		init.value = InitBuilder(pass, s.location).visit(s);
		init.step = Step.Processed;

		// If the struct has no dtor and only pod fields, it is a pod.
		auto hasDtor = s.resolve(s.location, BuiltinName!"__dtor");
		auto hasPostblit = s.resolve(s.location, BuiltinName!"__postblit");

		bool hasIndirection = false;
		bool isPod = !hasDtor && !hasPostblit;
		foreach (f; s.fields) {
			auto t = f.type.getCanonical();
			if (t.kind == TypeKind.Struct) {
				isPod = isPod && t.dstruct.isPod;
			}

			hasIndirection = hasIndirection || t.hasIndirection;
		}

		s.hasIndirection = hasIndirection;
		s.isPod = isPod;

		if (!isPod) {
			// TODO: Create default ctor and dtor
		}

		scheduler.require(s.fields);
		s.step = Step.Signed;

		// Must be done once the struct is signed, but really is part
		// of the process to get it signed, so we do it immediately.
		s.isSmall = (dataLayout.getSize(Type.get(s)) <= 32);

		scheduler.require(s.members);
		s.step = Step.Processed;
	}

	void analyze(UnionDeclaration d, Union u) {
		auto oldManglePrefix = manglePrefix;
		auto oldThisType = thisType;

		scope(exit) {
			manglePrefix = oldManglePrefix;
			thisType = oldThisType;
		}

		auto type = Type.get(u);
		thisType = type.getParamType(ParamKind.Ref);

		// Update mangle prefix.
		import std.conv;
		auto name = u.name.toString(context);
		manglePrefix = manglePrefix ~ name.length.to!string() ~ name;

		// XXX: For some reason dmd mangle the same way as structs ???
		assert(u.linkage == Linkage.D || u.linkage == Linkage.C);
		auto mangle = "S" ~ manglePrefix;
		u.mangle = context.getName(mangle);

		// XXX: d is hijacked without explicit import
		import source.name : BuiltinName;
		if (u.hasContext) {
			auto ctxPtr = Type.getContextType(ctxSym).getPointer();
			auto ctx = new Field(u.location, 0, ctxPtr, BuiltinName!"__ctx",
			                     new NullConstant(ctxPtr));

			ctx.step = Step.Processed;
			u.fields = [ctx];
		}

		auto members = DeclarationVisitor(pass).flatten(d.members, u);
		foreach (m; members) {
			if (auto f = cast(Field) m) {
				u.fields ~= f;
			} else {
				u.members ~= m;
			}
		}

		auto init = new ManifestConstant(u.location, BuiltinName!"init");
		init.step = Step.Signed;
		init.mangle = context.getName(
			"_D" ~ manglePrefix ~ to!string("init".length) ~ "init" ~ mangle);

		u.addSymbol(init);
		u.step = Step.Populated;

		import d.semantic.defaultinitializer;
		init.value = InitBuilder(pass, u.location).visit(u);
		init.step = Step.Processed;

		import std.algorithm;
		u.hasIndirection = u.fields.any!(f => f.type.hasIndirection);

		scheduler.require(u.fields);
		u.step = Step.Signed;

		scheduler.require(u.members);
		u.step = Step.Processed;
	}

	private
	auto generateVTable(Class c, Method[] baseMethods, Method[] newMethods) {
		Method[] methods = baseMethods.dup;

		NewMethodLoop: foreach (m; newMethods) {
			scheduler.require(m, Step.Signed);

			auto mt = m.type;
			auto rt = mt.returnType;
			auto ats = mt.parameters[1 .. $];

			CandidatesLoop: foreach (i, candidate; baseMethods) {
				if (!candidate || m.name != candidate.name) {
					continue;
				}

				auto ct = candidate.type;
				if (ct.isVariadic != mt.isVariadic) {
					continue;
				}

				auto crt = ct.returnType;
				auto cpts = ct.parameters[1 .. $];
				if (ats.length != cpts.length || rt.isRef != crt.isRef) {
					continue;
				}

				auto rk = implicitCastFrom(pass, rt.getType(), crt.getType());
				if (rk < CastKind.Exact) {
					continue;
				}

				import std.range;
				foreach (at, cpt; lockstep(ats, cpts)) {
					if (at.isRef != cpt.isRef) {
						continue CandidatesLoop;
					}

					auto pk =
						implicitCastFrom(pass, cpt.getType(), at.getType());
					if (pk < CastKind.Exact) {
						continue CandidatesLoop;
					}
				}

				if (m.index != -1) {
					import source.exception, std.format;
					throw new CompileException(
						m.location,
						format!"%s overrides a base class method but is not marked override."(
							m.name.toString(context))
					);
				}

				if (candidate.isFinal) {
					import source.exception, std.format;
					throw new CompileException(
						m.location,
						format!"%s overrides a final method."(
							m.name.toString(context)),
					);
				}

				m.index = candidate.index;

				assert(candidate.index == i);
				baseMethods[i] = null;
				methods[i] = m;

				// Remove candidate from scope.
				auto os = cast(OverloadSet) c.resolve(c.location, m.name);
				assert(os, "This must be an overload set!");

				uint k = 0;
				while (os.set[k] !is candidate) {
					k++;
				}

				foreach (s; os.set[k + 1 .. $]) {
					os.set[k++] = s;
				}

				os.set = os.set[0 .. k];
				continue NewMethodLoop;
			}

			if (m.index == -1) {
				import source.exception, std.format;
				throw new CompileException(
					m.location,
					format!"Override not found for %s."(
						m.name.toString(context))
				);
			}

			assert(m.index == methods.length, "Invalid method index!");
			methods ~= m;
		}

		return methods;
	}

	void analyze(ClassDeclaration d, Class c) {
		auto oldManglePrefix = manglePrefix;
		auto oldThisType = thisType;

		scope(exit) {
			manglePrefix = oldManglePrefix;
			thisType = oldThisType;
		}

		thisType = Type.get(c).getParamType(ParamKind.Final);

		// Update mangle prefix.
		import std.conv;
		auto name = c.name.toString(context);
		manglePrefix = manglePrefix ~ name.length.to!string() ~ name;
		c.mangle = context.getName("C" ~ manglePrefix);

		foreach (i; d.bases) {
			import d.semantic.identifier;
			c.base = IdentifierResolver(pass)
				.resolve(i).apply!(function Class(identified) {
					static if (is(typeof(identified) : Symbol)) {
						if (auto c = cast(Class) identified) {
							return c;
						}
					}

					static if (is(typeof(identified.location))) {
						import source.exception, std.format;
						throw new CompileException(
							identified.location,
							format!"%s is not a class."(typeid(identified))
						);
					} else {
						// for typeof(null)
						assert(0);
					}
				})();

			break;
		}

		// If no inheritance is specified, inherit from object.
		if (c.base is null) {
			c.base = pass.object.getObject();
		}

		// Cannot inherit from final classes.
		if (c.base.isFinal) {
			import source.exception, std.format;
			throw new CompileException(
				c.location,
				format!"%s cannot inherit from %s because it is final."(
					c.name.toString(context), c.base.name.toString(context))
			);
		}

		Field[] fields;
		Method[] baseMethods;
		uint fieldIndex = 0;
		uint methodIndex = 0;

		// object.Object, let's do some compiler magic.
		if (c is c.base) {
			auto vtblType =
				Type.get(BuiltinType.Void).getPointer(TypeQualifier.Immutable);

			import source.name : BuiltinName;
			auto vtbl = new Field(d.location, 0, vtblType, BuiltinName!"__vtbl",
			                      new NullConstant(vtblType));

			vtbl.step = Step.Processed;

			fields = [vtbl];
			fieldIndex = 1;
		} else {
			scheduler.require(c.base);
			c.primaries = c.base.primaries ~ c;

			// Base class fields.
			fields = c.base.fields;
			fieldIndex = cast(uint) fields.length;
			foreach (f; fields) {
				c.addSymbol(f);
			}

			// Base class methods.
			baseMethods = c.base.methods.dup;
			foreach (m; baseMethods) {
				c.addOverloadableSymbol(m);

				import std.algorithm;
				methodIndex = max(methodIndex, m.index + 1);
			}
		}

		if (c.hasContext) {
			// XXX: check for duplicate.
			auto ctxPtr = Type.getContextType(ctxSym).getPointer();

			import source.name;
			auto ctx = new Field(c.location, fieldIndex++, ctxPtr,
			                     BuiltinName!"__ctx", new NullConstant(ctxPtr));

			ctx.step = Step.Processed;
			fields ~= ctx;
		}

		auto members = DeclarationVisitor(pass)
			.flatten(d.members, c, fieldIndex, methodIndex);

		Method[] newMethods;
		foreach (member; members) {
			if (auto f = cast(Field) member) {
				fields ~= f;
				continue;
			}

			if (auto m = cast(Method) member) {
				newMethods ~= m;
				continue;
			}

			c.members ~= member;
		}

		c.fields = fields;
		c.step = Step.Populated;

		scheduler.require(fields);
		c.step = Step.Signed;

		auto methods = generateVTable(c, baseMethods, newMethods);
		scheduler.require(methods);
		c.methods = methods;

		scheduler.require(c.members);
		c.step = Step.Processed;
	}

	void analyze(InterfaceDeclaration d, Interface i) {
		auto oldManglePrefix = manglePrefix;
		auto oldThisType = thisType;

		scope(exit) {
			manglePrefix = oldManglePrefix;
			thisType = oldThisType;
		}

		thisType = Type.get(i).getParamType(ParamKind.Final);

		import std.conv;
		auto name = i.name.toString(context);
		manglePrefix = manglePrefix ~ name.length.to!string();

		i.mangle = context.getName("I" ~ manglePrefix);

		assert(d.members.length == 0,
		       "Member support not implemented for interfaces yet!");

		assert(d.bases.length == 0,
		       "Interface inheritance not implemented yet!");

		// TODO: lots of stuff to add

		i.step = Step.Processed;
	}

	void analyze(EnumDeclaration d, Enum e)
			in(e.name.isDefined, "Anonymous enum must be flattened!") {
		auto oldManglePrefix = manglePrefix;
		auto oldScope = currentScope;

		scope(exit) {
			manglePrefix = oldManglePrefix;
			currentScope = oldScope;
		}

		currentScope = e;

		import d.semantic.type : TypeVisitor;
		e.type = d.type.isAuto
			? Type.get(BuiltinType.Int)
			: TypeVisitor(pass).visit(d.type);

		if (e.type.kind != TypeKind.Builtin) {
			import source.exception, std.format;
			throw new CompileException(
				e.location,
				format!"Unsupported enum type %s."(e.type.toString(context))
			);
		}

		auto bt = e.type.builtin;
		if (!isIntegral(bt) && bt != BuiltinType.Bool) {
			import source.exception, std.format;
			throw new CompileException(
				e.location,
				format!"Unsupported enum type %s."(e.type.toString(context))
			);
		}

		import std.conv;
		auto name = e.name.toString(context);
		manglePrefix = manglePrefix ~ to!string(name.length) ~ name;

		assert(e.linkage == Linkage.D || e.linkage == Linkage.C);
		e.mangle = context.getName("E" ~ manglePrefix);

		auto entries = processEnumEntries(d.entries);
		auto type = Type.get(e);

		foreach (m; entries) {
			m.type = type;
			e.addSymbol(m);
		}

		e.entries = entries;
		e.step = Step.Signed;

		scheduler.require(e.entries);
		e.step = Step.Processed;
	}

	void analyze(AstExpression e, ManifestConstant m)
			in(m.type.kind == TypeKind.Enum) {
		m.step = Step.Signed;

		import d.semantic.expression;
		auto value = ExpressionVisitor(pass).visit(e);
		m.value = evaluate(value);
		m.step = Step.Processed;
	}

	auto processEnumEntries(VariableDeclaration[] vEntries) {
		ManifestConstant[] entries;
		AstExpression previous, one;

		foreach (vd; vEntries) {
			auto location = vd.location;
			auto m = new ManifestConstant(location, vd.name);
			entries ~= m;

			auto value = vd.value;
			scope(success) {
				scheduler.schedule(value, m);
				previous = value;
			}

			if (value !is null) {
				continue;
			}

			if (previous is null) {
				value = new IntegerLiteral(vd.location, 0, BuiltinType.Int);
				continue;
			}

			if (one is null) {
				one = new IntegerLiteral(vd.location, 1, BuiltinType.Int);
			}

			value = new AstBinaryExpression(location, AstBinaryOp.Add, previous,
			                                one);
		}

		return entries;
	}

	void analyze(TemplateDeclaration d, Template t) {
		// XXX: compute a proper mangling for templates.
		import std.conv;
		auto name = t.name.toString(context);
		t.mangle =
			context.getName(manglePrefix ~ name.length.to!string() ~ name);

		auto oldScope = currentScope;
		auto oldInPattern = inPattern;
		scope(exit) {
			currentScope = oldScope;
			inPattern = oldInPattern;
		}

		currentScope = t;
		inPattern = true;

		t.parameters.length = d.parameters.length;

		// Register parameter in the scope.
		auto none = Type.get(BuiltinType.None);
		foreach_reverse (i, p; d.parameters) {
			if (auto atp = cast(AstTypeTemplateParameter) p) {
				auto tp = new TypeTemplateParameter(atp.location, atp.name,
				                                    cast(uint) i, none, none);

				t.addSymbol(tp);

				import d.semantic.type : TypeVisitor;
				tp.specialization = TypeVisitor(pass).visit(atp.specialization);
				tp.defaultValue = TypeVisitor(pass).visit(atp.defaultValue);

				tp.step = Step.Signed;
				t.parameters[i] = tp;
			} else if (auto avp = cast(AstValueTemplateParameter) p) {
				auto vp = new ValueTemplateParameter(avp.location, avp.name,
				                                     cast(uint) i, none, null);

				t.addSymbol(vp);

				import d.semantic.type : TypeVisitor;
				vp.type = TypeVisitor(pass).visit(avp.type);

				if (avp.defaultValue !is null) {
					import d.semantic.expression : ExpressionVisitor;
					vp.defaultValue =
						ExpressionVisitor(pass).visit(avp.defaultValue);
				}

				vp.step = Step.Signed;
				t.parameters[i] = vp;
			} else if (auto aap = cast(AstAliasTemplateParameter) p) {
				auto ap = new AliasTemplateParameter(aap.location, aap.name,
				                                     cast(uint) i);

				t.addSymbol(ap);

				ap.step = Step.Signed;
				t.parameters[i] = ap;
			} else if (auto atap = cast(AstTypedAliasTemplateParameter) p) {
				auto tap =
					new TypedAliasTemplateParameter(atap.location, atap.name,
					                                cast(uint) i, none);

				t.addSymbol(tap);

				import d.semantic.type : TypeVisitor;
				tap.type = TypeVisitor(pass).visit(atap.type);

				tap.step = Step.Signed;
				t.parameters[i] = tap;
			} else {
				import std.format;
				assert(
					0,
					format!"%s template parameters are not supported."(
						typeid(p))
				);
			}
		}

		// TODO: support multiple IFTI.
		foreach (m; t.members) {
			if (auto fun = cast(FunctionDeclaration) m) {
				if (fun.name != t.name) {
					continue;
				}

				import d.semantic.type, std.algorithm, std.array;
				t.ifti = fun
					.params.map!(p => TypeVisitor(pass).visit(p.type).getType())
					.array();

				break;
			}
		}

		t.step = Step.Processed;
	}

	void analyze(Template t, TemplateInstance i) {
		auto oldManglePrefix = manglePrefix;
		auto oldCtxSym = ctxSym;

		scope(exit) {
			manglePrefix = oldManglePrefix;
			ctxSym = oldCtxSym;
		}

		ctxSym = null;
		if (t.hasThis) {
			i.hasThis = true;
			i.storage = Storage.Local;

			// Try to recover the template type.
			// XXX: There should be a way to keep it around.
			auto cs = t.getParentScope();
			while (true) {
				auto o = cast(Object) cs;
				if (auto s = cast(Struct) o) {
					thisType = Type.get(s).getParamType(ParamKind.Ref);
					break;
				}

				if (auto c = cast(Class) o) {
					thisType = Type.get(c).getParamType(ParamKind.Final);
					break;
				}

				if (auto u = cast(Union) o) {
					thisType = Type.get(u).getParamType(ParamKind.Ref);
					break;
				}

				if (auto iface = cast(Interface) o) {
					thisType = Type.get(iface).getParamType(ParamKind.Final);
					break;
				}

				cs = cs.getParentScope();
			}
		}

		manglePrefix = i.mangle.toString(context);

		// Prefilled members are template arguments.
		foreach (a; i.args) {
			if (a.tag != TemplateArgument.Tag.Symbol) {
				continue;
			}

			auto s = a.get!(TemplateArgument.Tag.Symbol);
			if (!s.hasContext) {
				continue;
			}

			assert(!i.hasContext, "Template can only have one context!");

			import d.semantic.closure;
			ctxSym = ContextFinder(pass).visit(s);

			i.hasContext = true;
			i.storage = Storage.Local;
		}

		import d.semantic.declaration;
		i.members = DeclarationVisitor(pass).flatten(t.members, i);
		i.step = Step.Signed;

		scheduler.require(i.members);
		i.step = Step.Processed;
	}

	void analyze(UnittestDeclaration ud, Function f) {
		// Functions are always populated as resolution is order dependent.
		f.step = Step.Populated;

		// Prepare statement visitor for return type.
		auto oldReturnType = returnType;
		auto oldManglePrefix = manglePrefix;
		auto oldCtxSym = ctxSym;
		scope(exit) {
			returnType = oldReturnType;
			manglePrefix = oldManglePrefix;
			ctxSym = oldCtxSym;
		}

		returnType = Type.get(BuiltinType.Void).getParamType(ParamKind.Regular);

		f.type = FunctionType(Linkage.D, returnType, [], false);

		string name;

		import source.name;
		if (f.name == BuiltinName!"") {
			// FIXME: can still collide with mixins,
			// but that should rare enough for now.
			auto offset = f.location.getFullLocation(context).getStartOffset();

			import std.conv;
			name = "__unittest" ~ offset.to!string();
			f.name = context.getName(name);
		} else {
			name = "__unittest." ~ f.name.toString(context);
		}

		import std.conv;
		manglePrefix = manglePrefix ~ to!string(name.length) ~ name;
		f.mangle = context.getName("_D" ~ manglePrefix);

		// Typed and mangled, ready to go !
		f.step = Step.Signed;

		// Now generate the body.
		ctxSym = f;

		import d.semantic.statement;
		StatementVisitor(pass).getBody(f, ud.fbody);

		import d.semantic.flow;
		f.closure = FlowAnalyzer(pass, f).getClosure();

		f.step = Step.Processed;

		// Register the test at the module level.
		// XXX: This may not be the right module when instantiating templates.
		currentScope.getModule().tests ~= f;
	}
}
