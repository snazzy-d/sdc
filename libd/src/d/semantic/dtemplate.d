module d.semantic.dtemplate;

import d.semantic.semantic;

import d.ast.declaration;

import d.ir.dscope;
import d.ir.expression;
import d.ir.symbol;
import d.ir.type;

import d.location;

import std.algorithm;
import std.array;
import std.range;

struct TemplateInstancier {
	private SemanticPass pass;
	alias pass this;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	auto instanciate(Location location, OverloadSet s, TemplateArgument[] args, Expression[] fargs) {
		auto cds = s.set.filter!((t) {
			if (auto asTemplate = cast(Template) t) {
				return asTemplate.parameters.length >= args.length;
			}
			
			assert(0, "this isn't a template");
		});
		
		Template match;
		TemplateArgument[] matchedArgs;
		CandidateLoop: foreach(candidate; cds) {
			auto t = cast(Template) candidate;
			assert(t, "We should have ensured that we only have templates at this point.");
			
			scheduler.require(t);
			
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
				
				import d.exception;
				throw new CompileException(p.location, typeid(p).toString() ~ " not implemented");
			}
			
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
		
		assert(match);
		return instanciateFromResolvedArgs(location, match, matchedArgs);
	}
	
	auto instanciate(Location location, Template t, TemplateArgument[] args, Expression[] fargs = []) {
		scheduler.require(t);
		
		TemplateArgument[] matchedArgs;
		if (t.parameters.length > 0) {
			matchedArgs.length = t.parameters.length;
			
			auto match = matchArguments(t, args, fargs, matchedArgs);
			if (!match) {
				import d.exception;
				throw new CompileException(location, "No match");
			}
		}
		
		return instanciateFromResolvedArgs(location, t, matchedArgs);
	}
	
private:
	bool matchArguments(Template t, TemplateArgument[] args, Expression[] fargs, TemplateArgument[] matchedArgs) in {
		assert(t.step == Step.Processed);
		assert(t.parameters.length >= args.length);
		assert(matchedArgs.length == t.parameters.length);
	} body {
		uint i = 0;
		foreach(a; args) {
			if (!matchArgument(t.parameters[i++], a, matchedArgs)) {
				return false;
			}
		}
		
		if (fargs.length == t.ifti.length) {
			foreach(j, a; fargs) {
				if (!IftiTypeMatcher(pass, matchedArgs, a.type).visit(t.ifti[j])) {
					return false;
				}
			}
		}
		
		// Match unspecified parameters.
		foreach(a; matchedArgs[i .. $]) {
			if (!matchArgument(t.parameters[i++], a, matchedArgs)) {
				return false;
			}
		}
		
		return true;
	}
	
	bool matchArgument(TemplateParameter p, TemplateArgument a, TemplateArgument[] matchedArgs) {
		return a.apply!(function bool() {
			assert(0, "All passed argument must be defined.");
		}, (identified) {
			static if (is(typeof(identified) : Type)) {
				return TypeParameterMatcher(pass, matchedArgs, identified).visit(p);
			} else static if (is(typeof(identified) : Expression)) {
				return ValueMatcher(pass, matchedArgs, identified).visit(p);
			} else static if (is(typeof(identified) : Symbol)) {
				return SymbolMatcher(pass, matchedArgs, identified).visit(p);
			} else {
				return false;
			}
		})();
	}
	
	auto instanciateFromResolvedArgs(Location location, Template t, TemplateArgument[] args) in {
		assert(t.parameters.length == args.length);
	} body {
		auto i = 0;
		Symbol[] argSyms;
		// XXX: have to put array once again to avoid multiple map.
		string id = args.map!(
			a => a.apply!(function string() {
				assert(0, "All passed argument must be defined.");
			}, delegate string(identified) {
				auto p = t.parameters[i++];
				
				static if (is(typeof(identified) : Type)) {
					auto a = new TypeAlias(p.location, p.name, identified);
					
					import d.semantic.mangler;
					a.mangle = TypeMangler(pass).visit(identified);
					a.step = Step.Processed;
					
					argSyms ~= a;
					return "T" ~ a.mangle;
				} else static if (is(typeof(identified) : CompileTimeExpression)) {
					auto a = new ValueAlias(p.location, p.name, identified);
					a.storage = Storage.Enum;
					
					import d.semantic.mangler;
					a.mangle = TypeMangler(pass).visit(identified.type) ~ ValueMangler(pass).visit(identified);
					a.step = Step.Processed;
					
					argSyms ~= a;
					return "V" ~ a.mangle;
				} else static if (is(typeof(identified) : Symbol)) {
					auto a = new SymbolAlias(p.location, p.name, identified);
					
					import d.semantic.symbol;
					SymbolAnalyzer(pass).process(a);
					
					argSyms ~= a;
					return "S" ~ a.mangle;
				} else {
					assert(0, typeid(identified).toString() ~ " is not supported.");
				}
			})
		).array().join();
		
		return t.instances.get(id, {
			auto oldManglePrefix = pass.manglePrefix;
			auto oldScope = pass.currentScope;
			scope(exit) {
				pass.manglePrefix = oldManglePrefix;
				pass.currentScope = oldScope;
			}
			
			auto i = new TemplateInstance(location, t, argSyms);
			i.mangle = t.mangle ~ "T" ~ id ~ "Z";
			i.storage = t.storage;
			
			pass.scheduler.schedule(t, i);
			return t.instances[id] = i;
		}());
	}
}

alias TemplateArgument = Type.UnionType!(typeof(null), Symbol, CompileTimeExpression);

auto apply(alias undefinedHandler, alias handler)(TemplateArgument a) {
	alias Tag = typeof(a.tag);
	final switch(a.tag) with(Tag) {
		case Undefined :
			return undefinedHandler();
		
		case Symbol :
			return handler(a.get!Symbol);
		
		case CompileTimeExpression :
			return handler(a.get!CompileTimeExpression);
		
		case Type :
			return handler(a.get!Type);
	}
}

unittest {
	TemplateArgument.init.apply!(() {}, (i) { assert(0); })();
}

// Conflict with Interface in object.di
alias Interface = d.ir.symbol.Interface;

struct TypeParameterMatcher {
	TemplateArgument[] matchedArgs;
	Type matchee;
	
	// XXX: used only in one place in caster, can probably be removed.
	// XXX: it used to cast classes in a way that isn't useful here.
	// XXX: let's move it away when we have a context and cannonical types.
	SemanticPass pass;
	
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
		
		if (!StaticTypeMatcher(pass, matchedArgs, matchee).visit(p.specialization.getCanonical())) {
			return false;
		}
		
		matchedArgs[p.index].apply!({
			matchedArgs[p.index] = TemplateArgument(originalMatchee);
		}, (_) {})();
		
		return originalMatched.apply!({ return true; }, (o) {
			static if (is(typeof(o) : Type)) {
				return matchedArgs[p.index].apply!({ return false; }, (m) {
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
	
	// XXX: used only in one place in caster, can probably be removed.
	// XXX: it used to cast classes in a way that isn't useful here.
	// XXX: let's move it away when we have a context and cannonical types.
	SemanticPass pass;
	
	this(SemanticPass pass, TemplateArgument[] matchedArgs, Type matchee) {
		this.matchedArgs = matchedArgs;
		this.matchee = matchee.getCanonical();
	}
	
	bool visit(Type t) {
		return t.accept(this);
	}
	
	bool visit(BuiltinType t) {
		return (matchee.kind == TypeKind.Builtin)
			? t == matchee.builtin
			: false;
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
		assert(0, "Not implemented.");
	}
	
	bool visit(Class c) {
		assert(0, "Not implemented.");
	}
	
	bool visit(Enum e) {
		assert(0, "Not implemented.");
	}
	
	bool visit(TypeAlias a) {
		assert(0, "Not implemented.");
	}
	
	bool visit(Interface i) {
		assert(0, "Not implemented.");
	}
	
	bool visit(Union u) {
		assert(0, "Not implemented.");
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
}

struct ValueMatcher {
	TemplateArgument[] matchedArgs;
	CompileTimeExpression matchee;
	
	// XXX: used only in one place in caster, can probably be removed.
	// XXX: it used to cast classes in a way that isn't useful here.
	// XXX: let's move it away when we have a context and cannonical types.
	SemanticPass pass;
	
	this(SemanticPass pass, TemplateArgument[] matchedArgs, CompileTimeExpression matchee) {
		this.pass = pass;
		this.matchedArgs = matchedArgs;
		this.matchee = matchee;
	}
	
	bool visit(TemplateParameter p) {
		return this.dispatch(p);
	}
	
	bool visit(ValueTemplateParameter p) {
		matchedArgs[p.index] = TemplateArgument(matchee);
		
		// TODO: If IFTI fails, go for cast.
		return IftiTypeMatcher(pass, matchedArgs, matchee.type).visit(p.type);
	}
	
	bool visit(AliasTemplateParameter p) {
		matchedArgs[p.index] = TemplateArgument(matchee);
		return true;
	}
	
	bool visit(TypedAliasTemplateParameter p) {
		matchedArgs[p.index] = TemplateArgument(matchee);
		
		// TODO: If IFTI fails, go for cast.
		return IftiTypeMatcher(pass, matchedArgs, matchee.type).visit(p.type);
	}
}

struct SymbolMatcher {
	TemplateArgument[] matchedArgs;
	Symbol matchee;
	
	SemanticPass pass;
	
	this(SemanticPass pass, TemplateArgument[] matchedArgs, Symbol matchee) {
		this.pass = pass;
		this.matchedArgs = matchedArgs;
		this.matchee = matchee;
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
			matchedArgs[p.index] = TemplateArgument(vs);
			
			import d.semantic.identifier;
			return SymbolPostProcessor!(delegate bool(identified) {
				alias T = typeof(identified);
				static if (is(T : Expression)) {
					// TODO: If IFTI fails, go for cast.
					return IftiTypeMatcher(pass, matchedArgs, identified.type).visit(p.type);
				} else {
					return false;
				}
			})(pass, p.location).visit(vs);
		}
		
		return false;
	}
	
	bool visit(TypeTemplateParameter p) {
		import d.semantic.identifier;
		return SymbolPostProcessor!(delegate bool(identified) {
			alias T = typeof(identified);
			static if (is(T : Type)) {
				return TypeParameterMatcher(pass, matchedArgs, identified).visit(p);
			} else {
				return false;
			}
		})(pass, p.location).visit(matchee);
	}
	
	bool visit(ValueTemplateParameter p) {
		import d.semantic.identifier;
		return SymbolPostProcessor!(delegate bool(identified) {
			alias T = typeof(identified);
			static if (is(T : Expression)) {
				return ValueMatcher(pass, matchedArgs, pass.evaluate(identified)).visit(p);
			} else {
				return false;
			}
		})(pass, p.location).visit(matchee);
	}
}

