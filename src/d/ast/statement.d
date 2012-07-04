module d.ast.statement;

import d.ast.base;
import d.ast.expression;

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

