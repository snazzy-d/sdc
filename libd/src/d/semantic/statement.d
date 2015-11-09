module d.semantic.statement;

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
	
public:
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	void getBody(Function f, AstBlockStatement b) {
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = f.dscope;
		f.fbody = getBody(b);
	}
	
	private BlockStatement getBody(AstBlockStatement b) {
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
		return this.dispatch(s);
	}
	
	private BlockStatement flatten(AstBlockStatement b) {
		auto oldScope = currentScope;
		auto oldFlattenedStmts = flattenedStmts;
		
		scope(exit) {
			currentScope = oldScope;
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
	
	void visit(AstExpressionStatement s) {
		import d.semantic.expression;
		auto e = ExpressionVisitor(pass).visit(s.expression);
		auto t = e.type;
		if (t.kind == TypeKind.Error) {
			import d.exception;
			throw new CompileException(t.error.location, t.error.message);
		}
		
		flattenedStmts ~= new ExpressionStatement(e);
	}
	
	void visit(DeclarationStatement s) {
		import d.semantic.declaration;
		auto syms = DeclarationVisitor(pass).flatten(s.declaration);
		
		scheduler.require(syms);
		
		foreach(sym; syms) {
			if (auto v = cast(Variable) sym) {
				flattenedStmts ~= new VariableStatement(v);
			} else if (auto f = cast(Function) sym) {
				flattenedStmts ~= new FunctionStatement(f);
			} else if (auto t = cast(TypeSymbol) sym) {
				flattenedStmts ~= new TypeStatement(t);
			} else {
				assert(0, typeid(sym).toString() ~ " is not supported");
			}
		}
	}
	
	void visit(IdentifierStarIdentifierStatement s) {
		import d.semantic.identifier;
		SymbolResolver!(delegate bool(identified) {
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
				
				flattenedStmts ~= new VariableStatement(v);
				return true;
			} else {
				assert(0, "Was not expecting " ~ T.stringof);
			}
		})(pass).visit(s.identifier);
	}
	
	private auto autoBlock(AstStatement s) {
		auto b = cast(AstBlockStatement) s;
		if (b is null) {
			b = new AstBlockStatement(s.location, [s]);
		}
		
		return flatten(b);
	}
	
	void visit(AstIfStatement s) {
		import d.semantic.caster, d.semantic.expression;
		auto condition = buildExplicitCast(pass, s.condition.location, Type.get(BuiltinType.Bool), ExpressionVisitor(pass).visit(s.condition));
		auto then = autoBlock(s.then);
		
		Statement elseStatement;
		if (s.elseStatement) {
			elseStatement = autoBlock(s.elseStatement);
		}
		
		flattenedStmts ~= new IfStatement(s.location, condition, then, elseStatement);
	}
	
	void visit(AstWhileStatement w) {
		import d.semantic.caster, d.semantic.expression;
		flattenedStmts ~= new WhileStatement(
			w.location,
			buildExplicitCast(pass, w.condition.location, Type.get(BuiltinType.Bool), ExpressionVisitor(pass).visit(w.condition)),
			autoBlock(w.statement),
		);
	}
	
	void visit(AstDoWhileStatement w) {
		import d.semantic.caster, d.semantic.expression;
		flattenedStmts ~= new DoWhileStatement(
			w.location,
			buildExplicitCast(pass, w.condition.location, Type.get(BuiltinType.Bool), ExpressionVisitor(pass).visit(w.condition)),
			autoBlock(w.statement),
		);
	}
	
	void visit(AstForStatement f) {
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = (cast(NestedScope) oldScope).clone();
		
		// FIXME: if initialize is flattened into several statement, scope is wrong.
		visit(f.initialize);
		auto initialize = flattenedStmts[$ - 1];
		
		import d.semantic.caster, d.semantic.expression;
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
		scope(exit) currentScope = oldScope;
		
		currentScope = (cast(NestedScope) oldScope).clone();
		
		assert(!f.reverse, "foreach_reverse not supported at this point.");
		
		import d.semantic.expression;
		auto iterated = ExpressionVisitor(pass).visit(f.iterated);
		
		import d.context.name;
		import d.semantic.identifier;
		auto length = SymbolResolver!(delegate Expression (e) {
			static if (is(typeof(e) : Expression)) {
				return e;
			} else {
				import d.ir.error;
				return new CompileError(
					iterated.location,
					typeid(e).toString() ~ " is not a valid length",
				).expression;
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
		
		auto initialize = new VariableStatement(idx);
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
			
			import d.semantic.caster;
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
		scope(exit) currentScope = oldScope;
		
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
		
		import d.semantic.caster;
		start = buildImplicitCast(pass, start.location, type, start);
		stop  = buildImplicitCast(pass, stop.location, type, stop);
		
		if (f.reverse) {
			auto tmp = start;
			start = stop;
			stop = tmp;
		}
		
		auto idx = new Variable(iDecl.location, type.getParamType(iDecl.type.isRef, false), iDecl.name, start);
		
		idx.step = Step.Processed;
		currentScope.addSymbol(idx);
		
		Expression idxExpr = new VariableExpression(idx.location, idx);
		Expression increment, condition;
		
		if (f.reverse) {
			// for(...; idx-- > stop; idx)
			condition = new BinaryExpression(
				loc, Type.get(BuiltinType.Bool), 
				BinaryOp.Greater, 
				new UnaryExpression(loc, type, UnaryOp.PostDec, idxExpr), 
				stop);
			increment = idxExpr;
		} else {
			// for(...; idx < stop; idx++)
			condition = new BinaryExpression(loc, Type.get(BuiltinType.Bool), BinaryOp.Less, idxExpr, stop);
			increment = new UnaryExpression(loc, type, UnaryOp.PreInc, idxExpr);
		}
		
		auto initialize = new VariableStatement(idx);
		
		flattenedStmts ~= new ForStatement(loc, initialize, condition, increment, autoBlock(f.statement));
	}
	
	void visit(AstReturnStatement s) {
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
			
			flattenedStmts ~= new ReturnStatement(s.location, null);
			return;
		}
		
		import d.semantic.expression;
		auto value = ExpressionVisitor(pass).visit(s.value);
		auto t = value.type;
		if (t.kind == TypeKind.Error) {
			import d.exception;
			throw new CompileException(t.error.location, t.error.message);
		}
		
		// TODO: Handle auto return by specifying it to this visitor instead of deducing it in dubious ways.
		if (isAutoReturn) {
			// TODO: auto ref return.
			returnType = value.type.getParamType(false, false);
		} else {
			import d.semantic.caster;
			value = buildImplicitCast(pass, s.location, returnType.getType(), value);
			if (returnType.isRef) {
				if (value.isLvalue) {
					value = new UnaryExpression(s.location, value.type.getPointer(), UnaryOp.AddressOf, value);
				} else {
					import d.exception;
					throw new CompileException(s.location, "Cannot ref return lvalues");
				}
			}
		}
		
		flattenedStmts ~= new ReturnStatement(s.location, value);
	}
	
	void visit(BreakStatement s) {
		flattenedStmts ~= s;
	}
	
	void visit(ContinueStatement s) {
		flattenedStmts ~= s;
	}
	
	void visit(AstSwitchStatement s) {
		import d.semantic.expression;
		flattenedStmts ~= new SwitchStatement(
			s.location,
			ExpressionVisitor(pass).visit(s.expression),
			autoBlock(s.statement),
		);
	}
	
	void visit(AstCaseStatement s) {
		import d.semantic.expression;
		import std.algorithm, std.array;
		flattenedStmts ~= new CaseStatement(
			s.location,
			s.cases.map!(e => pass.evaluate(ExpressionVisitor(pass).visit(e))).array(),
		);
	}
	
	void visit(AstLabeledStatement s) {
		auto labelIndex = flattenedStmts.length;
		
		visit(s.statement);
		
		flattenedStmts[labelIndex] = new LabeledStatement(s.location, s.label, flattenedStmts[labelIndex]);
	}
	
	void visit(GotoStatement s) {
		flattenedStmts ~= s;
	}
	
	void visit(AstScopeStatement s) {
		flattenedStmts ~= new ScopeStatement(s.location, s.kind, autoBlock(s.statement));
	}
	
	void visit(AstThrowStatement s) {
		import d.semantic.caster, d.semantic.expression;
		flattenedStmts ~= new ThrowStatement(s.location, buildExplicitCast(
			pass,
			s.value.location,
			Type.get(pass.object.getThrowable()),
			ExpressionVisitor(pass).visit(s.value),
		));
	}
	
	void visit(AstTryStatement s) {
		auto tryStmt = autoBlock(s.statement);
		
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
			catches ~= CatchBlock(c.location, iv.visit(c.type), c.name, autoBlock(c.statement));
		}
		
		if (s.finallyBlock) {
			flattenedStmts ~= new ScopeStatement(s.finallyBlock.location, ScopeKind.Exit, autoBlock(s.finallyBlock));
		}
		
		flattenedStmts ~= new TryStatement(s.location, tryStmt, catches);
	}
	
	void visit(StaticIf!AstStatement s) {
		import d.semantic.caster, d.semantic.expression;
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
		// TODO: Find a way to pass this info to the FlowAnalyzer.
		// mustTerminate = false;
	}
	
	void visit(StaticAssert!AstStatement s) {
		import d.semantic.caster, d.semantic.expression;
		auto condition = evalIntegral(buildExplicitCast(
			pass,
			s.condition.location,
			Type.get(BuiltinType.Bool),
			ExpressionVisitor(pass).visit(s.condition),
		));
		
		if (condition) {
			return;
		}
		
		import d.exception;
		if (s.message is null) {
			throw new CompileException(s.location, "assertion failure");
		}
		
		auto msg = evalString(buildExplicitCast(
			pass,
			s.condition.location,
			Type.get(BuiltinType.Char).getSlice(TypeQualifier.Immutable),
			ExpressionVisitor(pass).visit(s.message),
		));
		
		throw new CompileException(s.location, "assertion failure: " ~ msg);
	}
	
	void visit(Mixin!AstStatement s) {
		import d.semantic.expression;
		auto str = evalString(ExpressionVisitor(pass).visit(s.value));
		
		import d.lexer;
		auto base = context.registerMixin(s.location, str ~ '\0');
		auto trange = lex(base, context);
		
		trange.match(TokenType.Begin);
		while(trange.front.type != TokenType.End) {
			visit(trange.parseStatement());
		}
	}
}

