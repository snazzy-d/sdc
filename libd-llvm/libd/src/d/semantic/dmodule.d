/**
 * This module crawl the AST to resolve identifiers and process types.
 */
module d.semantic.dmodule;

import d.semantic.base;
import d.semantic.semantic;

import d.ast.declaration;
import d.ast.dmodule;
import d.ast.dscope;

import d.processor.scheduler;

import d.location;

import std.algorithm;
import std.array;
import std.range; // for range.

final class ModuleVisitor {
	private SemanticPass pass;
	alias pass this;
	
	private FileSource delegate(string[]) sourceFactory;
	
	private Module[string] cachedModules;
	
	this(SemanticPass pass, FileSource delegate(string[]) sourceFactory) {
		this.pass = pass;
		this.sourceFactory = sourceFactory;
	}
	
	Module visit(Module m) {
		auto name = getModuleName(m);
		
		auto oldCurrentScope = currentScope;
		scope(exit) currentScope = oldCurrentScope;
		
		currentScope = m.dscope;
		
		auto oldSymbol = symbol;
		scope(exit) symbol = oldSymbol;
		
		symbol = m;
		
		auto oldIsStatic = isStatic;
		scope(exit) isStatic = oldIsStatic;
		
		isStatic = true;
		
		// Update mangle prefix.
		auto oldManglePrefix = manglePrefix;
		scope(exit) manglePrefix = oldManglePrefix;
		
		import std.conv;
		
		manglePrefix = "";
		auto current = m.parent;
		while(current) {
			manglePrefix = to!string(current.name.length) ~ current.name ~ manglePrefix;
			current = current.parent;
		}
		
		manglePrefix ~= to!string(m.name.length) ~ m.name;
		
		// All modules implicitely import object.
		auto syms = pass.flatten(new ImportDeclaration(m.location, [["object"]]) ~ m.declarations, m);
		
		m.declarations = cast(Declaration[]) scheduler.require(syms);
		
		scheduler.register(m, m, Step.Processed);
		
		return m;
	}
	
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

