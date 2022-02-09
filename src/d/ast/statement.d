module d.ast.statement;

import d.ast.declaration;
import d.ast.expression;

import d.common.node;

import source.context;

class Statement : Node {
	this(Location location) {
		super(location);
	}

	string toString(const Context) const {
		assert(0, "toString not implement for " ~ typeid(this).toString());
	}
}

final:

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
 * Expressions
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
 * indentifier * identifier kind of things
 */
class IdentifierStarNameStatement : Statement {
	import source.name;
	Name name;

	import d.ast.identifier;
	Identifier identifier;
	AstExpression value;

	this(Location location, Identifier identifier, Name name,
	     AstExpression value) {
		super(location);

		this.identifier = identifier;
		this.name = name;
		this.value = value;
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

	this(Location location, AstExpression condition, Statement then,
	     Statement elseStatement) {
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

	this(Location location, Statement initialize, AstExpression condition,
	     AstExpression increment, Statement statement) {
		super(location);

		this.initialize = initialize;
		this.condition = condition;
		this.increment = increment;
		this.statement = statement;
	}
}

/**
 * foreach statements
 */
class ForeachStatement : Statement {
	ParamDecl[] tupleElements;
	AstExpression iterated;
	Statement statement;
	bool reverse;

	this(Location location, ParamDecl[] tupleElements, AstExpression iterated,
	     Statement statement, bool reverse) {
		super(location);

		this.tupleElements = tupleElements;
		this.iterated = iterated;
		this.statement = statement;
		this.reverse = reverse;
	}
}

/**
 * foreach statements
 */
class ForeachRangeStatement : Statement {
	ParamDecl[] tupleElements;
	AstExpression start;
	AstExpression stop;
	Statement statement;
	bool reverse;

	this(Location location, ParamDecl[] tupleElements, AstExpression start,
	     AstExpression stop, Statement statement, bool reverse) {
		super(location);

		this.tupleElements = tupleElements;
		this.start = start;
		this.stop = stop;
		this.statement = statement;
		this.reverse = reverse;
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
	Statement statement;

	this(Location location, AstExpression[] cases, Statement statement) {
		super(location);

		this.cases = cases;
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
 * goto statements
 */
class GotoStatement : Statement {
	import source.name;
	Name label;

	this(Location location, Name label) {
		super(location);

		this.label = label;
	}
}

/**
 * Label: statement
 */
class LabeledStatement : Statement {
	import source.name;
	Name label;

	Statement statement;

	this(Location location, Name label, Statement statement) {
		super(location);

		this.label = label;
		this.statement = statement;
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
 * Scope statement
 */
enum ScopeKind {
	Success,
	Exit,
	Failure,
}

class ScopeStatement : Statement {
	import std.bitmanip;
	mixin(taggedClassRef!(
		// sdfmt off
		Statement, "statement",
		ScopeKind, "kind", 2,
		// sdfmt on
	));

	this(Location location, ScopeKind kind, Statement statement) {
		super(location);

		this.kind = kind;
		this.statement = statement;
	}
}

/**
 * assert
 */
class AssertStatement : Statement {
	AstExpression condition;
	AstExpression message;

	this(Location location, AstExpression condition, AstExpression message) {
		super(location);

		this.condition = condition;
		this.message = message;
	}

	override string toString(const Context c) const {
		auto cstr = condition.toString(c);
		auto mstr = message ? ", " ~ message.toString(c) : "";

		return "assert(" ~ cstr ~ mstr ~ ")";
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
 * try statements
 */
class TryStatement : Statement {
	Statement statement;
	CatchBlock[] catches;

	// nullable
	Statement finallyBlock;

	this(Location location, Statement statement, CatchBlock[] catches,
	     Statement finallyBlock) {
		super(location);

		this.statement = statement;
		this.catches = catches;
		this.finallyBlock = finallyBlock;
	}
}

struct CatchBlock {
	Location location;

	import source.name;
	Name name;

	import d.ast.identifier;
	Identifier type;
	Statement statement;

	this(Location location, Identifier type, Name name, Statement statement) {
		this.location = location;
		this.name = name;
		this.type = type;
		this.statement = statement;
	}
}
