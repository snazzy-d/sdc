module d.semantic.statement;

import d.semantic.semantic;

import d.ast.conditional;
import d.ast.expression;
import d.ast.statement;

import d.context.location;
import d.context.name;

import d.ir.dscope;
import d.ir.expression;
import d.ir.instruction;
import d.ir.symbol;
import d.ir.type;

struct StatementVisitor {
private:
	SemanticPass pass;
	alias pass this;
	
	Body fbody;
	
	BasicBlockRef currentBlockRef;
	
	ref inout(BasicBlock) currentBlock() inout {
		return fbody[currentBlockRef];
	}
	
	bool doesTerminate(BasicBlockRef b) const {
		return !b || fbody[b].terminate;
	}
	
	@property terminate() const {
		return doesTerminate(currentBlockRef);
	}
	
	bool allowUnreachable;
	bool allowFallthrough;
	BreakKind breakKind;
	
	UnwindInfo[] unwindActions;
	
	VariableExpression retval;
	
	struct Label {
		BasicBlockRef block;
		uint level;
		
		alias block this;
	}
	
	Label breakLabel;
	Label continueLabel;
	
	Label[Name] labels;
	
	// Forward goto can only be resolved when the label is reached.
	struct UnresolvedGoto {
		UnwindInfo[] unwind;
		BasicBlockRef block;
	}
	
	UnresolvedGoto[][Name] inFlightGotos;
	
	CaseEntry[] cases;
	
	// Mechanism to detect jump over declaration.
	// XXX: Kind of clunky, but will do for now.
	Variable[] varStack;
	Variable[] switchStack;
	Variable[][Name] labelStacks;
	Variable[][][Name] inFlightGotosStacks;
	
public:
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	void getBody(Function f, BlockStatement b) {
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		scope(failure) dump(f);
		
		currentScope = f;
		auto entry = startNewBranch(BuiltinName!"entry");
		
		flatten(b);
		f.fbody = fbody;
		
		auto rt = returnType.getType();
		// TODO: Handle auto return by specifying it to this visitor
		// instead of deducing it in dubious ways.
		if (rt.kind == TypeKind.Builtin &&
			rt.qualifier == TypeQualifier.Mutable &&
			rt.builtin == BuiltinType.None) {
			returnType = Type.get(BuiltinType.Void).getParamType(false, false);
		}
		
		if (!terminate) {
			if (returnType.kind == TypeKind.Builtin &&
				returnType.builtin == BuiltinType.Void) {
				currentBlock.ret(b.location);
			} else {
				import d.exception;
				throw new CompileException(f.location, "Must return");
			}
		}
	}
	
	void dump(Function f) {
		import std.algorithm, std.range;
		auto params = f.params
			.map!(p => p.name.toString(pass.context))
			.join(", ");
		
		import std.stdio;
		write(f.name.toString(context), '(', params, ") {");
		fbody.dump(context);
		writeln("}\n");
	}
	
	void visit(Statement s) {
		if (!terminate) {
			goto Dispatch;
		}
		
		if (auto b = cast(BlockStatement) s) {
			return visit(b);
		}
		
		if (auto c = cast(CaseStatement) s) {
			return visit(c);
		}
		
		if (auto l = cast(LabeledStatement) s) {
			return visit(l);
		}
		
		if (allowUnreachable) {
			startNewBranch(BuiltinName!"unreachable");
		} else {
			import d.exception;
			throw new CompileException(s.location, "Unreachable statement");
		}
		
		Dispatch:
		allowUnreachable = false;
		this.dispatch(s);
	}
	
private:
	BasicBlockRef flatten(BlockStatement b) {
		return buildBlock(b.location, b.statements);
	}
	
	BasicBlockRef getUnwindBlock() {
		if (unwindActions.length == 0) {
			return BasicBlockRef();
		}
		
		auto ub = &unwindActions[$ - 1];
		if (!ub.unwindBlock) {
			ub.unwindBlock = fbody.newBasicBlock(BuiltinName!"unwind");
		}
		
		return ub.unwindBlock;
	}
	
	BasicBlockRef startNewBranch(Name name) {
		return currentBlockRef = fbody.newBasicBlock(name, getUnwindBlock());
	}
	
	BasicBlockRef maybeBranchToNewBlock(Location location, Name name) {
		if (currentBlockRef && currentBlock.empty) {
			auto unwindBlock = getUnwindBlock();
			currentBlock.landingpad = unwindBlock;
			return currentBlockRef;
		}
		
		return maybeBranchTo(location, currentBlockRef, startNewBranch(name));
	}
	
	BasicBlockRef maybeBranchTo(Location location, BasicBlockRef dst) {
		return maybeBranchTo(location, currentBlockRef, dst);
	}
	
	BasicBlockRef maybeBranchTo(
		Location location,
		BasicBlockRef src,
		BasicBlockRef dst,
	) {
		if (!doesTerminate(src)) {
			fbody[src].branch(location, dst);
		}
		
		return dst;
	}
	
	BasicBlockRef buildBlock(U...)(Location location, U args) {
		auto oldScope = currentScope;
		auto oldVarStack = varStack;
		scope(exit) {
			currentScope = oldScope;
			varStack = oldVarStack;
		}
		
		currentScope = new NestedScope(currentScope);
		
		auto unwindLevel = unwindActions.length;
		scope(success) unwindTo(unwindLevel);
		
		process(args);
		
		return currentBlockRef;
	}
	
	void process(Statement[] statements) {
		foreach(s; statements) {
			visit(s);
		}
	}
	
	void process(Statement s) {
		visit(s);
	}
	
	BasicBlockRef autoBlock(Statement s) {
		if (auto b = cast(BlockStatement) s) {
			return flatten(b);
		}
		
		return buildBlock(s.location, s);
	}
	
	Expression check(Expression e) {
		auto t = e.type;
		if (t.kind == TypeKind.Error) {
			import d.exception;
			throw new CompileException(t.error.location, t.error.message);
		}
		
		// FIXME: Update flags.
		
		return e;
	}
	
	auto buildExpression(AstExpression expr) {
		import d.semantic.expression;
		return check(ExpressionVisitor(pass).visit(expr));
	}
	
	auto buildExpression(AstExpression expr, Type type) {
		import d.semantic.caster, d.semantic.expression;
		return check(buildExplicitCast(
			pass,
			expr.location,
			type,
			ExpressionVisitor(pass).visit(expr),
		));
	}
	
	auto buildCondition(AstExpression expr) {
		return buildExpression(expr, Type.get(BuiltinType.Bool));
	}
	
	auto buildString(AstExpression expr) {
		return buildExpression(
			expr,
			Type.get(BuiltinType.Char).getSlice(TypeQualifier.Immutable),
		);
	}
	
public:
	void visit(BlockStatement b) {
		flatten(b);
	}
	
	void visit(ExpressionStatement s) {
		currentBlock.eval(s.location, buildExpression(s.expression));
	}
	
	void visit(DeclarationStatement s) {
		import d.semantic.declaration;
		auto syms = DeclarationVisitor(pass).flatten(s.declaration);
		
		scheduler.require(syms);
		
		foreach(sym; syms) {
			if (auto v = cast(Variable) sym) {
				currentBlock.alloca(v.location, v);
				varStack ~= v;
			} else if (cast(Function) sym || cast(Aggregate) sym) {
				// FIXME: We should get rid of this.
				currentBlock.declare(sym.location, sym);
			}
		}
	}
	
	void visit(IdentifierStarIdentifierStatement s) {
		import d.semantic.identifier;
		IdentifierResolver(pass)
			.build(s.identifier)
			.apply!(delegate void(identified) {
				alias T = typeof(identified);
				static if (is(T : Expression)) {
					assert(0, "expression identifier * identifier are not implemented.");
				} else static if (is(T : Type)) {
					auto t = identified.getPointer();
					
					import d.semantic.expression;
					import d.semantic.defaultinitializer : InitBuilder;
					auto value = s.value
						? ExpressionVisitor(pass).visit(s.value)
						: InitBuilder(pass, s.location).visit(t);
					
					import d.semantic.caster;
					auto v = new Variable(
						s.location,
						t.getParamType(false, false),
						s.name,
						buildImplicitCast(pass, s.location, t, value),
					);
					
					v.step = Step.Processed;
					pass.currentScope.addSymbol(v);
					
					currentBlock.alloca(s.location, v);
				} else {
					assert(0, "Was not expecting " ~ T.stringof);
				}
			})();
	}
	
	void visit(IfStatement s) {
		auto ifBlock = currentBlockRef;
		
		auto ifTrue = startNewBranch(BuiltinName!"then");
		auto mergeTrue = autoBlock(s.then);
		
		BasicBlockRef ifFalse, mergeBlock;
		if (s.elseStatement) {
			ifFalse = startNewBranch(BuiltinName!"else");
			autoBlock(s.elseStatement);
			if (!terminate) {
				mergeBlock = maybeBranchToNewBlock(
					s.elseStatement.location,
					BuiltinName!"endif",
				);
			}
		} else {
			ifFalse = mergeBlock = startNewBranch(BuiltinName!"endif");
		}
		
		if (!doesTerminate(mergeTrue)) {
			if (!mergeBlock) {
				mergeBlock = startNewBranch(BuiltinName!"endif");
			}
			
			maybeBranchTo(s.then.location, mergeTrue, mergeBlock);
		}
		
		fbody[ifBlock].branch(
			s.location,
			buildCondition(s.condition),
			ifTrue,
			ifFalse,
		);
	}
	
	void genLoop(
		Location location,
		Expression condition,
		Statement statement,
		Expression increment,
		Variable element = null,
		bool skipFirstCond = false,
	) {
		auto oldBreakKind = breakKind;
		auto oldBreakLabel = breakLabel;
		auto oldContinueLabel = continueLabel;
		scope(exit) {
			currentBlockRef = breakLabel.block;
			
			breakKind = oldBreakKind;
			breakLabel = oldBreakLabel;
			continueLabel = oldContinueLabel;
		}
		
		breakKind = BreakKind.Loop;
		
		auto entryBlock = currentBlockRef;
		auto incBlock = startNewBranch(BuiltinName!"loop.continue");
		if (increment) {
			currentBlock.eval(increment.location, increment);
		}
		
		auto testBlock = maybeBranchToNewBlock(location, BuiltinName!"loop.test");
		auto bodyBlock = startNewBranch(BuiltinName!"loop.body");
		
		continueLabel = Label(incBlock, cast(uint) unwindActions.length);
		breakLabel = Label(
			BasicBlockRef.init,
			cast(uint) unwindActions.length,
		);
		
		if (element !is null) {
			currentBlock.alloca(element.location, element);
		}
		
		autoBlock(statement);
		maybeBranchTo(location, incBlock);
		
		fbody[entryBlock].branch(location, skipFirstCond ? bodyBlock : testBlock);
		if (condition) {
			auto breakLabel = getBreakLabel(location);
			fbody[testBlock].branch(
				location,
				condition,
				bodyBlock,
				breakLabel.block,
			);
		} else {
			fbody[testBlock].branch(location, bodyBlock);
		}
	}
	
	void genLoop(
		Location location,
		AstExpression condition,
		Statement statement,
		AstExpression increment = null,
		Variable element = null,
		bool skipFirstCond = false,
	) {
		Expression cond, inc;
		
		if (condition) {
			cond = buildCondition(condition);
		}
		
		if (increment) {
			inc = buildExpression(increment);
		}
		
		genLoop(location, cond, statement, inc, element, skipFirstCond);
	}
	
	void visit(WhileStatement w) {
		genLoop(w.location, w.condition, w.statement);
	}
	
	void visit(DoWhileStatement w) {
		genLoop(w.location, w.condition, w.statement, null, null, true);
	}
	
	void visit(ForStatement f) {
		buildBlock(f.location, f);
	}
	
	void process(ForStatement f) {
		if (f.initialize) {
			visit(f.initialize);
		}
		
		genLoop(f.location, f.condition, f.statement, f.increment);
	}
	
	void visit(ForeachStatement f) {
		buildBlock(f.location, f);
	}
	
	void process(ForeachStatement f) {
		assert(!f.reverse, "foreach_reverse not supported at this point.");
		
		import d.semantic.expression;
		auto iterated = ExpressionVisitor(pass).visit(f.iterated);
		
		import d.context.name, d.semantic.identifier;
		auto length = IdentifierResolver(pass)
			.buildIn(iterated.location, iterated, BuiltinName!"length")
			.apply!(delegate Expression(e) {
				static if (is(typeof(e) : Expression)) {
					return e;
				} else {
					import d.ir.error;
					return new CompileError(
						iterated.location,
						typeid(e).toString() ~ " is not a valid length",
					).expression;
				}
			})();
		
		Variable idx;
		
		auto loc = f.location;
		switch(f.tupleElements.length) {
			case 1:
				import d.semantic.defaultinitializer;
				idx = new Variable(
					loc,
					length.type,
					BuiltinName!"",
					InitBuilder(pass, loc).visit(length.type),
				);
				
				idx.step = Step.Processed;
				break;
			
			case 2:
				auto idxDecl = f.tupleElements[0];
				assert(!idxDecl.type.isRef, "index can't be ref");
				
				import d.semantic.type;
				auto t = idxDecl.type.getType().isAuto
					? length.type
					: TypeVisitor(pass).visit(idxDecl.type.getType());
				
				auto idxLoc = idxDecl.location;
				
				import d.semantic.defaultinitializer;
				idx = new Variable(
					idxLoc,
					t,
					idxDecl.name,
					InitBuilder(pass, idxLoc).visit(t),
				);
				
				idx.step = Step.Processed;
				currentScope.addSymbol(idx);
				
				break;
			
			default:
				assert(0, "Wrong number of elements");
		}
		
		assert(idx);
		currentBlock.alloca(idx.location, idx);
		
		auto idxExpr = new VariableExpression(idx.location, idx);
		auto increment = build!UnaryExpression(
			loc,
			idx.type,
			UnaryOp.PreInc,
			idxExpr,
		);
		
		import d.semantic.caster;
		length = buildImplicitCast(pass, idx.location, idx.type, length);
		auto condition = build!ICmpExpression(loc, ICmpOp.Less, idxExpr, length);
		
		auto iType = iterated.type.getCanonical();
		assert(iType.hasElement, "Only array and slice are supported for now.");
		
		Type et = iType.element;
		
		auto eDecl = f.tupleElements[$ - 1];
		auto eLoc = eDecl.location;
		
		import d.semantic.expression;
		auto eVal = ExpressionVisitor(pass).getIndex(eLoc, iterated, idxExpr);
		auto eType = eVal.type.getParamType(eDecl.type.isRef, false);
		
		if (!eDecl.type.getType().isAuto) {
			import d.semantic.type;
			eType = TypeVisitor(pass).visit(eDecl.type);
			
			import d.semantic.caster;
			eVal = buildImplicitCast(pass, eLoc, eType.getType(), eVal);
		}
		
		auto element = new Variable(eLoc, eType, eDecl.name, eVal);
		element.step = Step.Processed;
		currentScope.addSymbol(element);
		
		genLoop(loc, condition, f.statement, increment, element);
	}
	
	void visit(ForeachRangeStatement f) {
		buildBlock(f.location, f);
	}
	
	void process(ForeachRangeStatement f) {
		import d.semantic.expression;
		auto start = ExpressionVisitor(pass).visit(f.start);
		auto stop  = ExpressionVisitor(pass).visit(f.stop);
		
		assert(f.tupleElements.length == 1, "Wrong number of elements");
		auto iDecl = f.tupleElements[0];
		
		auto loc = f.location;
		
		import d.semantic.type, d.semantic.typepromotion;
		auto type = iDecl.type.getType().isAuto
			? getPromotedType(pass, loc, start.type, stop.type)
			: TypeVisitor(pass).visit(iDecl.type).getType();
		
		import d.semantic.caster;
		start = buildImplicitCast(pass, start.location, type, start);
		stop  = buildImplicitCast(pass, stop.location, type, stop);
		
		if (f.reverse) {
			auto tmp = start;
			start = stop;
			stop = tmp;
		}
		
		auto idx = new Variable(
			iDecl.location,
			type.getParamType(iDecl.type.isRef, false),
			iDecl.name,
			start,
		);
		
		idx.step = Step.Processed;
		currentScope.addSymbol(idx);
		currentBlock.alloca(idx.location, idx);
		
		Expression idxExpr = new VariableExpression(idx.location, idx);
		Expression increment, condition;
		
		if (f.reverse) {
			// for(...; idx-- > stop; idx)
			condition = build!ICmpExpression(
				loc,
				ICmpOp.Greater,
				build!UnaryExpression(loc, type, UnaryOp.PostDec, idxExpr),
				stop,
			);
		} else {
			// for(...; idx < stop; idx++)
			condition = build!ICmpExpression(loc, ICmpOp.Less, idxExpr, stop);
			increment = build!UnaryExpression(loc, type, UnaryOp.PreInc, idxExpr);
		}
		
		genLoop(loc, condition, f.statement, increment);
	}
	
	void visit(ReturnStatement s) {
		// TODO: precompute autotype instead of managing it here.
		auto rt = returnType.getType();
		auto isAutoReturn =
			rt.kind == TypeKind.Builtin &&
			rt.qualifier == TypeQualifier.Mutable &&
			rt.builtin == BuiltinType.None;
		
		// return; has no value.
		if (s.value is null) {
			if (isAutoReturn) {
				returnType = Type.get(BuiltinType.Void).getParamType(false, false);
			}
			
			closeBlockTo(0);
			currentBlock.ret(s.location);
			return;
		}
		
		auto value = buildExpression(s.value);
		
		// TODO: Handle auto return by specifying it to this visitor
		// instead of deducing it in dubious ways.
		if (isAutoReturn) {
			// TODO: auto ref return.
			returnType = value.type.getParamType(false, false);
		} else {
			import d.semantic.caster;
			value = buildImplicitCast(pass, s.location, returnType.getType(), value);
			if (returnType.isRef) {
				if (!value.isLvalue) {
					import d.exception;
					throw new CompileException(s.location, "Cannot ref return lvalues");
				}
				
				value = build!UnaryExpression(
					s.location,
					value.type.getPointer(),
					UnaryOp.AddressOf,
					value,
				);
			}
		}
		
		// If unwind work is needed, store the result in a temporary.
		if (unwindActions.length) {
			auto location = value.location;
			if (retval is null) {
				auto v = new Variable(
					location,
					value.type,
					BuiltinName!"return",
					new VoidInitializer(location, value.type),
				);
				
				v.step = Step.Processed;
				retval = new VariableExpression(location, v);
			}
			
			currentBlock.eval(location, check(build!BinaryExpression(
				location,
				retval.type,
				BinaryOp.Assign,
				retval,
				value,
			)));
			
			value = retval;
		}
		
		closeBlockTo(0);
		if (!terminate) {
			currentBlock.ret(s.location, check(value));
		}
	}
	
	private BasicBlockRef unwindAndBranch(Location location, Label l) in {
		assert(l, "Invalid label");
	} body {
		closeBlockTo(l.level);
		return maybeBranchTo(location, l.block);
	}
	
	Label getBreakLabel(Location location) {
		if (breakLabel) {
			return breakLabel;
		}
		
		Name name;
		final switch(breakKind) with(BreakKind) {
			case None:
				import d.exception;
				throw new CompileException(
					location,
					"Cannot break outside of switches and loops",
				);
			
			case Loop:
				name = BuiltinName!"loop.exit";
				break;
			
			case Switch:
				name = BuiltinName!"endswitch";
				break;
		}
		
		auto oldCurrentBlock = currentBlockRef;
		scope(success) currentBlockRef = oldCurrentBlock;
		breakLabel.block = startNewBranch(name);
		return breakLabel;
	}
	
	void visit(BreakStatement s) {
		unwindAndBranch(s.location, getBreakLabel(s.location));
	}
	
	void visit(ContinueStatement s) {
		if (!continueLabel) {
			import d.exception;
			throw new CompileException(
				s.location,
				"Cannot continue outside of loops",
			);
		}
		
		unwindAndBranch(s.location, continueLabel);
	}
	
	void visit(SwitchStatement s) {
		auto oldBreakKind = breakKind;
		auto oldBreakLabel = breakLabel;
		auto oldCases = cases;
		auto oldAllowFallthrough = allowFallthrough;
		auto oldSwitchStack = switchStack;
		
		Label oldDefault;
		if (auto dPtr = BuiltinName!"default" in labels) {
			oldDefault = *dPtr;
			labels.remove(BuiltinName!"default");
		}
		
		scope(exit) {
			currentBlockRef = breakLabel.block;
			
			breakKind = oldBreakKind;
			breakLabel = oldBreakLabel;
			cases = oldCases;
			allowFallthrough = oldAllowFallthrough;
			switchStack = oldSwitchStack;
			
			if (oldDefault.block) {
				labels[BuiltinName!"default"] = oldDefault;
			}
		}
		
		switchStack = varStack;
		breakKind = BreakKind.Switch;
		
		auto switchBlock = currentBlockRef;
		
		cases = [CaseEntry.init];
		
		breakLabel = Label(
			BasicBlockRef.init,
			cast(uint) unwindActions.length,
		);
		
		currentBlockRef = null;
		allowFallthrough = true;
		visit(s.statement);
		
		if (!terminate) {
			unwindAndBranch(s.location, getBreakLabel(s.location));
		}
		
		if (BuiltinName!"case" in inFlightGotos) {
			import d.exception;
			throw new CompileException(
				s.location,
				"Reached end of switch statement with unresolved goto case;",
			);
		}
		
		BasicBlockRef defaultBlock;
		if (auto defaultLabel = BuiltinName!"default" in labels) {
			defaultBlock = defaultLabel.block;
			labels.remove(BuiltinName!"default");
		} else {
			import d.exception;
			throw new CompileException(
				s.location,
				"switch statement without a default; use 'final switch' "
				~ "or add 'default: assert(0);' or add 'default: break;'",
			);
		}
		
		auto v = buildExpression(s.expression);
		
		auto switchTable = cast(SwitchTable*) cases.ptr;
		switchTable.entryCount = cast(uint) (cases.length - 1);
		switchTable.defaultBlock = defaultBlock;
		
		fbody[switchBlock].doSwitch(s.location, v, switchTable);
	}
	
	private void fixupGoto(Location location, Name name, Label label) {
		if (auto ifgsPtr = name in inFlightGotos) {
			auto ifgs = *ifgsPtr;
			inFlightGotos.remove(name);
			
			foreach(ifg; ifgs) {
				auto oldCurrentBlock = currentBlockRef;
				auto oldunwindActions = unwindActions;
				scope(exit) {
					currentBlockRef = oldCurrentBlock;
					unwindActions = oldunwindActions;
				}
				
				currentBlockRef = ifg.block;
				unwindActions = ifg.unwind;
				
				unwindAndBranch(location, label);
			}
			
			scope(success) inFlightGotosStacks.remove(name);
			foreach(igs; inFlightGotosStacks[name]) {
				// Check that all inflight goto to thta label are valid.
				import std.algorithm.searching;
				bool isValid = igs.startsWith(varStack);
				if (!isValid) {
					import d.exception;
					throw new CompileException(
						location,
						"Cannot jump over variable initialization.",
					);
				}
			}
		}
	}
	
	private void setCaseEntry(
		Location location,
		string switchError,
		string fallthroughError,
	) out {
		assert(varStack == switchStack);
	} body {
		scope(success) varStack = switchStack;
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
		
		if (cases.length == 0) {
			import d.exception;
			throw new CompileException(location, switchError);
		}
		
		if (terminate) {
			return;
		}
		
		// Check for case a: case b:
		// TODO: consider default: case a:
		if (cases[$ - 1].block != currentBlockRef || !currentBlock.empty) {
			import d.exception;
			throw new CompileException(location, fallthroughError);
		}
	}
	
	void visit(CaseStatement s) {
		setCaseEntry(
			s.location,
			"Case statement can only appear within switch statement.",
			"Fallthrough is disabled, use goto case.",
		);
		
		auto caseBlock = maybeBranchToNewBlock(s.location, BuiltinName!"case");
		fixupGoto(
			s.location,
			BuiltinName!"case",
			Label(caseBlock, cast(uint) unwindActions.length),
		);
		
		foreach (e; s.cases) {
			auto c = cast(uint) evalIntegral(buildExpression(e));
			cases ~= CaseEntry(caseBlock, c);
		}
	}
	
	void visit(LabeledStatement s) {
		auto name = s.label;
		if (name == BuiltinName!"default") {
			setCaseEntry(
				s.location,
				"Default statement can only appear within switch statement.",
				"Fallthrough is disabled, use goto default.",
			);
		}
		
		if (name in labels) {
			import d.exception;
			throw new CompileException(s.location, "Label is already defined");
		}
		
		auto labelBlock = maybeBranchToNewBlock(s.location, name);
		auto label = Label(labelBlock, cast(uint) unwindActions.length);
		labels[name] = label;
		labelStacks[name] = varStack;
		
		fixupGoto(s.location, name, label);
		visit(s.statement);
	}
	
	void visit(GotoStatement s) {
		auto name = s.label;
		if (auto bPtr = name in labelStacks) {
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
		}
		
		if (auto bPtr = name in inFlightGotosStacks) {
			auto varStacks = *bPtr;
			varStacks ~= varStack;
			*bPtr = varStacks;
		} else {
			inFlightGotosStacks[name] = [varStack];
		}
		
		if (auto bPtr = name in labels) {
			unwindAndBranch(s.location, *bPtr);
			return;
		}
		
		auto unresolvedGoto = UnresolvedGoto(unwindActions, currentBlockRef);
		if (auto bPtr = name in inFlightGotos) {
			*bPtr ~= unresolvedGoto;
		} else {
			inFlightGotos[name] = [unresolvedGoto];
		}
		
		currentBlockRef = null;
	}
	
	void visit(ScopeStatement s) {
		unwindActions ~= UnwindInfo(cast(UnwindKind) s.kind, s.statement);
		maybeBranchToNewBlock(s.location, BuiltinName!"scope.entry");
	}
	
	void visit(AssertStatement s) {
		Expression msg;
		if (s.message) {
			msg = buildString(s.message);
		}
		
		bool isHalt;
		if (auto b = cast(BooleanLiteral) s.condition) {
			isHalt = !b.value;
		} else if (auto i = cast(IntegerLiteral) s.condition) {
			isHalt = !i.value;
		} else if (auto n = cast(NullLiteral) s.condition) {
			isHalt = true;
		}
		
		if (isHalt) {
			currentBlock.halt(s.location, msg);
			return;
		}
		
		auto testBlock = currentBlockRef;
		auto failBlock = startNewBranch(BuiltinName!"assert.fail");
		currentBlock.halt(s.location, msg);
		
		auto successBlock = startNewBranch(BuiltinName!"assert.success");
		fbody[testBlock].branch(
			s.location,
			buildCondition(s.condition),
			successBlock,
			failBlock,
		);
	}
	
	void visit(ThrowStatement s) {
		currentBlock.doThrow(s.location, buildExpression(
			s.value,
			Type.get(pass.object.getThrowable()),
		));
	}
	
	void visit(TryStatement s) {
		auto unwindLevel = unwindActions.length;
		scope(success) unwindTo(unwindLevel);
		
		if (s.finallyBlock) {
			unwindActions ~= UnwindInfo(UnwindKind.Exit, s.finallyBlock);
		}
		
		// No cath blocks, just bypass the whole thing.
		if (s.catches.length == 0) {
			maybeBranchToNewBlock(s.location, BuiltinName!"try");
			autoBlock(s.statement);
			return;
		}
		
		auto preCatchLevel = unwindActions.length;
		unwindActions ~= UnwindInfo(UnwindKind.Failure, null);
		
		maybeBranchToNewBlock(s.location, BuiltinName!"try");
		autoBlock(s.statement);
		
		auto preUnwindBlock = currentBlockRef;
		assert(unwindActions[$ - 1].kind == UnwindKind.Failure);
		assert(unwindActions[$ - 1].statement is null);
		
		auto catchSwitchBlock = unwindActions[$ - 1].unwindBlock;
		assert(catchSwitchBlock, "No catch switch block");
		
		unwindActions = unwindActions[0 .. preCatchLevel];
		
		CatchPad[] catchpads;
		catchpads.reserve(s.catches.length + 1);
		catchpads ~= CatchPad();
		
		BasicBlockRef endCatchBlock;
		foreach(c; s.catches) {
			import d.semantic.identifier;
			auto type = IdentifierResolver(pass)
				.resolve(c.type)
				.apply!(function Class(identified) {
					alias T = typeof(identified);
					static if (is(T : Symbol)) {
						if (auto c = cast(Class) identified) {
							return c;
						}
					}
					
					static if (is(T : Type)) {
						assert(0);
					} else {
						import d.exception;
						throw new CompileException(
							identified.location,
							typeid(identified).toString() ~ " is not a class.",
						);
					}
				})();
			
			auto catchBlock = startNewBranch(BuiltinName!"catch");
			catchpads ~= CatchPad(type, catchBlock);
			
			auto mergeCatchBlock = autoBlock(c.statement);
			if (terminate) {
				continue;
			}
			
			if (!endCatchBlock) {
				endCatchBlock = startNewBranch(BuiltinName!"endcatch");
			}
			
			maybeBranchTo(c.location, mergeCatchBlock, endCatchBlock);
		}
		
		auto catchTable = cast(CatchTable*) catchpads.ptr;
		catchTable.catchCount = catchpads.length - 1;
		fbody[catchSwitchBlock].doCatch(s.location, catchTable);
		
		if (doesTerminate(preUnwindBlock)) {
			currentBlockRef = endCatchBlock;
			return;
		}
		
		if (!endCatchBlock) {
			endCatchBlock = startNewBranch(BuiltinName!"endcatch");
		}
		
		maybeBranchTo(s.location, preUnwindBlock, endCatchBlock);
		currentBlockRef = endCatchBlock;
	}
	
	void visit(StaticIf!Statement s) {
		auto items = evalIntegral(buildCondition(s.condition))
			? s.items
			: s.elseItems;
		
		foreach(item; items) {
			visit(item);
		}
		
		// Do not error on unrechable statement after static if.
		allowUnreachable = true;
	}
	
	void visit(StaticAssert!Statement s) {
		if (evalIntegral(buildCondition(s.condition))) {
			return;
		}
		
		import d.exception;
		if (s.message is null) {
			throw new CompileException(s.location, "assertion failure");
		}
		
		auto msg = evalString(buildString(s.message));
		throw new CompileException(s.location, "assertion failure: " ~ msg);
	}
	
	void visit(Mixin!Statement s) {
		import d.lexer;
		auto str = evalString(buildString(s.value)) ~ '\0';
		auto base = context.registerMixin(s.location, str);
		auto trange = lex(base, context);
		
		import d.parser.base;
		trange.match(TokenType.Begin);
		while(trange.front.type != TokenType.End) {
			import d.parser.statement;
			visit(trange.parseStatement());
		}
	}
	
	/**
	 * Unwinding facilities
	 */
	void closeBlockTo(size_t level) {
		auto oldunwindActions = unwindActions;
		scope(exit) unwindActions = oldunwindActions;
		
		while(unwindActions.length > level) {
			if (terminate) {
				break;
			}
			
			auto b = unwindActions[$ - 1];
			unwindActions = unwindActions[0 .. $ - 1];
			
			if (!isCleanup(b.kind)) {
				continue;
			}
			
			autoBlock(b.statement);
		}
	}
	
	void concludeUnwind(Location location) {
		if (terminate) {
			return;
		}
		
		foreach_reverse(b; unwindActions) {
			if (!isUnwind(b.kind)) {
				continue;
			}
			
			auto src = currentBlockRef;
			if (!b.unwindBlock) {
				b.unwindBlock = startNewBranch(BuiltinName!"unwind");
			}
			
			fbody[src].branch(location, b.unwindBlock);
			return;
		}
		
		if (!terminate) {
			currentBlock.doThrow(location);
		}
	}
	
	void unwindTo(size_t level) in {
		assert(unwindActions.length >= level);
	} body {
		if (unwindActions.length == level) {
			// Nothing to unwind, done !
			return;
		}
		
		closeBlockTo(level);
		
		bool mustResume = false;
		
		auto preUnwindBlock = currentBlockRef;
		scope(exit) currentBlockRef = preUnwindBlock;
		
		auto i = unwindActions.length;
		while (i --> level) {
			auto b = unwindActions[i];
			if (!isUnwind(b.kind)) {
				continue;
			}
			
			assert(
				b.statement !is null,
				"Catch blocks must be handled with try statements",
			);
			
			unwindActions = unwindActions[0 .. i];
			
			// We have a scope(exit) or scope(failure).
			// Check if we need to chain unwinding.
			auto unwindBlock = b.unwindBlock;
			if (!unwindBlock) {
				if (!mustResume) {
					continue;
				}
				
				unwindBlock = startNewBranch(BuiltinName!"unwind");
			}
			
			// We encountered a scope statement that
			// can be reached while unwinding.
			mustResume = true;
			
			// Emit the exception cleanup code.
			currentBlockRef = unwindBlock;
			autoBlock(b.statement);
		}
		
		assert(unwindActions.length == level);
		if (mustResume) {
			concludeUnwind(Location.init);
		}
		
		if (!terminate) {
			maybeBranchToNewBlock(Location.init, BuiltinName!"resume");
		}
	}
}

private:

enum BreakKind {
	None,
	Loop,
	Switch,
}

struct UnwindInfo {
	import std.bitmanip;
	mixin(taggedClassRef!(
		Statement, "statement",
		UnwindKind, "kind", 2,
	));
	
	BasicBlockRef unwindBlock;
	BasicBlockRef cleanupBlock;
	
	this(UnwindKind kind, Statement statement) {
		this.kind = kind;
		this.statement = statement;
	}
}

enum UnwindKind {
	Success,
	Exit,
	Failure,
}

bool isCleanup(UnwindKind k) {
	return k <= UnwindKind.Exit;
}

bool isUnwind(UnwindKind k) {
	return k >= UnwindKind.Exit;
}

unittest {
	assert(isCleanup(UnwindKind.Success));
	assert(isCleanup(UnwindKind.Exit));
	assert(!isCleanup(UnwindKind.Failure));
	
	assert(!isUnwind(UnwindKind.Success));
	assert(isUnwind(UnwindKind.Exit));
	assert(isUnwind(UnwindKind.Failure));
	
	static assert(UnwindKind.Exit == ScopeKind.Exit);
	static assert(UnwindKind.Success == ScopeKind.Success);
	static assert(UnwindKind.Failure == ScopeKind.Failure);
}
