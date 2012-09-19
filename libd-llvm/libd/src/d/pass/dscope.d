/**
 * This prepare scopes for identifiers resolution.
 */
module d.pass.dscope;

import d.pass.base;

import d.ast.dmodule;

import std.algorithm;
import std.array;

auto dscope(Module m) {
	auto pass = new ScopePass();
	
	return pass.visit(m);
}

import d.ast.expression;
import d.ast.declaration;
import d.ast.statement;
import d.ast.type;

class ScopePass {
	private DeclarationVisitor declarationVisitor;
	private StatementVisitor statementVisitor;
	
	private Scope currentScope;
	private Scope adtScope;
	
	private uint scopeIndex;
	
	this() {
		declarationVisitor	= new DeclarationVisitor(this);
		statementVisitor	= new StatementVisitor(this);
	}
	
final:
	Module visit(Module m) {
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = m.dscope;
		
		foreach(decl; m.declarations) {
			visit(decl);
		}
		
		return m;
	}
	
	auto visit(TemplateInstance tpl, TemplateDeclaration tplDecl) {
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = new NestedScope(tplDecl.parentScope);
		
		foreach(i, p; tplDecl.parameters) {
			currentScope.addSymbol(new AliasDeclaration(p.location, p.name, (cast(TypeTemplateArgument) tpl.arguments[i]).type));
		}
		
		foreach(decl; tpl.declarations) {
			visit(decl);
		}
		
		tpl.dscope = currentScope;
		
		return tpl;
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
		
		s.members = s.members.map!(m => pass.visit(m)).array();
		
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

