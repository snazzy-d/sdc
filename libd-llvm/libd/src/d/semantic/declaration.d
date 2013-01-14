module d.semantic.declaration;

import d.semantic.base;
import d.semantic.semantic;

import d.ast.adt;
import d.ast.declaration;
import d.ast.dfunction;
import d.ast.dscope;
import d.ast.dtemplate;

import std.algorithm;
import std.array;

final class DeclarationVisitor {
	private SemanticPass pass;
	alias pass this;
	
	alias SemanticPass.Step Step;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	Symbol[] flatten(Declaration[] decls) {
		auto oldFlattenedDecls = flattenedDecls;
		scope(exit) flattenedDecls = oldFlattenedDecls;
		
		flattenedDecls = [];
		
		foreach(d; decls) {
			visit(d);
		}
		
		return flattenedDecls;
	}
	
	void visit(Declaration d) {
		return this.dispatch(d);
	}
	
	void visit(FunctionDeclaration d) {
		currentScope.addOverloadableSymbol(d);
		
		flattenedDecls ~= d;
	}
	
	void visit(FunctionDefinition d) {
		currentScope.addOverloadableSymbol(d);
		
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = d.dscope = new NestedScope(oldScope);
		
		foreach(p; d.parameters) {
			currentScope.addSymbol(p);
		}
		
		flattenedDecls ~= d;
	}
	
	void visit(VariableDeclaration d) {
		currentScope.addSymbol(d);
		
		flattenedDecls ~= d;
	}
	
	void visit(StructDefinition d) {
		currentScope.addSymbol(d);
		
		flattenedDecls ~= d;
	}
	
	void visit(ClassDefinition d) {
		currentScope.addSymbol(d);
		
		flattenedDecls ~= d;
	}
	
	void visit(EnumDeclaration d) {
		if(d.name) {
			currentScope.addSymbol(d);
		} else {
			auto oldFlattenedDecls = flattenedDecls;
			scope(exit) flattenedDecls = oldFlattenedDecls;
			
			foreach(e; d.enumEntries) {
				visit(e);
			}
		}
		
		flattenedDecls ~= d;
	}
	
	void visit(TemplateDeclaration d) {
		currentScope.addOverloadableSymbol(d);
		
		d.parentScope = currentScope;
		
		flattenedDecls ~= d;
	}
	
	void visit(AliasDeclaration d) {
		currentScope.addSymbol(d);
		
		flattenedDecls ~= d;
	}
}

