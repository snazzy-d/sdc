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

import source.name;

alias AstModule = d.ast.declaration.Module;
alias Module = d.ir.symbol.Module;

alias CallExpression = d.ir.expression.CallExpression;

final class SemanticPass {
	import source.context;
	Context context;

	string[] includePaths;
	bool enableUnittest;

	Scheduler scheduler;

	static struct State {
		import d.ir.dscope;
		Scope currentScope;

		ParamType returnType;
		ParamType thisType;

		Function ctxSym;

		string manglePrefix;

		// Indicate that what is being worked on is a
		// template specialization pattern.
		bool inPattern;
	}

	State state;
	alias state this;

	alias Step = d.ir.symbol.Step;

	import d.semantic.evaluator;
	Evaluator evaluator;

	import d.semantic.datalayout;
	DataLayout dataLayout;

	import d.semantic.dmodule;
	ModuleVisitorData moduleVisitorData;

	import d.object;
	ObjectReference object;

	Name[] versions = getDefaultVersions();

	alias EvaluatorBuilder = Evaluator delegate(SemanticPass);
	alias DataLayoutBuilder = DataLayout delegate(ObjectReference);

	this(
		Context context,
		string[] includePaths,
		string[] preload,
		ref Module[] preloadedModules,
		bool enableUnittest,
		EvaluatorBuilder evBuilder,
		DataLayoutBuilder dlBuilder,
	) {
		this.context = context;
		this.includePaths = includePaths;
		this.enableUnittest = enableUnittest;

		scheduler = new Scheduler(this);

		foreach (filename; preload) {
			preloadedModules ~= add(filename);
		}

		import source.name;
		auto obj = importModule([BuiltinName!"object"]);
		this.object = new ObjectReference(obj);

		evaluator = evBuilder(this);
		dataLayout = dlBuilder(this.object);

		scheduler.require(obj, Step.Populated);
	}

	Module add(string filename) {
		return ModuleVisitor(this).add(filename);
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
		return ModuleVisitor(this).importModule(pkgs);
	}

	Function buildMain(Module m) {
		import std.algorithm, std.array;
		auto candidates = m.members.map!((s) {
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
		auto call =
			new CallExpression(location, returnType,
			                   new FunctionExpression(location, main), []);

		import d.ir.instruction;
		Body fbody;
		auto bb = fbody.newBasicBlock(BuiltinName!"entry");
		if (returnType.kind == TypeKind.Builtin
			    && returnType.builtin == BuiltinType.Void) {
			fbody[bb].eval(location, call);
			fbody[bb].ret(location,
			              new IntegerLiteral(location, 0, BuiltinType.Int));
		} else {
			fbody[bb].ret(location, call);
		}

		auto bootstrap = new Function(
			main.location,
			main.getModule(),
			FunctionType(
				Linkage.C,
				Type.get(BuiltinType.Int).getParamType(ParamKind.Regular),
				[],
				false
			),
			BuiltinName!"_Dmain",
			[]
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
	import source.name;
	auto versions =
		[BuiltinName!"SDC", BuiltinName!"D_LP64", BuiltinName!"X86_64"];

	version(linux) {
		versions ~= BuiltinName!"linux";
	}

	version(OSX) {
		versions ~= BuiltinName!"OSX";
	}

	version(FreeBSD) {
		versions ~= BuiltinName!"FreeBSD";
	}

	version(Posix) {
		versions ~= BuiltinName!"Posix";
	}

	return versions;
}
