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
	
	uint extraIndent = 0;
	
	enum Mode {
		Declaration,
		Statement,
		Parameter,
	}

	Mode mode;
	
	auto changeMode(Mode m) {
		static struct Guard {
			~this() {
				parser.mode = oldMode;
			}
			
		private:
			Parser* parser;
			Mode oldMode;
		}
		
		Mode oldMode = mode;
		mode = m;
		
		return Guard(&this, oldMode);
	}
	
	/**
	 * When we can't parse we skip and forward chunks "as this"
	 */
	Location skipped;
	
	/**
	 * Comments to be emitted before the next token.
	 */
	Location[] inFlightComments;
	Location[] nextCommentBlock;
	
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
		flushComments();
		
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
	
	int newLineCount(Location location, Position previous) {
		return getStartLineNumber(location) - getLineNumber(previous);
	}
	
	int newLineCount(ref TokenRange r) {
		return newLineCount(r.front.location, r.previous);
	}
	
	int newLineCount() {
		return newLineCount(trange);
	}
	
	uint getStartOffset(Location loc) {
		return loc.getFullLocation(context).getStartOffset();
	}
	
	uint getSourceOffset(Position p) {
		return p.getFullPosition(context).getSourceOffset();
	}
	
	int whiteSpaceLength(Location location, Position previous) {
		return getStartOffset(location) - getSourceOffset(previous);
	}
	
	int whiteSpaceLength() {
		return whiteSpaceLength(token.location, trange.previous);
	}
	
	@property
	Token token() const {
		return trange.front;
	}
	
	void nextToken() {
		emitSkippedTokens();
		flushComments();
		
		// Process current token.
		builder.write(token.toString(context));
		
		if (match(TokenType.End)) {
			// We reached the end of our input.
			return;
		}
		
		trange.popFront();
		parseComments();
	}
	
	/**
	 * We skip over portions of the code we can't parse.
	 */
	void skipToken() {
		flushComments();
		
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
		
		parseComments();
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
	void emitComments(ref Location[] commentBlock, Location nextTokenLoc) {
		if (commentBlock.length == 0) {
			return;
		}
		
		scope(success) {
			commentBlock = [];
		}
		
		Position previous = commentBlock[0].start;
		
		foreach (loc; commentBlock) {
			scope(success) {
				previous = loc.stop;
			}
			
			emitSourceBasedWhiteSpace(loc, previous);
			
			auto comment = loc.getFullLocation(context).getSlice();
			builder.write(comment);
			
			if (comment[0 .. 2] == "//") {
				newline(1);
			}
		}
		
		emitSourceBasedWhiteSpace(nextTokenLoc, previous);
	}
	
	void emitInFlightComments() {
		auto nextTokenLoc = nextCommentBlock.length > 0
			? nextCommentBlock[0]
			: token.location;
		
		emitComments(inFlightComments, nextTokenLoc);
	}
	
	void flushComments() {
		emitInFlightComments();
		emitComments(nextCommentBlock, token.location);
	}
	
	void parseComments() in {
		assert(inFlightComments == []);
		assert(inFlightComments == []);
	} do {
		if (!match(TokenType.Comment)) {
			return;
		}
		
		emitSkippedTokens();
		emitSourceBasedWhiteSpace();
		
		/**
		 * We distrube comments in 3 groups:
		 *   1 - The comments attached to the previous structural element.
		 *   2 - The comments in flight between two structural elements.
		 *   3 - The comments attached to the next structural element.
		 * We want to emit group 1 right away, but wait for later when
		 * emitting groups 2 and 3.
		 */
		while (match(TokenType.Comment) && newLineCount() == 0) {
			auto comment = token.toString(context);
			builder.write(comment);
			trange.popFront();
			
			emitSourceBasedWhiteSpace();
		}
		
		Location[] commentBlock = [];
		while (match(TokenType.Comment)) {
			commentBlock ~= token.location;
			trange.popFront();
			
			if (newLineCount() < 2) {
				continue;
			}
			
			inFlightComments ~= commentBlock;
			commentBlock = [];
		}
		
		nextCommentBlock = commentBlock;
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
	
	void clearSplitType() {
		builder.clearSplitType();
	}
	
	void split() {
		builder.split();
	}
	
	void emitSourceBasedWhiteSpace(Location location, Position previous) {
		if (auto nl = newLineCount(location, previous)) {
			newline(nl);
			return;
		}
		
		if (whiteSpaceLength(location, previous) > 0) {
			space();
		}
	}
	
	void emitSourceBasedWhiteSpace() {
		emitSourceBasedWhiteSpace(token.location, trange.previous);
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
	
	/**
	 * Parsing
	 */
	void parseModule() {
		auto guard = changeMode(Mode.Declaration);
		
		while (!match(TokenType.End)) {
			parseStructuralElement();
		}
	}
	
	void parseStructuralElement() {
		emitInFlightComments();
		
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
				parseBlock(mode);
				
				// Blocks do not end with a semicolon.
				return;
			
			case Identifier:
				auto lookahead = trange.save.withComments(false);
				lookahead.popFront();
				auto t = lookahead.front.type;
				
				if (mode == Mode.Parameter && (t == Colon || t == Equal)) {
					parseTemplateParameter();
					break;
				}
				
				if (t != Colon) {
					// This is an expression or a declaration.
					goto default;
				}
				
				lookahead.popFront();
				if (newLineCount(lookahead)) {
					auto guard = builder.unindent();
					newline(2);
					nextToken();
					nextToken();
					newline();
				} else {
					nextToken();
					nextToken();
					space();
				}

				break;
			
			case If:
				parseIf();
				break;
			
			case Else:
				parseElse();
				break;
			
			case While:
				parseWhile();
				break;
			
			case Do:
				parseDoWhile();
				break;
			
			case For:
				parseFor();
				break;
			
			case Foreach, ForeachReverse:
				parseForeach();
				break;
			
			case Return:
				parseReturn();
				break;
			
			case Break, Continue:
				nextToken();
				runOnType!(Identifier, nextToken)();
				break;
			
			case With:
				parseWith();
				break;
			
			case Switch:
				parseSwitch();
				break;
			
			case Case: {
					auto guard = builder.unindent();
					newline();
					
					while (true) {
						nextToken();
						space();
						
						parseList!parseExpression(TokenType.Colon);
						
						if (!match(DotDot)) {
							break;
						}
						
						space();
						nextToken();
						space();
					}
				}
				
				newline();
				break;
			
			case Default: {
					auto guard = builder.unindent();
					newline();
					nextToken();
					runOnType!(Colon, nextToken)();
					newline();
				}
				
				break;

			case Goto:
				nextToken();
				if (match(Identifier) || match(Default)) {
					space();
					nextToken();
				} else if (match(Case)) {
					space();
					nextToken();
					
					if (!match(Semicolon)) {
						space();
						parseExpression();
					}
				}
				
				break;
			
			case Throw:
				nextToken();
				space();
				parseExpression();
				break;
			
			case Try:
				parseTry();
				break;
			
			case Catch:
				parseCatch();
				break;
			
			case Finally:
				parseFinally();
				break;
			
			case Scope:
				// FIXME: scope statements.
				goto StorageClass;
			
			case Assert:
				parseExpression();
				break;
			
			/**
			 * Declaration
			 */
			case This:
				// FIXME: customized parsing depending if declaration or statement are prefered.
				// For now, assume ctor.
				parseConstructor();
				break;
			
			case Template:
				parseTemplate();
				break;
			
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
			
			case Ref:
				nextToken();
				space();
				goto default;
			
			case Enum:
				auto lookahead = trange.save.withComments(false);
				lookahead.popFront();
				
				if (lookahead.front.type == Identifier) {
					lookahead.popFront();
				}
				
				if (lookahead.front.type == Colon || lookahead.front.type == OpenBrace) {
					parseEnum();
					break;
				}
				
				goto StorageClass;
			
			case Abstract, Align, Auto, Deprecated, Extern, Final, Nothrow, Override, Pure:
			StorageClass:
				bool success = parseStorageClass();
				assert(success, "Failed to parse storage class");
				break;
			
			case Struct, Union, Class, Interface:
				parseAggregate();
				break;
			
			case Alias:
				parseAlias();
				break;
			
			default:
				if (!parseIdentifier()) {
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
						break;
					
					default:
						break;
				}
				
				// We just have some kind of expression.
				parseBinaryExpression();
				break;
		}
		
		bool foundSemicolon = match(TokenType.Semicolon);
		if (foundSemicolon) {
			nextToken();
		}
		
		if (mode != Mode.Parameter) {
			if (foundSemicolon) {
				newline();
			} else {
				emitSourceBasedWhiteSpace();
			}
		}
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
	enum IdentifierKind {
		None,
		Symbol,
		Type,
		Expression,
	}
	
	bool parseIdentifier() {
		parseIdentifierPrefix();
		auto kind = parseBaseIdentifier();
		if (kind == IdentifierKind.None) {
			return false;
		}
		
		parseIdentifierSuffix(kind);
		return true;
	}
	
	void parseIdentifierPrefix() {
		while (true) {
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
					break;
				
				case Cast:
					nextToken();
					if (match(OpenParen)) {
						nextToken();
						parseType();
					}
					
					runOnType!(CloseParen, nextToken)();
					space();
					break;
				
				default:
					return;
			}
		}
	}
	
	IdentifierKind parseBaseIdentifier() {
		IdentifierKind kind = IdentifierKind.Symbol;
		
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
				kind = IdentifierKind.Expression;
				nextToken();
				break;
			
			case Assert:
				kind = IdentifierKind.Expression;
				nextToken();
				parseArgumentList();
				break;
			
			case New:
				kind = IdentifierKind.Expression;
				nextToken();
				space();
				parseType();
				parseArgumentList();
				break;
			
			case OpenParen:
				import d.parser.util;
				auto lookahead = trange.save.withComments(false);
				lookahead.popMatchingDelimiter!OpenParen();
				
				switch (lookahead.front.type) {
					case Dot:
						// Could be (type).identifier
						break;
					
					case OpenBrace:
						kind = IdentifierKind.Expression;
						parseParameterList();
						space();
						parseBlock(Mode.Statement);
						clearSplitType();
						break;
					
					case EqualMore:
						kind = IdentifierKind.Expression;
						parseParameterList();
						space();
						if (match(EqualMore)) {
							nextToken();
							space();
							parseExpression();
						}
						
						break;
					
					default:
						break;
				}
				
				parseArgumentList();
				break;
			
			case OpenBrace:
				// This is a parameterless lambda.
				parseBlock(Mode.Statement);
				clearSplitType();
				break;
			
			case OpenBracket:
				// TODO: maps
				parseArgumentList();
				break;
			
			case Typeid:
				kind = IdentifierKind.Expression;
				nextToken();
				parseArgumentList();
				break;
			
			case Mixin:
				// Assume it is an expression. Technically, it could be a declaration, but it
				// change nothing from a formatting perspective, so we are good.
				kind = IdentifierKind.Expression;
				nextToken();
				parseArgumentList();
				break;
			
			// Types
			case Typeof:
				kind = IdentifierKind.Type;
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
				kind = IdentifierKind.Type;
				nextToken();
				break;
			
			// Type qualifiers
			case Const, Immutable, Inout, Shared:
				kind = IdentifierKind.Type;
				nextToken();
				if (!match(OpenParen)) {
					space();
					goto BaseIdentifier;
				}
				
				nextToken();
				parseType();
				runOnType!(CloseParen, nextToken)();
				break;
			
			default:
				return IdentifierKind.None;
		}
		
		return kind;
	}
	
	void parseIdentifierSuffix(IdentifierKind kind) in {
		assert(kind != IdentifierKind.None);
	} body {
		while (true) {
			switch (token.type) with(TokenType) {
				case Dot:
					nextToken();
					// Put another coin in the Pachinko!
					kind = parseBaseIdentifier();
					break;
				
				case Star:
					final switch (kind) with(IdentifierKind) {
						case Type:
							// This is a pointer.
							nextToken();
							continue;
						
						case Expression:
							// This is a multiplication.
							return;
						
						case Symbol:
							// This could be either. Use lookahead.
							break;
						
						case None:
							assert(0);
					}
					
					auto lookahead = trange.save.withComments(false);
					lookahead.popFront();
					
					switch (lookahead.front.type) {
						case Star, Function, Delegate:
							kind = IdentifierKind.Type;
							nextToken();
							break;
						
						default:
							// No idea what this is, move on.
							return;
					}
					
					break;
				
				case Function, Delegate:
					kind = IdentifierKind.Type;
					space();
					nextToken();
					parseParameterList();
					break;
				
				case Bang:
					if (isBangIsOrIn()) {
						// This is a binary expression.
						return;
					}
					
					// Template instance.
					kind = IdentifierKind.Symbol;
					nextToken();
					if (match(OpenParen)) {
						parseArgumentList();
					} else {
						parseBaseIdentifier();
					}
					
					break;
				
				case PlusPlus, MinusMinus:
					kind = IdentifierKind.Expression;
					nextToken();
					break;
				
				case OpenParen, OpenBracket:
					parseArgumentList();
					break;
				
				default:
					return;
			}
		}
	}
	
	/**
	 * Statements
	 */
	void parseBlock(Mode m) {
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
			auto oldExtraIndent = extraIndent;
			scope(exit) {
				extraIndent = oldExtraIndent;
			}
			
			auto indentGuard = builder.indent(1 + extraIndent);
			auto modeGuard = changeMode(m);
			
			// Do not extra indent sub blocks.
			extraIndent = 0;
			
			newline(1);
			split();
			
			while (!match(TokenType.CloseBrace) && !match(TokenType.End)) {
				parseStructuralElement();
			}
			
			// Flush comments so that they have the proper indentation.
			flushComments();
		}
		
		if (match(TokenType.CloseBrace)) {
			clearSplitType();
			newline(1);
			nextToken();
			newline(2);
		}
	}
	
	bool parseControlFlowBlock() {
		bool isBlock = match(TokenType.OpenBrace);
		if (isBlock) {
			parseBlock(mode);
		} else {
			auto guard = builder.indent();
			newline(1);
			parseStructuralElement();
		}
		
		return isBlock;
	}
	
	void parseCondition() {
		if (match(TokenType.OpenParen)) {
			nextToken();
			auto guard = changeMode(Mode.Parameter);
			parseStructuralElement();
			runOnType!(TokenType.CloseParen, nextToken)();
		}
	}
	
	bool parseControlFlowBase() {
		nextToken();
		space();
		
		parseCondition();
		
		space();
		return parseControlFlowBlock();
	}
	
	void emitBlockControlFlowWhitespace(bool isBlock) {
		clearSplitType();
		if (isBlock) {
			space();
		} else {
			newline(1);
		}
	}
	
	void parseIf() in {
		assert(match(TokenType.If));
	} body {
		bool isBlock = parseControlFlowBase();
		if (!match(TokenType.Else)) {
			return;
		}
		
		emitBlockControlFlowWhitespace(isBlock);
		parseElse();
	}
	
	void parseElse() in {
		assert(match(TokenType.Else));
	} body {
		space();
		nextToken();
		space();
		
		if (match(TokenType.If)) {
			parseIf();
		} else {
			parseControlFlowBlock();
		}
	}
	
	void parseWhile() in {
		assert(match(TokenType.While));
	} body {
		parseControlFlowBase();
	}
	
	void parseDoWhile() in {
		assert(match(TokenType.Do));
	} body {
		nextToken();
		space();
		bool isBlock = parseControlFlowBlock();
		
		if (!match(TokenType.While)) {
			return;
		}
		
		emitBlockControlFlowWhitespace(isBlock);
		nextToken();
		
		if (match(TokenType.OpenParen)) {
			nextToken();
			auto guard = changeMode(Mode.Parameter);
			parseStructuralElement();
			runOnType!(TokenType.CloseParen, nextToken)();
		}
		
		runOnType!(TokenType.Semicolon, nextToken)();
		newline(2);
	}
	
	void parseFor() in {
		assert(match(TokenType.For));
	} body {
		nextToken();
		space();
		
		if (match(TokenType.OpenParen)) {
			nextToken();
			if (match(TokenType.Semicolon)) {
				nextToken();
			} else {
				parseStructuralElement();
				clearSplitType();
			}
			
			if (match(TokenType.Semicolon)) {
				nextToken();
			} else {
				space();
				parseExpression();
				runOnType!(TokenType.Semicolon, nextToken)();
			}
			
			if (match(TokenType.CloseParen)) {
				nextToken();
			} else {
				space();
				parseExpression();
			}

			runOnType!(TokenType.CloseParen, nextToken)();
		}
		
		space();
		parseControlFlowBlock();
	}
	
	void parseForeach() in {
		assert(match(TokenType.Foreach) || match(TokenType.ForeachReverse));
	} body {
		nextToken();
		space();
		
		if (match(TokenType.OpenParen)) {
			nextToken();
			auto guard = changeMode(Mode.Parameter);
			
			parseList!parseStructuralElement(TokenType.Semicolon);
			
			space();
			parseList!parseExpression(TokenType.CloseParen);
		}
		
		space();
		parseControlFlowBlock();
	}
	
	void parseReturn() in {
		assert(match(TokenType.Return));
	} body {
		nextToken();
		if (token.type == TokenType.Semicolon) {
			nextToken();
		} else {
			space();
			parseExpression();
		}
	}
	
	void parseWith() in {
		assert(match(TokenType.With));
	} body {
		nextToken();
		space();
		
		parseCondition();
		space();
		
		parseStructuralElement();
	}

	void parseSwitch() in {
		assert(match(TokenType.Switch));
	} body {
		nextToken();
		space();
		
		parseCondition();
		space();
		
		auto oldExtraIndent = extraIndent;
		scope(exit) {
			extraIndent = oldExtraIndent;
		}
		
		extraIndent = 1;
		parseStructuralElement();
	}
	
	void parseTry() in {
		assert(match(TokenType.Try));
	} body {
		nextToken();
		space();
		bool isBlock = parseControlFlowBlock();
		
		while (true) {
			while (match(TokenType.Catch)) {
				emitBlockControlFlowWhitespace(isBlock);
				isBlock = parseCatch();
			}
			
			if (!match(TokenType.Finally)) {
				break;
			}
			
			emitBlockControlFlowWhitespace(isBlock);
			isBlock = parseFinally();
		}
	}
	
	bool parseCatch() in {
		assert(match(TokenType.Catch));
	} body {
		nextToken();
		parseParameterList();
		space();
		return parseControlFlowBlock();
	}
	
	bool parseFinally() in {
		assert(match(TokenType.Finally));
	} body {
		nextToken();
		space();
		return parseControlFlowBlock();
	}
	
	/**
	 * Types
	 */
	void parseType() {
		parseIdentifier();

		// '*' could be a pointer or a multiply, so it is not parsed eagerly.
		parseIdentifierSuffix(IdentifierKind.Type);
	}
	
	/**
	 * Expressions
	 */
	void parseExpression() {
		parseBaseExpression();
		parseBinaryExpression();
	}
	
	void parseBaseExpression() {
		parseIdentifier();
	}
	
	bool isBangIsOrIn() in {
		assert(match(TokenType.Bang));
	} body {
		auto lookahead = trange.save.withComments(false);
		lookahead.popFront();
		auto t = lookahead.front.type;
		return t == TokenType.Is || t == TokenType.In;
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
					split();
					nextToken();
					space();
					break;
				
				case Bang:
					if (!isBangIsOrIn()) {
						return;
					}
					
					space();
					split();
					nextToken();
					nextToken();
					space();
					break;
				
				case QuestionMark:
					space();
					split();
					nextToken();
					space();
					parseExpression();
					space();
					
					if (match(Colon)) {
						split();
						nextToken();
						space();
					}
					
					parseExpression();
					break;
				
				default:
					return;
			}
			
			parseBaseExpression();
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
		bool loop = mode == Mode.Parameter;
		do {
			space();
			runOnType!(TokenType.Identifier, nextToken)();
			
			while (parseParameterList()) {}
			
			// Variable, template parameters, whatever.
			if (match(TokenType.Equal) || match(TokenType.Colon)) {
				space();
				nextToken();
				space();
				parseExpression();
			}

			if (!match(TokenType.Comma)) {
				break;
			}
			
			nextToken();
		} while (loop);
		
		while (true) {
			switch (token.type) with (TokenType) {
				case OpenBrace:
					// Function declaration.
					clearSplitType();
					break;
				
				case In, Body, Do:
					clearSplitType();
					space();
					nextToken();
					break;
				
				case Out:
					clearSplitType();
					space();
					nextToken();
					parseParameterList();
					break;
				
				default:
					return;
			}
			
			clearSplitType();
			space();
			if (match(TokenType.OpenBrace)) {
				parseBlock(Mode.Statement);
			}
		}
	}
	
	void parseConstructor() in {
		assert(match(TokenType.This));
	} body {
		nextToken();
		
		while (parseParameterList()) {}
		
		// Function declaration.
		if (match(TokenType.OpenBrace)) {
			space();
			parseBlock(Mode.Statement);
		}
	}
	
	void parseTemplate() in {
		assert(match(TokenType.Template));
	} body {
		nextToken();
		space();
		runOnType!(TokenType.Identifier, nextToken)();
		parseParameterList();
		space();
		parseBlock(Mode.Declaration);
	}
	
	void parseTemplateParameter() in {
		assert(token.type == TokenType.Identifier);
	} body {
		nextToken();
		
		while (match(TokenType.Colon) || match(TokenType.Equal)) {
			space();
			nextToken();
			space();
			parseType();
		}
	}
	
	bool parseParameterList() {
		auto guard = changeMode(Mode.Parameter);
		return parseList!parseStructuralElement();
	}
	
	bool parseStorageClass() {
		bool ret = false;
		while (true) {
			scope(success) {
				// This will be true after the first loop iterration.
				ret = true;
			}

			switch (token.type) with (TokenType) {
				case Abstract, Auto, Alias, Deprecated, Enum, Final, Nothrow, Override, Pure, Static:
				case Const, Immutable, Inout, Shared, __Gshared:
					nextToken();
					break;
				
				case Align, Extern, Scope, Synchronized:
					nextToken();
					parseArgumentList();
					space();
					break;
				
				default:
					return ret;
			}
			
			switch (token.type) with (TokenType) {
				case Colon:
					nextToken();
					newline(1);
					return true;
					
				case OpenBrace:
					space();
					parseBlock(mode);
					return true;
				
				case Identifier:
					auto lookahead = trange.save.withComments(false);
					lookahead.popFront();
					
					switch (lookahead.front.type) {
						case Equal:
						case OpenParen:
							parseTypedDeclaration();
							break;
						
						default:
							parseStructuralElement();
							break;
					}
					
					return true;
				
				default:
					break;
			}
		}
	}
	
	void parseEnum() in {
		assert(match(TokenType.Enum));
	} body {
		nextToken();
		
		if (match(TokenType.Identifier)) {
			space();
			nextToken();
		}
		
		if (match(TokenType.Colon)) {
			space();
			nextToken();
			space();
			parseType();
		}
		
		if (match(TokenType.OpenBrace)) {
			space();
			nextToken();
			parseList!parseExpression(TokenType.CloseBrace, true);
		}
	}
	
	void parseAggregate() in {
		assert(
			match(TokenType.Struct) ||
			match(TokenType.Union) ||
			match(TokenType.Class) ||
			match(TokenType.Interface));
	} body {
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
		
		parseBlock(Mode.Declaration);
	}
	
	void parseAlias() in {
		assert(match(TokenType.Alias));
	} body {
		nextToken();
		space();
		
		runOnType!(TokenType.Identifier, nextToken)();
		
		parseArgumentList();
		
		if (match(TokenType.This)) {
			space();
			nextToken();
			return;
		}
		
		while (match(TokenType.Equal) || match(TokenType.Colon)) {
			space();
			nextToken();
			space();
			parseExpression();
		}
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
		return parseList!fun(closingTokenType);
	}

	bool parseList(alias fun)(TokenType closingTokenType, bool addNewLines = false) {
		if (match(closingTokenType)) {
			nextToken();
			return true;
		}
		
		while (true) {
			auto guard = builder.indent();
			while (true) {
				if (addNewLines) {
					newline(1);
				} else {
					split();
				}
				
				fun();
				
				if (!match(TokenType.Comma)) {
					break;
				}
				
				nextToken();
				space();
			}
			
			if (!match(TokenType.DotDot)) {
				break;
			}
			
			space();
			nextToken();
			space();
		}
		
		if (match(closingTokenType)) {
			if (addNewLines) {
				newline(1);
			}
			
			nextToken();
		}
		
		if (addNewLines) {
			newline(2);
		}

		return true;
	}
}
