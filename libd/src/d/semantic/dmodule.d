/**
 * This module crawl the AST to resolve identifiers and process types.
 */
module d.semantic.dmodule;

import d.semantic.scheduler;
import d.semantic.semantic;

import d.ast.declaration;
import d.ast.dmodule;

import d.ir.symbol;

import d.base.name;

import d.location;

alias AstModule = d.ast.dmodule.Module;
alias Module = d.ir.symbol.Module;

alias AstPackage = d.ast.dmodule.Package;
alias Package = d.ir.symbol.Package;

alias SourceFactory = Source delegate(Name[]);
alias PackageNames = Name[];

final class ModuleVisitor {
	private SemanticPass pass;
	alias pass this;
	
	private SourceFactory sourceFactory;
	
	private Module[string] cachedModules;
	
	this(SemanticPass pass, SourceFactory sourceFactory) {
		this.pass = pass;
		this.sourceFactory = sourceFactory;
	}
	
	Module importModule(PackageNames packages) {
		import std.algorithm, std.range;
		auto name = packages.map!(p => p.toString(pass.context)).join(".");
		
		return cachedModules.get(name, {
			auto source = sourceFactory(packages);
			auto astm = pass.parse(source, packages);
			auto mod = modulize(astm);
			
			pass.scheduler.schedule(astm, mod);
			
			return cachedModules[name] = mod;
		}());
	}
	
	// XXX: temporary hack to preregister modules
	void preregister(Module mod) {
		cachedModules[getModuleName(mod)] = mod;
	}
	
	Module modulize(AstModule m) {
		auto parent = modulize(m.parent);
		
		auto ret = new Module(m.location, m.name, parent);
		
		void prepareScope(Package p) {
			if(p.parent) {
				prepareScope(p.parent);
				
				p.parent.dscope.addSymbol(p);
			}
			
			import d.ir.dscope;
			p.dscope = new Scope(ret);
		}
		
		prepareScope(ret);
		ret.dscope.addSymbol(ret);
		
		return ret;
	}
	
	Package modulize(AstPackage p) {
		if(p is null) {
			return null;
		}
		
		auto parent = modulize(p.parent);
		
		return new Package(p.location, p.name, parent);
	}
	
	private auto getModuleName(Module m) {
		auto name = m.name.toString(context);
		if(m.parent) {
			auto dpackage = m.parent;
			while(dpackage) {
				name = dpackage.name.toString(context) ~ "." ~ name;
				dpackage = dpackage.parent;
			}
		}
	
		return name;
	}
}

