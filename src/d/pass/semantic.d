/**
 * This module crawl the AST to resolve identifiers and process types.
 */
module d.pass.semantic;

import d.pass.base;

import d.ast.declaration;
import d.ast.dmodule;
import d.ast.dscope;
import d.ast.dtemplate;
import d.ast.expression;
import d.ast.identifier;
import d.ast.statement;
import d.ast.type;

import std.algorithm;
import std.array;

import d.processor.scheduler;

import d.pass.caster;
import d.pass.declaration;
import d.pass.defaultinitializer;
import d.pass.expression;
import d.pass.identifier2;
import d.pass.mangler;
import d.pass.sizeof;
import d.pass.statement;
import d.pass.type;

import sdc.location;

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
	
	static struct State {
		Declaration declaration;
		
		Scope currentScope;
		
		Type returnType;
		Type thisType;
		
		string manglePrefix;
	}
	
	State state;
	alias state this;
	
	Scheduler scheduler;
	
	this(Scheduler scheduler) {
		this.scheduler = scheduler;
		
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
		
		m.declarations = cast(Declaration[]) scheduler.schedule(this, m.declarations, d => visit(d));
		
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
	
	// TODO: merge that into template instanciation code.
	TemplateInstance visit(TemplateInstance tpl) {
		// Update scope.
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = tpl.dscope;
		
		tpl.declarations = cast(Declaration[]) scheduler.schedule(this, tpl.declarations, d => visit(d));
		
		return tpl;
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
	
	auto instanciate(Location location, TemplateDeclaration tplDecl, TemplateArgument[] arguments) {
		tplDecl = cast(TemplateDeclaration) scheduler.require(this, tplDecl);
		
		string id = arguments.map!(delegate string(TemplateArgument arg) { return "T" ~ typeMangler.visit((cast(TypeTemplateArgument) arg).type); }).join();
		
		return tplDecl.instances.get(id, {
			auto oldManglePrefix = this.manglePrefix;
			scope(exit) this.manglePrefix = oldManglePrefix;
			
			import std.conv;
			auto tplMangle = "__T" ~ to!string(tplDecl.name.length) ~ tplDecl.name ~ id ~ "Z";
			
			this.manglePrefix = tplDecl.mangle ~ to!string(tplMangle.length) ~ tplMangle;
			
			import d.pass.dscope;
			import d.pass.clone;
			auto clone = new ClonePass();
			
			auto members = tplDecl.declarations.map!(delegate Declaration(Declaration d) { return clone.visit(d); }).array();
			auto instance = visit((new ScopePass()).visit(new TemplateInstance(location, arguments, members), tplDecl));
			
			return tplDecl.instances[id] = instance;
		}());
	}
}

