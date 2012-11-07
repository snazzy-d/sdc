module d.parser.statement;

import d.ast.declaration;
import d.ast.expression;
import d.ast.statement;
import d.ast.type;

import d.parser.ambiguous : isDeclaration;
import d.parser.base;
import d.parser.conditional;
import d.parser.declaration;
import d.parser.expression;
import d.parser.type;

import std.range;

Statement parseStatement(TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange) {
	Location location = trange.front.location;
	
	switch(trange.front.type) {
		case TokenType.OpenBrace :
			return trange.parseBlock();
		
		case TokenType.If :
			trange.popFront();
			trange.match(TokenType.OpenParen);
			
			auto condition = trange.parseExpression();
			
			trange.match(TokenType.CloseParen);
			
			auto then = trange.parseStatement();
			
			if(trange.front.type == TokenType.Else) {
				trange.popFront();
				auto elseStatement = trange.parseStatement();
				
				location.spanTo(elseStatement.location);
				
				return new IfElseStatement(location, condition, then, elseStatement);
			}
			
			location.spanTo(then.location);
			return new IfStatement(location, condition, then);
		
		case TokenType.While :
			trange.popFront();
			trange.match(TokenType.OpenParen);
			auto condition = trange.parseExpression();
			
			trange.match(TokenType.CloseParen);
			
			auto statement = trange.parseStatement();
			
			location.spanTo(statement.location);
			return new WhileStatement(location, condition, statement);
		
		case TokenType.Do :
			trange.popFront();
			
			auto statement = trange.parseStatement();
			
			trange.match(TokenType.While);
			trange.match(TokenType.OpenParen);
			auto condition = trange.parseExpression();
			
			trange.match(TokenType.CloseParen);
			
			location.spanTo(trange.front.location);
			trange.match(TokenType.Semicolon);
			
			return new DoWhileStatement(location, condition, statement);
		
		case TokenType.For :
			trange.popFront();
			
			trange.match(TokenType.OpenParen);
			
			Statement init;
			if(trange.front.type == TokenType.Semicolon) {
				init = new BlockStatement(trange.front.location, []);
				trange.popFront();
			} else {
				init = trange.parseStatement();
			}
			
			Expression condition;
			if(trange.front.type != TokenType.Semicolon) {
				condition = trange.parseExpression();
			}
			
			trange.match(TokenType.Semicolon);
			
			Expression increment;
			if(trange.front.type != TokenType.CloseParen) {
				increment = trange.parseExpression();
			}
			
			trange.match(TokenType.CloseParen);
			
			auto statement = trange.parseStatement();
			
			location.spanTo(statement.location);
			return new ForStatement(location, init, condition, increment, statement);
		
		case TokenType.Foreach, TokenType.ForeachReverse :
			trange.popFront();
			trange.match(TokenType.OpenParen);
			
			VariableDeclaration parseForeachListElement() {
				Location elementLocation = trange.front.location;
				
				auto lookahead = trange.save;
				Type type;
				switch(trange.front.type) {
					case TokenType.Ref :
						lookahead.popFront();
						
						if(lookahead.front.type == TokenType.Identifier) goto case TokenType.Identifier;
						
						goto default;
					
					case TokenType.Identifier :
						lookahead.popFront();
						
						if(lookahead.front.type == TokenType.Comma || lookahead.front.type == TokenType.Semicolon) {
							if(trange.front.type == TokenType.Ref) {
								trange.popFront();
							}
							
							type = new AutoType(trange.front.location);
							break;
						}
						
						goto default;
					
					default :
						type = trange.parseType();
				}
				
				auto name = trange.front.value;
				elementLocation.spanTo(trange.front.location);
				
				trange.match(TokenType.Identifier);
				
				assert(0, "yada yada foreach ?");
				
				// return new VariableDeclaration(elementLocation, type, name, ARGUMENT?);
			}
			
			VariableDeclaration[] tupleElements = [parseForeachListElement()];
			while(trange.front.type == TokenType.Comma) {
				trange.popFront();
				tupleElements ~= parseForeachListElement();
			}
			
			trange.match(TokenType.Semicolon);
			auto iterrated = trange.parseExpression();
			
			if(trange.front.type == TokenType.DoubleDot) {
				trange.popFront();
				trange.parseExpression();
			}
			
			trange.match(TokenType.CloseParen);
			
			auto statement = trange.parseStatement();
			location.spanTo(statement.location);
			
			return new ForeachStatement(location, tupleElements, iterrated, statement);
		
		case TokenType.Return :
			trange.popFront();
			
			Expression value;
			if(trange.front.type != TokenType.Semicolon) {
				value = trange.parseExpression();
			}
			
			location.spanTo(trange.front.location);
			trange.match(TokenType.Semicolon);
			
			return new ReturnStatement(location, value);
		
		case TokenType.Break :
			trange.popFront();
			
			if(trange.front.type == TokenType.Identifier) trange.popFront();
			
			location.spanTo(trange.front.location);
			trange.match(TokenType.Semicolon);
			
			return new BreakStatement(location);
		
		case TokenType.Continue :
			trange.popFront();
			
			if(trange.front.type == TokenType.Identifier) trange.popFront();
			
			location.spanTo(trange.front.location);
			trange.match(TokenType.Semicolon);
			
			return new ContinueStatement(location);
		
		case TokenType.Switch :
			trange.popFront();
			trange.match(TokenType.OpenParen);
			
			auto expression = trange.parseExpression();
			
			trange.match(TokenType.CloseParen);
			
			auto statement = trange.parseStatement();
			location.spanTo(statement.location);
			
			return new SwitchStatement(location, expression, statement);
		
		case TokenType.Case :
			trange.popFront();
			
			Expression[] cases = trange.parseArguments();
			
			location.spanTo(trange.front.location);
			trange.match(TokenType.Colon);
			
			return new CaseStatement(location, cases);
		
		case TokenType.Default :
			// Other labeled statement will jump here !
			auto label = trange.front.value;
			trange.popFront();
			trange.match(TokenType.Colon);
			
			Statement statement;
			if(trange.front.type != TokenType.CloseBrace) {
				statement = trange.parseStatement();
				location.spanTo(statement.location);
			} else {
				location.spanTo(trange.front.location);
				statement = new BlockStatement(location, []);
			}
			
			return new LabeledStatement(location, label, statement);
		
		case TokenType.Identifier :
			auto lookahead = trange.save;
			lookahead.popFront();
			
			if(lookahead.front.type == TokenType.Colon) {
				goto case TokenType.Default;
			}
			
			// If it is not a labeled statement, then it is a declaration or an expression.
			goto default;
		
		case TokenType.Goto :
			trange.popFront();
			
			string label;
			switch(trange.front.type) {
				case TokenType.Identifier :
				case TokenType.Default :
				case TokenType.Case :
					label = trange.front.value;
					trange.popFront();
					break;
				
				default :
					trange.match(TokenType.Identifier);
			}
			
			trange.match(TokenType.Semicolon);
			
			location.spanTo(trange.front.location);
			
			return new GotoStatement(location, label);
		
		case TokenType.Synchronized :
			trange.popFront();
			if(trange.front.type == TokenType.OpenParen) {
				trange.popFront();
				
				trange.parseExpression();
				
				trange.match(TokenType.CloseParen);
			}
			
			auto statement = trange.parseStatement();
			location.spanTo(statement.location);
			
			return new SynchronizedStatement(location, statement);
		
		case TokenType.Try :
			trange.popFront();
			
			auto statement = trange.parseStatement();
			
			CatchBlock[] catches;
			while(trange.front.type == TokenType.Catch) {
				auto catchLocation = trange.front.location;
				trange.popFront();
				
				if(trange.front.type == TokenType.OpenParen) {
					trange.popFront();
					auto type = trange.parseBasicType();
					string name;
					
					if(trange.front.type == TokenType.Identifier) {
						name = trange.front.value;
						trange.popFront();
					}
					
					trange.match(TokenType.CloseParen);
					
					auto catchStatement = trange.parseStatement();
					
					location.spanTo(catchStatement.location);
					catches ~= new CatchBlock(location, type, name, catchStatement);
				} else {
					// TODO: handle final catches ?
					trange.parseStatement();
					break;
				}
			}
			
			if(trange.front.type == TokenType.Finally) {
				trange.popFront();
				auto finallyStatement = trange.parseStatement();
				
				location.spanTo(finallyStatement.location);
				return new TryFinallyStatement(location, statement, [], finallyStatement);
			}
			
			location.spanTo(catches.back.location);
			return new TryStatement(location, statement, []);
		
		case TokenType.Throw :
			trange.popFront();
			auto value = trange.parseExpression();
			
			location.spanTo(trange.front.location);
			trange.match(TokenType.Semicolon);
			
			return new ThrowStatement(location, value);
		
		case TokenType.Mixin :
			trange.popFront();
			trange.match(TokenType.OpenParen);
			trange.parseExpression();
			trange.match(TokenType.CloseParen);
			trange.match(TokenType.Semicolon);
			break;
		
		case TokenType.Static :
			auto lookahead = trange.save;
			lookahead.popFront();
			
			switch(lookahead.front.type) {
				case TokenType.If :
					return trange.parseStaticIf!Statement();
				
				case TokenType.Assert :
					trange.popFrontN(2);
					trange.match(TokenType.OpenParen);
					
					auto arguments = trange.parseArguments();
					
					trange.match(TokenType.CloseParen);
					
					location.spanTo(trange.front.location);
					trange.match(TokenType.Semicolon);
					
					return new StaticAssertStatement(location, arguments);
				
				default :
					auto declaration = trange.parseDeclaration();
					return new DeclarationStatement(declaration);
			}
		
		case TokenType.Version :
			return trange.parseVersion!Statement();
		
		case TokenType.Debug :
			return trange.parseDebug!Statement();
		
		default :
			if(trange.isDeclaration()) {
				auto declaration = trange.parseDeclaration();
				return new DeclarationStatement(declaration);
			} else {
				auto expression = trange.parseExpression();
				trange.match(TokenType.Semicolon);
				
				return new ExpressionStatement(expression);
			}
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

