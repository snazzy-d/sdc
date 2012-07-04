module d.ast.statement;

import d.ast.base;
import d.ast.expression;
import d.ast.type;

import sdc.location;

enum StatementType {
	Empty,
	Block,
	Labeled,
	Expression,
	Declaration,
	If,
	While,
	DoWhile,
	For,
	Foreach,
	Switch,
	Case,
	CaseRange,
	Default,
	Continue,
	Break,
	Return,
	Goto,
	With,
	Synchronized,
	Try,
	ScopeGuard,
	Throw,
	Asm,
	Pragma,
	Mixin,
	ForeachRange,
	Conditional,
	StaticAssert,
	TemplateMixin,
}


class Statement : Node {
	StatementType type;
	
	this(Location location, StatementType type) {
		super(location);
		
		this.type = type;
	}
}

/**
 * Blocks
 */
class BlockStatement : Statement {
	Statement[] statements;
	
	this(Location location, Statement[] statements) {
		super(location, StatementType.Block);
		
		this.statements = statements;
	}
}

/**
 * if statements
 */
class IfStatement : Statement {
	Expression condition;
	Statement then;
	
	this(Location location, Expression condition, Statement then) {
		super(location, StatementType.If);
		
		this.condition = condition;
		this.then = then;
	}
}

/**
 * if with else statement
 */
class IfElseStatement : IfStatement {
	Statement elseStatement;
	
	this(Location location, Expression condition, Statement then, Statement elseStatement) {
		super(location, condition, then);
		
		this.elseStatement = elseStatement;
	}
}

/**
 * while statements
 */
class WhileStatement : Statement {
	Expression condition;
	Statement statement;
	
	this(Location location, Expression condition, Statement statement) {
		super(location, StatementType.While);
		
		this.condition = condition;
		this.statement = statement;
	}
}

/**
 * do .. while statements
 */
class DoWhileStatement : Statement {
	Expression condition;
	Statement statement;
	
	this(Location location, Expression condition, Statement statement) {
		super(location, StatementType.DoWhile);
		
		this.condition = condition;
		this.statement = statement;
	}
}

/**
 * for statements
 */
class ForStatement : Statement {
	Statement init;
	Expression condition;
	Expression increment;
	Statement statement;
	
	this(Location location, Statement init, Expression condition, Expression increment, Statement statement) {
		super(location, StatementType.DoWhile);
		
		this.init = init;
		this.condition = condition;
		this.increment = increment;
		this.statement = statement;
	}
}

/**
 * break statements
 */
class BreakStatement : Statement {
	this(Location location) {
		super(location, StatementType.Break);
	}
}

/**
 * continue statements
 */
class ContinueStatement : Statement {
	this(Location location) {
		super(location, StatementType.Continue);
	}
}

/**
 * return statements
 */
class ReturnStatement : Statement {
	Expression value;
	
	this(Location location, Expression value) {
		super(location, StatementType.Return);
		
		this.value = value;
	}
}

/**
 * try statements
 */
class TryStatement : Statement {
	Statement statement;
	CatchBlock[] catches;
	
	this(Location location, Statement statement, CatchBlock[] catches) {
		super(location, StatementType.Try);
		
		this.statement = statement;
		this.catches = catches;
	}
}

class CatchBlock : Node {
	Type type;
	string name;
	Statement statement;
	
	this(Location location, Type type, string name, Statement statement) {
		super(location);
		
		this.type = type;
		this.name = name;
		this.statement = statement;
	}
}

/**
 * try .. finally statements
 */
class TryFinallyStatement : TryStatement {
	Statement finallyBlock;
	
	this(Location location, Statement statement, CatchBlock[] catches, Statement finallyBlock) {
		super(location, statement, catches);
		
		this.finallyBlock = finallyBlock;
	}
}

/**
 * throw statements
 */
class ThrowStatement : Statement {
	Expression value;
	
	this(Location location, Expression value) {
		super(location, StatementType.Throw);
		
		this.value = value;
	}
}

/**
 * static assert statements
 */
class StaticAssertStatement : Statement {
	Expression[] arguments;
	
	this(Location location, Expression[] arguments) {
		super(location, StatementType.StaticAssert);
		
		this.arguments = arguments;
	}
}

