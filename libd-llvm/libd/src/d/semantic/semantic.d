/**
 * This module crawl the AST to resolve identifiers and process types.
 */
module d.semantic.semantic;

import d.semantic.backend;
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

import d.parser.base;

import d.processor.scheduler;

import d.lexer;
import d.location;

import std.algorithm;
import std.array;
import std.bitmanip;
import std.range;

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
	
	Backend backend;
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
			bool, "buildMethods", 1,
			bool, "isStatic", 1,
			bool, "isThisRef", 1,
			uint, "", 4
		));
		
		Statement[] flattenedStmts;
		
		uint fieldIndex;
		uint methodIndex;
		
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
	
	this(Backend backend, Evaluator evaluator, FileSource delegate(string[]) sourceFactory) {
		this.backend		= backend;
		this.evaluator		= evaluator;
		
		isStatic	= true;
		
		moduleVisitor		= new ModuleVisitor(this, sourceFactory);
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
		
		importModule(["object"]);
	}
	
	Module parse(S)(S source, string[] packages) if(is(S : Source)) {
		auto trange = lex!((line, index, length) => Location(source, line, index, length))(source.content);
		return trange.parse(packages[$ - 1], packages[0 .. $-1]);
	}
	
	Module add(FileSource source, string[] packages) {
		auto mod = parse(source, packages);
		moduleVisitor.preregister(mod);
		
		scheduler.schedule(only(mod), (d) {
			auto m = moduleVisitor.visit(cast(Module) d);
			
			backend.visit(m);
			
			return m;
		});
		
		return mod;
	}
	
	void terminate() {
		scheduler.terminate();
	}
	
	Symbol[] flatten(Declaration[] decls, Symbol parent) {
		return declarationVisitor.flatten(decls, parent);
	}
	
	Symbol[] flatten(Declaration d) {
		return declarationVisitor.flatten(d);
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
	
	void buildMain(Module[] mods) {
		import d.ast.dfunction;
		auto candidates = mods.map!(m => m.declarations).joiner.map!((d) {
			if(auto fun = cast(FunctionDeclaration) d) {
				if(fun.name == "main") {
					return fun;
				}
			}
			
			return null;
		}).filter!(d => !!d).array();
		
		if(candidates.length == 1) {
			auto main = candidates[0];
			auto location = main.fbody.location;
			
			auto call = new CallExpression(location, new SymbolExpression(location, main), []);
			
			Statement[] fbody;
			if(cast(VoidType) main.returnType) {
				fbody ~= new ExpressionStatement(call);
				fbody ~= new ReturnStatement(location, makeLiteral(location, 0));
			} else {
				fbody ~= new ReturnStatement(location, call);
			}
			
			auto bootstrap = new FunctionDeclaration(main.location, "_Dmain", "C", new IntegerType(main.returnType.location, Integer.Int), [], false, new BlockStatement(location, fbody));
			bootstrap.isStatic = true;
			bootstrap.dscope = new NestedScope(new Scope(null));
			
			backend.visit(new Module(main.location, "main", [], [visit(bootstrap)]));
		}
		
		if(candidates.length > 1) {
			assert(0, "Several main functions");
		}
	}
}

