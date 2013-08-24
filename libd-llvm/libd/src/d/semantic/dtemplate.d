module d.semantic.dtemplate;

import d.semantic.identifiable;
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
		
		Symbol[] argSyms;
		uint i = 0;
		
		// XXX: have to put array once again.
		assert(t.parameters.length == args.length);
		string id = args.map!(
			a => a.apply!(delegate string(identified) {
				auto p = t.parameters[i++];
				
				static if(is(typeof(identified) : QualType)) {
					auto type = TypeMatcher(identified).visit(p);
					
					auto a = new TypeAlias(p.location, p.name, type);
					
					a.mangle = pass.typeMangler.visit(type);
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
	QualType matchee;
	
	this(QualType matchee) {
		this.matchee = peelAlias(matchee);
	}
	
	QualType visit(TemplateParameter p) {
		return this.dispatch(p);
	}
	
	QualType visit(TypeTemplateParameter p) {
		return visit(peelAlias(p.specialization));
	}
	
	QualType visit(QualType t) {
		return this.dispatch(t.type);
	}
	
	QualType visit(Type t) {
		return this.dispatch(t);
	}
	
	QualType visit(TemplatedType t) {
		return matchee;
	}
	
	QualType visit(PointerType t) {
		auto m = peelAlias(matchee).type;
		if(auto asPointer = cast(PointerType) m) {
			return TypeMatcher(asPointer.pointed).visit(t.pointed);
		}
		
		assert(0, matchee.toString() ~ " do not match");
	}
	
	QualType visit(SliceType t) {
		auto m = peelAlias(matchee).type;
		if(auto asSlice = cast(SliceType) m) {
			return TypeMatcher(asSlice.sliced).visit(t.sliced);
		}
		
		assert(0, matchee.toString() ~ " do not match");
	}
	
	QualType visit(ArrayType t) {
		auto m = peelAlias(matchee).type;
		if(auto asArray = cast(ArrayType) m) {
			// TODO: match values.
			assert(asArray.size == t.size, "array size do not match");
			
			return TypeMatcher(asArray.elementType).visit(t.elementType);
		}
		
		assert(0, matchee.toString() ~ " do not match");
	}
}

