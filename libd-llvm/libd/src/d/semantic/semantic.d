/**
 * This module crawl the AST to resolve identifiers and process types.
 */
module d.semantic.semantic;

import d.semantic.base;
import d.semantic.caster;
import d.semantic.defaultinitializer;
import d.semantic.dmodule;
import d.semantic.dtemplate;
import d.semantic.expression;
import d.semantic.evaluator;
import d.semantic.identifier;
import d.semantic.identifiable;
import d.semantic.mangler;
import d.semantic.sizeof;
import d.semantic.statement;
import d.semantic.symbol;
import d.semantic.type;

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
	private ModuleVisitor moduleVisitor;
	private SymbolVisitor symbolVisitor;
	private ExpressionVisitor expressionVisitor;
	private StatementVisitor statementVisitor;
	private TypeVisitor typeVisitor;
	private IdentifierVisitor identifierVisitor;
	
	private Caster!false implicitCaster;
	private Caster!true explicitCaster;
	/*
	private DeclarationFlattener declarationFlatener;
	private StatementFlattener statementFlatener;
	*/
	DefaultInitializerVisitor defaultInitializerVisitor;
	
	SizeofCalculator sizeofCalculator;
	TypeMangler typeMangler;
	
	TemplateInstancier templateInstancier;
	
	Evaluator evaluator;
	
	static struct State {
		Symbol symbol;
		
		Scope currentScope;
		
		Type returnType;
		Type thisType;
		
		string manglePrefix;
		
		Statement[] flattenedStmts;
		Symbol[] flattenedSyms;
	}
	
	State state;
	alias state this;
	
	Scheduler!SemanticPass scheduler;
	
	enum Step {
		Parsed,
		Flatened,
		Populated,
		Processed,
	}
	
	this(Evaluator evaluator) {
		this.evaluator = evaluator;
		
		moduleVisitor		= new ModuleVisitor(this);
		symbolVisitor		= new SymbolVisitor(this);
		expressionVisitor	= new ExpressionVisitor(this);
		statementVisitor	= new StatementVisitor(this);
		typeVisitor			= new TypeVisitor(this);
		identifierVisitor	= new IdentifierVisitor(this);
		
		implicitCaster		= new Caster!false(this);
		explicitCaster		= new Caster!true(this);
		/*
		declarationFlattener	= new DeclarationFlattener(this);
		statementFlattener		= new StatementFlattener(this);
		*/
		defaultInitializerVisitor	= new DefaultInitializerVisitor(this);
		
		sizeofCalculator	= new SizeofCalculator(this);
		typeMangler			= new TypeMangler(this);
		
		templateInstancier	= new TemplateInstancier(this);
		
		scheduler			= new Scheduler!SemanticPass(this);
	}
	
	auto process(Module[] modules) {
		Process[] allTasks;
		foreach(m; modules) {
			scheduler.register(m, m, Step.Populated);
			
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
		return moduleVisitor.visit(m);
	}
	
	Symbol visit(Symbol s) {
		return symbolVisitor.visit(s);
	}
	
	Expression visit(Expression e) {
		return expressionVisitor.visit(e);
	}
	
	BlockStatement visit(BlockStatement s) {
		return statementVisitor.flatten(s);
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

