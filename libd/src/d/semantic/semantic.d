/**
 * This module crawl the AST to resolve identifiers and process types.
 */
module d.semantic.semantic;

public import util.visitor;

import d.semantic.dmodule;
import d.semantic.scheduler;

import d.ast.declaration;
import d.ast.dmodule;
import d.ast.expression;
import d.ast.statement;

import d.ir.expression;
import d.ir.dscope;
import d.ir.statement;
import d.ir.symbol;
import d.ir.type;

import d.parser.base;

import d.base.name;

import d.exception;
import d.lexer;
import d.location;

alias AstModule = d.ast.dmodule.Module;
alias Module = d.ir.symbol.Module;

alias CallExpression = d.ir.expression.CallExpression;

alias BlockStatement = d.ir.statement.BlockStatement;
alias ExpressionStatement = d.ir.statement.ExpressionStatement;
alias ReturnStatement = d.ir.statement.ReturnStatement;

final class SemanticPass {
	private ModuleVisitor moduleVisitor;
	
	import d.base.context;
	Context context;
	
	import d.semantic.evaluator;
	Evaluator evaluator;
	
	import d.semantic.datalayout;
	DataLayout dataLayout;
	
	import d.object;
	ObjectReference object;
	
	Name[] versions = getDefaultVersions();
	
	static struct State {
		Scope currentScope;
		
		ParamType returnType;
		ParamType thisType;
		
		Function ctxSym;
		
		string manglePrefix;
		
		import std.bitmanip;
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
	
	this(Context context, Evaluator evaluator, DataLayout dataLayout, SourceFactory sourceFactory) {
		this.context	= context;
		this.evaluator	= evaluator;
		this.dataLayout	= dataLayout;
		
		moduleVisitor	= new ModuleVisitor(this, sourceFactory);
		scheduler		= new Scheduler(this);
		
		import d.base.name;
		auto obj	= importModule([BuiltinName!"object"]);
		this.object	= new ObjectReference(obj);
		
		scheduler.require(obj, Step.Populated);
	}
	
	AstModule parse(S)(S source, PackageNames packages) if(is(S : Source)) {
		auto trange = lex!((line, index, length) => Location(source, line, index, length))(source.content, context);
		return trange.parse(packages[$ - 1], packages[0 .. $-1]);
	}
	
	Module add(Source source, PackageNames packages) {
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
	
	auto evalIntegral(Expression e) {
		return evaluator.evalIntegral(e);
	}
	
	auto evalString(Expression e) {
		return evaluator.evalString(e);
	}
	
	auto importModule(Name[] pkgs) {
		return moduleVisitor.importModule(pkgs);
	}
	
	T raiseCondition(T)(Location location, string message) {
		if (buildErrorNode) {
			static if(is(T == Type)) {
				// FIXME: newtype
				// return QualType(new ErrorType(location, message));
				throw new CompileException(location, message);
			} else static if(is(T == Expression) || is(T == CompileTimeExpression)) {
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
		import std.algorithm, std.array;
		auto candidates = mods.map!(m => m.members).joiner.map!((s) {
			if (auto fun = cast(Function) s) {
				if (fun.name == BuiltinName!"main") {
					return fun;
				}
			}
			
			return null;
		}).filter!(s => !!s).array();
		
		assert(candidates.length < 2, "Several main functions");
		assert(candidates.length == 1, "No main function");
		
		auto main = candidates[0];
		auto location = main.fbody.location;
		
		auto type = main.type;
		auto returnType = type.returnType.getType();
		auto call = new CallExpression(location, returnType, new FunctionExpression(location, main), []);
		
		Statement[] fbody;
		if (returnType.kind == TypeKind.Builtin && returnType.builtin == BuiltinType.Void) {
			fbody ~= new ExpressionStatement(call);
			fbody ~= new ReturnStatement(location, new IntegerLiteral!true(location, 0, BuiltinType.Int));
		} else {
			fbody ~= new ReturnStatement(location, call);
		}
		
		type = FunctionType(Linkage.C, Type.get(BuiltinType.Int).getParamType(false, false), [], false);
		auto bootstrap = new Function(main.location, type, BuiltinName!"_Dmain", [], new BlockStatement(location, fbody));
		bootstrap.storage = Storage.Enum;
		bootstrap.visibility = Visibility.Public;
		bootstrap.step = Step.Processed;
		bootstrap.mangle = "_Dmain";
		
		return bootstrap;
	}
}

private:

auto getDefaultVersions() {
	import d.base.name;
	auto versions = [BuiltinName!"SDC", BuiltinName!"D_LP64", BuiltinName!"X86_64"];
	
	version(linux) {
		versions ~=  BuiltinName!"linux";
	}
	
	version(OSX) {
		versions ~=  BuiltinName!"OSX";
	}
	
	return versions;
}
