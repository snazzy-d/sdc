module d.semantic.flow;

import d.semantic.semantic;

import d.ir.statement;

import d.context.location;

struct FlowAnalyzer {
private:
	SemanticPass pass;
	alias pass this;
	
	Statement previousStatement;
	
	import d.ir.symbol;
	Variable[] varStack;
	
	uint[Variable] closure;
	uint nextClosureIndex;
	
	import d.context.name;
	Variable[][Name] labelStacks;
	Variable[][][Name] inFlightGotosStacks;
	
	Variable[] switchStack;
	SwitchStatement switchStmt;
	
	import std.bitmanip;
	mixin(bitfields!(
		bool, "mustTerminate", 1,
		bool, "funTerminate", 1,
		bool, "blockTerminate", 1,
		bool, "allowFallthrough", 1,
		bool, "switchMustTerminate", 1,
		bool, "switchFunTerminate", 1,
		bool, "switchHaveDefault", 1,
		uint, "", 1,
	));
	
public:
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	uint[Variable] getClosure(Function f) in {
		assert(f.fbody, "f does not have a body");
	} body {
		nextClosureIndex = f.hasContext;
		
		foreach(p; f.params) {
			if (p.storage == Storage.Capture) {
				assert(p !in closure);
				closure[p] = nextClosureIndex++;
			}
		}
		
		visit(f.fbody);
		
		if (funTerminate) {
			return closure;
		}
		
		import d.ir.type;
		if (returnType.kind == TypeKind.Builtin &&
			returnType.builtin == BuiltinType.Void) {
			return closure;
		}
		
		import d.exception;
		throw new CompileException(
			f.location,
			f.name.toString(context) ~ " "
				~ f.mangle.toString(context) ~ " does not terminate :(",
		);
	}
	
	void visit(Statement s) {
		if (!mustTerminate) {
			return this.dispatch(s);
		} else if (auto c = cast(CaseStatement) s) {
			return visit(c);
		} else if (auto l = cast(LabeledStatement) s) {
			// FIXME: Check if this is default or a goto jump here.
			return visit(l);
		}
		
		import d.exception;
		throw new CompileException(s.location, "Unreachable statement");
	}
	
	void visit(BlockStatement b) {
		auto oldPreviousStatement = previousStatement;
		auto oldVarStack = varStack;
		scope(exit) {
			previousStatement = oldPreviousStatement;
			varStack = oldVarStack;
		}
		
		previousStatement = null;
		foreach(i, s; b.statements) {
			visit(s);
			previousStatement = s;
		}
	}
	
	void visit(ExpressionStatement s) {}
	
	void visit(VariableStatement s) in {
		assert(s.var.step == Step.Processed);
	} body {
		auto v = s.var;
		if (v.storage.isGlobal) {
			return;
		}
		
		if (v.storage == Storage.Capture) {
			assert(v !in closure);
			closure[v] = nextClosureIndex++;
		}
		
		varStack ~= v;
	}
	
	void visit(FunctionStatement s) in {
		assert(s.fun.step == Step.Processed);
	} body {}
	
	void visit(AggregateStatement s) in {
		assert(s.aggregate.step == Step.Processed);
	} body {}
	
	void visit(ReturnStatement s) {
		terminateFun();
	}
	
	void visit(IfStatement s) {
		auto oldMustTerminate = mustTerminate;
		auto oldFunTerminate = funTerminate;
		auto oldBlockTerminate = blockTerminate;
		
		visit(s.then);
		
		auto thenMustTerminate = mustTerminate;
		auto thenFunTerminate = funTerminate;
		auto thenBlockTerminate = blockTerminate;
		scope(exit) {
			mustTerminate = thenMustTerminate && mustTerminate;
			funTerminate = thenFunTerminate && funTerminate;
			blockTerminate = thenBlockTerminate && blockTerminate;
		}
		
		mustTerminate = oldMustTerminate;
		funTerminate = oldFunTerminate;
		blockTerminate = oldBlockTerminate;
		
		if (s.elseStatement) {
			visit(s.elseStatement);
		}
	}
	
	void visit(LoopStatement s) {
		auto oldMustTerminate = mustTerminate;
		auto oldFunTerminate = funTerminate;
		auto oldBlockTerminate = blockTerminate;
		scope(exit) {
			if (!s.skipFirstCond) {
				funTerminate = oldFunTerminate && funTerminate;
			}
			
			if (!funTerminate) {
				mustTerminate = oldMustTerminate && mustTerminate;
				blockTerminate = oldBlockTerminate && blockTerminate;
			}
		}
		
		visit(s.fbody);
	}
	
	void visit(CleanupStatement s) {
		auto oldMustTerminate = mustTerminate;
		auto oldFunTerminate = funTerminate;
		auto oldBlockTerminate = blockTerminate;
		scope(exit) {
			mustTerminate = oldMustTerminate;
			funTerminate = oldFunTerminate;
			blockTerminate = oldBlockTerminate;
		}
		
		visit(s.cleanup);
	}
	
	void visit(SwitchStatement s) {
		auto oldSwitchStmt = switchStmt;
		auto oldSwitchStack = switchStack;
		auto oldAllowFallthrough = allowFallthrough;
		auto oldSwitchMustTerminate = switchMustTerminate;
		auto oldSwitchFunTerminate = switchFunTerminate;
		auto oldBlockTerminate = blockTerminate;
		auto oldSwitchHaveDefault = switchHaveDefault;
		
		scope(exit) {
			mustTerminate = switchMustTerminate && mustTerminate;
			funTerminate = switchFunTerminate && funTerminate;
			blockTerminate = oldBlockTerminate || funTerminate;
			
			switchStmt = oldSwitchStmt;
			switchStack = oldSwitchStack;
			allowFallthrough = oldAllowFallthrough;
			switchMustTerminate = oldSwitchMustTerminate;
			switchFunTerminate = oldSwitchFunTerminate;
			switchHaveDefault = oldSwitchHaveDefault;
		}
		
		switchStmt = s;
		switchStack = varStack;
		allowFallthrough = true;
		switchFunTerminate = true;
		
		visit(s.statement);

		if(!switchHaveDefault) {
			import d.exception;
			throw new CompileException(
				s.location,
				"switch statement without a default; use 'final switch' or add 'default: assert(0);' or add 'default: break;'",
				);
		}
	}
	
	void visit(BreakStatement s) {
		terminateBlock();
	}
	
	void visit(ContinueStatement s) {
		terminateBlock();
	}
	
	void visit(AssertStatement s) {}
	
	void visit(HaltStatement s) {
		terminateFun();
	}
	
	void visit(ThrowStatement s) {
		terminateFun();
	}
	
	void visit(TryStatement s) {
		auto oldMustTerminate = mustTerminate;
		auto oldFunTerminate = funTerminate;
		auto oldBlockTerminate = blockTerminate;
		
		visit(s.tbody);
		
		auto tryMustTerminate = mustTerminate;
		auto tryFunTerminate = funTerminate;
		auto tryBlockTerminate = blockTerminate;
		
		scope(exit) {
			mustTerminate = tryMustTerminate;
			funTerminate = tryFunTerminate;
			blockTerminate = tryBlockTerminate;
		}
		
		foreach(c; s.catches) {
			mustTerminate = oldMustTerminate;
			funTerminate = oldFunTerminate;
			blockTerminate = oldBlockTerminate;
			
			visit(c.cbody);
			
			tryMustTerminate = tryMustTerminate && mustTerminate;
			tryFunTerminate = tryFunTerminate && funTerminate;
			tryBlockTerminate = tryBlockTerminate && blockTerminate;
		}
	}
	
	private void setCaseEntry(
		Location location,
		string switchError,
		string fallthroughError,
	) out {
		assert(varStack == switchStack);
	} body {
		if (allowFallthrough) {
			allowFallthrough = false;
			if (varStack == switchStack) {
				return;
			}
			
			import d.exception;
			throw new CompileException(
				location,
				"Cannot jump over variable initialization.",
			);
		}
		
		if (switchStmt is null) {
			import d.exception;
			throw new CompileException(location, switchError);
		}
		
		if (blockTerminate) {
			switchMustTerminate = mustTerminate && switchMustTerminate;
			switchFunTerminate = funTerminate && switchFunTerminate;
		} else {
			// Check for case a: case b:
			// TODO: consider default: case a:
			if ((cast(CaseStatement) previousStatement) is null) {
				import d.exception;
				throw new CompileException(location, fallthroughError);
			}
		}
		
		varStack = switchStack;
	}
	
	void visit(CaseStatement s) {
		setCaseEntry(
			s.location,
			"Case statement can only appear within switch statement.",
			"Fallthrough is disabled, use goto case.",
		);
		
		unterminate();
	}
	
	void visit(LabeledStatement s) {
		auto label = s.label;
		if (label == BuiltinName!"default") {
			if(switchHaveDefault) {
				import d.exception;
				throw new CompileException(
						s.location,
						"switch statements with multiple defaults are not allowed.",
					);
			} else {
				switchHaveDefault = true;
			}

			setCaseEntry(
				s.location,
				"Default statement can only appear within switch statement.",
				"Fallthrough is disabled, use goto default.",
			);
		}
		
		unterminate();
		
		labelStacks[label] = varStack;
		if (auto bPtr = s.label in inFlightGotosStacks) {
			auto stacks = *bPtr;
			inFlightGotosStacks.remove(label);
			
			// Check that all inflight goto to thta label are valid.
			foreach(stack; stacks) {
				import std.algorithm.searching;
				bool isValid = stack.startsWith(varStack);
				
				if (!isValid) {
					import d.exception;
					throw new CompileException(
						s.location,
						"Cannot jump over variable initialization.",
					);
				}
			}
		}
		
		visit(s.statement);
	}
	
	void visit(GotoStatement s) {
		auto label = s.label;
		if (auto bPtr = label in labelStacks) {
			auto labelStack = *bPtr;
			
			import std.algorithm.searching;
			bool isValid = varStack.startsWith(labelStack);
			
			if (!isValid) {
				import d.exception;
				throw new CompileException(
					s.location,
					"Cannot goto over variable initialization.",
				);
			}
		} else if (auto bPtr = label in inFlightGotosStacks) {
			auto varStacks = *bPtr;
			varStacks ~= varStack;
			*bPtr = varStacks;
		} else {
			inFlightGotosStacks[label] = [varStack];
		}
		
		terminateFun();
	}

private:
	void terminateBlock() {
		mustTerminate = true;
		blockTerminate = true;
	}
	
	void terminateFun() {
		terminateBlock();
		funTerminate = true;
	}
	
	void unterminate() {
		mustTerminate = false;
		blockTerminate = false;
		funTerminate = false;
	}
}
