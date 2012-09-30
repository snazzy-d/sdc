/**
 * This prepare scopes for identifiers resolution.
 */
module d.pass.dscope;

import d.pass.base;

import d.ast.dmodule;

import std.algorithm;
import std.array;

import d.ast.expression;
import d.ast.declaration;
import d.ast.statement;
import d.ast.type;

import d.parser.base;

class ScopePass {
	private DeclarationVisitor declarationVisitor;
	private StatementVisitor statementVisitor;
	
	private Scope currentScope;
	private Scope adtScope;
	
	private uint scopeIndex;
	
	private Module[] imported;
	
	this() {
		declarationVisitor	= new DeclarationVisitor(this);
		statementVisitor	= new StatementVisitor(this);
	}
	
final:
	Module[] visit(Module[] modules) {
		import d.pass.flatten;
		auto flattenPass = new FlattenPass();
		
		modules = flattenPass.visit(modules);
		
		// Set reference to null to allow garbage collection.
		flattenPass = null;
		
		auto oldImported = imported;
		scope(exit) imported = oldImported;
		
		imported = [];
		
		// Must be separated because ~ operator don't preserve order of execution.
		modules = modules.map!(m => visit(m)).array();
		
		return modules ~ imported;
	}
	
	private Module visit(Module m) {
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = m.dscope;
		
		m.declarations = visit(m.declarations);
		
		return m;
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
	
	Declaration visit(StructDefinition s) {
		currentScope.addOverloadableSymbol(s);
		
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		auto oldAdtScope = adtScope;
		scope(exit) adtScope = oldAdtScope;
		
		auto oldScopeIndex = scopeIndex;
		scope(exit) scopeIndex = oldScopeIndex;
		
		scopeIndex = 0;
		adtScope = currentScope = new NestedScope(oldScope);
		
		s.members = pass.visit(s.members);
		
		s.dscope = currentScope;
		
		return s;
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
		auto filenames = d.modules.map!(pkg => pkg.join("/") ~ ".d").array();
		
		Module[] modules;
		
		foreach(filename; filenames) {
			import sdc.lexer;
			import sdc.source;
			import sdc.sdc;
			import sdc.tokenstream;
			
			auto src = new Source(filename);
			auto trange = TokenRange(lex(src));
			
			auto packages = filename[0 .. $-2].split("/");
			auto ast = trange.parse(packages.back, packages[0 .. $-1]);
			
			modules ~= ast;
		}
		
		imported ~= pass.visit(modules);
		
		currentScope.imports = imported;
		
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

