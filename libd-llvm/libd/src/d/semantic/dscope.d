/**
 * This prepare scopes for identifiers resolution.
 */
module d.semantic.dscope;

import d.semantic.base;
import d.semantic.flatten;

import d.ast.dmodule;

import std.algorithm;
import std.array;
import std.range;

import d.ast.adt;
import d.ast.conditional;
import d.ast.dfunction;
import d.ast.dscope;
import d.ast.dtemplate;
import d.ast.declaration;

import d.parser.base;

class ScopePass {
	private FlattenPass flattenPass;
	
	Scope currentScope;
	private Scope adtScope;
	
	private uint scopeIndex;
	
	private Module[string] cachedModules;
	
	this() {
		flattenPass = new FlattenPass();
	}
	
final:
	Module[] visit(Module[] modules) {
		modules = flattenPass.visit(modules);
		
		// Must be separated because ~ operator don't preserve order of execution.
		modules = modules.map!(m => visit(m)).array();
		
		// XXX: dirty hack to get the right module as last one.
		cachedModules.remove(getModuleName(modules.back));
		
		return cachedModules.values ~ modules.back;
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
	
	private Module visit(Module m) {
		auto name = getModuleName(m);
		
		return cachedModules.get(name, {
			auto oldScope = currentScope;
			scope(exit) currentScope = oldScope;
			
			// XXX: hack around the fact that scope will be filled latter now.
			currentScope = new Scope();
			
			cachedModules[name] = m;
			
			visit(new ImportDeclaration(m.location, [["object"]]));
			m.declarations = visit(m.declarations);
			
			m.dscope.imports = currentScope.imports;
			
			return m;
		}());
	}
	
	auto visit(Declaration[] decls) {
		Declaration[] ret;
		foreach(d; decls) {
			if(auto imp = cast(ImportDeclaration) d) {
				visit(imp);
			} else {
				ret ~= d;
			}
		}
		
		return ret;
	}
	
	void visit(ImportDeclaration d) {
		auto names = d.modules.map!(pkg => pkg.join(".")).array();
		auto filenames = d.modules.map!(pkg => pkg.join("/") ~ ".d").array();
		
		Module[] addToScope;
		foreach(name, filename; lockstep(names, filenames)) {
			addToScope ~= cachedModules.get(name, {
				import sdc.lexer;
				import sdc.source;
				import sdc.sdc;
				import sdc.tokenstream;
				
				auto src = new Source(filename);
				auto trange = TokenRange(lex(src));
				
				auto packages = filename[0 .. $-2].split("/");
				auto mod = trange.parse(packages.back, packages[0 .. $-1]);
				
				return visit(flattenPass.visit([mod]).back);
			}());
		}
		
		currentScope.imports ~= addToScope;
	}
}

