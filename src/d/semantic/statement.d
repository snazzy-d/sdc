module d.semantic.statement;

import d.semantic.base;
import d.semantic.semantic;

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
	
	void visit(Statement s) {
		this.dispatch(s);
	}
	
	void visit(BlockStatement b) {
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = b.dscope;
		
		foreach(s; b.statements) {
			visit(s);
		}
	}
	
	void visit(DeclarationStatement d) {
		d.declaration = scheduler.register(d.declaration, pass.visit(d.declaration), Step.Processed);
	}
	
	void visit(ExpressionStatement d) {
		d.expression = pass.visit(d.expression);
	}
	
	void visit(IfElseStatement ifs) {
		ifs.condition = explicitCast(ifs.condition.location, new BooleanType(ifs.condition.location), pass.visit(ifs.condition));
		
		visit(ifs.then);
		visit(ifs.elseStatement);
	}
	
	void visit(WhileStatement w) {
		w.condition = explicitCast(w.condition.location, new BooleanType(w.condition.location), pass.visit(w.condition));
		
		visit(w.statement);
	}
	
	void visit(DoWhileStatement w) {
		w.condition = explicitCast(w.condition.location, new BooleanType(w.condition.location), pass.visit(w.condition));
		
		visit(w.statement);
	}
	
	void visit(ForStatement f) {
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = f.dscope;
		
		visit(f.initialize);
		
		f.condition = explicitCast(f.condition.location, new BooleanType(f.condition.location), pass.visit(f.condition));
		f.increment = pass.visit(f.increment);
		
		visit(f.statement);
	}
	
	void visit(ReturnStatement r) {
		r.value = pass.visit(r.value);
		
		// TODO: precompute autotype instead of managing it here.
		if(typeid({ return pass.returnType; }()) is typeid(AutoType)) {
			returnType = r.value.type;
		} else {
			r.value = implicitCast(r.location, returnType, r.value);
		}
	}
	
	void visit(BreakStatement s) {
		// Nothing needs to be done.
	}
	
	void visit(ContinueStatement s) {
		// Nothing needs to be done.
	}
	
	void visit(SwitchStatement s) {
		s.expression = pass.visit(s.expression);
		
		visit(s.statement);
	}
	
	void visit(CaseStatement s) {
		s.cases = s.cases.map!(e => cast(typeof(e)) pass.evaluate(pass.visit(e))).array();
	}
	
	void visit(LabeledStatement s) {
		visit(s.statement);
	}
	
	void visit(GotoStatement s) {
		// Nothing needs to be done.
	}
}

