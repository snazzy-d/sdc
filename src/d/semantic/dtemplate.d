module d.semantic.dtemplate;

import d.semantic.semantic;

import d.ast.declaration;

import d.ir.expression;
import d.ir.symbol;
import d.ir.type;

import source.location;

struct TemplateInstancier {
	private SemanticPass pass;
	alias pass this;

	this(SemanticPass pass) {
		this.pass = pass;
	}

	auto instanciate(Location location, OverloadSet s, TemplateArgument[] args,
	                 Expression[] fargs) {
		import std.algorithm;
		auto cds = s.set.filter!((s) {
			if (auto t = cast(Template) s) {
				pass.scheduler.require(t);
				return t.parameters.length >= args.length;
			}

			assert(0, "this isn't a template");
		});

		Template match;
		TemplateArgument[] matchedArgs;
		CandidateLoop: foreach (candidate; cds) {
			auto t = cast(Template) candidate;
			assert(
				t,
				"We should have ensured that we only have templates at this point."
			);

			TemplateArgument[] cdArgs;
			cdArgs.length = t.parameters.length;
			if (!matchArguments(t, args, fargs, cdArgs)) {
				continue CandidateLoop;
			}

			if (!match) {
				match = t;
				matchedArgs = cdArgs;
				continue CandidateLoop;
			}

			TemplateArgument[] dummy;
			dummy.length = t.parameters.length;

			static buildArg(TemplateParameter p) {
				if (auto tp = cast(TypeTemplateParameter) p) {
					return TemplateArgument(tp.specialization);
				}

				// XXX: Clarify the specialization thing...
				if (auto ap = cast(ValueTemplateParameter) p) {
					return TemplateArgument.init;
				}

				if (auto ap = cast(AliasTemplateParameter) p) {
					return TemplateArgument.init;
				}

				import source.exception;
				throw new CompileException(
					p.location, typeid(p).toString() ~ " not implemented");
			}

			import std.algorithm, std.array;
			auto asArg = match.parameters.map!buildArg.array();
			bool match2t = matchArguments(t, asArg, [], dummy);

			dummy = null;
			dummy.length = match.parameters.length;
			asArg = t.parameters.map!buildArg.array();
			bool t2match = matchArguments(match, asArg, [], dummy);

			if (t2match == match2t) {
				assert(0, "Ambiguous template");
			}

			if (t2match) {
				match = t;
				matchedArgs = cdArgs;
				continue CandidateLoop;
			}
		}

		if (!match) {
			import source.exception;
			throw new CompileException(location, "No match");
		}

		return instanciateFromResolvedArgs(location, match, matchedArgs);
	}

	auto instanciate(Location location, Template t, TemplateArgument[] args,
	                 Expression[] fargs = []) {
		scheduler.require(t);

		TemplateArgument[] matchedArgs;
		if (t.parameters.length > 0) {
			matchedArgs.length = t.parameters.length;

			if (!matchArguments(t, args, fargs, matchedArgs)) {
				import source.exception;
				throw new CompileException(location, "No match");
			}
		}

		return instanciateFromResolvedArgs(location, t, matchedArgs);
	}

private:
	bool matchArguments(Template t, TemplateArgument[] args, Expression[] fargs,
	                    TemplateArgument[] matchedArgs) in {
		assert(t.step == Step.Processed);
		assert(t.parameters.length >= args.length);
		assert(matchedArgs.length == t.parameters.length);
	} do {
		uint i = 0;
		foreach (a; args) {
			if (!matchArgument(t.parameters[i++], a, matchedArgs)) {
				return false;
			}
		}

		if (fargs.length == t.ifti.length) {
			foreach (j, a; fargs) {
				auto m =
					IftiTypeMatcher(pass, matchedArgs, a.type).visit(t.ifti[j]);
				if (!m) {
					return false;
				}
			}
		}

		// Match unspecified parameters.
		foreach (a; matchedArgs[i .. $]) {
			if (!matchArgument(t.parameters[i++], a, matchedArgs)) {
				return false;
			}
		}

		return true;
	}

	bool matchArgument(TemplateParameter p, TemplateArgument a,
	                   TemplateArgument[] matchedArgs) {
		return a.apply!(delegate bool() {
			if (auto t = cast(TypeTemplateParameter) p) {
				return TypeParameterMatcher(pass, matchedArgs, t.defaultValue)
					.visit(t);
			}

			if (auto v = cast(ValueTemplateParameter) p) {
				if (v.defaultValue !is null) {
					import d.semantic.caster;
					auto e = pass.evaluate(
						buildImplicitCast(pass, v.location, v.type,
						                  v.defaultValue));
					return ValueMatcher(pass, matchedArgs, e).visit(v);
				}
			}

			return false;
		}, (identified) {
			static if (is(typeof(identified) : Type)) {
				return TypeParameterMatcher(pass, matchedArgs, identified)
					.visit(p);
			} else static if (is(typeof(identified) : Expression)) {
				return ValueMatcher(pass, matchedArgs, identified).visit(p);
			} else static if (is(typeof(identified) : Symbol)) {
				return SymbolMatcher(pass, matchedArgs, identified).visit(p);
			} else {
				return false;
			}
		})();
	}

	auto instanciateFromResolvedArgs(Location location, Template t,
	                                 TemplateArgument[] args) in {
		assert(t.step == Step.Processed);
		assert(t.parameters.length == args.length);
	} do {
		auto i = 0;
		Symbol[] argSyms;

		// XXX: have to put array once again to avoid multiple map.
		import std.algorithm, std.array;
		string id = args.map!(a => a.apply!(function string() {
			assert(0, "All passed argument must be defined.");
		}, delegate string(identified) {
			auto p = t.parameters[i++];

			alias T = typeof(identified);
			static if (is(T : Type)) {
				auto a = new TypeAlias(p.location, p.name, identified);

				import d.semantic.mangler;
				a.mangle =
					pass.context.getName(TypeMangler(pass).visit(identified));
				a.step = Step.Processed;

				argSyms ~= a;
				return "T" ~ a.mangle.toString(pass.context);
			} else static if (is(T : CompileTimeExpression)) {
				auto a = new ValueAlias(p.location, p.name, identified);

				import d.semantic.mangler;
				auto typeMangle = TypeMangler(pass).visit(identified.type);
				auto valueMangle = ValueMangler(pass).visit(identified);
				a.mangle = pass.context.getName(typeMangle ~ valueMangle);
				a.step = Step.Processed;

				argSyms ~= a;
				return "V" ~ a.mangle.toString(pass.context);
			} else static if (is(T : Symbol)) {
				auto a = new SymbolAlias(p.location, p.name, identified);

				import d.semantic.symbol;
				SymbolAnalyzer(pass).process(a);

				argSyms ~= a;
				return "S" ~ a.mangle.toString(pass.context);
			} else {
				assert(0, typeid(identified).toString() ~ " is not supported.");
			}
		})).array().join();

		return t.instances.get(id, {
			auto oldManglePrefix = pass.manglePrefix;
			auto oldScope = pass.currentScope;
			scope(exit) {
				pass.manglePrefix = oldManglePrefix;
				pass.currentScope = oldScope;
			}

			auto i = new TemplateInstance(location, t, args);
			auto mangle = t.mangle.toString(pass.context);
			i.mangle = pass.context.getName(mangle ~ "T" ~ id ~ "Z");
			i.storage = t.storage;

			// Prefill arguments.
			foreach (a; argSyms) {
				i.addSymbol(a);
			}

			pass.scheduler.schedule(t, i);
			return t.instances[id] = i;
		}());
	}
}

// Conflict with Interface in object.di
alias Interface = d.ir.symbol.Interface;

struct TypeParameterMatcher {
	TemplateArgument[] matchedArgs;
	Type matchee;

	SemanticPass pass;
	alias pass this;

	this(SemanticPass pass, TemplateArgument[] matchedArgs, Type matchee) {
		this.pass = pass;
		this.matchedArgs = matchedArgs;
		this.matchee = matchee.getCanonical();
	}

	bool visit(TemplateParameter p) {
		return this.dispatch(p);
	}

	bool visit(AliasTemplateParameter p) {
		matchedArgs[p.index] = TemplateArgument(matchee);
		return true;
	}

	bool visit(TypeTemplateParameter p) {
		auto originalMatchee = matchee;
		auto originalMatched = matchedArgs[p.index];
		matchedArgs[p.index] = TemplateArgument.init;

		auto ct = p.specialization.getCanonical();
		if (!StaticTypeMatcher(pass, matchedArgs, matchee).visit(ct)) {
			return false;
		}

		matchedArgs[p.index].apply!({
			matchedArgs[p.index] = TemplateArgument(originalMatchee);
		}, (_) {})();

		return originalMatched.apply!(() => true, (o) {
			static if (is(typeof(o) : Type)) {
				return matchedArgs[p.index].apply!(() => false, (m) {
					static if (is(typeof(m) : Type)) {
						import d.semantic.caster;
						return implicitCastFrom(pass, m, o) == CastKind.Exact;
					} else {
						return false;
					}
				})();
			} else {
				return false;
			}
		})();
	}
}

alias StaticTypeMatcher = TypeMatcher!false;
alias IftiTypeMatcher = TypeMatcher!true;

struct TypeMatcher(bool isIFTI) {
	TemplateArgument[] matchedArgs;
	Type matchee;

	SemanticPass pass;
	alias pass this;

	this(SemanticPass pass, TemplateArgument[] matchedArgs, Type matchee) {
		this.pass = pass;
		this.matchedArgs = matchedArgs;
		this.matchee = matchee.getCanonical();
	}

	bool visit(Type t) {
		return t.getCanonical().accept(this);
	}

	bool visit(BuiltinType t) {
		import d.semantic.caster;
		auto castKind = implicitCastFrom(pass, matchee, Type.get(t));
		return isIFTI
			? castKind > CastKind.Invalid
			: castKind == CastKind.Exact;
	}

	bool visitPointerOf(Type t) {
		if (matchee.kind != TypeKind.Pointer) {
			return false;
		}

		matchee = matchee.element.getCanonical();
		return visit(t);
	}

	bool visitSliceOf(Type t) {
		if (matchee.kind != TypeKind.Slice) {
			return false;
		}

		matchee = matchee.element.getCanonical();
		return visit(t);
	}

	bool visitArrayOf(uint size, Type t) {
		if (matchee.kind != TypeKind.Array) {
			return false;
		}

		if (matchee.size != size) {
			return false;
		}

		matchee = matchee.element.getCanonical();
		return visit(t);
	}

	bool visit(Struct s) {
		if (matchee.kind != TypeKind.Struct) {
			return false;
		}

		return s is matchee.dstruct;
	}

	bool visit(Class c) {
		assert(0, "Not implemented.");
	}

	bool visit(Enum e) {
		if (matchee.kind != TypeKind.Enum) {
			return visit(e.type);
		}

		return matchee.denum is e;
	}

	bool visit(TypeAlias a) {
		assert(0, "Not implemented.");
	}

	bool visit(Interface i) {
		assert(0, "Not implemented.");
	}

	bool visit(Union u) {
		if (matchee.kind != TypeKind.Union) {
			return false;
		}

		return u is matchee.dunion;
	}

	bool visit(Function f) {
		assert(0, "Not implemented.");
	}

	bool visit(Type[] seq) {
		assert(0, "Not implemented.");
	}

	bool visit(FunctionType f) {
		assert(0, "Not implemented.");
	}

	bool visit(Pattern p) {
		return p.accept(this);
	}

	bool visit(TypeTemplateParameter p) {
		auto i = p.index;
		return matchedArgs[i].apply!({
			matchedArgs[i] = TemplateArgument(matchee);
			return true;
		}, delegate bool(identified) {
			static if (is(typeof(identified) : Type)) {
				import d.semantic.caster;
				auto castKind = implicitCastFrom(pass, matchee, identified);
				return isIFTI
					? castKind > CastKind.Invalid
					: castKind == CastKind.Exact;
			} else {
				return false;
			}
		})();
	}

	bool visit(Type t, ValueTemplateParameter p) {
		if (matchee.kind != TypeKind.Array) {
			return false;
		}

		auto size = matchee.size;
		matchee = matchee.element.getCanonical();
		if (!visit(t)) {
			return false;
		}

		auto s = new IntegerLiteral(p.location, size,
		                            pass.object.getSizeT().type.builtin);

		return ValueMatcher(pass, matchedArgs, s).visit(p);
	}

	bool visit(Symbol s, TemplateArgument[] args) {
		// We are matching a template aggregate.
		if (!matchee.isAggregate()) {
			return false;
		}

		// If this is not a templated type, bail.
		auto a = matchee.aggregate;
		if (!a.inTemplate) {
			return false;
		}

		auto name = a.name;
		auto ti = cast(TemplateInstance) a.getParentScope();
		if (ti is null) {
			// Cannot find the template instance.
			return false;
		}

		if (args.length > ti.args.length) {
			// Incompatible argument count.
			return false;
		}

		// Match the template itself.
		Template t = ti.getTemplate();
		if (!SymbolMatcher(pass, matchedArgs, t).visit(s)) {
			return false;
		}

		// We got our instance, let's match parameters.
		foreach (i, arg; args) {
			if (arg.tag != TemplateArgument.Tag.Symbol) {
				assert(0, "Only symbols are implemented for now");
			}

			auto p =
				cast(TemplateParameter) arg.get!(TemplateArgument.Tag.Symbol);
			assert(p !is null, "Expected a tepmplate argument");

			if (!TemplateInstancier(pass)
				    .matchArgument(p, ti.args[i], matchedArgs)) {
				return false;
			}
		}

		return true;
	}

	import d.ir.error;
	bool visit(CompileError e) {
		assert(0, "Not implemented.");
	}
}

struct ValueMatcher {
	TemplateArgument[] matchedArgs;
	CompileTimeExpression matchee;

	SemanticPass pass;
	alias pass this;

	this(SemanticPass pass, TemplateArgument[] matchedArgs,
	     CompileTimeExpression matchee) {
		this.pass = pass;
		this.matchedArgs = matchedArgs;
		this.matchee = matchee;
	}

	bool visit(TemplateParameter p) {
		return this.dispatch(p);
	}

	private bool matchTyped(Type t, uint i) {
		if (t.kind == TypeKind.Pattern) {
			matchedArgs[i] = TemplateArgument(matchee);
			return IftiTypeMatcher(pass, matchedArgs, matchee.type).visit(t);
		}

		import d.semantic.caster;
		matchee =
			evaluate(buildImplicitCast(pass, matchee.location, t, matchee));

		import d.ir.error;
		if (cast(ErrorExpression) matchee) {
			return false;
		}

		matchedArgs[i] = TemplateArgument(matchee);
		return true;
	}

	bool visit(ValueTemplateParameter p) {
		return matchTyped(p.type, p.index);
	}

	bool visit(AliasTemplateParameter p) {
		matchedArgs[p.index] = TemplateArgument(matchee);
		return true;
	}

	bool visit(TypedAliasTemplateParameter p) {
		return matchTyped(p.type, p.index);
	}
}

struct SymbolMatcher {
	TemplateArgument[] matchedArgs;
	Symbol matchee;

	SemanticPass pass;
	alias pass this;

	this(SemanticPass pass, TemplateArgument[] matchedArgs, Symbol matchee) {
		this.pass = pass;
		this.matchedArgs = matchedArgs;
		this.matchee = matchee;
	}

	bool visit(Symbol s) {
		if (auto p = cast(TemplateParameter) s) {
			return visit(p);
		}

		// Peel aliases
		while (true) {
			auto a = cast(SymbolAlias) s;
			if (a is null) {
				break;
			}

			s = a;
		}

		// We have a match.
		return s is matchee;
	}

	bool visit(TemplateParameter p) {
		return this.dispatch(p);
	}

	bool visit(AliasTemplateParameter p) {
		matchedArgs[p.index] = TemplateArgument(matchee);
		return true;
	}

	bool visit(TypedAliasTemplateParameter p) {
		if (auto vs = cast(ValueSymbol) matchee) {
			import d.semantic.identifier : IdentifierResolver, apply;
			return IdentifierResolver(pass)
				.postProcess(p.location, vs).apply!(delegate bool(i) {
					alias T = typeof(i);
					static if (is(T : Expression)) {
						auto v = pass.evaluate(i);
						return ValueMatcher(pass, matchedArgs, v).visit(p);
					} else {
						return false;
					}
				})();
		}

		return false;
	}

	bool visit(TypeTemplateParameter p) {
		import d.semantic.identifier : IdentifierResolver, apply;
		return IdentifierResolver(pass)
			.postProcess(p.location, matchee).apply!(delegate bool(identified) {
				alias T = typeof(identified);
				static if (is(T : Type)) {
					return TypeParameterMatcher(pass, matchedArgs, identified)
						.visit(p);
				} else {
					return false;
				}
			})();
	}

	bool visit(ValueTemplateParameter p) {
		import d.semantic.identifier : IdentifierResolver, apply;
		return IdentifierResolver(pass)
			.postProcess(p.location, matchee).apply!(delegate bool(identified) {
				alias T = typeof(identified);
				static if (is(T : Expression)) {
					auto v = pass.evaluate(identified);
					return ValueMatcher(pass, matchedArgs, v).visit(p);
				} else {
					return false;
				}
			})();
	}
}
