module sdc.format.parser;

/**
 * While we already have a parser in libd, we cannot use it here.
 * This is because libd's parser is meant to validate that the source
 * is well a formed D program. However, we want to be able to format
 * even incomplete programs as part of the developper's process.
 *
 * This parser, on the other hand, is meant to recognize common patterns
 * in the language, without ensuring that they are indeed correct.
 */
struct Parser {
private:
	import d.context;
	Context context;
	
	import d.lexer;
	TokenRange trange;
	
	import sdc.format.chunk;
	Builder builder;
	
	/**
	 * When we can't parse we skip and forward chunks "as this"
	 */
	Location skipped;
	
public:	
	this(Context context, ref TokenRange trange) {
		this.context = context;
		this.trange = trange.withComments();
	}
	
	Chunk[] parse() in {
		assert(match(TokenType.Begin));
	} body {
		// Eat the begin token and get the game rolling.
		nextToken();
		parseModule();
		
		assert(match(TokenType.End));
		
		emitSkippedTokens();
		return builder.build();
	}

private:
	/**
	 * Token Processing.
	 */
	import d.context.location;
	uint getStartLineNumber(Location loc) {
		return loc.getFullLocation(context).getStartLineNumber();
	}
	
	uint getLineNumber(Position p) {
		return p.getFullPosition(context).getLineNumber();
	}
	
	int newLineCount() {
		return getStartLineNumber(trange.front.location) - getLineNumber(trange.previous);
	}
	
	uint getStartOffset(Location loc) {
		return loc.getFullLocation(context).getStartOffset();
	}
	
	uint getSourceOffset(Position p) {
		return p.getFullPosition(context).getSourceOffset();
	}
	
	int whiteSpaceLength() {
		return getStartOffset(trange.front.location) - getSourceOffset(trange.previous);
	}
	
	@property
	Token token() const {
		return trange.front;
	}
	
	void nextToken() {
		emitSkippedTokens();
		
		// Process current token.
		builder.write(token.toString(context));
		
		if (match(TokenType.End)) {
			// We reached the end of our input.
			return;
		}
		
		trange.popFront();
		emitComments();
	}
	
	/**
	 * We skip over portions of the code we can't parse.
	 */
	void skipToken() {
		if (skipped.length == 0) {
			emitSourceBasedWhiteSpace();
			split();
			
			skipped = token.location;
		} else {
			skipped.spanTo(token.location);
		}
		
		trange.popFront();
		
		// Skip over comment that look related too.
		while (match(TokenType.Comment) && newLineCount() == 0) {
			skipped.spanTo(token.location);
			trange.popFront();
		}
		
		emitComments();
	}
	
	void emitSkippedTokens() {
		if (skipped.length == 0) {
			return;
		}
		
		builder.write(skipped.getFullLocation(context).getSlice());
		skipped = Location.init;
		
		emitSourceBasedWhiteSpace();
		split();
	}
	
	/**
	 * Comments management
	 */
	void emitComments() {
		if (!match(TokenType.Comment)) {
			return;
		}
		
		emitSkippedTokens();
		emitSourceBasedWhiteSpace();
		
		// TODO: Process comments here.
		while (match(TokenType.Comment)) {
			auto comment = token.toString(context);
			builder.write(comment);
			
			trange.popFront();
			
			if (comment[0 .. 2] == "//") {
				newline(newLineCount() + 1);
			} else {
				emitSourceBasedWhiteSpace();
			}
		}
	}
	
	/**
	 * Chunk builder facilities
	 */
	void space() {
		builder.space();
	}
	
	void newline() {
		newline(newLineCount());
	}
	
	void newline(int nl) {
		builder.newline(nl);
	}
	
	void split() {
		builder.split();
	}
	
	void emitSourceBasedWhiteSpace() {
		auto nl = newLineCount();
		if (nl) {
			newline(nl);
		} else if (whiteSpaceLength() > 0) {
			space();
		}
	}
	
	/**
	 * Parser utilities
	 */
	bool match(TokenType t) {
		return token.type == t;
	}
	
	auto runOnType(TokenType T, alias fun)() {
		if (match(T)) {
			return fun();
		}
	}
	
	void nextTokenAndNewLine() {
		nextToken();
		newline();
	}
	
	void nextTokenAndSplit() {
		nextToken();
		space();
	}
	
	/**
	 * Parsing
	 */
	void parseLevelImpl(bool StopOnClosingBrace)() {
		while (!match(TokenType.End)) {
			if (StopOnClosingBrace && match(TokenType.CloseBrace)) {
				break;
			}
			
			parseStructuralElement();
		}
	}
	
	alias parseModule = parseLevelImpl!false;
	alias parseLevel = parseLevelImpl!true;
	
	void parseStructuralElement() {
		Entry:
		switch (token.type) with(TokenType) {
			case End:
				return;
			
			case Module:
				parseModuleDeclaration();
				break;
			
			/**
			 * Statements
			 */
			case OpenBrace:
				parseBlock();
				
				// Blocks do not end with a semicolon.
				return;
			
			case Identifier:
				// FIXME: Labels.
				goto default;
			
			case If:
				parseIf();
				break;
			
			case Else:
				parseElse();
				break;
			
			case While:
			case Do:
			case For:
			case Foreach, ForeachReverse:
				goto default;
			
			case Return:
				parseReturn();
				break;
			
			case Break, Continue:
			case Switch,Case, Default:
			case Goto:
				goto default;
			
			case Scope:
				goto StorageClass;
			
			case Assert:
			case Throw, Try:
				goto default;
			
			case Synchronized:
				goto StorageClass;
			
			case Mixin:
				goto default;
			
			case Static:
				nextToken();
				space();
				goto Entry;
			
			case Version, Debug:
				goto default;
			
			case Abstract, Align, Alias, Auto, Deprecated, Extern, Final, Nothrow, Override, Pure:
			StorageClass:
				parseStorageClass();
				break;
			
			case Struct, Union, Class, Interface:
				parseAggregate();
				break;
			
			default:
				Location loc = token.location;
				parseIdentifier();
				
				if (token.location == loc) {
					// We made no progress, start skipping.
					skipToken();
					return;
				}
				
				switch (token.type) {
					case Star:
						auto lookahead = trange.save.withComments(false);
						lookahead.popFront();
						
						if (lookahead.front.type != Identifier) {
							break;
						}
						
						// This is a pointer type.
						nextToken();
						goto case;
					
					case Identifier:
						// We have a declaration.
						parseTypedDeclaration();
						// parseTypedDeclaration eats the semicolon
						return;
					
					default:
						break;
				}
				
				// We just have some kind of expression.
				parseBinaryExpression();
				break;
		}
		
		runOnType!(TokenType.Semicolon, nextTokenAndNewLine)();
	}
	
	/**
	 * Structural elements.
	 */
	void parseModuleDeclaration() in {
		assert (match(TokenType.Module));
	} body {
		nextToken();
		space();
		parseIdentifier();
	}
	
	/**
	 * Identifiers
	 */
	void parseIdentifier() {
		PrefixLoop: while (true) {
			switch (token.type) with(TokenType) {
				// Prefixes.
				case Dot:
				case Ampersand:
				case PlusPlus:
				case MinusMinus:
				case Star:
				case Plus:
				case Minus:
				case Bang:
				case Tilde:
					nextToken();
					continue;
				
				case Cast:
					nextToken();
					parseArgumentList();
					space();
					continue;
				
				default:
					break PrefixLoop;
			}
		}
		
		runOnType!(TokenType.Dot, nextToken)();
		
		BaseIdentifier:
		switch (token.type) with(TokenType) {
			case Identifier:
				nextToken();
				break;
			
			// Litterals
			case This:
			case Super:
			case True:
			case False:
			case Null:
			case IntegerLiteral:
			case StringLiteral:
			case CharacterLiteral:
			case __File__:
			case __Line__:
			case Dollar:
				nextToken();
				break;
			
			case OpenParen:
				// TODO: lambdas
				parseArgumentList();
				break;
			
			case OpenBracket:
				// TODO: maps
				parseArgumentList();
				break;
			
			// Types
			case Typeof:
				nextToken();
				parseArgumentList();
				break;
			
			case Bool:
			case Byte, Ubyte:
			case Short, Ushort:
			case Int, Uint:
			case Long, Ulong:
			case Cent, Ucent:
			case Char, Wchar, Dchar:
			case Float, Double, Real:
			case Void:
				nextToken();
				break;
			
			// Type qualifiers
			case Const, Immutable, Inout, Shared:
				nextToken();
				if (!match(TokenType.OpenParen)) {
					space();
					goto BaseIdentifier;
				}
				
				nextToken();
				parseIdentifier();
				runOnType!(TokenType.Dot, nextToken)();
				break;
			
			default:
				return;
		}
		
		SuffixLoop: while (true) {
			switch (token.type) with(TokenType) {
				case Dot:
					nextToken();
					// Put another coin in the Pachinko!
					goto BaseIdentifier;
				
				case Bang:
					nextToken();
					if (match(OpenParen)) {
						parseArgumentList();
					}
					
					break;
				
				case PlusPlus, MinusMinus:
					nextToken();
					break;
				
				case OpenParen, OpenBracket:
					parseArgumentList();
					break;
				
				default:
					break SuffixLoop;
			}
		}
	}
	
	/**
	 * Statements
	 */
	void parseBlock() {
		if (!match(TokenType.OpenBrace)) {
			return;
		}
		
		nextToken();
		if (match(TokenType.CloseBrace)) {
			nextToken();
			newline();
			return;
		}
		
		{
			auto guard = builder.indent();
			
			newline(1);
			split();
			
			// TODO: Indentation and nesting business.
			
			parseLevel();
		}
		
		if (match(TokenType.CloseBrace)) {
			builder.forceNewLine();
			nextToken();
			newline(2);
		}
	}
	
	void parseIf() in {
		assert(match(TokenType.If));
	} body {
		nextToken();
		space();
		
		if (match(TokenType.OpenParen)) {
			nextToken();
			parseStructuralElement();
			runOnType!(TokenType.CloseParen, nextToken)();
		}
		
		space();
		parseStructuralElement();
		
		runOnType!(TokenType.Else, parseElse)();
	}
	
	void parseElse() in {
		assert(match(TokenType.Else));
	} body {
		builder.forceSpace();
		nextToken();
		space();
		split();
		parseStructuralElement();
	}
	
	void parseReturn() in {
		assert(match(TokenType.Return));
	} body {
		nextToken();
		space();
		parseExpression();
	}
	
	/**
	 * Expressions
	 */
	void parseExpression() {
		parseIdentifier();
		parseBinaryExpression();
	}
	
	void parseBinaryExpression() {
		while (true) {
			switch (token.type) with(TokenType) {
				case Equal:
				case PlusEqual:
				case MinusEqual:
				case StarEqual:
				case SlashEqual:
				case PercentEqual:
				case AmpersandEqual:
				case PipeEqual:
				case CaretEqual:
				case TildeEqual:
				case LessLessEqual:
				case MoreMoreEqual:
				case MoreMoreMoreEqual:
				case CaretCaretEqual:
				case PipePipe:
				case AmpersandAmpersand:
				case Pipe:
				case Caret:
				case Ampersand:
				case EqualEqual:
				case BangEqual:
				case More:
				case MoreEqual:
				case Less:
				case LessEqual:
				case BangLessMoreEqual:
				case BangLessMore:
				case LessMore:
				case LessMoreEqual:
				case BangMore:
				case BangMoreEqual:
				case BangLess:
				case BangLessEqual:
				case Is:
				case In:
				case Bang:
				case LessLess:
				case MoreMore:
				case MoreMoreMore:
				case Plus:
				case Minus:
				case Tilde:
				case Slash:
				case Star:
				case Percent:
					space();
					nextToken();
					space();
					break;
				
				case QuestionMark:
					goto default;
				
				default:
					return;
			}
			
			parseIdentifier();
		}
	}
	
	bool parseArgumentList() {
		return parseList!parseExpression();
	}
	
	/**
	 * Declarations
	 */
	void parseTypedDeclaration() in {
		assert(match(TokenType.Identifier));
	} body {
		while (true) {
			space();
			runOnType!(TokenType.Identifier, nextToken)();
			
			while (parseParameterList()) {}
			
			// Function declaration.
			if (match(TokenType.OpenBrace)) {
				space();
				parseBlock();
				return;
			}
			
			// Variable, template parameters, whatever.
			while (match(TokenType.Equal) || match(TokenType.Colon)) {
				space();
				nextToken();
				space();
				parseExpression();
			}
			
			if (!match(TokenType.Comma)) {
				break;
			}
			
			nextToken();
		}
		
		runOnType!(TokenType.Semicolon, nextTokenAndNewLine)();
	}
	
	bool parseParameterList() {
		return parseList!parseStructuralElement();
	}
	
	void parseStorageClass() {
		while (true) {
			switch (token.type) with (TokenType) {
				case Abstract, Auto, Alias, Deprecated, Final, Nothrow, Override, Pure, Static:
				case Const, Immutable, Inout, Shared, __Gshared:
					nextToken();
					break;
				
				case Align, Extern, Scope, Synchronized:
					nextToken();
					parseArgumentList();
					space();
					break;
				
				default:
					return;
					
			}
			
			runOnType!(TokenType.Colon, nextTokenAndSplit)();
			space();
		}
	}
	
	void parseAggregate() in {
		assert(
			match(TokenType.Struct) ||
			match(TokenType.Union) ||
			match(TokenType.Class) ||
			match(TokenType.Interface));
	} body {
		parseStorageClass();
		
		nextToken();
		space();
		
		runOnType!(TokenType.Identifier, nextToken)();
		
		parseArgumentList();
		space();
		
		if (match(TokenType.Colon)) {
			split();
			nextToken();
			space();
		}
		
		// TODO inheritance.
		
		parseBlock();
	}
	
	/**
	 * Parsing utilities
	 */
	bool parseList(alias fun)() {
		TokenType closingTokenType;
		switch (token.type) with(TokenType) {
			case OpenParen:
				closingTokenType = CloseParen;
				break;
			
			case OpenBracket:
				closingTokenType = CloseBracket;
				break;
			
			default:
				return false;
		}
		
		nextToken();
		if (match(closingTokenType)) {
			nextToken();
			return true;
		}
		
		while (true) {
			split();
			fun();
			
			if (!match(TokenType.Comma)) {
				break;
			}

			nextToken();
			space();
			split();
		}
		
		if (match(closingTokenType)) {
			nextToken();
		}
		
		return true;
	}
}
