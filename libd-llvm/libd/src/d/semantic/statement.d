module d.semantic.statement;

import d.semantic.base;
import d.semantic.semantic;

import d.ast.conditional;
import d.ast.declaration;
import d.ast.dscope;
import d.ast.expression;
import d.ast.statement;
import d.ast.type;

import std.algorithm;
import std.array;

final class StatementVisitor {
	private SemanticPass pass;
	alias pass this;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	BlockStatement flatten(BlockStatement b) {
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = (cast(NestedScope) oldScope).clone();
		
		auto oldFlattenedStmts = flattenedStmts;
		scope(exit) flattenedStmts = oldFlattenedStmts;
		
		flattenedStmts = [];
		
		foreach(ref s; b.statements) {
			visit(s);
		}
		
		b.statements = flattenedStmts;
		
		return b;
	}
	
	void visit(Statement s) {
		return this.dispatch(s);
	}
	
	void visit(BlockStatement b) {
		flattenedStmts ~= flatten(b);
	}
	
	void visit(DeclarationStatement s) {
		// TODO: avoid allocating an array for that.
		auto syms = pass.visit([s.declaration]);
		
		flattenedStmts ~= scheduler.require(syms).map!(d => new DeclarationStatement(d)).array();
	}
	
	void visit(ExpressionStatement s) {
		s.expression = pass.visit(s.expression);
		
		flattenedStmts ~= s;
	}
	
	private auto autoBlock(Statement s) {
		if(auto b = cast(BlockStatement) s) {
			return flatten(b);
		}
		
		return flatten(new BlockStatement(s.location, [s]));
	}
	
	void visit(IfStatement ifs) {
		ifs.condition = explicitCast(ifs.condition.location, new BooleanType(ifs.condition.location), pass.visit(ifs.condition));
		
		ifs.then = autoBlock(ifs.then);
		
		if(ifs.elseStatement) {
			ifs.elseStatement = autoBlock(ifs.elseStatement);
		}
		
		flattenedStmts ~= ifs;
	}
	
	void visit(WhileStatement w) {
		w.condition = explicitCast(w.condition.location, new BooleanType(w.condition.location), pass.visit(w.condition));
		
		w.statement = autoBlock(w.statement);
		
		flattenedStmts ~= w;
	}
	
	void visit(DoWhileStatement w) {
		w.condition = explicitCast(w.condition.location, new BooleanType(w.condition.location), pass.visit(w.condition));
		
		w.statement = autoBlock(w.statement);
		
		flattenedStmts ~= w;
	}
	
	void visit(ForStatement f) {
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = (cast(NestedScope) oldScope).clone();
		
		// FIXME: if initialize is flattened into several statement, scope is wrong.
		visit(f.initialize);
		f.initialize = flattenedStmts[$ - 1];
		
		if(f.condition) {
			f.condition = explicitCast(f.condition.location, new BooleanType(f.condition.location), pass.visit(f.condition));
		} else {
			f.condition = makeLiteral(f.location, true);
		}
		
		if(f.increment) {
			f.increment = pass.visit(f.increment);
		} else {
			f.increment = makeLiteral(f.location, true);
		}
		
		f.statement = autoBlock(f.statement);
		
		flattenedStmts[$ - 1] = f;
	}
	
	void visit(ReturnStatement r) {
		r.value = pass.visit(r.value);
		
		// TODO: precompute autotype instead of managing it here.
		if(typeid({ return pass.returnType; }()) is typeid(AutoType)) {
			returnType = r.value.type;
		} else {
			r.value = implicitCast(r.location, returnType, r.value);
		}
		
		flattenedStmts ~= r;
	}
	
	void visit(BreakStatement s) {
		flattenedStmts ~= s;
	}
	
	void visit(ContinueStatement s) {
		flattenedStmts ~= s;
	}
	
	void visit(SwitchStatement s) {
		s.expression = pass.visit(s.expression);
		
		s.statement = autoBlock(s.statement);
		
		flattenedStmts ~= s;
	}
	
	void visit(CaseStatement s) {
		s.cases = s.cases.map!(e => cast(typeof(e)) pass.evaluate(pass.visit(e))).array();
		
		flattenedStmts ~= s;
	}
	
	void visit(LabeledStatement s) {
		auto labelIndex = flattenedStmts.length;
		
		visit(s.statement);
		
		s.statement = flattenedStmts[labelIndex];
		
		flattenedStmts[labelIndex] = s;
	}
	
	void visit(GotoStatement s) {
		flattenedStmts ~= s;
	}
	
	void visit(StaticIfElse!Statement s) {
		s.condition = evaluate(explicitCast(s.condition.location, new BooleanType(s.condition.location), pass.visit(s.condition)));
		
		if((cast(BooleanLiteral) s.condition).value) {
			foreach(item; s.items) {
				visit(item);
			}
		} else {
			foreach(item; s.elseItems) {
				visit(item);
			}
		}
	}
	
	void visit(Mixin!Statement s) {
		auto value = evaluate(pass.visit(s.value));
		
		if(auto str = cast(StringLiteral) value) {
			import sdc.lexer;
			import sdc.sdc;
			auto trange = TokenRange(lex(str.value, s.location));
			
			import d.parser.base;
			match(trange, TokenType.Begin);
			
			while(trange.front.type != TokenType.End) {
				import d.parser.statement;
				visit(parseStatement(trange));
			}
			
			match(trange, TokenType.End);
		} else {
			assert(0, "mixin parameter should evalutate as a string.");
		}
	}
}

