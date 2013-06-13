module d.parser.statement;

import d.ast.declaration;
import d.ast.expression;
import d.ast.statement;
import d.ast.type;

import d.parser.ambiguous;
import d.parser.base;
import d.parser.conditional;
import d.parser.declaration;
import d.parser.expression;
import d.parser.type;

import std.range;

Statement parseStatement(TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange) {
	Location location = trange.front.location;
	
	switch(trange.front.type) with(TokenType) {
		case OpenBrace :
			return trange.parseBlock();
		
		case If :
			trange.popFront();
			trange.match(OpenParen);
			
			auto condition = trange.parseExpression();
			
			trange.match(CloseParen);
			
			auto then = trange.parseStatement();
			
			Statement elseStatement;
			if(trange.front.type == Else) {
				trange.popFront();
				
				elseStatement = trange.parseStatement();
				
				location.spanTo(elseStatement.location);
			} else {
				location.spanTo(then.location);
			}
			
			return new IfStatement(location, condition, then, elseStatement);
		
		case While :
			trange.popFront();
			trange.match(OpenParen);
			auto condition = trange.parseExpression();
			
			trange.match(CloseParen);
			
			auto statement = trange.parseStatement();
			
			location.spanTo(statement.location);
			return new WhileStatement(location, condition, statement);
		
		case TokenType.Do :
			trange.popFront();
			
			auto statement = trange.parseStatement();
			
			trange.match(While);
			trange.match(OpenParen);
			auto condition = trange.parseExpression();
			
			trange.match(CloseParen);
			
			location.spanTo(trange.front.location);
			trange.match(Semicolon);
			
			return new DoWhileStatement(location, condition, statement);
		
		case TokenType.For :
			trange.popFront();
			
			trange.match(OpenParen);
			
			Statement init;
			if(trange.front.type == Semicolon) {
				init = new BlockStatement(trange.front.location, []);
				trange.popFront();
			} else {
				init = trange.parseStatement();
			}
			
			AstExpression condition;
			if(trange.front.type != Semicolon) {
				condition = trange.parseExpression();
			}
			
			trange.match(Semicolon);
			
			AstExpression increment;
			if(trange.front.type != CloseParen) {
				increment = trange.parseExpression();
			}
			
			trange.match(CloseParen);
			
			auto statement = trange.parseStatement();
			
			location.spanTo(statement.location);
			return new ForStatement(location, init, condition, increment, statement);
		
		case Foreach, ForeachReverse :
			trange.popFront();
			trange.match(OpenParen);
			
			VariableDeclaration parseForeachListElement() {
				Location elementLocation = trange.front.location;
				
				auto lookahead = trange.save;
				QualAstType type;
				switch(trange.front.type) {
					case Ref :
						lookahead.popFront();
						
						if(lookahead.front.type == Identifier) goto case Identifier;
						
						goto default;
					
					case Identifier :
						lookahead.popFront();
						
						if(lookahead.front.type == Comma || lookahead.front.type == Semicolon) {
							if(trange.front.type == Ref) {
								trange.popFront();
							}
							
							type = QualAstType(new AutoType());
							break;
						}
						
						goto default;
					
					default :
						type = trange.parseType();
				}
				
				auto name = trange.front.value;
				elementLocation.spanTo(trange.front.location);
				
				trange.match(Identifier);
				
				assert(0, "yada yada foreach ?");
				
				// return new VariableDeclaration(elementLocation, type, name, ARGUMENT?);
			}
			
			VariableDeclaration[] tupleElements = [parseForeachListElement()];
			while(trange.front.type == Comma) {
				trange.popFront();
				tupleElements ~= parseForeachListElement();
			}
			
			trange.match(Semicolon);
			auto iterrated = trange.parseExpression();
			
			if(trange.front.type == DoubleDot) {
				trange.popFront();
				trange.parseExpression();
			}
			
			trange.match(CloseParen);
			
			auto statement = trange.parseStatement();
			location.spanTo(statement.location);
			
			return new ForeachStatement(location, tupleElements, iterrated, statement);
		
		case Return :
			trange.popFront();
			
			AstExpression value;
			if(trange.front.type != Semicolon) {
				value = trange.parseExpression();
			}
			
			location.spanTo(trange.front.location);
			trange.match(Semicolon);
			
			return new ReturnStatement(location, value);
		
		case Break :
			trange.popFront();
			
			if(trange.front.type == Identifier) trange.popFront();
			
			location.spanTo(trange.front.location);
			trange.match(Semicolon);
			
			return new BreakStatement(location);
		
		case Continue :
			trange.popFront();
			
			if(trange.front.type == Identifier) trange.popFront();
			
			location.spanTo(trange.front.location);
			trange.match(Semicolon);
			
			return new ContinueStatement(location);
		
		case Switch :
			trange.popFront();
			trange.match(OpenParen);
			
			auto expression = trange.parseExpression();
			
			trange.match(CloseParen);
			
			auto statement = trange.parseStatement();
			location.spanTo(statement.location);
			
			return new SwitchStatement(location, expression, statement);
		
		case Case :
			trange.popFront();
			
			AstExpression[] cases = trange.parseArguments();
			
			location.spanTo(trange.front.location);
			trange.match(Colon);
			
			return new CaseStatement(location, cases);
		
		case Default :
			// Other labeled statement will jump here !
			auto label = trange.front.value;
			trange.popFront();
			trange.match(Colon);
			
			Statement statement;
			if(trange.front.type != CloseBrace) {
				statement = trange.parseStatement();
				location.spanTo(statement.location);
			} else {
				location.spanTo(trange.front.location);
				statement = new BlockStatement(location, []);
			}
			
			return new LabeledStatement(location, label, statement);
		
		case Identifier :
			auto lookahead = trange.save;
			lookahead.popFront();
			
			if(lookahead.front.type == Colon) {
				goto case Default;
			}
			
			// If it is not a labeled statement, then it is a declaration or an expression.
			goto default;
		
		case Goto :
			trange.popFront();
			
			string label;
			switch(trange.front.type) {
				case Identifier :
				case Default :
				case Case :
					label = trange.front.value;
					trange.popFront();
					break;
				
				default :
					trange.match(Identifier);
			}
			
			trange.match(Semicolon);
			
			location.spanTo(trange.front.location);
			
			return new GotoStatement(location, label);
		
		case Synchronized :
			trange.popFront();
			if(trange.front.type == OpenParen) {
				trange.popFront();
				
				trange.parseExpression();
				
				trange.match(CloseParen);
			}
			
			auto statement = trange.parseStatement();
			location.spanTo(statement.location);
			
			return new SynchronizedStatement(location, statement);
		
		case Try :
			trange.popFront();
			
			auto statement = trange.parseStatement();
			
			CatchBlock[] catches;
			while(trange.front.type == Catch) {
				auto catchLocation = trange.front.location;
				trange.popFront();
				
				if(trange.front.type == OpenParen) {
					trange.popFront();
					auto type = trange.parseBasicType();
					string name;
					
					if(trange.front.type == Identifier) {
						name = trange.front.value;
						trange.popFront();
					}
					
					trange.match(CloseParen);
					
					auto catchStatement = trange.parseStatement();
					
					location.spanTo(catchStatement.location);
					catches ~= new CatchBlock(location, type, name, catchStatement);
				} else {
					// TODO: handle final catches ?
					trange.parseStatement();
					break;
				}
			}
			
			if(trange.front.type == Finally) {
				trange.popFront();
				auto finallyStatement = trange.parseStatement();
				
				location.spanTo(finallyStatement.location);
				return new TryFinallyStatement(location, statement, [], finallyStatement);
			}
			
			location.spanTo(catches.back.location);
			return new TryStatement(location, statement, []);
		
		case Throw :
			trange.popFront();
			auto value = trange.parseExpression();
			
			location.spanTo(trange.front.location);
			trange.match(Semicolon);
			
			return new ThrowStatement(location, value);
		
		case Mixin :
			return trange.parseMixin!Statement();
		
		case Static :
			auto lookahead = trange.save;
			lookahead.popFront();
			
			switch(lookahead.front.type) {
				case If :
					return trange.parseStaticIf!Statement();
				
				case Assert :
					trange.popFrontN(2);
					trange.match(OpenParen);
					
					auto arguments = trange.parseArguments();
					
					trange.match(CloseParen);
					
					location.spanTo(trange.front.location);
					trange.match(Semicolon);
					
					return new StaticAssertStatement(location, arguments);
				
				default :
					auto declaration = trange.parseDeclaration();
					return new DeclarationStatement(declaration);
			}
		
		case Version :
			return trange.parseVersion!Statement();
		
		case Debug :
			return trange.parseDebug!Statement();
		
		default :
			return trange.parseDeclarationOrExpression!(delegate Statement(parsed) {
				alias typeof(parsed) caseType;
				
				static if(is(caseType : AstExpression)) {
					trange.match(Semicolon);
					return new ExpressionStatement(parsed);
				} else {
					return new DeclarationStatement(parsed);
				}
			})();
	}
	
	assert(0);
}

BlockStatement parseBlock(TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange) {
	Location location = trange.front.location;
	
	trange.match(TokenType.OpenBrace);
	
	Statement[] statements;
	
	while(trange.front.type != TokenType.CloseBrace) {
		statements ~= trange.parseStatement();
	}
	
	location.spanTo(trange.front.location);
	trange.popFront();
	
	return new BlockStatement(location, statements);
}

