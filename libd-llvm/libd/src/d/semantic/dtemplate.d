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

final class TemplateInstancier {
	private SemanticPass pass;
	alias pass this;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	auto instanciate(Location location, Template t, TemplateArgument[] args) {
		scheduler.require(t);
		
		assert(t.parameters.length >= args.length);
		TemplateArgument[] resolvedArgs;
		resolvedArgs.length = t.parameters.length;
		
		uint i = 0;
		foreach(a; args) {
			a.apply!({
				assert(0, "All passed argument must be defined.");
			}, (identified) {
				auto p = t.parameters[i++];
				static if(is(typeof(identified) : QualType)) {
					assert(TypeMatcher(pass, resolvedArgs, identified).visit(p), identified.toString() ~ " do not match");
				} else {
					assert(0, "Only type argument are supported.");
				}
			})();
		}
		
		// Match unspecified parameters.
		foreach(a; resolvedArgs[i .. $]) {
			a.apply!({
				assert(0, "All passed argument must be defined.");
			}, (identified) {
				auto p = t.parameters[i++];
				static if(is(typeof(identified) : QualType)) {
					assert(TypeMatcher(pass, resolvedArgs, identified).visit(p), identified.toString() ~ " do not match");
				} else {
					assert(0, "Only type argument are supported.");
				}
			})();
		}
		
		i = 0;
		Symbol[] argSyms;
		// XXX: have to put array once again to avoid multiple map.
		string id = resolvedArgs.map!(
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
			
			pass.scheduler.schedule(only(instance), i => visit(cast(TemplateInstance) i));
			instance.members = argSyms ~ dv.flatten(t.members, instance);
			
			return t.instances[id] = instance;
		}());
	}
	
	TemplateInstance visit(TemplateInstance instance) {
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
	// XXX: used only in one place in caster, can probably be removed.
	SemanticPass pass;
	
	TemplateArgument[] resolvedArgs;
	QualType matchee;
	
	this(SemanticPass pass, TemplateArgument[] resolvedArgs, QualType matchee) {
		this.pass = pass;
		this.resolvedArgs = resolvedArgs;
		this.matchee = peelAlias(matchee);
	}
	
	bool visit(TemplateParameter p) {
		return this.dispatch(p);
	}
	
	bool visit(TypeTemplateParameter p) {
		auto originalMatchee = matchee;
		auto match = visit(peelAlias(p.specialization));
		
		resolvedArgs[p.index].apply!({
			resolvedArgs[p.index] = TemplateArgument(originalMatchee);
		}, (_) {})();
		
		return match;
	}
	
	bool visit(QualType t) {
		return this.dispatch(t.type);
	}
	
	bool visit(Type t) {
		return this.dispatch(t);
	}
	
	bool visit(TemplatedType t) {
		auto i = t.param.index;
		return resolvedArgs[i].apply!({
			resolvedArgs[i] = TemplateArgument(matchee);
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
}

