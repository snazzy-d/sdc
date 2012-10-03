/**
 * This prepare scopes for identifiers resolution.
 */
module d.pass.dscope;

import d.pass.base;
import d.pass.flatten;

import d.ast.dmodule;

import std.algorithm;
import std.array;
import std.range;

import d.ast.expression;
import d.ast.declaration;
import d.ast.statement;
import d.ast.type;

import d.parser.base;

class ScopePass {
	private DeclarationVisitor declarationVisitor;
	private StatementVisitor statementVisitor;
	
	private FlattenPass flattenPass;
	
	private Scope currentScope;
	private Scope adtScope;
	
	private uint scopeIndex;
	
	private Module[string] cachedModules;
	
	this() {
		declarationVisitor	= new DeclarationVisitor(this);
		statementVisitor	= new StatementVisitor(this);
		
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
			
			currentScope = m.dscope;
			
			cachedModules[name] = m;
			
			visit(new ImportDeclaration(Location.init, [["object"]]));
			m.declarations = visit(m.declarations);
			
			return m;
		}());
	}
	
	auto visit(TemplateInstance tpl, TemplateDeclaration tplDecl) {
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = new NestedScope(tplDecl.parentScope);
		
		foreach(i, p; tplDecl.parameters) {
			currentScope.addSymbol(new AliasDeclaration(p.location, p.name, (cast(TypeTemplateArgument) tpl.arguments[i]).type));
		}
		
		tpl.declarations = visit(tpl.declarations);
		
		tpl.dscope = currentScope;
		
		return tpl;
	}
	
	auto visit(Declaration[] decls) {
		// XXX: array in the middle because each decl is passed 2 times without.
		return decls.map!(d => visit(d)).array().filter!(e => typeid(e) !is typeid(ImportDeclaration)).array();
	}
	
	auto visit(Declaration decl) {
		return declarationVisitor.visit(decl);
	}
	
	auto visit(Statement stmt) {
		return statementVisitor.visit(stmt);
	}
}

import d.ast.adt;
import d.ast.dfunction;
import d.ast.dscope;
import d.ast.dtemplate;

class DeclarationVisitor {
	private ScopePass pass;
	alias pass this;
	
	this(ScopePass pass) {
		this.pass = pass;
	}
	
final:
	Declaration visit(Declaration d) {
		return this.dispatch(d);
	}
	
	Declaration visit(FunctionDeclaration d) {
		currentScope.addOverloadableSymbol(d);
		
		return d;
	}
	
	Declaration visit(FunctionDefinition fun) {
		currentScope.addOverloadableSymbol(fun);
		
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = new NestedScope(oldScope);
		
		foreach(p; fun.parameters) {
			currentScope.addSymbol(p);
		}
		
		pass.visit(fun.fbody);
		
		fun.dscope = currentScope;
		
		return fun;
	}
	
	Declaration visit(VariableDeclaration var) {
		if(adtScope is currentScope) {
			var = new FieldDeclaration(var, scopeIndex++);
		}
		
		currentScope.addSymbol(var);
		
		return var;
	}
	
	Declaration visit(StructDefinition d) {
		currentScope.addOverloadableSymbol(d);
		
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		auto oldAdtScope = adtScope;
		scope(exit) adtScope = oldAdtScope;
		
		auto oldScopeIndex = scopeIndex;
		scope(exit) scopeIndex = oldScopeIndex;
		
		scopeIndex = 0;
		adtScope = currentScope = new NestedScope(oldScope);
		
		auto type = new SymbolType(d.location, d);
		auto init = new VariableDeclaration(d.location, type, "init", new DefaultInitializer(type));
		init.isStatic = true;
		
		d.members = init ~ pass.visit(d.members);
		
		currentScope.addSymbol(init);
		
		d.dscope = currentScope;
		
		return d;
	}
	
	Declaration visit(TemplateDeclaration tpl) {
		currentScope.addOverloadableSymbol(tpl);
		
		tpl.parentScope = currentScope;
		
		return tpl;
	}
	
	Declaration visit(AliasDeclaration a) {
		currentScope.addSymbol(a);
		
		return a;
	}
	
	Declaration visit(ImportDeclaration d) {
		auto names = d.modules.map!(pkg => pkg.join(".")).array();
		auto filenames = d.modules.map!(pkg => pkg.join("/") ~ ".d").array();
		
		Module[] addToScope;
		foreach(name, filename; lockstep(names, filenames)) {
			addToScope ~= pass.cachedModules.get(name, {
				import sdc.lexer;
				import sdc.source;
				import sdc.sdc;
				import sdc.tokenstream;
				
				auto src = new Source(filename);
				auto trange = TokenRange(lex(src));
				
				auto packages = filename[0 .. $-2].split("/");
				auto mod = trange.parse(packages.back, packages[0 .. $-1]);
				
				return pass.visit(pass.flattenPass.visit([mod]).back);
			}());
		}
		
		currentScope.imports ~= addToScope;
		
		return d;
	}
}

class StatementVisitor {
	private ScopePass pass;
	alias pass this;
	
	this(ScopePass pass) {
		this.pass = pass;
	}
	
final:
	void visit(Statement s) {
		this.dispatch(s);
	}
	
	void visit(ExpressionStatement e) {
		// Nothing needs to be done.
	}
	
	void visit(DeclarationStatement ds) {
		pass.visit(ds.declaration);
	}
	
	void visit(BlockStatement b) {
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = new NestedScope(oldScope);
		
		foreach(s; b.statements) {
			visit(s);
		}
		
		b.dscope = currentScope;
	}
	
	void visit(IfElseStatement ifs) {
		visit(ifs.then);
		visit(ifs.elseStatement);
	}
	
	void visit(WhileStatement w) {
		visit(w.statement);
	}
	
	void visit(DoWhileStatement w) {
		visit(w.statement);
	}
	
	void visit(ForStatement f) {
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = new NestedScope(oldScope);
		
		visit(f.initialize);
		visit(f.statement);
		
		f.dscope = currentScope;
	}
	
	void visit(ReturnStatement r) {
		// Nothing needs to be done.
	}
}

