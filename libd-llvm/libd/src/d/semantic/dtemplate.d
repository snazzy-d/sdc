module d.semantic.dtemplate;

import d.semantic.identifier : Identifiable, apply;

import d.semantic.semantic;

import d.ast.declaration;

import d.ir.dscope;
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
	
	auto instanciate(Location location, Template t, Identifiable[] args) {
		scheduler.require(t);
		
		assert(t.parameters.length >= args.length);
		Identifiable[] resolvedArgs = t.parameters.map!(p => Identifiable.init).array();
		
		uint i = 0;
		foreach(a; args) {
			a.apply!((identified) {
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
			a.apply!((identified) {
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
			a => a.apply!(delegate string(identified) {
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

struct TypeMatcher {
	// XXX: used only in one place in caster, can probably be removed.
	SemanticPass pass;
	
	Identifiable[] resolvedArgs;
	QualType matchee;
	
	this(SemanticPass pass, Identifiable[] resolvedArgs, QualType matchee) {
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
		
		resolvedArgs[p.index].apply!((identified) {
			static if(is(typeof(identified) : Symbol)) {
				if(identified is null) {
					resolvedArgs[p.index] = Identifiable(originalMatchee);
				}
			}
		})();
		
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
		return resolvedArgs[i].apply!(delegate bool(identified) {
			static if(is(typeof(identified) : Symbol)) {
				if(identified is null) {
					resolvedArgs[i] = Identifiable(matchee);
					return true;
				}
				
				return false;
			} else static if(is(typeof(identified) : QualType)) {
				import d.semantic.caster;
				import d.ir.expression;
				return implicitCastFrom(pass, matchee, identified) == CastKind.Exact;
			} else {
				assert(0, "Expressions are not supported");
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

