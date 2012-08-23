module d.ast.statement;

import d.ast.base;
import d.ast.declaration;
import d.ast.dscope;
import d.ast.expression;
import d.ast.type;

class Statement : Node {
	this(Location location) {
		super(location);
	}
}

/**
 * Blocks
 */
class BlockStatement : Statement {
	Statement[] statements;
	
	Scope dscope;
	
	this(Location location, Statement[] statements) {
		super(location);
		
		this.statements = statements;
	}
}

/**
 * Expressions
 */
class ExpressionStatement : Statement {
	Expression expression;
	
	this(Expression expression) {
		super(expression.location);
		
		this.expression = expression;
	}
}

/**
 * Declarations
 */
class DeclarationStatement : Statement {
	Declaration declaration;
	
	this(Declaration declaration) {
		super(declaration.location);
		
		this.declaration = declaration;
	}
}

/**
 * if else statements.
 */
class IfElseStatement : Statement {
	Expression condition;
	Statement then;
	Statement elseStatement;
	
	this(Location location, Expression condition, Statement then) {
		this(location, condition, then, new BlockStatement(location, []));
	}
	
	this(Location location, Expression condition, Statement then, Statement elseStatement) {
		super(location);
		
		this.condition = condition;
		this.then = then;
		this.elseStatement = elseStatement;
	}
}

/**
 * if statements with no else.
 */
class IfStatement : Statement {
	Expression condition;
	Statement then;
	
	this(Location location, Expression condition, Statement then) {
		super(location);
		
		this.condition = condition;
		this.then = then;
	}
}

/**
 * while statements
 */
class WhileStatement : Statement {
	Expression condition;
	Statement statement;
	
	this(Location location, Expression condition, Statement statement) {
		super(location);
		
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
		super(location);
		
		this.condition = condition;
		this.statement = statement;
	}
}

/**
 * for statements
 */
class ForStatement : Statement {
	Statement initialize;
	Expression condition;
	Expression increment;
	Statement statement;
	
	Scope dscope;
	
	this(Location location, Statement initialize, Expression condition, Expression increment, Statement statement) {
		super(location);
		
		this.initialize = initialize;
		this.condition = condition;
		this.increment = increment;
		this.statement = statement;
	}
}

/**
 * for statements
 */
class ForeachStatement : Statement {
	VariableDeclaration[] tupleElements;
	Expression iterrated;
	Statement statement;
	
	this(Location location, VariableDeclaration[] tupleElements, Expression iterrated, Statement statement) {
		super(location);
		
		this.tupleElements = tupleElements;
		this.iterrated = iterrated;
		this.statement = statement;
	}
}

/**
 * break statements
 */
class BreakStatement : Statement {
	this(Location location) {
		super(location);
	}
}

/**
 * continue statements
 */
class ContinueStatement : Statement {
	this(Location location) {
		super(location);
	}
}

/**
 * return statements
 */
class ReturnStatement : Statement {
	Expression value;
	
	this(Location location, Expression value) {
		super(location);
		
		this.value = value;
	}
}

/**
 * synchronized statements
 */
class SynchronizedStatement : Statement {
	Statement statement;
	
	this(Location location, Statement statement) {
		super(location);
		
		this.statement = statement;
	}
}

/**
 * try statements
 */
class TryStatement : Statement {
	Statement statement;
	CatchBlock[] catches;
	
	this(Location location, Statement statement, CatchBlock[] catches) {
		super(location);
		
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
		super(location);
		
		this.value = value;
	}
}

/**
 * static assert statements
 */
class StaticAssertStatement : Statement {
	Expression[] arguments;
	
	this(Location location, Expression[] arguments) {
		super(location);
		
		this.arguments = arguments;
	}
}

