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

final class StatementVisitor {
	private SemanticPass pass;
	alias pass this;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	BlockStatement flatten(AstBlockStatement b) {
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = (cast(NestedScope) oldScope).clone();
		
		auto oldFlattenedStmts = flattenedStmts;
		scope(exit) flattenedStmts = oldFlattenedStmts;
		
		flattenedStmts = [];
		
		foreach(ref s; b.statements) {
			visit(s);
		}
		
		return new BlockStatement(b.location, flattenedStmts);
	}
	
	void visit(AstStatement s) {
		return this.dispatch(s);
	}
	
	void visit(AstBlockStatement b) {
		flattenedStmts ~= flatten(b);
	}
	
	void visit(DeclarationStatement s) {
		auto syms = pass.flatten(s.declaration);
		scheduler.require(syms);
		
		flattenedStmts ~= syms.map!(d => new SymbolStatement(d)).array();
	}
	
	void visit(AstExpressionStatement s) {
		flattenedStmts ~= new ExpressionStatement(pass.visit(s.expression));
	}
	
	private auto autoBlock(AstStatement s) {
		if(auto b = cast(AstBlockStatement) s) {
			return flatten(b);
		}
		
		return flatten(new AstBlockStatement(s.location, [s]));
	}
	
	void visit(AstIfStatement s) {
		auto condition = buildExplicitCast(s.condition.location, getBuiltin(TypeKind.Bool), pass.visit(s.condition));
		auto then = autoBlock(s.then);
		
		Statement elseStatement;
		if(s.elseStatement) {
			elseStatement = autoBlock(s.elseStatement);
		}
		
		flattenedStmts ~= new IfStatement(s.location, condition, then, elseStatement);
	}
	
	void visit(AstWhileStatement w) {
		auto condition = buildExplicitCast(w.condition.location, getBuiltin(TypeKind.Bool), pass.visit(w.condition));
		auto statement = autoBlock(w.statement);
		
		flattenedStmts ~= new WhileStatement(w.location, condition, statement);
	}
	
	void visit(AstDoWhileStatement w) {
		auto condition = buildExplicitCast(w.condition.location, getBuiltin(TypeKind.Bool), pass.visit(w.condition));
		auto statement = autoBlock(w.statement);
		
		flattenedStmts ~= new DoWhileStatement(w.location, condition, statement);
	}
	
	void visit(AstForStatement f) {
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = (cast(NestedScope) oldScope).clone();
		
		// FIXME: if initialize is flattened into several statement, scope is wrong.
		visit(f.initialize);
		auto initialize = flattenedStmts[$ - 1];
		
		Expression condition;
		if(f.condition) {
			condition = buildExplicitCast(f.condition.location, getBuiltin(TypeKind.Bool), pass.visit(f.condition));
		} else {
			condition = new BooleanLiteral(f.location, true);
		}
		
		Expression increment;
		if(f.increment) {
			increment = pass.visit(f.increment);
		} else {
			increment = new BooleanLiteral(f.location, true);
		}
		
		auto statement = autoBlock(f.statement);
		
		flattenedStmts[$ - 1] = new ForStatement(f.location, initialize, condition, increment, statement);
	}
	
	void visit(AstReturnStatement r) {
		auto value = pass.visit(r.value);
		
		// TODO: precompute autotype instead of managing it here.
		auto doCast = true;
		if(auto bt = cast(BuiltinType) returnType.type) {
			if(bt.kind == TypeKind.None) {
				// TODO: auto ref return.
				returnType = ParamType(value.type, false);
				doCast = false;
			}
		}
		
		if(doCast) {
			value = buildImplicitCast(r.location, QualType(returnType.type, returnType.qualifier), value);
		}
		
		flattenedStmts ~= new ReturnStatement(r.location, value);
	}
	
	void visit(BreakStatement s) {
		flattenedStmts ~= s;
	}
	
	void visit(ContinueStatement s) {
		flattenedStmts ~= s;
	}
	
	void visit(AstSwitchStatement s) {
		auto expression = pass.visit(s.expression);
		auto statement = autoBlock(s.statement);
		
		flattenedStmts ~= new SwitchStatement(s.location, expression, statement);
	}
	
	void visit(AstCaseStatement s) {
		auto cases = s.cases.map!(e => pass.evaluate(pass.visit(e))).array();
		
		flattenedStmts ~= new CaseStatement(s.location, cases);
	}
	
	void visit(AstLabeledStatement s) {
		auto labelIndex = flattenedStmts.length;
		
		visit(s.statement);
		
		auto statement = flattenedStmts[labelIndex];
		
		flattenedStmts[labelIndex] = new LabeledStatement(s.location, s.label, statement);
	}
	
	void visit(GotoStatement s) {
		flattenedStmts ~= s;
	}
	
	void visit(StaticIf!AstStatement s) {
		auto condition = evaluate(buildExplicitCast(s.condition.location, getBuiltin(TypeKind.Bool), pass.visit(s.condition)));
		
		if((cast(BooleanLiteral) condition).value) {
			foreach(item; s.items) {
				visit(item);
			}
		} else {
			foreach(item; s.elseItems) {
				visit(item);
			}
		}
	}
	
	void visit(Mixin!AstStatement s) {
		auto value = evaluate(pass.visit(s.value));
		
		if(auto str = cast(StringLiteral) value) {
			import d.lexer;
			auto source = new MixinSource(s.location, str.value);
			auto trange = lex!((line, begin, length) => Location(source, line, begin, length))(str.value ~ '\0');
			
			trange.match(TokenType.Begin);
			
			while(trange.front.type != TokenType.End) {
				visit(trange.parseStatement());
			}
		} else {
			assert(0, "mixin parameter should evalutate as a string.");
		}
	}
}

