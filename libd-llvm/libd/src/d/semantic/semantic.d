/**
 * This module crawl the AST to resolve identifiers and process types.
 */
module d.semantic.semantic;

import d.semantic.base;
import d.semantic.caster;
import d.semantic.declaration;
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

import d.location;

import std.algorithm;
import std.array;
import std.bitmanip;

final class SemanticPass {
	private ModuleVisitor moduleVisitor;
	private DeclarationVisitor declarationVisitor;
	private SymbolVisitor symbolVisitor;
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
	
	string[] versions = ["SDC", "D_LP64"];
	
	static struct State {
		// XXX: symbol will have to go at some point.
		Symbol symbol;
		
		Scope currentScope;
		
		Type returnType;
		Type thisType;
		
		string manglePrefix;
		
		string linkage = "D";
		
		mixin(bitfields!(
			bool, "buildFields", 1,
			bool, "isStatic", 1,
			uint, "", 6
		));
		
		Statement[] flattenedStmts;
		Symbol[] flattenedDecls;
		
		uint fieldIndex;
		
		TypeQualifier qualifier;
	}
	
	State state;
	alias state this;
	
	Scheduler!SemanticPass scheduler;
	
	enum Step {
		Parsed,
		Populated,
		Processed,
	}
	
	this(Evaluator evaluator) {
		this.evaluator = evaluator;
		
		isStatic	= true;
		
		moduleVisitor		= new ModuleVisitor(this);
		declarationVisitor	= new DeclarationVisitor(this);
		symbolVisitor		= new SymbolVisitor(this);
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
		moduleVisitor.preregister(modules);
		
		scheduler.schedule(modules, d => visit(cast(Module) d));
		modules = cast(Module[]) scheduler.require(modules);
		
		scheduler.terminate();
		
		return modules;
	}
	
	Module visit(Module m) {
		return moduleVisitor.visit(m);
	}
	
	Symbol[] visit(Declaration[] decls, Symbol parent = null) {
		return declarationVisitor.flatten(decls, parent);
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
		auto oldQualifier = qualifier;
		scope(exit) qualifier = oldQualifier;
		
		// No qualifier is assumed to be mutable.
		qualifier = TypeQualifier.Mutable;
		
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
	
	auto importModule(string[] pkgs) {
		return moduleVisitor.importModule(pkgs);
	}
}

