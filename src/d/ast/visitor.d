module d.ast.visitor;

import d.ast.expression;

interface ExpressionVisitor {
	void visit(IntegerLiteral!int);
	void visit(IntegerLiteral!uint);
	void visit(IntegerLiteral!long);
	void visit(IntegerLiteral!ulong);
}

import d.ast.statement;

interface StatementVisitor {
	void visit(ReturnStatement);
}

import d.ast.declaration;
import d.ast.dfunction;

interface DeclarationVisitor {
	void visit(FunctionDefinition);
}

