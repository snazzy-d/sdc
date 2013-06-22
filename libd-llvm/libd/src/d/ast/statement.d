module d.ast.statement;

import d.ast.base;
import d.ast.declaration;
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
	
	this(Location location, Statement[] statements) {
		super(location);
		
		this.statements = statements;
	}
}

/**
 * AstExpressions
 */
class ExpressionStatement : Statement {
	AstExpression expression;
	
	this(AstExpression expression) {
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
 * Declarations
 */
class SymbolStatement : Statement {
	import d.ir.symbol;
	Symbol symbol;
	
	this(Symbol symbol) {
		super(symbol.location);
		
		this.symbol = symbol;
	}
}

/**
 * if statements.
 */
class IfStatement : Statement {
	AstExpression condition;
	Statement then;
	
	// Nullable
	Statement elseStatement;
	
	this(Location location, AstExpression condition, Statement then, Statement elseStatement) {
		super(location);
		
		this.condition = condition;
		this.then = then;
		this.elseStatement = elseStatement;
	}
}

/**
 * while statements
 */
class WhileStatement : Statement {
	AstExpression condition;
	Statement statement;
	
	this(Location location, AstExpression condition, Statement statement) {
		super(location);
		
		this.condition = condition;
		this.statement = statement;
	}
}

/**
 * do .. while statements
 */
class DoWhileStatement : Statement {
	AstExpression condition;
	Statement statement;
	
	this(Location location, AstExpression condition, Statement statement) {
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
	AstExpression condition;
	AstExpression increment;
	Statement statement;
	
	this(Location location, Statement initialize, AstExpression condition, AstExpression increment, Statement statement) {
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
	AstExpression iterrated;
	Statement statement;
	
	this(Location location, VariableDeclaration[] tupleElements, AstExpression iterrated, Statement statement) {
		super(location);
		
		this.tupleElements = tupleElements;
		this.iterrated = iterrated;
		this.statement = statement;
	}
}

/**
 * return statements
 */
class ReturnStatement : Statement {
	AstExpression value;
	
	this(Location location, AstExpression value) {
		super(location);
		
		this.value = value;
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
 * switch statements
 */
class SwitchStatement : Statement {
	AstExpression expression;
	Statement statement;
	
	this(Location location, AstExpression expression, Statement statement) {
		super(location);
		
		this.expression = expression;
		this.statement = statement;
	}
}

/**
 * case statements
 */
class CaseStatement : Statement {
	AstExpression[] cases;
	
	this(Location location, AstExpression[] cases) {
		super(location);
		
		this.cases = cases;
	}
}

/**
 * Label: statement
 */
class LabeledStatement : Statement {
	string label;
	Statement statement;
	
	this(Location location, string label, Statement statement) {
		super(location);
		
		this.label = label;
		this.statement = statement;
	}
}

/**
 * goto statements
 */
class GotoStatement : Statement {
	string label;
	
	this(Location location, string label) {
		super(location);
		
		this.label = label;
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
	QualAstType type;
	string name;
	Statement statement;
	
	this(Location location, QualAstType type, string name, Statement statement) {
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
	AstExpression value;
	
	this(Location location, AstExpression value) {
		super(location);
		
		this.value = value;
	}
}

/**
 * static assert statements
 */
class StaticAssertStatement : Statement {
	AstExpression[] arguments;
	
	this(Location location, AstExpression[] arguments) {
		super(location);
		
		this.arguments = arguments;
	}
}

