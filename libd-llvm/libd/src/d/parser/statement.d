module d.parser.statement;

import d.ast.declaration;
import d.ast.expression;
import d.ast.statement;
import d.ast.type;

import d.ir.statement;

import d.parser.ambiguous;
import d.parser.base;
import d.parser.conditional;
import d.parser.declaration;
import d.parser.expression;
import d.parser.type;

import std.range;

AstStatement parseStatement(TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange) {
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
			
			AstStatement elseStatement;
			if(trange.front.type == Else) {
				trange.popFront();
				
				elseStatement = trange.parseStatement();
				
				location.spanTo(elseStatement.location);
			} else {
				location.spanTo(then.location);
			}
			
			return new AstIfStatement(location, condition, then, elseStatement);
		
		case While :
			trange.popFront();
			trange.match(OpenParen);
			auto condition = trange.parseExpression();
			
			trange.match(CloseParen);
			
			auto statement = trange.parseStatement();
			
			location.spanTo(statement.location);
			return new AstWhileStatement(location, condition, statement);
		
		case Do :
			trange.popFront();
			
			auto statement = trange.parseStatement();
			
			trange.match(While);
			trange.match(OpenParen);
			auto condition = trange.parseExpression();
			
			trange.match(CloseParen);
			
			location.spanTo(trange.front.location);
			trange.match(Semicolon);
			
			return new AstDoWhileStatement(location, condition, statement);
		
		case For :
			trange.popFront();
			
			trange.match(OpenParen);
			
			AstStatement init;
			if(trange.front.type != Semicolon) {
				init = trange.parseStatement();
			} else {
				init = new AstBlockStatement(trange.front.location, []);
				trange.popFront();
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
			return new AstForStatement(location, init, condition, increment, statement);
		
		case Foreach, ForeachReverse :
			bool reverse = (trange.front.type == ForeachReverse);
			trange.popFront();
			trange.match(OpenParen);
			
			ParamDecl parseForeachListElement() {
				Location elementLocation = trange.front.location;
				
				bool isRef = trange.front.type == Ref;
				if (isRef) {
					trange.popFront();
				}
				
				bool parseType = true;
				// If we have an idientifer, check if the type is implicit.
				if (trange.front.type == Identifier) {
						auto lookahead = trange.save;
						lookahead.popFront();
						if (lookahead.front.type == Comma || lookahead.front.type == Semicolon) {
							parseType = false;
						}
				}
				
				auto type = parseType
					? trange.parseType()
					: AstType.getAuto();
				
				auto name = trange.front.name;
				elementLocation.spanTo(trange.front.location);
				
				trange.match(Identifier);
				
				return ParamDecl(elementLocation, type.getParamType(isRef, false), name, null);
			}
			
			ParamDecl[] tupleElements = [parseForeachListElement()];
			while(trange.front.type == Comma) {
				trange.popFront();
				tupleElements ~= parseForeachListElement();
			}
			
			trange.match(Semicolon);
			auto iterrated = trange.parseExpression();
			
			bool isRange = trange.front.type == DoubleDot;
			
			AstExpression endOfRange;
			if (isRange) {
				trange.popFront();
				endOfRange = trange.parseExpression();
			}
			
			trange.match(CloseParen);
			
			auto statement = trange.parseStatement();
			location.spanTo(statement.location);
			
			return isRange
				? new ForeachRangeStatement(location, tupleElements, iterrated, endOfRange, statement, reverse)
				: new ForeachStatement(location, tupleElements, iterrated, statement, reverse);
		
		case Return :
			trange.popFront();
			
			AstExpression value;
			if(trange.front.type != Semicolon) {
				value = trange.parseExpression();
			}
			
			location.spanTo(trange.front.location);
			trange.match(Semicolon);
			
			return new AstReturnStatement(location, value);
		
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
			
			return new AstSwitchStatement(location, expression, statement);
		
		case Case :
			trange.popFront();
			
			AstExpression[] cases = trange.parseArguments();
			
			location.spanTo(trange.front.location);
			trange.match(Colon);
			
			return new AstCaseStatement(location, cases);
		
		case Default :
			// Other labeled statement will jump here !
			auto label = trange.front.name;
			trange.popFront();
			trange.match(Colon);
			
			AstStatement statement;
			if (trange.front.type != CloseBrace) {
				statement = trange.parseStatement();
				location.spanTo(statement.location);
			} else {
				location.spanTo(trange.front.location);
				statement = new AstBlockStatement(location, []);
			}
			
			return new AstLabeledStatement(location, label, statement);
		
		case Identifier :
			auto lookahead = trange.save;
			lookahead.popFront();
			
			if (lookahead.front.type == Colon) {
				goto case Default;
			}
			
			// If it is not a labeled statement, then it is a declaration or an expression.
			goto default;
		
		case Goto :
			trange.popFront();
			
			Name label;
			switch(trange.front.type) {
				case Identifier :
				case Default :
				case Case :
					label = trange.front.name;
					trange.popFront();
					break;
				
				default :
					trange.match(Identifier);
			}
			
			location.spanTo(trange.front.location);
			trange.match(Semicolon);
			
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
			
			return new AstSynchronizedStatement(location, statement);
		
		case Scope :
			trange.popFront();
			trange.match(OpenParen);
			
			auto name = trange.front.name;
			trange.match(Identifier);
			
			ScopeKind kind;
			if(name == BuiltinName!"exit") {
				kind = ScopeKind.Exit;
			} else if(name == BuiltinName!"success") {
				kind = ScopeKind.Success;
			} else if(name == BuiltinName!"failure") {
				kind = ScopeKind.Failure;
			} else {
				assert(0, name.toString(trange.context) ~ " is not a valid scope identifier.");
			}
			
			trange.match(CloseParen);
			
			auto statement = trange.parseStatement();
			location.spanTo(statement.location);
			
			return new AstScopeStatement(location, kind, statement);
		
		case Throw :
			trange.popFront();
			auto value = trange.parseExpression();
			
			location.spanTo(trange.front.location);
			trange.match(Semicolon);
			
			return new AstThrowStatement(location, value);
		
		case Try :
			trange.popFront();
			
			auto statement = trange.parseStatement();
			
			AstCatchBlock[] catches;
			while(trange.front.type == Catch) {
				auto catchLocation = trange.front.location;
				trange.popFront();
				
				if(trange.front.type == OpenParen) {
					trange.popFront();
					
					import d.parser.identifier;
					auto type = trange.parseIdentifier();
					
					Name name;
					if(trange.front.type == Identifier) {
						name = trange.front.name;
						trange.popFront();
					}
					
					trange.match(CloseParen);
					
					auto catchStatement = trange.parseStatement();
					
					location.spanTo(catchStatement.location);
					catches ~= AstCatchBlock(location, type, name, catchStatement);
				} else {
					// TODO: handle final catches ?
					trange.parseStatement();
					assert(0, "Final catches not implemented");
				}
			}
			
			AstStatement finallyStatement;
			if(trange.front.type == Finally) {
				trange.popFront();
				finallyStatement = trange.parseStatement();
				
				location.spanTo(finallyStatement.location);
			} else {
				location.spanTo(catches.back.location);
			}
			
			return new AstTryStatement(location, statement, catches, finallyStatement);
		
		case Mixin :
			return trange.parseMixin!AstStatement();
		
		case Static :
			auto lookahead = trange.save;
			lookahead.popFront();
			
			switch(lookahead.front.type) {
				case If :
					return trange.parseStaticIf!AstStatement();
				
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
			return trange.parseVersion!AstStatement();
		
		case Debug :
			return trange.parseDebug!AstStatement();
		
		default :
			return trange.parseDeclarationOrExpression!(delegate AstStatement(parsed) {
				alias typeof(parsed) caseType;
				
				static if(is(caseType : AstExpression)) {
					trange.match(Semicolon);
					return new AstExpressionStatement(parsed);
				} else {
					return new DeclarationStatement(parsed);
				}
			})();
	}
	
	assert(0);
}

AstBlockStatement parseBlock(TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange) {
	Location location = trange.front.location;
	
	trange.match(TokenType.OpenBrace);
	
	AstStatement[] statements;
	
	while(trange.front.type != TokenType.CloseBrace) {
		statements ~= trange.parseStatement();
	}
	
	location.spanTo(trange.front.location);
	trange.popFront();
	
	return new AstBlockStatement(location, statements);
}

