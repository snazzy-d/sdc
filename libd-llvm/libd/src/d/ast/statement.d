module d.ast.statement;

import d.ast.base;
import d.ast.declaration;
import d.ast.expression;
import d.ast.type;

class AstStatement : Node {
	this(Location location) {
		super(location);
	}
}

final:
/**
 * Blocks
 */
class BlockStatement(S) if(is(S : AstStatement)) : S {
	S[] statements;
	
	this(Location location, S[] statements) {
		super(location);
		
		this.statements = statements;
	}
}

alias AstBlockStatement = BlockStatement!AstStatement;

/**
 * Expressions
 */
class ExpressionStatement(E, S) if(is(E : AstExpression) && is(S : AstStatement)) : S {
	E expression;
	
	this(E expression) {
		super(expression.location);
		
		this.expression = expression;
	}
}

alias AstExpressionStatement = ExpressionStatement!(AstExpression, AstStatement);

/**
 * Declarations
 */
class DeclarationStatement : AstStatement {
	Declaration declaration;
	
	this(Declaration declaration) {
		super(declaration.location);
		
		this.declaration = declaration;
	}
}

/**
 * if statements.
 */
class IfStatement(E, S) if(is(E : AstExpression) && is(S : AstStatement)) : S {
	E condition;
	S then;
	
	// Nullable
	S elseStatement;
	
	this(Location location, E condition, S then, S elseStatement) {
		super(location);
		
		this.condition = condition;
		this.then = then;
		this.elseStatement = elseStatement;
	}
}

alias AstIfStatement = IfStatement!(AstExpression, AstStatement);

/**
 * while statements
 */
class WhileStatement(E, S) if(is(E : AstExpression) && is(S : AstStatement)) : S {
	E condition;
	S statement;
	
	this(Location location, E condition, S statement) {
		super(location);
		
		this.condition = condition;
		this.statement = statement;
	}
}

alias AstWhileStatement = WhileStatement!(AstExpression, AstStatement);

/**
 * do .. while statements
 */
class DoWhileStatement(E, S) if(is(E : AstExpression) && is(S : AstStatement)) : S {
	E condition;
	S statement;
	
	this(Location location, E condition, S statement) {
		super(location);
		
		this.condition = condition;
		this.statement = statement;
	}
}

alias AstDoWhileStatement = DoWhileStatement!(AstExpression, AstStatement);

/**
 * for statements
 */
class ForStatement(E, S) if(is(E : AstExpression) && is(S : AstStatement)) : S {
	S initialize;
	E condition;
	E increment;
	S statement;
	
	this(Location location, S initialize, E condition, E increment, S statement) {
		super(location);
		
		this.initialize = initialize;
		this.condition = condition;
		this.increment = increment;
		this.statement = statement;
	}
}

alias AstForStatement = ForStatement!(AstExpression, AstStatement);

/**
 * for statements
 */
class ForeachStatement : AstStatement {
	VariableDeclaration[] tupleElements;
	AstExpression iterrated;
	AstStatement statement;
	
	this(Location location, VariableDeclaration[] tupleElements, AstExpression iterrated, AstStatement statement) {
		super(location);
		
		this.tupleElements = tupleElements;
		this.iterrated = iterrated;
		this.statement = statement;
	}
}

/**
 * return statements
 */
class ReturnStatement(E, S) if(is(E : AstExpression) && is(S : AstStatement)) : S {
	E value;
	
	this(Location location, E value) {
		super(location);
		
		this.value = value;
	}
}

alias AstReturnStatement = ReturnStatement!(AstExpression, AstStatement);

/**
 * switch statements
 */
class SwitchStatement(E, S) if(is(E : AstExpression) && is(S : AstStatement)) : S {
	E expression;
	S statement;
	
	this(Location location, E expression, S statement) {
		super(location);
		
		this.expression = expression;
		this.statement = statement;
	}
}

alias AstSwitchStatement = SwitchStatement!(AstExpression, AstStatement);

/**
 * case statements
 */
class CaseStatement(E, S) if(is(E : AstExpression) && is(S : AstStatement)) : S {
	E[] cases;
	
	this(Location location, E[] cases) {
		super(location);
		
		this.cases = cases;
	}
}

alias AstCaseStatement = CaseStatement!(AstExpression, AstStatement);

/**
 * Label: statement
 */
class LabeledStatement(S) if(is(S : AstStatement)) : S {
	string label;
	S statement;
	
	this(Location location, string label, S statement) {
		super(location);
		
		this.label = label;
		this.statement = statement;
	}
}

alias AstLabeledStatement = LabeledStatement!AstStatement;

/**
 * synchronized statements
 */
class SynchronizedStatement(S) if(is(S : AstStatement)) : S {
	S statement;
	
	this(Location location, S statement) {
		super(location);
		
		this.statement = statement;
	}
}

alias AstSynchronizedStatement = SynchronizedStatement!AstStatement;

/**
 * try statements
 */
class TryStatement : AstStatement {
	AstStatement statement;
	CatchBlock[] catches;
	
	// nullable
	AstStatement finallyBlock;
	
	this(Location location, AstStatement statement, CatchBlock[] catches, AstStatement finallyBlock) {
		super(location);
		
		this.statement = statement;
		this.catches = catches;
		this.finallyBlock = finallyBlock;
	}
}

class CatchBlock : Node {
	QualAstType type;
	string name;
	AstStatement statement;
	
	this(Location location, QualAstType type, string name, AstStatement statement) {
		super(location);
		
		this.type = type;
		this.name = name;
		this.statement = statement;
	}
}

/**
 * throw statements
 */
class ThrowStatement(E, S) if(is(E : AstExpression) && is(S : AstStatement)) : S {
	AstExpression value;
	
	this(Location location, AstExpression value) {
		super(location);
		
		this.value = value;
	}
}

alias AstThrowStatement = ThrowStatement!(AstExpression, AstStatement);

/**
 * static assert statements
 */
class StaticAssertStatement : AstStatement {
	AstExpression[] arguments;
	
	this(Location location, AstExpression[] arguments) {
		super(location);
		
		this.arguments = arguments;
	}
}

