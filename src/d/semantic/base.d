module d.semantic.base;

public import util.visitor;

import util.condition;

import sdc.compilererror;

import d.ast.expression;
import d.ast.type;

import d.location;

private enum Outcome {
	Throw,
	ErrorNode,
}

struct CompilationCondition {
	Location location;
	string message;
	
	Outcome outcome;
	
	this(Location location, string message) {
		this.location = location;
		this.message = message;
	}
	
	void error() in {
		assert(outcome == Outcome.Throw);
	} body {
		outcome = Outcome.ErrorNode;
	}
	
	invariant() {
		assert(location != location.init);
	}
}

auto compilationCondition(T)(Location location, string message) {
	auto cond = CompilationCondition(location, message);
	final switch(raiseCondition(cond).outcome) {
		case Outcome.Throw :
			throw new CompilerError(location, message);
		
		case Outcome.ErrorNode:
			static if(is(T == Type)) {
				return new ErrorType(location, message);
			} else static if(is(T == Expression)) {
				return new ErrorExpression(location, message);
			} else {
				static assert(false, "compilationCondition only works for Types and Expressions.");
			}
	}
}

