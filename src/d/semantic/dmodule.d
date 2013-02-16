/**
 * This module crawl the AST to resolve identifiers and process types.
 */
module d.semantic.dmodule;

import d.semantic.base;
import d.semantic.semantic;

import d.ast.declaration;
import d.ast.dmodule;
import d.ast.dscope;

import d.parser.base;

import d.processor.scheduler;

import d.location;

import std.algorithm;
import std.array;
import std.range; // for range.

final class ModuleVisitor {
	private SemanticPass pass;
	alias pass this;
	
	private Module[string] cachedModules;
	
	this(SemanticPass pass) {
		this.pass = pass;
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
		
		// All modules implicitely import object.
		auto syms = pass.visit(new ImportDeclaration(m.location, [["object"]]) ~ m.declarations, m);
		
		import std.conv;
		manglePrefix = "";
		auto current = m.parent;
		while(current) {
			manglePrefix = to!string(current.name.length) ~ current.name ~ manglePrefix;
			current = current.parent;
		}
		
		manglePrefix ~= to!string(m.name.length) ~ m.name;
		
		m.declarations = cast(Declaration[]) scheduler.require(syms);
		
		scheduler.register(m, m, Step.Processed);
		
		return m;
	}
	
	Module importModule(string[] pkgs) {
		auto name = pkgs.join(".");
		auto filename = pkgs.join("/") ~ ".d";
		
		return cachedModules.get(name, {
			import d.lexer;
			
			auto fileSource = new FileSource(filename);
			auto trange = lex!((line, index, length) => Location(fileSource, line, index, length))(fileSource.content);
			
			auto packages = filename[0 .. $-2].split("/");
			auto mod = trange.parse(packages.back, packages[0 .. $-1]);
			
			cachedModules[name] = mod;
			
			pass.scheduler.schedule(only(mod), (s) {
				auto m = cast(Module) s;
				assert(m, "How come that this isn't a module ?");
				
				return visit(m);
			});
			
			return mod;
		}());
	}
	
	// XXX: temporary hack to preregister modules
	void preregister(Module[] modules) {
		foreach(m; modules) {
			cachedModules[getModuleName(m)] = m;
		}
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

