module d.ir.statement;

import d.ir.expression;

import d.ast.statement;

import d.context;
import d.location;

class Statement : AstStatement {
	this(Location location) {
		super(location);
	}
}

alias BlockStatement = d.ast.statement.BlockStatement!Statement;
alias ExpressionStatement = d.ast.statement.ExpressionStatement!(Expression, Statement);
alias IfStatement = d.ast.statement.IfStatement!(Expression, Statement);
alias WhileStatement = d.ast.statement.WhileStatement!(Expression, Statement);
alias DoWhileStatement = d.ast.statement.DoWhileStatement!(Expression, Statement);
alias ForStatement = d.ast.statement.ForStatement!(Expression, Statement);
alias ReturnStatement = d.ast.statement.ReturnStatement!(Expression, Statement);
alias SwitchStatement = d.ast.statement.SwitchStatement!(Expression, Statement);
alias CaseStatement = d.ast.statement.CaseStatement!(CompileTimeExpression, Statement);
alias LabeledStatement = d.ast.statement.LabeledStatement!Statement;
alias SynchronizedStatement = d.ast.statement.SynchronizedStatement!Statement;
alias ScopeStatement = d.ast.statement.ScopeStatement!Statement;
alias ScopeKind = d.ast.statement.ScopeKind;
alias ThrowStatement = d.ast.statement.ThrowStatement!(Expression, Statement);

import d.ir.symbol;
alias CatchBlock = d.ast.statement.CatchBlock!(Class, Statement);

final:

/**
 * Symbols
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

