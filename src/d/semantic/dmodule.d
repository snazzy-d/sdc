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

import sdc.location;

import std.algorithm;
import std.array;

final class ModuleVisitor {
	private SemanticPass pass;
	alias pass this;
	
	private Module[string] cachedModules;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	auto getModuleName(Module m) {
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
	
	Module visit(Module m) {
		auto name = getModuleName(m);
		
		auto oldCurrentScope = currentScope;
		scope(exit) currentScope = oldCurrentScope;
		
		currentScope = m.dscope;
		
		auto oldSymbol = symbol;
		scope(exit) symbol = oldSymbol;
		
		symbol = m;
		
		import std.conv;
		
		manglePrefix = "";
		auto current = m.parent;
		while(current) {
			manglePrefix = to!string(current.name.length) ~ current.name ~ manglePrefix;
			current = current.parent;
		}
		
		manglePrefix ~= to!string(m.name.length) ~ m.name;
		
		auto syms = cast(Symbol[]) m.declarations;
		m.declarations = cast(Declaration[]) scheduler.schedule(syms, d => pass.visit(d));
		
		return m;
	}
}

