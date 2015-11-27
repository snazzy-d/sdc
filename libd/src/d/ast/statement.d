module d.ast.statement;

import d.ast.declaration;
import d.ast.expression;

import d.common.node;

class AstStatement : Node {
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
class BlockStatement(S) : S if (is(S : AstStatement)) {
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
class ExpressionStatement(E, S) : S if (is(E : AstExpression) && is(S : AstStatement)) {
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
 * indentifier * identifier kind of things
 */
class IdentifierStarIdentifierStatement : AstStatement {
	import d.context.name;
	Name name;
	
	Identifier identifier;
	AstExpression value;
	
	this(
		Location location,
		Identifier identifier,
		Name name,
		AstExpression value,
	) {
		super(location);
		
		this.identifier = identifier;
		this.name = name;
		this.value = value;
	}
}

/**
 * if statements.
 */
class IfStatement(E, S) : S if (is(E : AstExpression) && is(S : AstStatement)) {
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
class WhileStatement(E, S) : S if (is(E : AstExpression) && is(S : AstStatement)) {
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
class DoWhileStatement(E, S) : S if(is(E : AstExpression) && is(S : AstStatement)) {
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
class ForStatement(E, S) : S if (is(E : AstExpression) && is(S : AstStatement)) {
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
 * foreach statements
 */
class ForeachStatement : AstStatement {
	ParamDecl[] tupleElements;
	AstExpression iterated;
	AstStatement statement;
	bool reverse;
	
	this(
		Location location,
		ParamDecl[] tupleElements,
		AstExpression iterated,
		AstStatement statement,
		bool reverse,
	) {
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
class ForeachRangeStatement : AstStatement {
	ParamDecl[] tupleElements;
	AstExpression start;
	AstExpression stop;
	AstStatement statement;
	bool reverse;
	
	this(
		Location location,
		ParamDecl[] tupleElements,
		AstExpression start,
		AstExpression stop,
		AstStatement statement,
		bool reverse,
	) {
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
class ReturnStatement(E, S) : S if (is(E : AstExpression) && is(S : AstStatement)) {
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
class SwitchStatement(E, S) : S if (is(E : AstExpression) && is(S : AstStatement)) {
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
class CaseStatement(E, S) : S if (is(E : AstExpression) && is(S : AstStatement)) {
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
class LabeledStatement(S) : S if (is(S : AstStatement)) {
	import d.context.name;
	Name label;

	S statement;
	
	this(Location location, Name label, S statement) {
		super(location);
		
		this.label = label;
		this.statement = statement;
	}
}

alias AstLabeledStatement = LabeledStatement!AstStatement;

/**
 * synchronized statements
 */
class SynchronizedStatement(S) : S if (is(S : AstStatement)) {
	S statement;
	
	this(Location location, S statement) {
		super(location);
		
		this.statement = statement;
	}
}

alias AstSynchronizedStatement = SynchronizedStatement!AstStatement;

/**
 * Scope statement
 */
enum ScopeKind {
	Exit,
	Success,
	Failure,
}

class ScopeStatement(S) : S if (is(S : AstStatement)) {
	ScopeKind kind;
	S statement;
	
	this(Location location, ScopeKind kind, S statement) {
		super(location);
		
		this.kind = kind;
		this.statement = statement;
	}
}

alias AstScopeStatement = ScopeStatement!AstStatement;

/**
 * assert
 */
class AssertStatement(E, S) : S if (is(E : AstExpression) && is(S : AstStatement)) {
	E condition;
	E message;
	
	this(Location location, E condition, E message) {
		super(location);
		
		this.condition = condition;
		this.message = message;
	}
	
	override string toString(const Context c) const {
		auto cstr = condition.toString(c);
		auto mstr = message
			? ", " ~ message.toString(c)
			: "";
		
		return "assert(" ~ cstr ~ mstr ~ ")";
	}
}

alias AstAssertStatement = AssertStatement!(AstExpression, AstStatement);

/**
 * throw statements
 */
class ThrowStatement(E, S) : S if (is(E : AstExpression) && is(S : AstStatement)) {
	E value;
	
	this(Location location, E value) {
		super(location);
		
		this.value = value;
	}
}

alias AstThrowStatement = ThrowStatement!(AstExpression, AstStatement);

/**
 * try statements
 */
class AstTryStatement : AstStatement {
	AstStatement statement;
	AstCatchBlock[] catches;
	
	// nullable
	AstStatement finallyBlock;
	
	this(
		Location location,
		AstStatement statement,
		AstCatchBlock[] catches,
		AstStatement finallyBlock,
	) {
		super(location);
		
		this.statement = statement;
		this.catches = catches;
		this.finallyBlock = finallyBlock;
	}
}

struct CatchBlock(T, S) if(is(S : AstStatement)) {
	Location location;

	import d.context.name;
	Name name;
	
	T type;
	S statement;
	
	this(Location location, T type, Name name, S statement) {
		this.location = location;
		this.name = name;
		this.type = type;
		this.statement = statement;
	}
}

import d.ast.identifier;
alias AstCatchBlock = CatchBlock!(d.ast.identifier.Identifier, AstStatement);
