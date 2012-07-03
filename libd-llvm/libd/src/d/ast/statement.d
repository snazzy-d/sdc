module d.ast.statement;

import d.ast.base;

import sdc.location;

enum StatementType {
	EmptyStatement,
	BlockStatement,
	LabeledStatement,
	ExpressionStatement,
	DeclarationStatement,
	IfStatement,
	WhileStatement,
	DoStatement,
	ForStatement,
	ForeachStatement,
	SwitchStatement,
	CaseStatement,
	CaseRangeStatement,
	DefaultStatement,
	ContinueStatement,
	BreakStatement,
	ReturnStatement,
	GotoStatement,
	WithStatement,
	SynchronizedStatement,
	TryStatement,
	ScopeGuardStatement,
	ThrowStatement,
	AsmStatement,
	PragmaStatement,
	MixinStatement,
	ForeachRangeStatement,
	ConditionalStatement,
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
		super(location, StatementType.BlockStatement);
		
		this.statements = statements;
	}
}

