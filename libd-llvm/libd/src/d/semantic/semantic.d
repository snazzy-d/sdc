/**
 * This module crawl the AST to resolve identifiers and process types.
 */
module d.semantic.semantic;

public import util.visitor;

import d.semantic.backend;
import d.semantic.defaultinitializer;
import d.semantic.dmodule;
import d.semantic.dtemplate;
import d.semantic.expression;
import d.semantic.evaluator;
import d.semantic.mangler;
import d.semantic.sizeof;
import d.semantic.statement;
import d.semantic.symbol;
import d.semantic.type;

import d.ast.base;
import d.ast.declaration;
import d.ast.dmodule;
import d.ast.expression;
import d.ast.statement;
import d.ast.type;

import d.ir.expression;
import d.ir.dscope;
import d.ir.statement;
import d.ir.symbol;
import d.ir.type;

import d.parser.base;

import d.processor.scheduler;

import d.exception;
import d.lexer;
import d.location;

import std.algorithm;
import std.array;
import std.bitmanip;
import std.range;

alias AstModule = d.ast.dmodule.Module;
alias Module = d.ir.symbol.Module;

alias FunctionType = d.ir.type.FunctionType;
alias CallExpression = d.ir.expression.CallExpression;

alias BlockStatement = d.ir.statement.BlockStatement;
alias ExpressionStatement = d.ir.statement.ExpressionStatement;
alias ReturnStatement = d.ir.statement.ReturnStatement;

final class SemanticPass {
	private ModuleVisitor moduleVisitor;
	private SymbolVisitor symbolVisitor;
	private ExpressionVisitor expressionVisitor;
	private StatementVisitor statementVisitor;
	private TypeVisitor typeVisitor;
	
	DefaultInitializerVisitor defaultInitializerVisitor;
	
	SizeofCalculator sizeofCalculator;
	TypeMangler typeMangler;
	
	TemplateInstancier templateInstancier;
	
	Backend backend;
	Evaluator evaluator;
	
	string[] versions = ["SDC", "D_LP64"];
	
	static struct State {
		Scope currentScope;
		
		ParamType returnType;
		ParamType thisType;
		
		string manglePrefix;
		
		mixin(bitfields!(
			bool, "buildErrorNode", 1,
			uint, "", 7,
		));
		
		Statement[] flattenedStmts;
		
		uint fieldIndex;
		uint methodIndex;
	}
	
	State state;
	alias state this;
	
	Scheduler!SemanticPass scheduler;
	
	alias Step = d.ir.symbol.Step;
	
	this(Backend backend, Evaluator evaluator, FileSource delegate(string[]) sourceFactory) {
		this.backend		= backend;
		this.evaluator		= evaluator;
		
		moduleVisitor		= new ModuleVisitor(this, sourceFactory);
		symbolVisitor		= new SymbolVisitor(this);
		expressionVisitor	= new ExpressionVisitor(this);
		statementVisitor	= new StatementVisitor(this);
		typeVisitor			= new TypeVisitor(this);
		
		defaultInitializerVisitor	= new DefaultInitializerVisitor(this);
		
		sizeofCalculator	= new SizeofCalculator(this);
		typeMangler			= new TypeMangler(this);
		
		templateInstancier	= new TemplateInstancier(this);
		
		scheduler			= new Scheduler!SemanticPass(this);
		
		importModule(["object"]);
	}
	
	AstModule parse(S)(S source, string[] packages) if(is(S : Source)) {
		auto trange = lex!((line, index, length) => Location(source, line, index, length))(source.content);
		return trange.parse(packages[$ - 1], packages[0 .. $-1]);
	}
	
	Module add(FileSource source, string[] packages) {
		auto astm = parse(source, packages);
		auto mod = moduleVisitor.modulize(astm);
		
		moduleVisitor.preregister(mod);
		
		scheduler.schedule(only(mod), d => moduleVisitor.visit(astm, cast(Module) d));
		
		return mod;
	}
	
	void terminate() {
		scheduler.terminate();
	}
	
	Symbol visit(Declaration d, Symbol s) {
		return symbolVisitor.visit(d, s);
	}
	
	Expression visit(AstExpression e) {
		return expressionVisitor.visit(e);
	}
	
	BlockStatement visit(AstBlockStatement s) {
		return statementVisitor.flatten(s);
	}
	
	QualType visit(QualAstType t) {
		return typeVisitor.visit(t);
	}
	
	ParamType visit(ParamAstType t) {
		return typeVisitor.visit(t);
	}
	
	TemplateInstance instanciate(Location location, Template t, TemplateArgument[] args) {
		return templateInstancier.instanciate(location, t, args);
	}
	
	auto evaluate(Expression e) {
		return evaluator.evaluate(e);
	}
	
	auto importModule(string[] pkgs) {
		return moduleVisitor.importModule(pkgs);
	}
	
	auto raiseCondition(T)(Location location, string message) {
		if(buildErrorNode) {
			static if(is(T == Type)) {
				return QualType(new ErrorType(location, message));
			} else static if(is(T == Expression)) {
				return new ErrorExpression(location, message);
			} else {
				static assert(false, "compilationCondition only works for Types and Expressions.");
			}
		} else {
			throw new CompileException(location, message);
		}
	}
	
	void buildMain(Module[] mods) {
		auto candidates = mods.map!(m => m.members).joiner.map!((s) {
			if(auto fun = cast(Function) s) {
				if(fun.name == "main") {
					return fun;
				}
			}
			
			return null;
		}).filter!(s => !!s).array();
		
		if(candidates.length > 1) {
			assert(0, "Several main functions");
		}
		
		if(candidates.length == 1) {
			auto main = candidates[0];
			auto location = main.fbody.location;
			
			auto type = cast(FunctionType) main.type.type;
			auto returnType = cast(BuiltinType) type.returnType.type;
			auto call = new CallExpression(location, QualType(returnType), new SymbolExpression(location, main), []);
			
			Statement[] fbody;
			if(returnType && returnType.kind == TypeKind.Void) {
				fbody ~= new ExpressionStatement(call);
				fbody ~= new ReturnStatement(location, new IntegerLiteral!true(location, 0, TypeKind.Int));
			} else {
				fbody ~= new ReturnStatement(location, call);
			}
			
			type = new FunctionType(Linkage.C, ParamType(getBuiltin(TypeKind.Int), false), [], false);
			auto bootstrap = new Function(main.location, QualType(type), "_Dmain", [], new BlockStatement(location, fbody));
			bootstrap.isStatic = true;
			bootstrap.step = Step.Processed;
			bootstrap.mangle = "_Dmain";
			
			auto m = new Module(main.location, "main", null);
			m.members = [bootstrap];
			
			backend.visit(m);
		}
	}
}

