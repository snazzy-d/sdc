module d.semantic.statement;

import d.semantic.base;
import d.semantic.semantic;

import d.ast.conditional;
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
	
	Statement visit(Statement s) {
		return this.dispatch(s);
	}
	
	Statement visit(BlockStatement b) {
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = b.dscope;
		
		foreach(ref s; b.statements) {
			s = visit(s);
		}
		
		return b;
	}
	
	Statement visit(DeclarationStatement d) {
		d.declaration = scheduler.register(d.declaration, pass.visit(d.declaration), Step.Processed);
		
		return d;
	}
	
	Statement visit(ExpressionStatement s) {
		s.expression = pass.visit(s.expression);
		
		return s;
	}
	
	Statement visit(IfElseStatement ifs) {
		ifs.condition = explicitCast(ifs.condition.location, new BooleanType(ifs.condition.location), pass.visit(ifs.condition));
		
		ifs.then = visit(ifs.then);
		ifs.elseStatement = visit(ifs.elseStatement);
		
		return ifs;
	}
	
	Statement visit(WhileStatement w) {
		w.condition = explicitCast(w.condition.location, new BooleanType(w.condition.location), pass.visit(w.condition));
		
		w.statement = visit(w.statement);
		
		return w;
	}
	
	Statement visit(DoWhileStatement w) {
		w.condition = explicitCast(w.condition.location, new BooleanType(w.condition.location), pass.visit(w.condition));
		
		w.statement = visit(w.statement);
		
		return w;
	}
	
	Statement visit(ForStatement f) {
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = f.dscope;
		
		f.initialize = visit(f.initialize);
		
		f.condition = explicitCast(f.condition.location, new BooleanType(f.condition.location), pass.visit(f.condition));
		f.increment = pass.visit(f.increment);
		
		f.statement = visit(f.statement);
		
		return f;
	}
	
	Statement visit(ReturnStatement r) {
		r.value = pass.visit(r.value);
		
		// TODO: precompute autotype instead of managing it here.
		if(typeid({ return pass.returnType; }()) is typeid(AutoType)) {
			returnType = r.value.type;
		} else {
			r.value = implicitCast(r.location, returnType, r.value);
		}
		
		return r;
	}
	
	Statement visit(BreakStatement s) {
		return s;
	}
	
	Statement visit(ContinueStatement s) {
		return s;
	}
	
	Statement visit(SwitchStatement s) {
		s.expression = pass.visit(s.expression);
		
		s.statement = visit(s.statement);
		
		return s;
	}
	
	Statement visit(CaseStatement s) {
		s.cases = s.cases.map!(e => cast(typeof(e)) pass.evaluate(pass.visit(e))).array();
		
		return s;
	}
	
	Statement visit(LabeledStatement s) {
		s.statement = visit(s.statement);
		
		return s;
	}
	
	Statement visit(GotoStatement s) {
		return s;
	}
	
	Statement visit(StaticIfElse!Statement s) {
		s.condition = evaluate(explicitCast(s.condition.location, new BooleanType(s.condition.location), pass.visit(s.condition)));
		
		if((cast(BooleanLiteral) s.condition).value) {
			assert(s.items.length == 1, "static if must have one and only one item");
			
			return visit(s.items[0]);
		} else {
			assert(s.elseItems.length == 1, "static else must have one and only one item");
			
			return visit(s.elseItems[0]);
		}
	}
}

