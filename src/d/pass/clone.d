/**
 * This module is used to clone AST.
 */
module d.pass.clone;

import d.pass.base;

import d.pass.dscope;

import d.ast.declaration;
import d.ast.dmodule;
import d.ast.dscope;
import d.ast.identifier;

import std.algorithm;
import std.array;

import d.ast.expression;
import d.ast.declaration;
import d.ast.statement;
import d.ast.type;

class ClonePass {
	private DeclarationVisitor declarationVisitor;
	private StatementVisitor statementVisitor;
	private ExpressionVisitor expressionVisitor;
	private TypeVisitor typeVisitor;
	private IdentifierVisitor identifierVisitor;
	
	this() {
		declarationVisitor	= new DeclarationVisitor(this);
		statementVisitor	= new StatementVisitor(this);
		expressionVisitor	= new ExpressionVisitor(this);
		typeVisitor			= new TypeVisitor(this);
		identifierVisitor	= new IdentifierVisitor(this);
	}
	
final:
	Module visit(Module m) {
		assert(0, "Not implemented.");
		// return new Module(m.location, visit(m.moduleDeclaration), m.declarations.map!(d => visit(d)).array());
	}
	
	auto visit(Declaration decl) {
		return declarationVisitor.visit(decl);
	}
	
	auto visit(Statement stmt) {
		return statementVisitor.visit(stmt);
	}
	
	auto visit(Expression e) {
		return expressionVisitor.visit(e);
	}
	
	auto visit(Type t) {
		return typeVisitor.visit(t);
	}
	
	auto visit(Identifier i) {
		return identifierVisitor.visit(i);
	}
}

import d.ast.adt;
import d.ast.dfunction;
import d.ast.dtemplate;

/**
 * Clone declaration.
 */
class DeclarationVisitor {
	private ClonePass pass;
	alias pass this;
	
	this(ClonePass pass) {
		this.pass = pass;
	}
	
final:
	Declaration visit(Declaration d) {
		return this.dispatch(d);
	}
	
	VariableDeclaration visit(VariableDeclaration d) {
		auto clone = new VariableDeclaration(d.location, pass.visit(d.type), d.name, pass.visit(d.value));
		
		clone.isStatic = d.isStatic;
		
		return clone;
	}
	
	AliasDeclaration visit(AliasDeclaration d) {
		return new AliasDeclaration(d.location, d.name, pass.visit(d.type));
	}
}

import d.ast.statement;

/**
 * Clone statement.
 */
class StatementVisitor {
	private ClonePass pass;
	alias pass this;
	
	this(ClonePass pass) {
		this.pass = pass;
	}
	
final:
	void visit(Statement s) {
		this.dispatch(s);
	}
}

import d.ast.expression;

/**
 * Clone expression.
 */
class ExpressionVisitor {
	private ClonePass pass;
	alias pass this;
	
	this(ClonePass pass) {
		this.pass = pass;
	}
	
final:
	Expression visit(Expression e) {
		return this.dispatch(e);
	}
	
	DefaultInitializer visit(DefaultInitializer d) {
		return new DefaultInitializer(pass.visit(d.type));
	}
}

import d.ast.type;

/**
 * Clone type.
 */
class TypeVisitor {
	private ClonePass pass;
	alias pass this;
	
	this(ClonePass pass) {
		this.pass = pass;
	}
	
final:
	Type visit(Type t) {
		return this.dispatch(t);
	}
	
	IdentifierType visit(IdentifierType t) {
		return new IdentifierType(pass.visit(t.identifier));
	}
}

import d.ast.base;
import d.pass.util;

/**
 * Clone identifier.
 */
class IdentifierVisitor {
	private ClonePass pass;
	alias pass this;
	
	this(ClonePass pass) {
		this.pass = pass;
	}
	
final:
	Identifier visit(Identifier i) {
		return this.dispatch(i);
	}
	
	BasicIdentifier visit(BasicIdentifier i) {
		return new BasicIdentifier(i.location, i.name);
	}
}

