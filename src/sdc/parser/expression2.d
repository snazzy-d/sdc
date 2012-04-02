module sdc.parser.expression2;

import sdc.tokenstream;
import sdc.ast.expression2;

/**
 * Template used to parse basic BinaryExpressions.
 */
auto parseBinaryExpression(TokenType tokenType, BinaryExpressionType, alias parseNext)(TokenStream tstream) if(is(BinaryExpressionType: BinaryExpression) && is(typeof(parseNext(tstream)) : Expression)) {
	auto start = tstream.peek.location;
	
	Expression result = parseNext(tstream);
	
	while(tstream.peek.type == tokenType) {
		tstream.get();
		
		auto rhs = parseNext(tstream);
		auto location = start;
		location.spanTo(tstream.previous.location);
		
		result = new BinaryExpressionType(location, result, rhs);
	}
	
	return result;
}

alias parseBinaryExpression!(TokenType.DoublePipe, LogicalBinaryExpression!(BinaryOperation.LogicalOr), function Expression(TokenStream tstream) { return parseLogicalAndExpression(tstream); }) parseLogicalOrExpression;

alias parseBinaryExpression!(TokenType.DoubleAmpersand, LogicalBinaryExpression!(BinaryOperation.LogicalAnd), function Expression(TokenStream tstream) { return parseBitwiseOrExpression(tstream); }) parseLogicalAndExpression;

alias parseBinaryExpression!(TokenType.Pipe, BitwiseBinaryExpression!(BinaryOperation.BitwiseOr), function Expression(TokenStream tstream) { return parseBitwiseXorExpression(tstream); }) parseBitwiseOrExpression;

alias parseBinaryExpression!(TokenType.Caret, BitwiseBinaryExpression!(BinaryOperation.BitwiseXor), function Expression(TokenStream tstream) { return parseBitwiseAndExpression(tstream); }) parseBitwiseXorExpression;

alias parseBinaryExpression!(TokenType.Ampersand, BitwiseBinaryExpression!(BinaryOperation.BitwiseAnd), function Expression(TokenStream tstream) { return parseEqualExpression(tstream); }) parseBitwiseAndExpression;

/**
 * Parse == and !=
 */
auto parseEqualExpression(TokenStream tstream) {
	auto start = tstream.peek.location;
	
	Expression result = parseComparaisonExpression(tstream);
	
	while(1) {
		void processToken(BinaryExpressionType)() {
			tstream.get();
			
			auto rhs = parseComparaisonExpression(tstream);
			
			auto location = start;
			location.spanTo(tstream.previous.location);
			
			result = new BinaryExpressionType(location, result, rhs);
		}
		
		switch(tstream.peek.type) {
			case TokenType.DoubleAssign :
				processToken!(EqualityBinaryExpression!(BinaryOperation.Equality))();
				break;
			case TokenType.BangAssign :
				processToken!(EqualityBinaryExpression!(BinaryOperation.NotEquality))();
				break;
			default :
				return result;
		}
	}
}

/**
 * Parse comparaisons
 */
auto parseComparaisonExpression(TokenStream tstream) {
	auto start = tstream.peek.location;
	
	Expression result = parseShiftExpression(tstream);
	
	while(1) {
		void processToken(BinaryExpressionType)() {
			tstream.get();
			
			auto rhs = parseShiftExpression(tstream);
			
			auto location = start;
			location.spanTo(tstream.previous.location);
			
			result = new BinaryExpressionType(location, result, rhs);
		}
		
		switch(tstream.peek.type) {
			case TokenType.Less :
				processToken!(ComparaisonBinaryExpression!(BinaryOperation.Less))();
				break;
			case TokenType.LessAssign :
				processToken!(ComparaisonBinaryExpression!(BinaryOperation.LessEqual))();
				break;
			case TokenType.Greater:
				processToken!(ComparaisonBinaryExpression!(BinaryOperation.Greater))();
				break;
			case TokenType.GreaterAssign:
				processToken!(ComparaisonBinaryExpression!(BinaryOperation.GreaterEqual))();
				break;
			case TokenType.BangLessGreaterAssign:
				processToken!(ComparaisonBinaryExpression!(BinaryOperation.Unordered))();
				break;
			case TokenType.BangLessGreater:
				processToken!(ComparaisonBinaryExpression!(BinaryOperation.UnorderedEqual))();
				break;
			case TokenType.LessGreater:
				processToken!(ComparaisonBinaryExpression!(BinaryOperation.LessGreater))();
				break;
			case TokenType.LessGreaterAssign:
				processToken!(ComparaisonBinaryExpression!(BinaryOperation.LessEqualGreater))();
				break;
			case TokenType.BangGreater:
				processToken!(ComparaisonBinaryExpression!(BinaryOperation.UnorderedLessEqual))();
				break;
			case TokenType.BangGreaterAssign:
				processToken!(ComparaisonBinaryExpression!(BinaryOperation.UnorderedLess))();
				break;
			case TokenType.BangLess:
				processToken!(ComparaisonBinaryExpression!(BinaryOperation.UnorderedGreaterEqual))();
				break;
			case TokenType.BangLessAssign:
				processToken!(ComparaisonBinaryExpression!(BinaryOperation.UnorderedGreater))();
				break;
			// TODO: Parse in and is expressions.
			
			default :
				return result;
		}
	}
}

/**
 * Parse <<, >> and >>>
 */
auto parseShiftExpression(TokenStream tstream) {
	auto start = tstream.peek.location;
	
	Expression result = parseAddExpression(tstream);
	
	while(1) {
		void processToken(BinaryExpressionType)() {
			tstream.get();
			
			auto rhs = parseAddExpression(tstream);
			
			auto location = start;
			location.spanTo(tstream.previous.location);
			
			result = new BinaryExpressionType(location, result, rhs);
		}
		
		switch(tstream.peek.type) {
			case TokenType.DoubleLess :
				processToken!(ShiftBinaryExpression!(BinaryOperation.LeftShift))();
				break;
			case TokenType.DoubleGreater :
				processToken!(ShiftBinaryExpression!(BinaryOperation.SignedRightShift))();
				break;
			case TokenType.TripleGreater :
				processToken!(ShiftBinaryExpression!(BinaryOperation.UnsignedRightShift))();
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
	auto start = tstream.peek.location;
	
	Expression result = parseMulExpression(tstream);
	
	while(1) {
		void processToken(BinaryExpressionType)() {
			tstream.get();
			
			auto rhs = parseMulExpression(tstream);
			
			auto location = start;
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
	auto start = tstream.peek.location;
	
	Expression result = parseUnaryExpression(tstream);
	
	while(1) {
		void processToken(BinaryExpressionType)() {
			tstream.get();
			
			auto rhs = parseUnaryExpression(tstream);
			
			auto location = start;
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

Expression parseUnaryExpression(TokenStream tstream) {
	auto location = tstream.peek.location;
	
	Expression result;
	
	void processToken(UnaryExpressionType)() {
		tstream.get();
		
		result = parseUnaryExpression(tstream);
		location.spanTo(tstream.previous.location);
		
		result = new UnaryExpressionType(location, result);
	}
	
	switch(tstream.peek.type) {
		case TokenType.Ampersand :
			processToken!AddressOfUnaryExpression();
			break;
		case TokenType.DoublePlus :
			processToken!(OpAssignUnaryExpression!(UnaryPrefix.PrefixInc))();
			break;
		case TokenType.DoubleDash :
			processToken!(OpAssignUnaryExpression!(UnaryPrefix.PrefixDec))();
			break;
		case TokenType.Asterix :
			processToken!DereferenceUnaryExpression();
			break;
		case TokenType.Plus :
			processToken!(OperationUnaryExpression!(UnaryPrefix.UnaryPlus))();
			break;
		case TokenType.Dash :
			processToken!(OperationUnaryExpression!(UnaryPrefix.UnaryMinus))();
			break;
		case TokenType.Bang :
			processToken!NotUnaryExpression();
			break;
		case TokenType.Tilde :
			processToken!CompelementExpression();
			break;
		default :
			// TODO: parse postfix and ^^
			assert(0);
	}
	
	// Ensure we do not return null.
	assert(result);
	
	return result;
}

alias returnNull parsePostfixExpression;

auto returnNull(TokenStream tstream) {
	return null;
}

unittest {
	parseLogicalOrExpression(null);
}

