/**
 * This module crawl the AST to resolve identifiers and process types.
 */
module d.semantic.semantic;

public import util.visitor;

import d.semantic.scheduler;

import d.ast.declaration;
import d.ast.expression;
import d.ast.statement;

import d.ir.expression;
import d.ir.symbol;
import d.ir.type;

import d.context.name;

alias AstModule = d.ast.declaration.Module;
alias Module = d.ir.symbol.Module;

alias CallExpression = d.ir.expression.CallExpression;

final class SemanticPass {
	import d.context.context;
	Context context;
	
	Scheduler scheduler;
	
	static struct State {
		import d.ir.dscope;
		Scope currentScope;
		
		ParamType returnType;
		ParamType thisType;
		
		Function ctxSym;
		
		string manglePrefix;
	}
	
	State state;
	alias state this;
	
	alias Step = d.ir.symbol.Step;
	
	import d.semantic.evaluator;
	Evaluator evaluator;
	
	import d.semantic.datalayout;
	DataLayout dataLayout;
	
	import d.semantic.dmodule;
	ModuleVisitor moduleVisitor;
	
	import d.object;
	ObjectReference object;
	
	Name[] versions = getDefaultVersions();
	
	alias EvaluatorBuilder = Evaluator delegate(Scheduler, ObjectReference);
	alias DataLayoutBuilder = DataLayout delegate(ObjectReference);
	
	this(
		Context context,
		EvaluatorBuilder evBuilder,
		DataLayoutBuilder dlBuilder,
		string[] includePaths,
	) {
		this.context	= context;
		
		moduleVisitor	= new ModuleVisitor(this, includePaths);
		scheduler		= new Scheduler(this);
		
		import d.context.name;
		auto obj	= importModule([BuiltinName!"object"]);
		this.object	= new ObjectReference(obj);
		
		evaluator = evBuilder(scheduler, this.object);
		dataLayout = dlBuilder(this.object);
		
		scheduler.require(obj, Step.Populated);
	}
	
	Module add(string filename) {
		return moduleVisitor.add(filename);
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
		auto location = main.location;
		
		auto type = main.type;
		auto returnType = type.returnType.getType();
		auto call = new CallExpression(location, returnType, new FunctionExpression(location, main), []);
		
		import d.ir.instruction;
		Body fbody;
		auto bb = fbody.newBasicBlock(BuiltinName!"entry");
		if (returnType.kind == TypeKind.Builtin && returnType.builtin == BuiltinType.Void) {
			fbody[bb].eval(location, call);
			fbody[bb].ret(location, new IntegerLiteral(location, 0, BuiltinType.Int));
		} else {
			fbody[bb].ret(location, call);
		}
		
		auto bootstrap = new Function(
			main.location,
			main.getModule(),
			FunctionType(
				Linkage.C,
				Type.get(BuiltinType.Int).getParamType(false, false),
				[],
				false,
			),
			BuiltinName!"_Dmain",
			[],
		);
		
		bootstrap.fbody = fbody;
		
		bootstrap.visibility = Visibility.Public;
		bootstrap.step = Step.Processed;
		bootstrap.mangle = BuiltinName!"_Dmain";
		
		return bootstrap;
	}
}

private:

auto getDefaultVersions() {
	import d.context.name;
	auto versions = [BuiltinName!"SDC", BuiltinName!"D_LP64", BuiltinName!"X86_64", BuiltinName!"Posix"];
	
	version(linux) {
		versions ~=  BuiltinName!"linux";
	}
	
	version(OSX) {
		versions ~=  BuiltinName!"OSX";
	}
	
	version(Posix) {
		versions ~=  BuiltinName!"Posix";
	}
	
	return versions;
}
