/**
 * This module crawl the AST to resolve identifiers and process types.
 */
module d.pass.semantic;

import d.pass.base;
import d.pass.caster;
import d.pass.declaration;
import d.pass.defaultinitializer;
import d.pass.dtemplate;
import d.pass.expression;
import d.pass.evaluator;
import d.pass.identifier;
import d.pass.identifiable;
import d.pass.mangler;
import d.pass.sizeof;
import d.pass.statement;
import d.pass.type;

import d.ast.declaration;
import d.ast.dmodule;
import d.ast.dscope;
import d.ast.dtemplate;
import d.ast.expression;
import d.ast.identifier;
import d.ast.statement;
import d.ast.type;

import d.processor.scheduler;

import sdc.location;

import std.algorithm;
import std.array;

final class SemanticPass {
	private DeclarationVisitor declarationVisitor;
	private ExpressionVisitor expressionVisitor;
	private StatementVisitor statementVisitor;
	private TypeVisitor typeVisitor;
	private IdentifierVisitor identifierVisitor;
	
	private Caster!false implicitCaster;
	private Caster!true explicitCaster;
	
	DefaultInitializerVisitor defaultInitializerVisitor;
	
	SizeofCalculator sizeofCalculator;
	TypeMangler typeMangler;
	
	TemplateInstancier templateInstancier;
	
	Evaluator evaluator;
	
	static struct State {
		Declaration declaration;
		
		Scope currentScope;
		
		Type returnType;
		Type thisType;
		
		string manglePrefix;
	}
	
	State state;
	alias state this;
	
	Scheduler!SemanticPass scheduler;
	
	enum Steps {
		Parsed,
		Flatened,
		Populated,
		Processed,
	}
	
	this(Evaluator evaluator) {
		this.evaluator = evaluator;
		
		declarationVisitor	= new DeclarationVisitor(this);
		expressionVisitor	= new ExpressionVisitor(this);
		statementVisitor	= new StatementVisitor(this);
		typeVisitor			= new TypeVisitor(this);
		identifierVisitor	= new IdentifierVisitor(this);
		
		implicitCaster		= new Caster!false(this);
		explicitCaster		= new Caster!true(this);
		
		defaultInitializerVisitor	= new DefaultInitializerVisitor(this);
		
		sizeofCalculator	= new SizeofCalculator(this);
		typeMangler			= new TypeMangler(this);
		
		templateInstancier	= new TemplateInstancier(this);
		
		scheduler			= new Scheduler!SemanticPass(this);
	}
	
	auto process(Module[] modules) {
		Process[] allTasks;
		foreach(m; modules) {
			auto t = new Process();
			t.init(m, d => visit(cast(Module) d));
			
			allTasks ~= t;
		}
		
		auto tasks = allTasks;
		while(tasks) {
			tasks = tasks.filter!(t => t.result is null).array();
			
			foreach(t; tasks) {
				t.call();
			}
		}
		
		return cast(Module[]) allTasks.map!(t => t.result).array();
	}
	
	Module visit(Module m) {
		auto oldCurrentScope = currentScope;
		scope(exit) currentScope = oldCurrentScope;
		
		currentScope = m.dscope;
		
		auto oldDeclaration = declaration;
		scope(exit) declaration = oldDeclaration;
		
		declaration = m;
		
		import std.conv;
		
		manglePrefix = "";
		auto current = m.parent;
		while(current) {
			manglePrefix = to!string(current.name.length) ~ current.name ~ manglePrefix;
			current = current.parent;
		}
		
		manglePrefix ~= to!string(m.name.length) ~ m.name;
		
		m.declarations = cast(Declaration[]) scheduler.schedule(m.declarations, d => visit(d));
		
		return m;
	}
	
	Symbol visit(Declaration d) {
		return declarationVisitor.visit(d);
	}
	
	Expression visit(Expression e) {
		return expressionVisitor.visit(e);
	}
	
	void visit(Statement s) {
		statementVisitor.visit(s);
	}
	
	Type visit(Type t) {
		return typeVisitor.visit(t);
	}
	
	Identifiable visit(Identifier i) {
		return identifierVisitor.visit(i);
	}
	
	auto implicitCast(Location location, Type to, Expression value) {
		return implicitCaster.build(location, to, value);
	}
	
	auto explicitCast(Location location, Type to, Expression value) {
		return explicitCaster.build(location, to, value);
	}
	
	TemplateInstance instanciate(Location location, TemplateDeclaration tplDecl, TemplateArgument[] arguments) {
		return templateInstancier.instanciate(location, tplDecl, arguments);
	}
	
	auto evaluate(Expression e) {
		return evaluator.evaluate(e);
	}
}

