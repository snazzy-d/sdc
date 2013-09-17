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
	
	auto instanciate(Location location, OverloadSet s, TemplateArgument[] args) {
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
			if(!matchArguments(t, args, cdArgs)) {
				continue CandidateLoop;
			}
			
			if(!match) {
				match = t;
				matchedArgs = cdArgs;
				continue CandidateLoop;
			}
			
			TemplateArgument[] dummy;
			dummy.length = t.parameters.length;
			
			auto asArg = match.parameters.map!(p => TemplateArgument((cast(TypeTemplateParameter) p).specialization)).array();
			bool match2t = matchArguments(t, asArg, dummy);
			
			dummy = null;
			dummy.length = match.parameters.length;
			asArg = t.parameters.map!(p => TemplateArgument((cast(TypeTemplateParameter) p).specialization)).array();
			bool t2match = matchArguments(match, asArg, dummy);
			
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
			
			auto match = matchArguments(t, args, matchedArgs, fargs);
			assert(match, "no match");
		}
		
		return instanciateFromResolvedArgs(location, t, matchedArgs);
	}
	
	bool matchArguments(Template t, TemplateArgument[] args, TemplateArgument[] matchedArgs, Expression[] fargs = []) {
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
					
					a.mangle = pass.typeMangler.visit(identified);
					a.step = Step.Processed;
					
					argSyms ~= a;
					
					return "T" ~ a.mangle;
				} else {
					assert(0, "Only type argument are supported.");
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
			
			auto instance = new TemplateInstance(location, t, []);
			
			pass.manglePrefix = t.mangle ~ "T" ~ id ~ "Z";
			auto dscope = pass.currentScope = instance.dscope = new SymbolScope(instance, t.dscope);
			
			foreach(s; argSyms) {
				dscope.addSymbol(s);
			}
			
			// XXX: that is doomed to explode fireworks style.
			import d.semantic.declaration;
			auto dv = DeclarationVisitor(pass, t.linkage, t.isStatic);
			
			auto localPass = pass;
			pass.scheduler.schedule(only(instance), i => visit(localPass, cast(TemplateInstance) i));
			instance.members = argSyms ~ dv.flatten(t.members, instance);
			
			return t.instances[id] = instance;
		}());
	}
	
	static auto visit(SemanticPass pass, TemplateInstance instance) {
		pass.scheduler.require(instance.members);
		
		instance.step = Step.Processed;
		
		return instance;
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
		Expression expr;
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
	
	this(Expression e) {
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

TemplateArgument argHandler(T)(T t) {
	static if(is(T == typeof(null))) {
		assert(0);
	} else {
		return TemplateArgument(t);
	}
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

