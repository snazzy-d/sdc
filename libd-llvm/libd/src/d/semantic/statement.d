module d.semantic.statement;

import d.semantic.caster;
import d.semantic.semantic;

import d.ast.conditional;
import d.ast.declaration;
import d.ast.expression;
import d.ast.statement;
import d.ast.type;

import d.ir.dscope;
import d.ir.expression;
import d.ir.statement;
import d.ir.symbol;
import d.ir.type;

import d.parser.base;
import d.parser.statement;

import std.algorithm;
import std.array;

alias BlockStatement = d.ir.statement.BlockStatement;
alias ExpressionStatement = d.ir.statement.ExpressionStatement;
alias IfStatement = d.ir.statement.IfStatement;
alias WhileStatement = d.ir.statement.WhileStatement;
alias DoWhileStatement = d.ir.statement.DoWhileStatement;
alias ForStatement = d.ir.statement.ForStatement;
alias ReturnStatement = d.ir.statement.ReturnStatement;
alias SwitchStatement = d.ir.statement.SwitchStatement;
alias CaseStatement = d.ir.statement.CaseStatement;
alias LabeledStatement = d.ir.statement.LabeledStatement;
alias ScopeStatement = d.ir.statement.ScopeStatement;
alias ThrowStatement = d.ir.statement.ThrowStatement;
alias CatchBlock = d.ir.statement.CatchBlock;

struct StatementVisitor {
private:
	SemanticPass pass;
	alias pass this;
	
	Statement[] flattenedStmts;
	
	uint[] declBlockStack = [0];
	uint nextDeclBlock = 1;
	uint switchBlock = -1;
	
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
	
	uint[Name] labelBlocks;
	uint[][][Name] inFlightGotosStacks;
	
public:
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	BlockStatement getBody(AstBlockStatement b) {
		auto fbody = flatten(b);
		
		auto rt = returnType.getType();
		// TODO: Handle auto return by specifying it to this visitor instead of deducing it in dubious ways.
		if (rt.kind == TypeKind.Builtin && rt.qualifier == TypeQualifier.Mutable && rt.builtin == BuiltinType.None) {
			returnType = Type.get(BuiltinType.Void).getParamType(false, false);
		} else if (rt.kind != TypeKind.Builtin || rt.builtin != BuiltinType.Void) {
			// FIXME: check that function actually returns.
		}
		
		return fbody;
	}
	
	void visit(AstStatement s) {
		if (!mustTerminate) {
			return this.dispatch(s);
		}
		
		if (auto c = cast(AstCaseStatement) s) {
			return visit(c);
		} else if (auto l = cast(AstLabeledStatement) s) {
			return visit(l);
		}
		
		import d.exception;
		throw new CompileException(
			s.location,
			"Unreachable statement. " ~ typeid(s).toString(),
		);
	}
	
	private BlockStatement flatten(AstBlockStatement b) {
		auto oldScope = currentScope;
		auto oldDeclBlockStack = declBlockStack;
		auto oldFlattenedStmts = flattenedStmts;
		
		scope(exit) {
			currentScope = oldScope;
			declBlockStack = oldDeclBlockStack;
			flattenedStmts = oldFlattenedStmts;
		}
		
		flattenedStmts = [];
		currentScope = (cast(NestedScope) oldScope).clone();
		
		foreach(ref s; b.statements) {
			visit(s);
		}
		
		return new BlockStatement(b.location, flattenedStmts);
	}
	
	void visit(AstBlockStatement b) {
		flattenedStmts ~= flatten(b);
	}
	
	void visit(DeclarationStatement s) {
		import d.semantic.declaration;
		auto syms = DeclarationVisitor(pass, AddContext.Yes, Visibility.Private).flatten(s.declaration);
		scheduler.require(syms);
		
		foreach(sym; syms) {
			if (auto v = cast(Variable) sym) {
				if (v.storage.isNonLocal) {
					continue;
				}
				
				declBlockStack ~= nextDeclBlock++;
				
				// Only one variable is enough to create a new block.
				break;
			}
		}
		
		flattenedStmts ~= syms.map!(d => new SymbolStatement(d)).array();
	}
	
	void visit(AstExpressionStatement s) {
		import d.semantic.expression;
		flattenedStmts ~= new ExpressionStatement(ExpressionVisitor(pass).visit(s.expression));
	}
	
	private auto autoBlock(AstStatement s) {
		auto b = cast(AstBlockStatement) s;
		if (b is null) {
			b = new AstBlockStatement(s.location, [s]);
		}
		
		return flatten(b);
	}
	
	void visit(AstIfStatement s) {
		auto oldMustTerminate = mustTerminate;
		auto oldFunTerminate = funTerminate;
		auto oldBlockTerminate = blockTerminate;
		
		import d.semantic.expression;
		auto condition = buildExplicitCast(pass, s.condition.location, Type.get(BuiltinType.Bool), ExpressionVisitor(pass).visit(s.condition));
		auto then = autoBlock(s.then);
		
		auto thenMustTerminate = mustTerminate;
		auto thenFunTerminate = funTerminate;
		auto thenBlockTerminate = blockTerminate;
		
		mustTerminate = oldMustTerminate;
		funTerminate = oldFunTerminate;
		blockTerminate = oldBlockTerminate;
		
		Statement elseStatement;
		if (s.elseStatement) {
			elseStatement = autoBlock(s.elseStatement);
			
			mustTerminate = thenMustTerminate && mustTerminate;
			funTerminate = thenFunTerminate && funTerminate;
			blockTerminate = thenBlockTerminate && blockTerminate;
		}
		
		flattenedStmts ~= new IfStatement(s.location, condition, then, elseStatement);
	}
	
	void visit(AstWhileStatement w) {
		auto oldMustTerminate = mustTerminate;
		auto oldFunTerminate = funTerminate;
		auto oldBlockTerminate = blockTerminate;
		scope(exit) {
			mustTerminate = oldMustTerminate;
			funTerminate = oldFunTerminate;
			blockTerminate = oldBlockTerminate;
		}
		
		import d.semantic.expression;
		flattenedStmts ~= new WhileStatement(
			w.location,
			buildExplicitCast(pass, w.condition.location, Type.get(BuiltinType.Bool), ExpressionVisitor(pass).visit(w.condition)),
			autoBlock(w.statement),
		);
	}
	
	void visit(AstDoWhileStatement w) {
		auto oldMustTerminate = mustTerminate;
		auto oldFunTerminate = funTerminate;
		auto oldBlockTerminate = blockTerminate;
		scope(exit) {
			mustTerminate = oldMustTerminate;
			funTerminate = oldFunTerminate;
			blockTerminate = oldBlockTerminate;
		}
		
		import d.semantic.expression;
		flattenedStmts ~= new DoWhileStatement(
			w.location,
			buildExplicitCast(pass, w.condition.location, Type.get(BuiltinType.Bool), ExpressionVisitor(pass).visit(w.condition)),
			autoBlock(w.statement),
		);
	}
	
	void visit(AstForStatement f) {
		auto oldScope = currentScope;
		
		auto oldMustTerminate = mustTerminate;
		auto oldFunTerminate = funTerminate;
		auto oldBlockTerminate = blockTerminate;
		scope(exit) {
			currentScope = oldScope;
			
			mustTerminate = oldMustTerminate;
			funTerminate = oldFunTerminate;
			blockTerminate = oldBlockTerminate;
		}
		
		currentScope = (cast(NestedScope) oldScope).clone();
		
		// FIXME: if initialize is flattened into several statement, scope is wrong.
		visit(f.initialize);
		auto initialize = flattenedStmts[$ - 1];
		
		import d.semantic.expression;
		Expression condition = f.condition
			? buildExplicitCast(pass, f.condition.location, Type.get(BuiltinType.Bool), ExpressionVisitor(pass).visit(f.condition))
			: new BooleanLiteral(f.location, true);
		
		Expression increment = f.increment
			? ExpressionVisitor(pass).visit(f.increment)
			: new BooleanLiteral(f.location, true);
		
		flattenedStmts[$ - 1] = new ForStatement(f.location, initialize, condition, increment, autoBlock(f.statement));
	}
	
	void visit(ForeachStatement f) {
		auto oldScope = currentScope;
		
		auto oldMustTerminate = mustTerminate;
		auto oldFunTerminate = funTerminate;
		auto oldBlockTerminate = blockTerminate;
		scope(exit) {
			currentScope = oldScope;
			
			mustTerminate = oldMustTerminate;
			funTerminate = oldFunTerminate;
			blockTerminate = oldBlockTerminate;
		}
		
		currentScope = (cast(NestedScope) oldScope).clone();
		
		assert(!f.reverse, "foreach_reverse not supported at this point.");
		
		import d.semantic.expression;
		auto iterated = ExpressionVisitor(pass).visit(f.iterated);
		
		import d.semantic.identifier;
		auto length = SymbolResolver!(delegate Expression (e) {
			static if(is(typeof(e) : Expression)) {
				return e;
			} else {
				return pass.raiseCondition!Expression(iterated.location, typeid(e).toString() ~ " is not a valid length.");
			}
		})(pass).resolveInExpression(iterated.location, iterated, BuiltinName!"length");
		
		Variable idx;
		
		auto loc = f.location;
		switch(f.tupleElements.length) {
			case 1 :
				import d.semantic.defaultinitializer;
				idx = new Variable(loc, length.type, BuiltinName!"", InitBuilder(pass, loc).visit(length.type));
				
				idx.step = Step.Processed;
				break;
			
			case 2 :
				auto idxDecl = f.tupleElements[0];
				assert(!idxDecl.type.isRef, "index can't be ref");
				
				import d.semantic.type;
				auto t = idxDecl.type.getType().isAuto
					? length.type
					: TypeVisitor(pass).visit(idxDecl.type.getType());
				
				auto idxLoc = idxDecl.location;
				
				import d.semantic.defaultinitializer;
				idx = new Variable(idxLoc, t, idxDecl.name, InitBuilder(pass, idxLoc).visit(t));
				
				idx.step = Step.Processed;
				currentScope.addSymbol(idx);
				
				break;
			
			default :
				assert(0, "Wrong number of elements");
		}
		
		assert(idx);
		
		auto initialize = new SymbolStatement(idx);
		auto idxExpr = new VariableExpression(idx.location, idx);
		auto condition = new BinaryExpression(loc, Type.get(BuiltinType.Bool), BinaryOp.Less, idxExpr, length);
		auto increment = new UnaryExpression(loc, idxExpr.type, UnaryOp.PreInc, idxExpr);
		
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
			eVal = buildImplicitCast(pass, eLoc, eType.getType(), eVal);
		}
		
		auto element = new Variable(eLoc, eType, eDecl.name, eVal);
		element.step = Step.Processed;
		currentScope.addSymbol(element);
		
		auto assign = new BinaryExpression(loc, eType.getType(), BinaryOp.Assign, new VariableExpression(eLoc, element), eVal);
		auto stmt = new BlockStatement(f.statement.location, [new ExpressionStatement(assign), autoBlock(f.statement)]);
		
		flattenedStmts ~= new ForStatement(loc, initialize, condition, increment, stmt);
	}
	
	void visit(ForeachRangeStatement f) {
		auto oldScope = currentScope;
		
		auto oldMustTerminate = mustTerminate;
		auto oldFunTerminate = funTerminate;
		auto oldBlockTerminate = blockTerminate;
		scope(exit) {
			currentScope = oldScope;
			
			mustTerminate = oldMustTerminate;
			funTerminate = oldFunTerminate;
			blockTerminate = oldBlockTerminate;
		}
		
		currentScope = (cast(NestedScope) oldScope).clone();
		
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
		
		start = buildImplicitCast(pass, start.location, type, start);
		stop  = buildImplicitCast(pass, stop.location, type, stop);

		BinaryOp cmp_op;
		UnaryOp inc_op;

		if (f.reverse) {
			swap(start, stop);
			cmp_op = BinaryOp.GreaterEqual;
			inc_op = UnaryOp.PreDec;
		} else {
			cmp_op = BinaryOp.Less;
			inc_op = UnaryOp.PreInc;
		}
		
		auto idx = new Variable(iDecl.location, type.getParamType(iDecl.type.isRef, false), iDecl.name, start);

		idx.step = Step.Processed;
		currentScope.addSymbol(idx);

		auto idxExpr = new VariableExpression(idx.location, idx);		
		auto initialize = f.reverse 
			? new ExpressionStatement(new UnaryExpression(loc, idx.type, UnaryOp.PreDec, idxExpr))
			: new SymbolStatement(idx);
		auto condition = new BinaryExpression(loc, Type.get(BuiltinType.Bool), cmp_op, idxExpr, stop);
		auto increment = new UnaryExpression(loc, type, inc_op, idxExpr);
		
		flattenedStmts ~= new ForStatement(loc, initialize, condition, increment, autoBlock(f.statement));
	}
	
	private void terminateBlock() {
		mustTerminate = true;
		blockTerminate = true;
	}
	
	private void terminateFun() {
		terminateBlock();
		funTerminate = true;
	}
	
	private void unterminate() {
		mustTerminate = false;
		blockTerminate = false;
		funTerminate = false;
	}
	
	void visit(AstReturnStatement s) {
		import d.semantic.expression;
		auto value = ExpressionVisitor(pass).visit(s.value);
		
		// TODO: precompute autotype instead of managing it here.
		auto rt = returnType.getType();
		
		// TODO: Handle auto return by specifying it to this visitor instead of deducing it in dubious ways.
		if (rt.kind == TypeKind.Builtin && rt.qualifier == TypeQualifier.Mutable && rt.builtin == BuiltinType.None) {
			// TODO: auto ref return.
			returnType = value.type.getParamType(false, false);
		} else {
			value = buildImplicitCast(pass, s.location, returnType.getType(), value);
			if (returnType.isRef) {
				if (value.isLvalue) {
					value = new UnaryExpression(s.location, value.type.getPointer(), UnaryOp.AddressOf, value);
				} else {
					import d.exception;
					throw new CompileException(s.location, "Cannot ref return lvalues.");
				}
			}
		}
		
		assert(value, "return; not implemented.");
		
		flattenedStmts ~= new ReturnStatement(s.location, value);
		terminateFun();
	}
	
	void visit(BreakStatement s) {
		flattenedStmts ~= s;
		terminateBlock();
	}
	
	void visit(ContinueStatement s) {
		flattenedStmts ~= s;
		terminateBlock();
	}
	
	void visit(AstSwitchStatement s) {
		auto oldSwitchBlock = switchBlock;
		auto oldAllowFallthrough = allowFallthrough;
		auto oldSwitchMustTerminate = switchMustTerminate;
		auto oldSwitchFunTerminate = switchFunTerminate;
		
		auto oldBlockTerminate = blockTerminate;
		scope(exit) {
			mustTerminate = switchMustTerminate;
			funTerminate = switchFunTerminate;
			blockTerminate = oldBlockTerminate || funTerminate;
			
			switchBlock = oldSwitchBlock;
			allowFallthrough = oldAllowFallthrough;
			switchMustTerminate = oldSwitchMustTerminate;
			switchFunTerminate = oldSwitchFunTerminate;
		}
		
		switchBlock = declBlockStack[$ - 1];
		allowFallthrough = true;
		switchFunTerminate = true;
		
		import d.semantic.expression;
		flattenedStmts ~= new SwitchStatement(
			s.location,
			ExpressionVisitor(pass).visit(s.expression),
			autoBlock(s.statement),
		);
	}
	
	private void setCaseEntry(Location location, string switchError, string fallthroughError) out {
		assert(declBlockStack[$ - 1] == switchBlock);
	} body {
		if (allowFallthrough) {
			allowFallthrough = false;
			if (declBlockStack[$ - 1] == switchBlock) {
				return;
			}
			
			import d.exception;
			throw new CompileException(location, "Cannot jump over variable initialization.");
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
			bool isValid = false;
			if (flattenedStmts.length > 0) {
				auto s = flattenedStmts[$ - 1];
				if (auto c = cast(CaseStatement) s) {
					isValid = true;
				}
			}
			
			if (!isValid) {
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
	
	void visit(AstCaseStatement s) {
		setCaseEntry(
			s.location,
			"Case statement can only appear within switch statement.",
			"Fallthrough is disabled, use goto case.",
		);
		
		unterminate();
		
		import d.semantic.expression;
		flattenedStmts ~= new CaseStatement(
			s.location,
			s.cases.map!(e => pass.evaluate(ExpressionVisitor(pass).visit(e))).array(),
		);
	}
	
	void visit(AstLabeledStatement s) {
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
					throw new CompileException(s.location, "Cannot jump over variable initialization.");
				}
			}
		}
		
		auto labelIndex = flattenedStmts.length;
		
		visit(s.statement);
		
		flattenedStmts[labelIndex] = new LabeledStatement(s.location, label, flattenedStmts[labelIndex]);
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
				throw new CompileException(s.location, "Cannot goto over variable initialization.");
			}
		} else if (auto bPtr = label in inFlightGotosStacks) {
			auto blockStacks = *bPtr;
			blockStacks ~= declBlockStack;
			inFlightGotosStacks[label] = blockStacks;
		} else {
			inFlightGotosStacks[label] = [declBlockStack];
		}
		
		flattenedStmts ~= s;
		terminateBlock();
	}
	
	void visit(AstScopeStatement s) {
		auto oldMustTerminate = mustTerminate;
		auto oldFunTerminate = funTerminate;
		auto oldBlockTerminate = blockTerminate;
		scope(exit) {
			mustTerminate = oldMustTerminate;
			funTerminate = oldFunTerminate;
			blockTerminate = oldBlockTerminate;
		}
		
		flattenedStmts ~= new ScopeStatement(s.location, s.kind, autoBlock(s.statement));
	}
	
	void visit(AstThrowStatement s) {
		import d.semantic.expression;
		flattenedStmts ~= new ThrowStatement(s.location, buildExplicitCast(
			pass,
			s.value.location,
			Type.get(pass.object.getThrowable()),
			ExpressionVisitor(pass).visit(s.value),
		));
		
		terminateFun();
	}
	
	void visit(AstTryStatement s) {
		auto oldMustTerminate = mustTerminate;
		auto oldFunTerminate = funTerminate;
		auto oldBlockTerminate = blockTerminate;
		
		auto tryStmt = autoBlock(s.statement);
		
		auto tryMustTerminate = mustTerminate;
		auto tryFunTerminate = funTerminate;
		auto tryBlockTerminate = blockTerminate;
		
		scope(exit) {
			mustTerminate = tryMustTerminate;
			funTerminate = tryFunTerminate;
			blockTerminate = tryBlockTerminate;
		}
		
		import d.semantic.identifier : AliasResolver;
		auto iv = AliasResolver!(function Class(identified) {
			static if(is(typeof(identified) : Symbol)) {
				if(auto c = cast(Class) identified) {
					return c;
				}
			}
			
			static if(is(typeof(identified.location))) {
				import d.exception;
				throw new CompileException(identified.location, typeid(identified).toString() ~ " is not a class.");
			} else {
				// for typeof(null)
				assert(0);
			}
		})(pass);
		
		CatchBlock[] catches;
		foreach(c; s.catches) {
			mustTerminate = oldMustTerminate;
			funTerminate = oldFunTerminate;
			blockTerminate = oldBlockTerminate;
			
			catches ~= CatchBlock(c.location, iv.visit(c.type), c.name, autoBlock(c.statement));
			
			tryMustTerminate = tryMustTerminate && mustTerminate;
			tryFunTerminate = tryFunTerminate && funTerminate;
			tryBlockTerminate = tryBlockTerminate && blockTerminate;
		}
		
		if (s.finallyBlock) {
			mustTerminate = oldMustTerminate;
			funTerminate = oldFunTerminate;
			blockTerminate = oldBlockTerminate;
			
			flattenedStmts ~= new ScopeStatement(s.finallyBlock.location, ScopeKind.Exit, autoBlock(s.finallyBlock));
		}
		
		flattenedStmts ~= new TryStatement(s.location, tryStmt, catches);
	}
	
	void visit(StaticIf!AstStatement s) {
		import d.semantic.expression;
		auto condition = evalIntegral(buildExplicitCast(
			pass,
			s.condition.location,
			Type.get(BuiltinType.Bool),
			ExpressionVisitor(pass).visit(s.condition),
		));
		
		auto items = condition
			? s.items
			: s.elseItems;
		
		foreach(item; items) {
			visit(item);
		}
		
		// Do not error on unrechable statement after static if.
		mustTerminate = false;
	}
	
	void visit(Mixin!AstStatement s) {
		import d.semantic.expression;
		auto str = evalString(ExpressionVisitor(pass).visit(s.value));
		
		import d.lexer;
		auto source = new MixinSource(s.location, str);
		auto trange = lex!((line, begin, length) => Location(source, line, begin, length))(str ~ '\0', context);
		
		trange.match(TokenType.Begin);
		while(trange.front.type != TokenType.End) {
			visit(trange.parseStatement());
		}
	}
}

