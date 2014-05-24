/**
 * This module crawl the AST to resolve identifiers and process types.
 */
module d.semantic.dmodule;

import d.semantic.semantic;

import d.ast.declaration;
import d.ast.dmodule;

import d.ir.symbol;

import d.processor.scheduler;

import d.context;
import d.location;

import std.algorithm;
import std.array;
import std.range; // for range.

alias AstModule = d.ast.dmodule.Module;
alias Module = d.ir.symbol.Module;

alias AstPackage = d.ast.dmodule.Package;
alias Package = d.ir.symbol.Package;

final class ModuleVisitor {
	private SemanticPass pass;
	alias pass this;
	
	private FileSource delegate(Name[]) sourceFactory;
	
	private Module[string] cachedModules;
	
	this(SemanticPass pass, FileSource delegate(Name[]) sourceFactory) {
		this.pass = pass;
		this.sourceFactory = sourceFactory;
	}
	
	Module visit(AstModule astm, Module m) {
		auto oldCurrentScope = currentScope;
		auto oldManglePrefix = manglePrefix;
		
		scope(exit) {
			currentScope = oldCurrentScope;
			manglePrefix = oldManglePrefix;
		}
		
		manglePrefix = "";
		currentScope = m.dscope;
		
		import std.conv;
		auto current = astm.parent;
		while(current) {
			auto name = current.name.toString(context);
			manglePrefix = to!string(name.length) ~ name ~ manglePrefix;
			current = current.parent;
		}
		
		auto name = astm.name.toString(context);
		manglePrefix ~= to!string(name.length) ~ name;
		
		import d.semantic.declaration;
		auto dv = DeclarationVisitor(pass);
		
		// All modules implicitely import object.
		import d.context;
		m.members = dv.flatten(new ImportDeclaration(m.location, [[BuiltinName!"object"]]) ~ astm.declarations, m);
		m.step = Step.Populated;
		
		scheduler.require(m.members);
		
		m.step = Step.Processed;
		return m;
	}
	
	Module importModule(Name[] packages) {
		auto name = packages.map!(p => p.toString(pass.context)).join(".");
		
		return cachedModules.get(name, {
			auto source = sourceFactory(packages);
			auto astm = pass.parse(source, packages);
			auto mod = modulize(astm);
			
			pass.scheduler.schedule(only(mod), (s) {
				auto m = cast(Module) s;
				assert(m, "How come that this isn't a module ?");
				
				return visit(astm, m);
			});
			
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

