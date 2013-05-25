/**
 * This module is used to clone AST.
 */
module d.semantic.clone;

import d.semantic.semantic;

import d.ast.conditional;
import d.ast.declaration;
import d.ast.dmodule;
import d.ast.dscope;
import d.ast.identifier;

import std.algorithm;
import std.array;

import d.ast.adt;
import d.ast.base;
import d.ast.declaration;
import d.ast.dfunction;
import d.ast.dtemplate;
import d.ast.expression;
import d.ast.statement;
import d.ast.type;

final:

class ClonePass {
	private DeclarationVisitor declarationVisitor;
	private StatementVisitor statementVisitor;
	private ExpressionVisitor expressionVisitor;
	private TypeVisitor typeVisitor;
	private IdentifierVisitor identifierVisitor;
	
	this() {
		declarationVisitor	= new DeclarationVisitor(this);
		statementVisitor	= new StatementVisitor(this);
		expressionVisitor	= new ExpressionVisitor(this);
		typeVisitor			= new TypeVisitor(this);
		identifierVisitor	= new IdentifierVisitor(this);
	}
	
	Module visit(Module m) {
		assert(0, "Not implemented.");
		// return new Module(m.location, visit(m.moduleDeclaration), m.declarations.map!(d => visit(d)).array());
	}
	
	auto visit(Declaration decl) {
		return declarationVisitor.visit(decl);
	}
	
	auto visit(Statement stmt) {
		return statementVisitor.visit(stmt);
	}
	
	auto visit(Expression e) {
		return expressionVisitor.visit(e);
	}
	
	auto visit(Type t) {
		return typeVisitor.visit(t);
	}
	
	auto visit(Identifier i) {
		return identifierVisitor.visit(i);
	}
}

/**
 * Clone declaration.
 */
class DeclarationVisitor {
	private ClonePass pass;
	alias pass this;
	
	this(ClonePass pass) {
		this.pass = pass;
	}
	
	Declaration visit(Declaration d) {
		return this.dispatch(d);
	}
	
	FunctionDeclaration visit(FunctionDeclaration d) {
		auto parameters = cast(Parameter[]) d.parameters.map!(p => visit(p)).array();
		auto clone = new FunctionDeclaration(d.location, d.name, d.linkage, pass.visit(d.returnType), parameters, d.isVariadic, d.fbody?(cast(BlockStatement) pass.visit(d.fbody)):null);
		
		clone.isStatic = d.isStatic;
		clone.isEnum = d.isEnum;
		
		return clone;
	}
	
	Parameter visit(Parameter d) {
		return new Parameter(d.location, d.name, pass.visit(d.type));
	}
	
	VariableDeclaration visit(VariableDeclaration d) {
		auto clone = new VariableDeclaration(d.location, pass.visit(d.type), d.name, pass.visit(d.value));
		
		clone.isStatic = d.isStatic;
		clone.isEnum = d.isEnum;
		
		return clone;
	}
	
	VariablesDeclaration visit(VariablesDeclaration d) {
		return new VariablesDeclaration(d.location, d.variables.map!(var => visit(var)).array());
	}
	
	AliasDeclaration visit(AliasDeclaration d) {
		return new AliasDeclaration(d.location, d.name, pass.visit(d.type));
	}
	
	StaticIf!Declaration visit(StaticIf!Declaration d) {
		auto condition = pass.visit(d.condition);
		
		auto items = d.items.map!(i => visit(i)).array();
		auto elseItems = d.elseItems.map!(i => visit(i)).array();
		
		return new StaticIf!Declaration(d.location, condition, items, elseItems);
	}
}

/**
 * Clone statement.
 */
class StatementVisitor {
	private ClonePass pass;
	alias pass this;
	
	this(ClonePass pass) {
		this.pass = pass;
	}
	
	Statement visit(Statement s) {
		return this.dispatch(s);
	}
	
	Statement visit(BlockStatement s) {
		auto statements = s.statements.map!(s => visit(s)).array();
		
		return new BlockStatement(s.location, statements);
	}
	
	Statement visit(DeclarationStatement s) {
		return new DeclarationStatement(pass.visit(s.declaration));
	}
	
	Statement visit(ForStatement s) {
		auto initialize = visit(s.initialize);
		
		auto condition = pass.visit(s.condition);
		auto increment = pass.visit(s.increment);
		
		auto statement = visit(s.statement);
		
		return new ForStatement(s.location, initialize, condition, increment, statement);
	}
	
	Statement visit(ReturnStatement s) {
		return new ReturnStatement(s.location, pass.visit(s.value));
	}
	
	Statement visit(StaticIf!Statement s) {
		auto condition = pass.visit(s.condition);
		
		auto items = s.items.map!(i => visit(i)).array();
		auto elseItems = s.elseItems.map!(i => visit(i)).array();
		
		return new StaticIf!Statement(s.location, condition, items, elseItems);
	}
	
	Statement visit(Mixin!Statement s) {
		return new Mixin!Statement(s.location, pass.visit(s.value));
	}
}

/**
 * Clone expression.
 */
class ExpressionVisitor {
	private ClonePass pass;
	alias pass this;
	
	this(ClonePass pass) {
		this.pass = pass;
	}
	
	Expression visit(Expression e) {
		return this.dispatch(e);
	}
	
	Expression visit(ParenExpression e) {
		return new ParenExpression(e.location, visit(e.expression));
	}
	
	Expression visit(BooleanLiteral e) {
		return new BooleanLiteral(e.location, e.value);
	}
	
	private auto handleLiteral(LiteralExpression)(LiteralExpression e) {
		return new LiteralExpression(e.location, e.value, cast(typeof(null)) pass.visit(e.type));
	}
	
	Expression visit(IntegerLiteral!true e) {
		return handleLiteral(e);
	}
	
	Expression visit(IntegerLiteral!false e) {
		return handleLiteral(e);
	}
	
	Expression visit(FloatLiteral e) {
		return handleLiteral(e);
	}
	
	Expression visit(CharacterLiteral e) {
		return handleLiteral(e);
	}
	
	Expression visit(StringLiteral e) {
		return new StringLiteral(e.location, e.value);
	}
	
	private auto handleBinaryExpression(string operation)(BinaryExpression!operation e) {
		return new BinaryExpression!operation(e.location, visit(e.lhs), visit(e.rhs));
	}
	
	Expression visit(CommaExpression e) {
		return handleBinaryExpression(e);
	}
	
	Expression visit(AssignExpression e) {
		return handleBinaryExpression(e);
	}
	
	Expression visit(AddExpression e) {
		return handleBinaryExpression(e);
	}
	
	Expression visit(SubExpression e) {
		return handleBinaryExpression(e);
	}
	
	Expression visit(AddAssignExpression e) {
		return handleBinaryExpression(e);
	}
	
	Expression visit(SubAssignExpression e) {
		return handleBinaryExpression(e);
	}
	
	Expression visit(MulExpression e) {
		return handleBinaryExpression(e);
	}
	
	Expression visit(DivExpression e) {
		return handleBinaryExpression(e);
	}
	
	Expression visit(ModExpression e) {
		return handleBinaryExpression(e);
	}
	
	Expression visit(EqualityExpression e) {
		return handleBinaryExpression(e);
	}
	
	Expression visit(NotEqualityExpression e) {
		return handleBinaryExpression(e);
	}
	
	Expression visit(GreaterExpression e) {
		return handleBinaryExpression(e);
	}
	
	Expression visit(GreaterEqualExpression e) {
		return handleBinaryExpression(e);
	}
	
	Expression visit(LessExpression e) {
		return handleBinaryExpression(e);
	}
	
	Expression visit(LessEqualExpression e) {
		return handleBinaryExpression(e);
	}
	
	Expression visit(LogicalAndExpression e) {
		return handleBinaryExpression(e);
	}
	
	Expression visit(LogicalOrExpression e) {
		return handleBinaryExpression(e);
	}
	
	Expression visit(CastExpression e) {
		return new CastExpression(e.location, pass.visit(e.type), visit(e.expression));
	}
	
	Expression visit(CallExpression e) {
		auto arguments = e.arguments.map!(a => visit(a)).array();
		
		return new CallExpression(e.location, visit(e.callee), arguments);
	}
	
	Expression visit(IdentifierExpression e) {
		return new IdentifierExpression(pass.visit(e.identifier));
	}
	
	Expression visit(DefaultInitializer e) {
		return new DefaultInitializer(pass.visit(e.type));
	}
}

/**
 * Clone type.
 */
class TypeVisitor {
	private ClonePass pass;
	alias pass this;
	
	this(ClonePass pass) {
		this.pass = pass;
	}
	
	Type visit(Type t) {
		auto ret = this.dispatch(t);
		ret.qualifier = t.qualifier;
		
		return ret;
	}
	
	Type visit(BooleanType t) {
		return new BooleanType(t.location);
	}
	
	private auto handleBasicType(BasicType)(BasicType t) {
		return new BasicType(t.location, t.type);
	}
	
	Type visit(IntegerType t) {
		return handleBasicType(t);
	}
	
	Type visit(FloatType t) {
		return handleBasicType(t);
	}
	
	Type visit(CharacterType t) {
		return handleBasicType(t);
	}
	
	Type visit(VoidType t) {
		return new VoidType(t.location);
	}
	
	Type visit(FunctionType t) {
		auto parameters = cast(Parameter[]) t.parameters.map!(p => pass.visit(p)).array();
		return new FunctionType(t.location, t.linkage, visit(t.returnType), parameters, t.isVariadic);
	}
	
	Type visit(IdentifierType t) {
		return new IdentifierType(pass.visit(t.identifier));
	}
	
	Type visit(AutoType t) {
		return new AutoType(t.location);
	}
}

/**
 * Clone identifier.
 */
class IdentifierVisitor {
	private ClonePass pass;
	alias pass this;
	
	this(ClonePass pass) {
		this.pass = pass;
	}
	
	Identifier visit(Identifier i) {
		return this.dispatch(i);
	}
	
	Identifier visit(BasicIdentifier i) {
		return new BasicIdentifier(i.location, i.name);
	}
	
	Identifier visit(IdentifierDotIdentifier i) {
		return new IdentifierDotIdentifier(i.location, i.name, visit(i.identifier));
	}
}

