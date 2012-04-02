module sdc.parser.expression2;

import sdc.tokenstream;
import sdc.location;
import sdc.ast.expression2;

/**
 * Template used to parse basic BinaryExpressions.
 */
auto parseBinaryExpression(TokenType tokenType, BinaryExpressionType, alias parseNext)(TokenStream tstream) if(is(BinaryExpressionType: BinaryExpression) && is(typeof(parseNext(tstream)) : Expression)) {
	auto location = tstream.peek.location;
	
	Expression result = parseNext(tstream);
	
	while(tstream.peek.type == tokenType) {
		tstream.get();
		
		auto rhs = parseNext(tstream);
		
		location.spanTo(tstream.previous.location);
		
		result = new BinaryExpressionType(location, result, rhs);
	}
	
	return result;
}

alias parseBinaryExpression!(TokenType.DoublePipe, LogicalBinaryExpression!(BinaryOperation.LogicalOr), function Expression(TokenStream tstream) { return parseLogicalAndExpression(tstream); }) parseLogicalOrExpression;

alias parseBinaryExpression!(TokenType.DoubleAmpersand, LogicalBinaryExpression!(BinaryOperation.LogicalAnd), function Expression(TokenStream tstream) { return parseBitwiseOrExpression(tstream); }) parseLogicalAndExpression;

alias parseBinaryExpression!(TokenType.Pipe, BitwiseBinaryExpression!(BinaryOperation.BitwiseOr), function Expression(TokenStream tstream) { return parseBitwiseXorExpression(tstream); }) parseBitwiseOrExpression;

alias parseBinaryExpression!(TokenType.Caret, BitwiseBinaryExpression!(BinaryOperation.BitwiseXor), function Expression(TokenStream tstream) { return parseBitwiseAndExpression(tstream); }) parseBitwiseXorExpression;

alias parseBinaryExpression!(TokenType.Ampersand, BitwiseBinaryExpression!(BinaryOperation.BitwiseAnd), function Expression(TokenStream tstream) { return parseComparaisonExpression(tstream); }) parseBitwiseAndExpression;

/**
 * Parse ==, != and comparaisons
 */
auto parseComparaisonExpression(TokenStream tstream) {
	auto location = tstream.peek.location;
	
	Expression result = parseShiftExpression(tstream);
	
	void processToken(BinaryExpressionType)() {
		tstream.get();
		
		auto rhs = parseShiftExpression(tstream);
		
		location.spanTo(tstream.previous.location);
		
		result = new BinaryExpressionType(location, result, rhs);
	}
	
	switch(tstream.peek.type) {
		case TokenType.DoubleAssign :
			processToken!(EqualityExpression!(BinaryOperation.Equality))();
			break;
		case TokenType.BangAssign :
			processToken!(EqualityExpression!(BinaryOperation.NotEquality))();
			break;
		case TokenType.Less :
			processToken!(ComparaisonExpression!(BinaryOperation.Less))();
			break;
		case TokenType.LessAssign :
			processToken!(ComparaisonExpression!(BinaryOperation.LessEqual))();
			break;
		case TokenType.Greater:
			processToken!(ComparaisonExpression!(BinaryOperation.Greater))();
			break;
		case TokenType.GreaterAssign:
			processToken!(ComparaisonExpression!(BinaryOperation.GreaterEqual))();
			break;
		case TokenType.BangLessGreaterAssign:
			processToken!(ComparaisonExpression!(BinaryOperation.Unordered))();
			break;
		case TokenType.BangLessGreater:
			processToken!(ComparaisonExpression!(BinaryOperation.UnorderedEqual))();
			break;
		case TokenType.LessGreater:
			processToken!(ComparaisonExpression!(BinaryOperation.LessGreater))();
			break;
		case TokenType.LessGreaterAssign:
			processToken!(ComparaisonExpression!(BinaryOperation.LessEqualGreater))();
			break;
		case TokenType.BangGreater:
			processToken!(ComparaisonExpression!(BinaryOperation.UnorderedLessEqual))();
			break;
		case TokenType.BangGreaterAssign:
			processToken!(ComparaisonExpression!(BinaryOperation.UnorderedLess))();
			break;
		case TokenType.BangLess:
			processToken!(ComparaisonExpression!(BinaryOperation.UnorderedGreaterEqual))();
			break;
		case TokenType.BangLessAssign:
			processToken!(ComparaisonExpression!(BinaryOperation.UnorderedGreater))();
			break;
			// TODO: Parse in and is expressions.
		
		default :
			// We have no comparaison, so we just return.
	}
	
	return result;
}

/**
 * Parse <<, >> and >>>
 */
auto parseShiftExpression(TokenStream tstream) {
	auto location = tstream.peek.location;
	
	Expression result = parseAddExpression(tstream);
	
	while(1) {
		void processToken(BinaryExpressionType)() {
			tstream.get();
			
			auto rhs = parseAddExpression(tstream);
			
			location.spanTo(tstream.previous.location);
			
			result = new BinaryExpressionType(location, result, rhs);
		}
		
		switch(tstream.peek.type) {
			case TokenType.DoubleLess :
				processToken!(ShiftExpression!(BinaryOperation.LeftShift))();
				break;
			case TokenType.DoubleGreater :
				processToken!(ShiftExpression!(BinaryOperation.SignedRightShift))();
				break;
			case TokenType.TripleGreater :
				processToken!(ShiftExpression!(BinaryOperation.UnsignedRightShift))();
				break;
			default :
				return result;
		}
	}
}

/**
 * Parse +, - and ~
 */
auto parseAddExpression(TokenStream tstream) {
	auto location = tstream.peek.location;
	
	Expression result = parseMulExpression(tstream);
	
	while(1) {
		void processToken(BinaryExpressionType)() {
			tstream.get();
			
			auto rhs = parseMulExpression(tstream);
			
			location.spanTo(tstream.previous.location);
			
			result = new BinaryExpressionType(location, result, rhs);
		}
		
		switch(tstream.peek.type) {
			case TokenType.Plus :
				processToken!(OperationBinaryExpression!(BinaryOperation.Addition))();
				break;
			case TokenType.Dash :
				processToken!(OperationBinaryExpression!(BinaryOperation.Subtraction))();
				break;
			case TokenType.Tilde :
				processToken!(OperationBinaryExpression!(BinaryOperation.Concat))();
				break;
			default :
				return result;
		}
	}
}

/**
 * Parse *, / and %
 */
auto parseMulExpression(TokenStream tstream) {
	auto location = tstream.peek.location;
	
	Expression result = parsePrefixExpression(tstream);
	
	while(1) {
		void processToken(BinaryExpressionType)() {
			tstream.get();
			
			auto rhs = parsePrefixExpression(tstream);
			
			location.spanTo(tstream.previous.location);
			
			result = new BinaryExpressionType(location, result, rhs);
		}
		
		switch(tstream.peek.type) {
			case TokenType.Asterix :
				processToken!(OperationBinaryExpression!(BinaryOperation.Multiplication))();
				break;
			case TokenType.Slash :
				processToken!(OperationBinaryExpression!(BinaryOperation.Division))();
				break;
			case TokenType.Percent :
				processToken!(OperationBinaryExpression!(BinaryOperation.Modulus))();
				break;
			default :
				return result;
		}
	}
}

/**
 * Unary prefixes
 */
Expression parsePrefixExpression(TokenStream tstream) {
	auto location = tstream.peek.location;
	
	Expression result;
	
	void processToken(UnaryExpressionType)() {
		tstream.get();
		
		result = parsePrefixExpression(tstream);
		location.spanTo(tstream.previous.location);
		
		result = new UnaryExpressionType(location, result);
	}
	
	switch(tstream.peek.type) {
		case TokenType.Ampersand :
			processToken!AddressOfExpression();
			break;
		case TokenType.DoublePlus :
			processToken!(OpAssignUnaryExpression!(UnaryPrefix.PrefixInc))();
			break;
		case TokenType.DoubleDash :
			processToken!(OpAssignUnaryExpression!(UnaryPrefix.PrefixDec))();
			break;
		case TokenType.Asterix :
			processToken!DereferenceExpression();
			break;
		case TokenType.Plus :
			processToken!(OperationUnaryExpression!(UnaryPrefix.UnaryPlus))();
			break;
		case TokenType.Dash :
			processToken!(OperationUnaryExpression!(UnaryPrefix.UnaryMinus))();
			break;
		case TokenType.Bang :
			processToken!NotExpression();
			break;
		case TokenType.Tilde :
			processToken!CompelementExpression();
			break;
			// TODO: new, cast.
		default :
			result = parsePrimaryExpression(tstream);
			result = parsePostfixExpression(tstream, location, result);
	}
	
	// Ensure we do not screwed up.
	assert(result);
	
	return parsePowExpression(tstream, location, result);
}

auto parsePowExpression(TokenStream tstream, Location location, Expression expression) {
	while (tstream.peek.type == TokenType.DoubleCaret) {
		tstream.get();
		Expression power = parsePrefixExpression(tstream);
		location.spanTo(tstream.previous.location);
		expression = new OperationBinaryExpression!(BinaryOperation.Pow)(location, expression, power);
	}
	
	return expression;
}

Expression parsePostfixExpression(TokenStream tstream, Location location, Expression expression) {
	while(1) {
		void processToken(UnaryExpressionType)() {
			tstream.get();
			
			location.spanTo(tstream.previous.location);
		
			expression = new UnaryExpressionType(location, expression);
		}
		
		switch(tstream.peek.type) {
			case TokenType.DoublePlus :
				processToken!(OpAssignUnaryExpression!(PostfixType.PostfixInc))();
				break;
			case TokenType.DoubleDash :
				processToken!(OpAssignUnaryExpression!(PostfixType.PostfixDec))();
				break;
				// TODO: Dots, Calls, Indices, Slices.
			default :
				return expression;
		}
	}
}

alias returnNull parsePrimaryExpression;

auto returnNull(TokenStream tstream) {
	return null;
}

unittest {
	parseLogicalOrExpression(null);
}

