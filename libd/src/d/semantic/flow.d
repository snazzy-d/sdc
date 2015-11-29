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
	uint[Variable] closure;
	
	import d.context.name;
	uint[Name] labelBlocks;
	uint[][][Name] inFlightGotosStacks;
	
	uint[] declBlockStack = [0];
	uint switchBlock = -1;
	
	uint nextDeclBlock = 1;
	uint nextClosureIndex;
	
	import std.bitmanip;
	mixin(bitfields!(
		bool, "mustTerminate", 1,
		bool, "funTerminate", 1,
		bool, "blockTerminate", 1,
		bool, "allowFallthrough", 1,
		bool, "switchMustTerminate", 1,
		bool, "switchFunTerminate", 1,
		uint, "", 2,
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
		auto oldDeclBlockStack = declBlockStack;
		auto oldPreviousStatement = previousStatement;
		scope(exit) {
			declBlockStack = oldDeclBlockStack;
			previousStatement = oldPreviousStatement;
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
		
		declBlockStack ~= nextDeclBlock++;
	}
	
	void visit(FunctionStatement s) in {
		assert(s.fun.step == Step.Processed);
	} body {}
	
	void visit(TypeStatement s) in {
		assert(s.type.step == Step.Processed);
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
	
	void visit(ScopeStatement s) {
		auto oldMustTerminate = mustTerminate;
		auto oldFunTerminate = funTerminate;
		auto oldBlockTerminate = blockTerminate;
		scope(exit) {
			mustTerminate = oldMustTerminate;
			funTerminate = oldFunTerminate;
			blockTerminate = oldBlockTerminate;
		}
		
		visit(s.statement);
	}
	
	void visit(SwitchStatement s) {
		auto oldSwitchBlock = switchBlock;
		auto oldAllowFallthrough = allowFallthrough;
		auto oldSwitchMustTerminate = switchMustTerminate;
		auto oldSwitchFunTerminate = switchFunTerminate;
		auto oldBlockTerminate = blockTerminate;
		
		scope(exit) {
			mustTerminate = switchMustTerminate && mustTerminate;
			funTerminate = switchFunTerminate && funTerminate;
			blockTerminate = oldBlockTerminate || funTerminate;
			
			switchBlock = oldSwitchBlock;
			allowFallthrough = oldAllowFallthrough;
			switchMustTerminate = oldSwitchMustTerminate;
			switchFunTerminate = oldSwitchFunTerminate;
		}
		
		switchBlock = declBlockStack[$ - 1];
		allowFallthrough = true;
		switchFunTerminate = true;
		
		visit(s.statement);
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
		
		visit(s.statement);
		
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
			
			visit(c.statement);
			
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
		assert(declBlockStack[$ - 1] == switchBlock);
	} body {
		if (allowFallthrough) {
			allowFallthrough = false;
			if (declBlockStack[$ - 1] == switchBlock) {
				return;
			}
			
			import d.exception;
			throw new CompileException(
				location,
				"Cannot jump over variable initialization.",
			);
		}
		
		if (switchBlock == -1) {
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
		
		foreach_reverse(i, b; declBlockStack) {
			if (b == switchBlock) {
				declBlockStack = declBlockStack[0 .. i + 1];
				break;
			}
		}
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
			setCaseEntry(
				s.location,
				"Default statement can only appear within switch statement.",
				"Fallthrough is disabled, use goto default.",
			);
		}
		
		unterminate();
		
		auto labelBlock = declBlockStack[$ - 1];
		labelBlocks[label] = labelBlock;
		if (auto bPtr = s.label in inFlightGotosStacks) {
			auto inFlightGotoStacks = *bPtr;
			inFlightGotosStacks.remove(label);
			
			foreach(inFlightGotoStack; inFlightGotoStacks) {
				bool isValid = false;
				foreach(block; inFlightGotoStack) {
					if (block == labelBlock) {
						isValid = true;
						break;
					}
				}
				
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
		if (auto bPtr = label in labelBlocks) {
			auto labelBlock = *bPtr;
			
			bool isValid = false;
			foreach(block; declBlockStack) {
				if (block == labelBlock) {
					isValid = true;
					break;
				}
			}
			
			if (!isValid) {
				import d.exception;
				throw new CompileException(
					s.location,
					"Cannot goto over variable initialization.",
				);
			}
		} else if (auto bPtr = label in inFlightGotosStacks) {
			auto blockStacks = *bPtr;
			blockStacks ~= declBlockStack;
			inFlightGotosStacks[label] = blockStacks;
		} else {
			inFlightGotosStacks[label] = [declBlockStack];
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
