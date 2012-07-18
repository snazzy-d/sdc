module d.ast.visitor;

import d.ast.expression;

interface ExpressionVisitor {
	void visit(IntegerLiteral!int);
	void visit(IntegerLiteral!uint);
	void visit(IntegerLiteral!long);
	void visit(IntegerLiteral!ulong);
	
	void visit(AdditionExpression);
	void visit(SubstractionExpression);
	void visit(ConcatExpression);
	void visit(MultiplicationExpression);
	void visit(DivisionExpression);
	void visit(ModulusExpression);
	void visit(PowExpression);
}

import d.ast.statement;

interface StatementVisitor {
	void visit(Declaration);
	
	void visit(BlockStatement);
	void visit(ReturnStatement);
}

import d.ast.declaration;
import d.ast.dfunction;

interface DeclarationVisitor {
	void visit(FunctionDefinition);
	void visit(VariablesDeclaration);
	void visit(VariableDeclaration);
}

