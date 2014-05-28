/**
 * This module crawl the AST to resolve identifiers and process types.
 */
module d.semantic.semantic;

public import util.visitor;

import d.semantic.dmodule;
import d.semantic.evaluator;
import d.semantic.scheduler;

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

import d.context;
import d.exception;
import d.lexer;
import d.location;
import d.object;

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
	
	Context context;
	
	Evaluator evaluator;
	
	ObjectReference object;
	
	Name[] versions = [BuiltinName!"SDC", BuiltinName!"D_LP64"];
	
	static struct State {
		Scope currentScope;
		
		ParamType returnType;
		ParamType thisType;
		
		string manglePrefix;
		
		mixin(bitfields!(
			bool, "buildErrorNode", 1,
			uint, "", 7,
		));
		
		uint fieldIndex;
		uint methodIndex;
	}
	
	State state;
	alias state this;
	
	Scheduler scheduler;
	
	alias Step = d.ir.symbol.Step;
	
	this(Context context, Evaluator evaluator, FileSource delegate(Name[]) sourceFactory) {
		this.context	= context;
		this.evaluator	= evaluator;
		
		moduleVisitor		= new ModuleVisitor(this, sourceFactory);
		scheduler			= new Scheduler(this);
		
		auto obj	= importModule([BuiltinName!"object"]);
		object		= new ObjectReference(obj);
		
		scheduler.require(obj, Step.Populated);
	}
	
	AstModule parse(S)(S source, Name[] packages) if(is(S : Source)) {
		auto trange = lex!((line, index, length) => Location(source, line, index, length))(source.content, context);
		return trange.parse(packages[$ - 1], packages[0 .. $-1]);
	}
	
	Module add(FileSource source, Name[] packages) {
		auto astm = parse(source, packages);
		auto mod = moduleVisitor.modulize(astm);
		
		moduleVisitor.preregister(mod);
		
		scheduler.schedule(astm, mod);
		
		return mod;
	}
	
	void terminate() {
		scheduler.terminate();
	}
	
	auto evaluate(Expression e) {
		return evaluator.evaluate(e);
	}
	
	auto importModule(Name[] pkgs) {
		return moduleVisitor.importModule(pkgs);
	}
	
	auto raiseCondition(T)(Location location, string message) {
		if(buildErrorNode) {
			static if(is(T == Type)) {
				return QualType(new ErrorType(location, message));
			} else static if(is(T == Expression)) {
				return new ErrorExpression(location, message);
			} else static if(is(T == Symbol)) {
				return new ErrorSymbol(location, message);
			} else {
				static assert(false, "compilationCondition only works for Types and Expressions.");
			}
		} else {
			throw new CompileException(location, message);
		}
	}
	
	Function buildMain(Module[] mods) {
		auto candidates = mods.map!(m => m.members).joiner.map!((s) {
			if(auto fun = cast(Function) s) {
				if(fun.name == BuiltinName!"main") {
					return fun;
				}
			}
			
			return null;
		}).filter!(s => !!s).array();
		
		assert(candidates.length < 2, "Several main functions");
		assert(candidates.length == 1, "No candidate");
		
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
		auto bootstrap = new Function(main.location, QualType(type), BuiltinName!"_Dmain", [], new BlockStatement(location, fbody));
		bootstrap.isStatic = true;
		bootstrap.step = Step.Processed;
		bootstrap.mangle = "_Dmain";
		
		return bootstrap;
	}
}

