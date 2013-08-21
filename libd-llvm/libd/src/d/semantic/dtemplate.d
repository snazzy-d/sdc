module d.semantic.dtemplate;

import d.semantic.identifiable;
import d.semantic.semantic;

import d.ast.declaration;
import d.ast.identifier;

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
	
	auto instanciate(Location location, Template t, TemplateArgument[] args) {
		scheduler.require(t);
		
		Symbol[] argSyms;
		uint i = 0;
		
		// XXX: have to put array once again.
		assert(t.parameters.length == args.length);
		string id = args.map!(
			arg => visit(arg).apply!(delegate string(identified) {
				static if(is(typeof(identified) : QualType)) {
					auto a = new TypeAlias(arg.location, t.parameters[i++].name, identified);
					
					a.mangle = pass.typeMangler.visit(a.type);
					a.step = Step.Processed;
					
					argSyms ~= a;
					
					return "T" ~ pass.typeMangler.visit(identified);
				} else {
					assert(0, "Only type argument are supported.");
				}
			})
		).array().join();
		
		return t.instances.get(id, {
			auto oldManglePrefix = pass.manglePrefix;
			auto oldLinkage = pass.linkage;
			auto oldIsStatic = pass.isStatic;
			auto oldScope = pass.currentScope;
			scope(exit) {
				pass.manglePrefix = oldManglePrefix;
				pass.linkage = oldLinkage;
				pass.isStatic = oldIsStatic;
				pass.currentScope = oldScope;
			}
			
			auto instance = new TemplateInstance(location, t, []);
			
			pass.manglePrefix = t.mangle ~ "T" ~ id ~ "Z";
			pass.linkage = t.linkage;
			pass.isStatic = t.isStatic;
			auto dscope = pass.currentScope = instance.dscope = new SymbolScope(instance, t.parentScope);
			
			foreach(s; argSyms) {
				dscope.addSymbol(s);
			}
			
			// XXX: that is doomed to explode fireworks style.
			pass.scheduler.schedule(only(instance), i => visit(cast(TemplateInstance) i));
			instance.members = argSyms ~ pass.flatten(t.members, instance);
			
			return t.instances[id] = instance;
		}());
	}
	
	TemplateInstance visit(TemplateInstance instance) {
		pass.scheduler.require(instance.members);
		
		instance.step = Step.Processed;
		
		return instance;
	}
	
	Identifiable visit(TemplateArgument arg) {
		return this.dispatch(arg);
	}
	
	Identifiable visit(TypeTemplateArgument arg) {
		return Identifiable(pass.visit(arg.type));
	}
	
	Identifiable visit(IdentifierTemplateArgument arg) {
		return pass.visit(arg.identifier);
	}
}

