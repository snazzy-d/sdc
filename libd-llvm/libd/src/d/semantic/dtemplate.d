module d.semantic.dtemplate;

import d.semantic.semantic;

import d.ast.declaration;

import d.ir.dscope;
import d.ir.dtemplate;
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
			if(auto asTemplate = cast(Template) t) {
				return asTemplate.parameters.length >= args.length;
			}
			
			assert(0, "this isn't a template");
		});
		
		Template match;
		TemplateArgument[] matchedArgs;
		CandidateLoop: foreach(candidate; cds) {
			auto t = cast(Template) candidate;
			assert(t, "We should have ensured that we only have templates at this point.");
			
			TemplateArgument[] cdArgs;
			cdArgs.length = t.parameters.length;
			if(!matchArguments(t, args, fargs, cdArgs)) {
				continue CandidateLoop;
			}
			
			if(!match) {
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
			
			if(t2match == match2t) {
				assert(0, "Ambiguous template");
			}
			
			if(t2match) {
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
		if(t.parameters.length > 0) {
			matchedArgs.length = t.parameters.length;
			
			auto match = matchArguments(t, args, fargs, matchedArgs);
			if (!match) {
				import d.exception;
				throw new CompileException(location, "No match");
			}
		}
		
		return instanciateFromResolvedArgs(location, t, matchedArgs);
	}
	
	bool matchArguments(Template t, TemplateArgument[] args, Expression[] fargs, TemplateArgument[] matchedArgs) {
		scheduler.require(t);
		assert(t.parameters.length >= args.length);
		assert(matchedArgs.length == t.parameters.length);
		
		uint i = 0;
		foreach(a; args) {
			if(!matchArgument(t.parameters[i++], a, matchedArgs)) {
				return false;
			}
		}
		
		foreach(j, a; fargs) {
			if(!IftiTypeMatcher(matchedArgs, a.type).visit(t.ifti[j])) {
				return false;
			}
		}
		
		// Match unspecified parameters.
		foreach(a; matchedArgs[i .. $]) {
			if(!matchArgument(t.parameters[i++], a, matchedArgs)) {
				return false;
			}
		}
		
		return true;
	}
	
	bool matchArgument(TemplateParameter p, TemplateArgument a, TemplateArgument[] matchedArgs) {
		return a.apply!(function bool() {
			assert(0, "All passed argument must be defined.");
		}, (identified) {
			static if(is(typeof(identified) : QualType)) {
				return TypeMatcher(pass, matchedArgs, identified).visit(p);
			} else static if(is(typeof(identified) : Expression)) {
				return ValueMatcher(pass, matchedArgs, identified).visit(p);
			} else static if(is(typeof(identified) : Symbol)) {
				return SymbolMatcher(pass, matchedArgs, identified).visit(p);
			} else {
				return false;
			}
		})();
	}
	
	auto instanciateFromResolvedArgs(Location location, Template t, TemplateArgument[] args) {
		assert(t.parameters.length == args.length);
		
		auto i = 0;
		Symbol[] argSyms;
		// XXX: have to put array once again to avoid multiple map.
		string id = args.map!(
			a => a.apply!(function string() {
				assert(0, "All passed argument must be defined.");
			}, delegate string(identified) {
				auto p = t.parameters[i++];
				
				static if(is(typeof(identified) : QualType)) {
					auto a = new TypeAlias(p.location, p.name, identified);
					
					import d.semantic.mangler;
					a.mangle = TypeMangler(pass).visit(identified);
					a.step = Step.Processed;
					
					argSyms ~= a;
					return "T" ~ a.mangle;
				} else static if(is(typeof(identified) : CompileTimeExpression)) {
					auto a = new ValueAlias(p.location, p.name, identified);
					
					import d.ast.base;
					a.storage = Storage.Enum;
					
					import d.semantic.mangler;
					a.mangle = TypeMangler(pass).visit(identified.type) ~ ValueMangler(pass).visit(identified);
					a.step = Step.Processed;
					
					argSyms ~= a;
					return "V" ~ a.mangle;
				} else static if(is(typeof(identified) : Symbol)) {
					auto a = new SymbolAlias(p.location, p.name, identified);
					
					import d.semantic.symbol;
					auto sa = SymbolAnalyzer(pass);
					sa.process(a);
					
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
			
			pass.scheduler.schedule(t, i);
			return t.instances[id] = i;
		}());
	}
}

enum Tag {
	Undefined,
	Symbol,
	Expression,
	Type,
}

struct TemplateArgument {
	union {
		Symbol sym;
		CompileTimeExpression expr;
		Type type;
	}
	
	import d.ast.base : TypeQualifier;
	
	import std.bitmanip;
	mixin(bitfields!(
		Tag, "tag", 2,
		TypeQualifier, "qual", 3,
		uint, "", 3,
	));
	
	// For type inference.
	this(typeof(null));
	
	this(TemplateArgument a) {
		this = a;
	}
	
	this(Symbol s) {
		tag = Tag.Symbol;
		sym = s;
	}
	
	this(CompileTimeExpression e) {
		tag = Tag.Expression;
		expr = e;
	}
	
	this(QualType qt) {
		tag = Tag.Type;
		qual = qt.qualifier;
		type = qt.type;
	}
}

unittest {
	static assert(TemplateArgument.init.tag == Tag.Undefined);
}

auto apply(alias undefinedHandler, alias handler)(TemplateArgument a) {
	final switch(a.tag) with(Tag) {
		case Undefined :
			return undefinedHandler();
		
		case Symbol :
			return handler(a.sym);
		
		case Expression :
			return handler(a.expr);
		
		case Type :
			return handler(QualType(a.type, a.qual));
	}
}

struct TypeMatcher {
	TemplateArgument[] matchedArgs;
	QualType matchee;
	
	// XXX: used only in one place in caster, can probably be removed.
	// XXX: it used to cast classes in a way that isn't useful here.
	// XXX: let's move it away when we have a context and cannonical types.
	SemanticPass pass;
	
	this(SemanticPass pass, TemplateArgument[] matchedArgs, QualType matchee) {
		this.pass = pass;
		this.matchedArgs = matchedArgs;
		this.matchee = peelAlias(matchee);
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
		
		if(!visit(peelAlias(p.specialization))) {
			return false;
		}
		
		matchedArgs[p.index].apply!({
			matchedArgs[p.index] = TemplateArgument(originalMatchee);
		}, (_) {})();
		
		return originalMatched.apply!({ return true; }, (o) {
			static if(is(typeof(o) : QualType)) {
				return matchedArgs[p.index].apply!({ return false; }, (m) {
					static if(is(typeof(m) : QualType)) {
						import d.semantic.caster;
						import d.ir.expression;
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
	
	bool visit(QualType t) {
		return this.dispatch(t.type);
	}
	
	bool visit(Type t) {
		return this.dispatch(t);
	}
	
	bool visit(TemplatedType t) {
		auto i = t.param.index;
		return matchedArgs[i].apply!({
			matchedArgs[i] = TemplateArgument(matchee);
			return true;
		}, delegate bool(identified) {
			static if(is(typeof(identified) : QualType)) {
				import d.semantic.caster;
				import d.ir.expression;
				return implicitCastFrom(pass, matchee, identified) == CastKind.Exact;
			} else {
				return false;
			}
		})();
	}
	
	bool visit(PointerType t) {
		auto m = peelAlias(matchee).type;
		if(auto asPointer = cast(PointerType) m) {
			matchee = asPointer.pointed;
			return visit(t.pointed);
		}
		
		return false;
	}
	
	bool visit(SliceType t) {
		auto m = peelAlias(matchee).type;
		if(auto asSlice = cast(SliceType) m) {
			matchee = asSlice.sliced;
			return visit(t.sliced);
		}
		
		return false;
	}
	
	bool visit(ArrayType t) {
		auto m = peelAlias(matchee).type;
		if(auto asArray = cast(ArrayType) m) {
			if(asArray.size == t.size) {
				matchee = asArray.elementType;
				return visit(t.elementType);
			}
		}
		
		return false;
	}
	
	bool visit(BuiltinType t) {
		auto m = peelAlias(matchee).type;
		if(auto asBuiltin = cast(BuiltinType) m) {
			return t.kind == asBuiltin.kind;
		}
		
		return false;
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
		return IftiTypeMatcher(matchedArgs, matchee.type).visit(p.type);
	}
	
	bool visit(AliasTemplateParameter p) {
		matchedArgs[p.index] = TemplateArgument(matchee);
		return true;
	}
	
	bool visit(TypedAliasTemplateParameter p) {
		matchedArgs[p.index] = TemplateArgument(matchee);
		
		// TODO: If IFTI fails, go for cast.
		return IftiTypeMatcher(matchedArgs, matchee.type).visit(p.type);
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
		if(auto vs = cast(ValueSymbol) matchee) {
			matchedArgs[p.index] = TemplateArgument(vs);
			
			import d.semantic.identifier;
			return IdentifierVisitor!(delegate bool(identified) {
				alias type = typeof(identified);
				
				// IdentifierVisitor must know the return value of the closure.
				// To do so, it instanciate it with null as parameter.
				static if(is(type : Expression) && !is(type == typeof(null))) {
					// TODO: If IFTI fails, go for cast.
					return IftiTypeMatcher(matchedArgs, identified.type).visit(p.type);
				} else {
					return false;
				}
			})(pass).visit(p.location, vs);
		}
		
		return false;
	}
	
	bool visit(TypeTemplateParameter p) {
		import d.semantic.identifier;
		return IdentifierVisitor!(delegate bool(identified) {
			static if(is(typeof(identified) : QualType)) {
				return TypeMatcher(pass, matchedArgs, identified).visit(p);
			} else {
				return false;
			}
		})(pass).visit(p.location, matchee);
	}
	
	bool visit(ValueTemplateParameter p) {
		import d.semantic.identifier;
		return IdentifierVisitor!(delegate bool(identified) {
			static if(is(typeof(identified) : Expression)) {
				return ValueMatcher(pass, matchedArgs, pass.evaluate(identified)).visit(p);
			} else {
				return false;
			}
		})(pass).visit(p.location, matchee);
	}
}

// XXX: Massive code duplication as static if somehow do not work here.
// XXX: probable a dmd bug, but I have no time to investigate.
struct IftiTypeMatcher {
	TemplateArgument[] matchedArgs;
	QualType matchee;
	
	this(TemplateArgument[] matchedArgs, QualType matchee) {
		this.matchedArgs = matchedArgs;
		this.matchee = peelAlias(matchee);
	}
	
	bool visit(QualType t) {
		return visit(t.type);
	}
	
	bool visit(Type t) {
		return this.dispatch(t);
	}
	
	bool visit(TemplatedType t) {
		auto i = t.param.index;
		return matchedArgs[i].apply!({
			matchedArgs[i] = TemplateArgument(matchee);
			return true;
		}, delegate bool(identified) {
			return true;
		})();
	}
	
	bool visit(PointerType t) {
		auto m = peelAlias(matchee).type;
		if(auto asPointer = cast(PointerType) m) {
			matchee = asPointer.pointed;
			return visit(t.pointed);
		}
		
		return false;
	}
	
	bool visit(SliceType t) {
		auto m = peelAlias(matchee).type;
		if(auto asSlice = cast(SliceType) m) {
			matchee = asSlice.sliced;
			return visit(t.sliced);
		}
		
		return false;
	}
	
	bool visit(ArrayType t) {
		auto m = peelAlias(matchee).type;
		if(auto asArray = cast(ArrayType) m) {
			if(asArray.size == t.size) {
				matchee = asArray.elementType;
				return visit(t.elementType);
			}
		}
		
		return false;
	}
	
	bool visit(BuiltinType t) {
		auto m = peelAlias(matchee).type;
		if(auto asBuiltin = cast(BuiltinType) m) {
			return t.kind == asBuiltin.kind;
		}
		
		return false;
	}
}

