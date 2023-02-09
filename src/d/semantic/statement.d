module d.semantic.statement;

import d.semantic.semantic;

import d.ast.conditional;
import d.ast.expression;
import d.ast.statement;

import source.location;
import source.name;

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

	@property
	bool terminate() const {
		return doesTerminate(currentBlockRef);
	}

	bool allowUnreachable;
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

		scope(failure) {
			f.fbody = fbody;
			f.dump(context);
		}

		currentScope = f;
		auto entry = startNewBranch(BuiltinName!"entry");

		flatten(b);
		f.fbody = fbody;

		auto rt = returnType.getType();
		// TODO: Handle auto return by specifying it to this visitor
		// instead of deducing it in dubious ways.
		if (rt.kind == TypeKind.Builtin && rt.qualifier == TypeQualifier.Mutable
			    && rt.builtin == BuiltinType.None) {
			returnType =
				Type.get(BuiltinType.Void).getParamType(ParamKind.Regular);
		}

		if (!terminate) {
			if (returnType.kind == TypeKind.Builtin
				    && returnType.builtin == BuiltinType.Void) {
				currentBlock.ret(b.location);
			} else {
				import source.exception;
				throw new CompileException(f.location, "Must return");
			}
		}
	}

	void visit(Statement s) {
		if (s is null) {
			return;
		}

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

		if (!allowUnreachable) {
			import source.exception;
			throw new CompileException(s.location, "Unreachable statement");
		}

		startNewBranch(BuiltinName!"unreachable");

	Dispatch:
		allowUnreachable = false;
		this.dispatch(s);
	}

private:
	BasicBlockRef flatten(BlockStatement b) {
		return buildBlock(b.location, b.statements);
	}

	BasicBlockRef getUnwindBlock() {
		foreach_reverse (ref b; unwindActions) {
			if (!b.isUnwind()) {
				continue;
			}

			if (!b.unwindBlock) {
				b.unwindBlock = fbody.newBasicBlock(BuiltinName!"unwind");
			}

			return b.unwindBlock;
		}

		return BasicBlockRef();
	}

	BasicBlockRef makeNewBranch(Name name) {
		return fbody.newBasicBlock(name, getUnwindBlock());
	}

	BasicBlockRef startNewBranch(Name name) {
		return currentBlockRef = makeNewBranch(name);
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

	BasicBlockRef maybeBranchTo(Location location, BasicBlockRef src,
	                            BasicBlockRef dst) {
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
		process(args);
		unwindTo(unwindLevel);

		return currentBlockRef;
	}

	void process(Statement[] statements) {
		foreach (s; statements) {
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

	void alloca(Variable v) {
		currentBlock.alloca(v.location, v);
		varStack ~= v;

		auto t = v.type.getCanonical();
		if (t.kind != TypeKind.Struct || t.dstruct.isPod) {
			return;
		}

		unwindActions ~= UnwindInfo(v);
		maybeBranchToNewBlock(v.location, BuiltinName!"");
	}

	Expression check(Expression e) {
		auto t = e.type;
		if (t.kind == TypeKind.Error) {
			import source.exception;
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
		return check(buildExplicitCast(pass, expr.location, type,
		                               ExpressionVisitor(pass).visit(expr)));
	}

	auto buildCondition(AstExpression expr) {
		return buildExpression(expr, Type.get(BuiltinType.Bool));
	}

	auto buildString(AstExpression expr) {
		return buildExpression(
			expr, Type.get(BuiltinType.Char).getSlice(TypeQualifier.Immutable));
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

		foreach (sym; syms) {
			if (auto v = cast(Variable) sym) {
				alloca(v);
			} else if (cast(Aggregate) sym) {
				// FIXME: We should get rid of this.
				currentBlock.declare(sym.location, sym);
			}
		}
	}

	void visit(IdentifierStarNameStatement s) {
		import d.semantic.identifier;
		IdentifierResolver(
			pass
		).build(s.identifier).apply!(delegate void(identified) {
			alias T = typeof(identified);
			static if (is(T : Expression)) {
				assert(
					0, "expression identifier * identifier are not implemented."
				);
			} else static if (is(T : Type)) {
				auto t = identified.getPointer();

				import d.semantic.expression;
				import d.semantic.defaultinitializer : InitBuilder;
				auto value = s.value
					? ExpressionVisitor(pass).visit(s.value)
					: InitBuilder(pass, s.location).visit(t);

				import d.semantic.caster;
				auto v = new Variable(
					s.location, t.getParamType(ParamKind.Regular), s.name,
					buildImplicitCast(pass, s.location, t, value));

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
				mergeBlock = maybeBranchToNewBlock(s.elseStatement.location,
				                                   BuiltinName!"endif");
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

		fbody[ifBlock]
			.branch(s.location, buildCondition(s.condition), ifTrue, ifFalse);
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

		auto testBlock =
			maybeBranchToNewBlock(location, BuiltinName!"loop.test");
		auto bodyBlock = startNewBranch(BuiltinName!"loop.body");

		continueLabel = Label(incBlock, cast(uint) unwindActions.length);
		breakLabel = Label(BasicBlockRef.init, cast(uint) unwindActions.length);

		if (element !is null) {
			currentBlock.alloca(element.location, element);
		}

		autoBlock(statement);
		maybeBranchTo(location, incBlock);

		fbody[entryBlock]
			.branch(location, skipFirstCond ? bodyBlock : testBlock);
		if (condition) {
			auto breakLabel = getBreakLabel(location);
			fbody[testBlock]
				.branch(location, condition, bodyBlock, breakLabel.block);
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

		import source.name, d.semantic.identifier;
		auto length = IdentifierResolver(pass)
			.buildIn(iterated.location, iterated, BuiltinName!"length")
			.apply!(delegate Expression(e) {
				static if (is(typeof(e) : Expression)) {
					return e;
				} else {
					import d.ir.error;
					return new CompileError(
						iterated.location,
						typeid(e).toString() ~ " is not a valid length"
					).expression;
				}
			})();

		Variable idx;

		auto loc = f.location;
		switch (f.tupleElements.length) {
			case 1:
				import d.semantic.defaultinitializer;
				idx = new Variable(loc, length.type, BuiltinName!"",
				                   InitBuilder(pass, loc).visit(length.type));

				idx.step = Step.Processed;
				break;

			case 2:
				auto idxDecl = f.tupleElements[0];
				if (idxDecl.type.paramKind != ParamKind.Regular) {
					assert(0, "index can't be ref");
				}

				import d.semantic.type;
				auto t = idxDecl.type.getType().isAuto
					? length.type
					: TypeVisitor(pass).visit(idxDecl.type.getType());

				auto idxLoc = idxDecl.location;

				import d.semantic.defaultinitializer;
				idx = new Variable(idxLoc, t, idxDecl.name,
				                   InitBuilder(pass, idxLoc).visit(t));

				idx.step = Step.Processed;
				currentScope.addSymbol(idx);

				break;

			default:
				assert(0, "Wrong number of elements");
		}

		assert(idx);
		currentBlock.alloca(idx.location, idx);

		auto idxExpr = new VariableExpression(idx.location, idx);
		auto increment =
			build!UnaryExpression(loc, idx.type, UnaryOp.PreInc, idxExpr);

		import d.semantic.caster;
		length = buildImplicitCast(pass, idx.location, idx.type, length);
		auto condition =
			build!ICmpExpression(loc, ICmpOp.SmallerThan, idxExpr, length);

		auto iType = iterated.type.getCanonical();
		assert(iType.hasElement, "Only array and slice are supported for now.");

		Type et = iType.element;

		auto eDecl = f.tupleElements[$ - 1];
		auto eLoc = eDecl.location;

		import d.semantic.expression;
		auto eVal = ExpressionVisitor(pass).getIndex(eLoc, iterated, idxExpr);
		auto eType = eVal.type.getParamType(eDecl.type.paramKind);

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
		auto stop = ExpressionVisitor(pass).visit(f.stop);

		assert(f.tupleElements.length == 1, "Wrong number of elements");
		auto iDecl = f.tupleElements[0];

		auto loc = f.location;

		import d.semantic.type, d.semantic.typepromotion;
		auto type = iDecl.type.getType().isAuto
			? getPromotedType(pass, loc, start.type, stop.type)
			: TypeVisitor(pass).visit(iDecl.type).getType();

		import d.semantic.caster;
		start = buildImplicitCast(pass, start.location, type, start);
		stop = buildImplicitCast(pass, stop.location, type, stop);

		if (f.reverse) {
			auto tmp = start;
			start = stop;
			stop = tmp;
		}

		auto idx = new Variable(
			iDecl.location, type.getParamType(iDecl.type.paramKind), iDecl.name,
			start);

		idx.step = Step.Processed;
		currentScope.addSymbol(idx);
		currentBlock.alloca(idx.location, idx);

		Expression idxExpr = new VariableExpression(idx.location, idx);
		Expression increment, condition;

		if (f.reverse) {
			// for(...; idx-- > stop; idx)
			condition = build!ICmpExpression(
				loc,
				ICmpOp.GreaterThan,
				build!UnaryExpression(loc, type, UnaryOp.PostDec, idxExpr),
				stop
			);
		} else {
			// for(...; idx < stop; idx++)
			condition =
				build!ICmpExpression(loc, ICmpOp.SmallerThan, idxExpr, stop);
			increment =
				build!UnaryExpression(loc, type, UnaryOp.PreInc, idxExpr);
		}

		genLoop(loc, condition, f.statement, increment);
	}

	void visit(ReturnStatement s) {
		// TODO: precompute autotype instead of managing it here.
		auto rt = returnType.getType();
		auto isAutoReturn = rt.kind == TypeKind.Builtin
			&& rt.qualifier == TypeQualifier.Mutable
			&& rt.builtin == BuiltinType.None;

		// return; has no value.
		if (s.value is null) {
			if (isAutoReturn) {
				returnType =
					Type.get(BuiltinType.Void).getParamType(ParamKind.Regular);
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
			returnType = value.type.getParamType(ParamKind.Regular);
		} else {
			import d.semantic.caster;
			value = buildImplicitCast(pass, s.location, returnType.getType(),
			                          value);
			if (returnType.isRef) {
				if (!value.isLvalue) {
					import source.exception;
					throw new CompileException(s.location,
					                           "Cannot ref return lvalues");
				}

				value =
					build!UnaryExpression(s.location, value.type.getPointer(),
					                      UnaryOp.AddressOf, value);
			}
		}

		// If unwind work is needed, store the result in a temporary.
		if (unwindActions.length) {
			auto location = value.location;
			if (retval is null) {
				auto v =
					new Variable(location, value.type, BuiltinName!"return",
					             new VoidInitializer(location, value.type));

				v.step = Step.Processed;
				retval = new VariableExpression(location, v);
			}

			currentBlock.eval(
				location,
				check(build!BinaryExpression(location, retval.type,
				                             BinaryOp.Assign, retval, value))
			);

			value = retval;
		}

		closeBlockTo(0);
		if (!terminate) {
			currentBlock.ret(s.location, check(value));
		}
	}

	private BasicBlockRef unwindAndBranch(Location location, Label l)
			in(l, "Invalid label") {
		closeBlockTo(l.level);
		return maybeBranchTo(location, l.block);
	}

	Label getBreakLabel(Location location) {
		if (breakLabel) {
			return breakLabel;
		}

		Name name;
		final switch (breakKind) with (BreakKind) {
			case None:
				import source.exception;
				throw new CompileException(
					location, "Cannot break outside of switches and loops");

			case Loop:
				name = BuiltinName!"loop.exit";
				break;

			case Switch:
				name = BuiltinName!"endswitch";
				break;
		}

		breakLabel.block = makeNewBranch(name);
		return breakLabel;
	}

	void visit(BreakStatement s) {
		unwindAndBranch(s.location, getBreakLabel(s.location));
	}

	void visit(ContinueStatement s) {
		if (!continueLabel) {
			import source.exception;
			throw new CompileException(s.location,
			                           "Cannot continue outside of loops");
		}

		unwindAndBranch(s.location, continueLabel);
	}

	void visit(SwitchStatement s) {
		auto oldBreakKind = breakKind;
		auto oldBreakLabel = breakLabel;
		auto oldCases = cases;
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
			switchStack = oldSwitchStack;

			if (oldDefault.block) {
				labels[BuiltinName!"default"] = oldDefault;
			}
		}

		switchStack = varStack;
		breakKind = BreakKind.Switch;

		auto switchBlock = currentBlockRef;

		cases = [CaseEntry.init];

		breakLabel = Label(BasicBlockRef.init, cast(uint) unwindActions.length);

		currentBlockRef = null;
		visit(s.statement);

		if (!terminate) {
			unwindAndBranch(s.location, getBreakLabel(s.location));
		}

		if (BuiltinName!"case" in inFlightGotos) {
			import source.exception;
			throw new CompileException(
				s.location,
				"Reached end of switch statement with unresolved goto case;"
			);
		}

		auto defaultLabel = BuiltinName!"default" in labels;
		if (!defaultLabel) {
			import source.exception;
			throw new CompileException(
				s.location,
				"switch statement without a default; use 'final switch' "
					~ "or add 'default: assert(0);' or add 'default: break;'"
			);
		}

		BasicBlockRef defaultBlock = defaultLabel.block;
		labels.remove(BuiltinName!"default");

		auto v = buildExpression(s.expression);

		auto switchTable = cast(SwitchTable*) cases.ptr;
		switchTable.entryCount = cast(uint) (cases.length - 1);
		switchTable.defaultBlock = defaultBlock;

		fbody[switchBlock].doSwitch(s.location, v, switchTable);
	}

	private void fixupGoto(Location location, Name name, Label label) {
		auto ifgsPtr = name in inFlightGotos;
		if (!ifgsPtr) {
			return;
		}

		auto ifgs = *ifgsPtr;
		inFlightGotos.remove(name);

		foreach (ifg; ifgs) {
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
		foreach (igs; inFlightGotosStacks[name]) {
			// Check that all inflight goto to thta label are valid.
			import std.algorithm.searching;
			bool isValid = igs.startsWith(varStack);
			if (!isValid) {
				import source.exception;
				throw new CompileException(
					location, "Cannot jump over variable initialization.");
			}
		}
	}

	private void setCaseEntry(Location location, string switchError,
	                          string fallthroughError) {
		scope(success) {
			varStack = switchStack;
		}

		if (cases.length == 0) {
			import source.exception;
			throw new CompileException(location, switchError);
		}

		if (terminate) {
			return;
		}

		// Check for case a: case b:
		// TODO: consider default: case a:
		if (cases[$ - 1].block != currentBlockRef || !currentBlock.empty) {
			import source.exception;
			throw new CompileException(location, fallthroughError);
		}
	}

	void visit(CaseStatement s) {
		setCaseEntry(
			s.location,
			"Case statement can only appear within switch statement.",
			"Fallthrough is disabled, use goto case."
		);

		auto caseBlock = maybeBranchToNewBlock(s.location, BuiltinName!"case");
		fixupGoto(s.location, BuiltinName!"case",
		          Label(caseBlock, cast(uint) unwindActions.length));

		foreach (e; s.cases) {
			auto c = cast(uint) evalIntegral(buildExpression(e));
			cases ~= CaseEntry(caseBlock, c);
		}

		visit(s.statement);
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
			import source.exception;
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
				import source.exception;
				throw new CompileException(
					s.location, "Cannot goto over variable initialization.");
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
		unwindActions ~= UnwindInfo(s.kind, s.statement);
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
		fbody[testBlock].branch(s.location, buildCondition(s.condition),
		                        successBlock, failBlock);
	}

	void visit(ThrowStatement s) {
		currentBlock.doThrow(
			s.location,
			buildExpression(s.value, Type.get(pass.object.getThrowable()))
		);
	}

	void visit(TryStatement s) {
		auto unwindLevel = unwindActions.length;
		scope(success) unwindTo(unwindLevel);

		if (s.finallyBlock) {
			unwindActions ~= UnwindInfo(ScopeKind.Exit, s.finallyBlock);
		}

		// No cath blocks, just bypass the whole thing.
		if (s.catches.length == 0) {
			maybeBranchToNewBlock(s.location, BuiltinName!"try");
			autoBlock(s.statement);
			return;
		}

		auto preCatchLevel = unwindActions.length;
		unwindActions ~= UnwindInfo(ScopeKind.Failure, null);

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
		foreach (c; s.catches) {
			import d.semantic.identifier;
			auto type = IdentifierResolver(pass)
				.resolve(c.type).apply!(function Class(identified) {
					alias T = typeof(identified);
					static if (is(T : Symbol)) {
						if (auto c = cast(Class) identified) {
							return c;
						}
					}

					static if (is(T : Type)) {
						assert(0);
					} else {
						import source.exception;
						throw new CompileException(
							identified.location,
							typeid(identified).toString() ~ " is not a class."
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
		auto items =
			evalIntegral(buildCondition(s.condition)) ? s.items : s.elseItems;

		foreach (item; items) {
			visit(item);
		}

		// Do not error on unrechable statement after static if.
		allowUnreachable = true;
	}

	void visit(StaticAssert!Statement s) {
		if (evalIntegral(buildCondition(s.condition))) {
			return;
		}

		import source.exception;
		if (s.message is null) {
			throw new CompileException(s.location, "assertion failure");
		}

		auto msg = evalString(buildString(s.message));
		throw new CompileException(s.location, "assertion failure: " ~ msg);
	}

	void visit(Version!Statement d) {
		foreach (v; versions) {
			if (d.versionId == v) {
				foreach (item; d.items) {
					visit(item);
				}

				return;
			}
		}

		// Version has not been found.
		foreach (item; d.elseItems) {
			visit(item);
		}
	}

	void visit(Mixin!Statement s) {
		auto str = evalString(buildString(s.value)) ~ '\0';
		auto base = context.registerMixin(s.location, str);

		import source.dlexer;
		auto trange = lex(base, context);

		import d.parser.base;
		trange.match(TokenType.Begin);
		while (trange.front.type != TokenType.End) {
			import d.parser.statement;
			visit(trange.parseStatement());
		}
	}

	void destroy(Variable v) {
		maybeBranchToNewBlock(v.location, BuiltinName!"destroy");
		currentBlock.destroy(v.location, v);
	}

	/**
	 * Unwinding facilities
	 */
	void closeBlockTo(size_t level) {
		auto oldunwindActions = unwindActions;
		scope(exit) unwindActions = oldunwindActions;

		while (unwindActions.length > level) {
			if (terminate) {
				break;
			}

			auto b = unwindActions[$ - 1];
			unwindActions = unwindActions[0 .. $ - 1];

			final switch (b.kind) with (UnwindKind) {
				case Success, Exit:
					maybeBranchToNewBlock(Location.init, BuiltinName!"cleanup");
					autoBlock(b.statement);
					break;

				case Failure:
					continue;

				case Destroy:
					destroy(b.var);
					break;
			}
		}
	}

	void concludeUnwind(Location location) {
		if (terminate) {
			return;
		}

		foreach_reverse (ref b; unwindActions) {
			if (!b.isUnwind()) {
				continue;
			}

			if (!b.unwindBlock) {
				b.unwindBlock = makeNewBranch(BuiltinName!"unwind");
			}

			currentBlock.branch(location, b.unwindBlock);
			return;
		}

		if (!terminate) {
			currentBlock.doThrow(location);
		}
	}

	void unwindTo(size_t level) in(unwindActions.length >= level) {
		if (unwindActions.length == level) {
			// Nothing to unwind, done !
			return;
		}

		closeBlockTo(level);

		auto preUnwindBlock = currentBlockRef;
		scope(exit) currentBlockRef = preUnwindBlock;

		auto i = unwindActions.length;
		while (i-- > level) {
			auto bPtr = &unwindActions[i];
			auto b = *bPtr;
			if (!b.isUnwind()) {
				continue;
			}

			unwindActions = unwindActions[0 .. i];

			// We encountered a scope statement that
			// can be reached while unwinding.
			scope(success) concludeUnwind(Location.init);

			// Emit the exception cleanup code.
			currentBlockRef = b.unwindBlock;
			final switch (b.kind) with (UnwindKind) {
				case Success:
					assert(0);

				case Exit:
					autoBlock(b.statement);
					break;

				case Failure:
					assert(b.statement !is null,
					       "Catch blocks must be handled with try statements");

					goto case Exit;

				case Destroy:
					destroy(b.var);
					break;
			}
		}

		if (unwindActions.length != level) {
			foreach (b; unwindActions[level .. $]) {
				assert(!b.isUnwind());
			}

			unwindActions = unwindActions[0 .. level];
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
private:
	import std.bitmanip;
	mixin(taggedClassRef!(
		// sdfmt off
		Statement, "_statement",
		UnwindKind, "_kind", 2,
		// sdfmt on
	));

public:
	@property
	auto kind() const {
		return _kind;
	}

	@property
	auto statement() inout in(kind != UnwindKind.Destroy) {
		return _statement;
	}

	@property
	auto var() inout in(kind == UnwindKind.Destroy) {
		auto s = _statement;
		return *(cast(Variable*) &s);
	}

	BasicBlockRef unwindBlock;
	BasicBlockRef cleanupBlock;

	this(ScopeKind kind, Statement statement) {
		_kind = cast(UnwindKind) kind;
		_statement = statement;
	}

	this(Variable v) in(!v.type.dstruct.isPod) {
		_kind = UnwindKind.Destroy;
		_statement = *(cast(Statement*) &v);
	}

	bool isCleanup() const {
		return .isCleanup(kind);
	}

	bool isUnwind() const {
		return .isUnwind(kind);
	}
}

enum UnwindKind {
	Success,
	Exit,
	Failure,
	Destroy,
}

bool isCleanup(UnwindKind k) {
	return k != UnwindKind.Failure;
}

bool isUnwind(UnwindKind k) {
	return k != UnwindKind.Success;
}

unittest {
	assert(isCleanup(UnwindKind.Success));
	assert(isCleanup(UnwindKind.Exit));
	assert(!isCleanup(UnwindKind.Failure));
	assert(isCleanup(UnwindKind.Destroy));

	assert(!isUnwind(UnwindKind.Success));
	assert(isUnwind(UnwindKind.Exit));
	assert(isUnwind(UnwindKind.Failure));
	assert(isUnwind(UnwindKind.Destroy));

	import std.conv;
	static assert(
		UnwindKind.Exit.asOriginalType() == ScopeKind.Exit.asOriginalType());
	static assert(UnwindKind.Success.asOriginalType()
		== ScopeKind.Success.asOriginalType());
	static assert(UnwindKind.Failure.asOriginalType()
		== ScopeKind.Failure.asOriginalType());
}
