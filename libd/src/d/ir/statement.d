module d.ir.statement;

import d.ir.dscope;
import d.ir.expression;

import d.ast.statement;

import d.context.location;

class Statement : AstStatement {
	this(Location location) {
		super(location);
	}
}

alias AssertStatement = d.ast.statement.AssertStatement!(Expression, Statement);
alias ExpressionStatement = d.ast.statement.ExpressionStatement!(Expression, Statement);
alias ReturnStatement = d.ast.statement.ReturnStatement!(Expression, Statement);
alias SwitchStatement = d.ast.statement.SwitchStatement!(Expression, Statement);
alias CaseStatement = d.ast.statement.CaseStatement!(CompileTimeExpression, Statement);
alias LabeledStatement = d.ast.statement.LabeledStatement!Statement;
alias SynchronizedStatement = d.ast.statement.SynchronizedStatement!Statement;
alias ScopeStatement = d.ast.statement.ScopeStatement!Statement;
alias ScopeKind = d.ast.statement.ScopeKind;
alias ThrowStatement = d.ast.statement.ThrowStatement!(Expression, Statement);

final:
/**
 * Blocks
 */
class BlockStatement : Statement, Scope {
	mixin ScopeSymbol;
	Statement[] statements;
	
	this(Location location, Scope parentScope, Statement[] statements) in {
	} body {
		super(location);
		fillParentScope(parentScope);
		
		this.statements = statements;
	}
}

/**
 * Variable
 */
class VariableStatement : Statement {
	import d.ir.symbol;
	Variable var;
	
	this(Variable variable) {
		super(variable.location);
		
		var = variable;
	}
}

/**
 * Function
 */
class FunctionStatement : Statement {
	import d.ir.symbol;
	Function fun;
	
	this(Function dfunction) {
		super(dfunction.location);
		
		fun = dfunction;
	}
}

/**
 * Type
 */
class TypeStatement : Statement {
	import d.ir.symbol;
	TypeSymbol type;
	
	this(TypeSymbol type) {
		super(type.location);
		
		this.type = type;
	}
}

/**
 * if statements.
 */
class IfStatement : Statement {
	Expression condition;
	BlockStatement then;
	
	// Nullable
	BlockStatement elseStatement;
	
	this(
		Location location,
		Expression condition,
		BlockStatement then,
		BlockStatement elseStatement,
	) {
		super(location);
		
		this.condition = condition;
		this.then = then;
		this.elseStatement = elseStatement;
	}
}

/**
 * loop statements
 */
class LoopStatement : Statement {
	Expression condition;
	BlockStatement fbody;
	Expression increment;
	
	// For do/while.
	bool skipFirstCond;
	
	this(
		Location location,
		Expression condition,
		BlockStatement fbody,
		Expression increment = null,
	) {
		super(location);
		
		this.condition = condition;
		this.fbody = fbody;
		this.increment = increment;
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
 * goto statements
 */
class GotoStatement : Statement {
	import d.context.name;
	Name label;
	
	this(Location location, Name label) {
		super(location);
		
		this.label = label;
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

struct CatchBlock {
	Location location;
	
	import d.context.name;
	Name name;
	
	import d.ir.symbol;
	Class type;
	
	BlockStatement statement;
	
	this(Location location, Class type, Name name, BlockStatement statement) {
		this.location = location;
		this.name = name;
		this.type = type;
		this.statement = statement;
	}
}

/**
 * halt statements (asserts that always fail)
 */
class HaltStatement : Statement {
	Expression message;
	
	this(Location location, Expression message) {
		super(location);
		
		this.message = message;
	}
}
