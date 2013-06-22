/**
 * This module crawl the AST to resolve identifiers and process types.
 */
module d.semantic.dmodule;

import d.semantic.semantic;

import d.ast.declaration;
import d.ast.dmodule;

import d.ir.symbol;

import d.processor.scheduler;

import d.location;

import std.algorithm;
import std.array;
import std.range; // for range.

alias AstModule = d.ast.dmodule.Module;
alias Module = d.ir.symbol.Module;

final class ModuleVisitor {
	private SemanticPass pass;
	alias pass this;
	
	private FileSource delegate(string[]) sourceFactory;
	
	private Module[string] cachedModules;
	
	this(SemanticPass pass, FileSource delegate(string[]) sourceFactory) {
		this.pass = pass;
		this.sourceFactory = sourceFactory;
	}
	
	Module visit(AstModule astm) {
		auto oldCurrentScope = currentScope;
		auto oldIsStatic = isStatic;
		auto oldManglePrefix = manglePrefix;
		scope(exit) {
			currentScope = oldCurrentScope;
			isStatic = oldIsStatic;
			manglePrefix = oldManglePrefix;
		}
		
		// FIXME: scope.
		// currentScope = m.dscope;
		isStatic = true;
		manglePrefix = "";
		
		import std.conv;
		auto current = astm.parent;
		while(current) {
			manglePrefix = to!string(current.name.length) ~ current.name ~ manglePrefix;
			current = current.parent;
		}
		
		manglePrefix ~= to!string(astm.name.length) ~ astm.name;
		
		// FIXME: actually create a module :D
		Module m;
		
		// All modules implicitely import object.
		m.members = pass.flatten(new ImportDeclaration(m.location, [["object"]]) ~ astm.declarations, m);
		m.step = Step.Populated;
		
		scheduler.require(m.members);
		
		m.step = Step.Processed;
		return m;
	}
	/+
	Module importModule(string[] packages) {
		auto name = packages.join(".");
		
		return cachedModules.get(name, {
			auto source = sourceFactory(packages);
			auto mod = pass.parse(source, packages);
			
			pass.scheduler.schedule(only(mod), (s) {
				auto m = cast(Module) s;
				assert(m, "How come that this isn't a module ?");
				
				return visit(m);
			});
			
			return cachedModules[name] = mod;
		}());
	}
	+/
	// XXX: temporary hack to preregister modules
	void preregister(Module mod) {
		cachedModules[getModuleName(mod)] = mod;
	}
}

private auto getModuleName(Module m) {
	auto name = m.name;
	if(m.parent) {
		auto dpackage = m.parent;
		while(dpackage) {
			name = dpackage.name ~ "." ~ name;
			dpackage = dpackage.parent;
		}
	}
	
	return name;
}

