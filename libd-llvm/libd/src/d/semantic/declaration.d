module d.semantic.declaration;

import d.semantic.base;
import d.semantic.semantic;

import d.ast.adt;
import d.ast.conditional;
import d.ast.declaration;
import d.ast.dfunction;
import d.ast.dmodule;
import d.ast.dscope;
import d.ast.dtemplate;
import d.ast.expression;
import d.ast.type;

import std.algorithm;
import std.array;
import std.range;

final class DeclarationVisitor {
	private SemanticPass pass;
	alias pass this;
	
	alias SemanticPass.Step Step;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	Symbol[] flatten(Declaration[] decls, Symbol parent) {
		auto oldFlattenedDecls = flattenedDecls;
		scope(exit) flattenedDecls = oldFlattenedDecls;
		
		flattenedDecls = [];
		
		foreach(d; decls) {
			visit(d);
		}
		
		if(parent) {
			scheduler.register(parent, parent, Step.Populated);
		}
		
		return flattenedDecls;
	}
	
	void visit(Declaration d) {
		return this.dispatch(d);
	}
	
	private void select(Symbol s) {
		flattenedDecls ~= scheduler.schedule(s.repeat(1), s => pass.visit(s));
	}
	
	void visit(FunctionDeclaration d) {
		currentScope.addOverloadableSymbol(d);
		
		select(d);
	}
	
	void visit(FunctionDefinition d) {
		currentScope.addOverloadableSymbol(d);
		
		// XXX: move that to symbol pass.
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = d.dscope = new NestedScope(oldScope);
		
		foreach(p; d.parameters) {
			currentScope.addSymbol(p);
		}
		
		select(d);
	}
	
	void visit(VariableDeclaration d) {
		currentScope.addSymbol(d);
		
		select(d);
	}
	
	void visit(StructDefinition d) {
		currentScope.addSymbol(d);
		
		select(d);
	}
	
	void visit(ClassDefinition d) {
		currentScope.addSymbol(d);
		
		select(d);
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
		
		select(d);
	}
	
	void visit(TemplateDeclaration d) {
		currentScope.addOverloadableSymbol(d);
		
		d.parentScope = currentScope;
		
		select(d);
	}
	
	void visit(AliasDeclaration d) {
		currentScope.addSymbol(d);
		
		select(d);
	}
	
	void visit(ImportDeclaration d) {
		auto names = d.modules.map!(pkg => pkg.join(".")).array();
		auto filenames = d.modules.map!(pkg => pkg.join("/") ~ ".d").array();
		
		Module[] addToScope;
		foreach(name; d.modules) {
			addToScope ~= importModule(name);
		}
		
		currentScope.imports ~= addToScope;
	}
	
	void visit(StaticIfElse!Declaration d) {
		d.condition = evaluate(explicitCast(d.condition.location, new BooleanType(d.condition.location), pass.visit(d.condition)));
		
		if((cast(BooleanLiteral) d.condition).value) {
			foreach(item; d.items) {
				visit(item);
			}
		} else {
			foreach(item; d.elseItems) {
				visit(item);
			}
		}
	}
}

