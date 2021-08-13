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
	
	/**
	 * Passthrough for portion of code not to be formatted.
	 *
	 * When formatting is disabled, we keep parsing anyways. This ensures
	 * the state of affairs, such as identation levels, are kept track off.
	 * However, nothign is sent to the builder as parsing progresses, and
	 * everything is sent as one signle chunk at the end of it.
	 */
	Position sdfmtOffStart;
	
	bool skipFormatting() const {
		return sdfmtOffStart != Position();
	}
	
public:
	this(Context context, ref TokenRange trange) {
		this.context = context;
		this.trange = trange.withComments();
	}
	
	Chunk[] parse() in {
		assert(match(TokenType.Begin));
	} do {
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
	 * Chunk builder facilities
	 */
	void write(string s) {
		if (skipFormatting()) {
			return;
		}
		
		builder.write(s);
	}
	
	void space() {
		if (skipFormatting()) {
			return;
		}
		
		builder.space();
	}
	
	void newline() {
		newline(newLineCount());
	}
	
	void newline(int nl) {
		if (skipFormatting()) {
			return;
		}
		
		builder.newline(nl);
	}
	
	void clearSplitType() {
		if (skipFormatting()) {
			return;
		}
		
		builder.clearSplitType();
	}
	
	void split() {
		if (skipFormatting()) {
			return;
		}
		
		builder.split();
	}
	
	import sdc.format.span;
	auto span(S = Span)() {
		emitSkippedTokens();
		emitInFlightComments();
		
		return builder.span!S();
	}
	
	auto spliceSpan(S = Span)() {
		auto guard = span!S();
		builder.spliceSpan();
		
		return guard;
	}
	
	auto block() {
		return builder.block();
	}
	
	/**
	 * Whitespace management.
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
	 * Token processing.
	 */
	@property
	Token token() const {
		return trange.front;
	}
	
	bool match(TokenType t) {
		return token.type == t;
	}
	
	auto runOnType(TokenType T, alias fun)() {
		if (match(T)) {
			return fun();
		}
	}
	
	void nextToken() {
		emitSkippedTokens();
		flushComments();
		
		if (match(TokenType.End)) {
			// We reached the end of our input.
			return;
		}
		
		// Process current token.
		write(token.toString(context));
		
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
		
		write(skipped.getFullLocation(context).getSlice());
		skipped = Location.init;
		
		emitSourceBasedWhiteSpace();
		split();
	}
	
	/**
	 * Comments management
	 */
	void emitComment(Location loc, Position previous) {
		emitSourceBasedWhiteSpace(loc, previous);
		
		import std.string;
		auto comment = loc.getFullLocation(context).getSlice().strip();
		if (skipFormatting() && comment == "// sdfmt on") {
			auto content = Location(sdfmtOffStart, loc.start).getFullLocation(context).getSlice();
			sdfmtOffStart = Position();
			write(content);
		}
		
		write(comment);
		
		if (comment == "// sdfmt off") {
			sdfmtOffStart = loc.stop;
			assert(skipFormatting(), "We should start skipping.");
		}
	}
	 
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
			
			emitComment(loc, previous);
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
		assert(nextCommentBlock == []);
	} do {
		if (!match(TokenType.Comment)) {
			return;
		}
		
		emitSkippedTokens();
		
		/**
		 * We distrube comments in 3 groups:
		 *   1 - The comments attached to the previous structural element.
		 *   2 - The comments in flight between two structural elements.
		 *   3 - The comments attached to the next structural element.
		 * We want to emit group 1 right away, but wait for later when
		 * emitting groups 2 and 3.
		 */
		while (match(TokenType.Comment) && newLineCount() == 0) {
			emitComment(token.location, trange.previous);
			trange.popFront();
		}
		
		emitSourceBasedWhiteSpace();
		
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
	 * Parsing
	 */
	void parseModule() {
		auto guard = changeMode(Mode.Declaration);
		
		while (!match(TokenType.End)) {
			parseStructuralElement();
		}
	}
	
	void parseColonBlock() {
		runOnType!(TokenType.Colon, nextToken)();
		if (!match(TokenType.OpenBrace)) {
			newline(1);
			return;
		}
		
		import d.parser.util;
		auto lookahead = trange.save.withComments(false);
		lookahead.popMatchingDelimiter!(TokenType.OpenBrace)();
		
		auto nextType = lookahead.front.type;
		if (nextType != TokenType.CloseBrace && nextType != TokenType.Case && nextType != TokenType.Default) {
			newline(1);
			return;
		}
		
		auto guard = builder.unindent();
		space();
		parseBlock(mode);
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
					parseColonBlock();
				} else {
					nextToken();
					nextToken();
					space();
				}

				break;
			
			case If:
				parseIf();
				break;
			
			case Version, Debug:
				parseVersion();
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
			
			case Return, Throw:
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
				
				parseColonBlock();
				break;
			
			case Default: {
					auto guard = builder.unindent();
					newline();
					nextToken();
					parseColonBlock();
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
				parseScope();
				break;
			
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
			
			case Import:
				auto lookahead = trange.save.withComments(false);
				lookahead.popFront();
				
				if (lookahead.front.type == TokenType.OpenParen) {
					// This is an import expression.
					goto default;
				}
				
				parseImport();
				break;
			
			case Unittest:
				nextToken();
				space();
				
				if (match(Identifier)) {
					nextToken();
					space();
				}
				
				parseBlock(Mode.Statement);
				
				// Blocks do not end with a semicolon.
				return;
			
			case Mixin:
				goto default;
			
			case Pragma:
				nextToken();
				parseArgumentList();
				if (match(Semicolon)) {
					break;
				}
				
				newline(1);
				goto Entry;
			
			case At:
				while(match(At)) {
					nextToken();
					parseIdentifier();
					space();
				}
				
				newline(1);
				goto Entry;
			
			case Public, Private, Protected, Package, Export:
				auto lookahead = trange.save.withComments(false);
				lookahead.popFront();
				
				if (lookahead.front.type != Colon) {
					nextToken();
					space();
					goto Entry;
				}
				
				{
					auto guard = builder.unindent();
					newline();
					nextToken();
					nextToken();
					newline();
				}
				
				break;
			
			case Enum:
				parseEnum();
				break;
			
			case Alias:
				parseAlias();
				break;
			
			case Struct, Union, Class, Interface:
				parseAggregate();
				break;
			
			default:
				if (parseStorageClassDeclaration()) {
					break;
				}
				
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
						// We just have some kind of expression.
						parseAssignExpression();
						break;
				}
				
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
	} do {
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
		flushComments();
		auto guard = span();
		
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
					split();
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
				
				if (!match(EqualMore)) {
					break;
				}
				
				// Lambda expression
				kind = IdentifierKind.Expression;
				space();
				nextToken();
				space();
				split();
				parseExpression();
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
			
			case __Traits:
				kind = IdentifierKind.Symbol;
				nextToken();
				parseArgumentList();
				break;
			
			case Assert, Import:
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
			
			case Is:
				kind = IdentifierKind.Expression;
				parseIsExpression();
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
							split();
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
				
				if (!match(OpenParen)) {
					break;
				}
				
				auto lookahead = trange.save.withComments(false);
				lookahead.popFront();
				
				if (lookahead.front.type == Return) {
					nextToken();
					nextToken();
					nextToken();
				} else {
					parseArgumentList();
				}
				
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
	} do {
		while (true) {
			switch (token.type) with(TokenType) {
				case Dot:
					split();
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
		if (match(TokenType.CloseBrace) || match(TokenType.End)) {
			{
				// Flush comments so that they have the proper indentation.
				auto guard = builder.indent();
				flushComments();
			}
			
			nextToken();
			newline(mode == Mode.Declaration ? 2 : 1);
			return;
		}
		
		{
			// We have an actual block.
			clearSplitType();
			auto blockGuard = block();
			
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
			nextToken();
			newline(2);
		}
	}
	
	bool parseControlFlowBlock(bool forceNewLine = true) {
		bool isBlock = match(TokenType.OpenBrace);
		if (isBlock) {
			parseBlock(mode);
		} else {
			auto guard = span();
			
			if (forceNewLine) {
				newline(1);
			} else {
				space();
				split();
			}
			
			parseStructuralElement();
		}
		
		return isBlock;
	}
	
	void parseElsableBlock() {
		bool isBlock = parseControlFlowBlock();
		if (!match(TokenType.Else)) {
			return;
		}
		
		emitBlockControlFlowWhitespace(isBlock);
		parseElse();
	}
	
	void parseCondition() {
		if (match(TokenType.OpenParen)) {
			nextToken();
			
			auto guard = span!AlignedSpan();
			split();
			
			auto modeGuard = changeMode(Mode.Parameter);
			
			parseStructuralElement();
			runOnType!(TokenType.CloseParen, nextToken)();
		}
	}
	
	void parseControlFlowBase() {
		nextToken();
		space();
		
		parseCondition();
		
		space();
		parseElsableBlock();
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
	} do {
		parseControlFlowBase();
	}
	
	void parseVersion() in {
		assert(match(TokenType.Version) || match(TokenType.Debug));
	} do {
		nextToken();
		
		if (match(TokenType.OpenParen)) {
			space();
			nextToken();
			
			if (match(TokenType.Identifier) || match(TokenType.Unittest)) {
				nextToken();
			}
			
			runOnType!(TokenType.CloseParen, nextToken)();
		}
		
		space();
		parseElsableBlock();
	}
	
	void parseElse() in {
		assert(match(TokenType.Else));
	} do {
		space();
		nextToken();
		space();
		
		static bool isControlFlow(TokenType t) {
			return t == TokenType.If || t == TokenType.Do || t == TokenType.While
				|| t == TokenType.For || t == TokenType.Foreach || t == TokenType.ForeachReverse
				|| t == TokenType.Version || t == TokenType.Debug;
		}
		
		bool useControlFlowBlock = !isControlFlow(token.type);
		if (useControlFlowBlock && match(TokenType.Static)) {
			auto lookahead = trange.save.withComments(false);
			lookahead.popFront();
			
			useControlFlowBlock = !isControlFlow(lookahead.front.type);
		}
		
		if (useControlFlowBlock) {
			parseControlFlowBlock();
		} else {
			parseStructuralElement();
		}
	}
	
	void parseWhile() in {
		assert(match(TokenType.While));
	} do {
		// Technically, this means while can have an else clause, and I think it is beautiful.
		parseControlFlowBase();
	}
	
	void parseDoWhile() in {
		assert(match(TokenType.Do));
	} do {
		nextToken();
		space();
		bool isBlock = parseControlFlowBlock();
		
		if (!match(TokenType.While)) {
			return;
		}
		
		emitBlockControlFlowWhitespace(isBlock);
		nextToken();
		
		if (match(TokenType.OpenParen)) {
			space();
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
	} do {
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
	} do {
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
		assert(match(TokenType.Return) || match(TokenType.Throw));
	} do {
		nextToken();
		if (token.type == TokenType.Semicolon) {
			nextToken();
			return;
		}
		
		auto guard = span();
		
		space();
		split();
		
		parseExpression();
	}
	
	void parseWith() in {
		assert(match(TokenType.With));
	} do {
		nextToken();
		space();
		
		parseCondition();
		space();
		
		parseStructuralElement();
	}

	void parseSwitch() in {
		assert(match(TokenType.Switch));
	} do {
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
	} do {
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
	} do {
		nextToken();
		space();
		parseParameterList();
		space();
		return parseControlFlowBlock();
	}
	
	bool parseFinally() in {
		assert(match(TokenType.Finally));
	} do {
		nextToken();
		space();
		return parseControlFlowBlock();
	}
	
	void parseScope() in {
		assert(match(TokenType.Scope));
	} do {
		auto lookahead = trange.save.withComments(false);
		lookahead.popFront();
		
		if (lookahead.front.type != TokenType.OpenParen) {
			parseStorageClassDeclaration();
			return;
		}
		
		nextToken();
		parseArgumentList();
		
		space();
		parseControlFlowBlock(false);
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
		parseAssignExpression();
	}
	
	void parseBaseExpression() {
		parseIdentifier();
	}
	
	void parseAssignExpression() {
		parseConditionalExpression();
		
		static bool isAssignExpression(TokenType t) {
			return t == TokenType.Equal || t == TokenType.PlusEqual || t == TokenType.MinusEqual
				|| t == TokenType.StarEqual || t == TokenType.SlashEqual || t == TokenType.PercentEqual
				|| t == TokenType.AmpersandEqual || t == TokenType.PipeEqual || t == TokenType.CaretEqual
				|| t == TokenType.TildeEqual || t == TokenType.LessLessEqual
				|| t == TokenType.MoreMoreEqual || t == TokenType.MoreMoreMoreEqual || t == TokenType.CaretCaretEqual;
		}
		
		if (!isAssignExpression(token.type)) {
			return;
		}
		
		auto guard = span();
		do {
			space();
			nextToken();
			split();
			space();
			
			parseBaseExpression();
			parseConditionalExpression();
		} while (isAssignExpression(token.type));
	}
	
	void parseConditionalExpression() {
		parseBinaryExpression();
		
		while (match(TokenType.QuestionMark)) {
			auto guard = spliceSpan!ConditionalSpan();
			
			space();
			split();
			
			guard.registerFix(function(ConditionalSpan s, size_t i) {
				s.setQuestionMarkIndex(i);
			});
			
			nextToken();
			space();
			
			parseBaseExpression();
			parseBinaryExpression();
			
			if (!match(TokenType.Colon)) {
				continue;
			}
			
			space();
			split();
			
			guard.registerFix(function(ConditionalSpan s, size_t i) {
				s.setColonIndex(i);
			});
			
			nextToken();
			space();
			
			parseBaseExpression();
			parseBinaryExpression();
		}
	}
	
	bool isBangIsOrIn() in {
		assert(match(TokenType.Bang));
	} do {
		auto lookahead = trange.save.withComments(false);
		lookahead.popFront();
		auto t = lookahead.front.type;
		return t == TokenType.Is || t == TokenType.In;
	}
	
	uint getPrecedence() {
		switch (token.type) with(TokenType) {
			case PipePipe:
				return 1;
			
			case AmpersandAmpersand:
				return 2;
			
			case Pipe:
				return 3;
			
			case Caret:
				return 4;
			
			case Ampersand:
				return 5;
			
			case Is:
			case In:
				return 6;
			
			case Bang:
				return isBangIsOrIn() ? 6 : 0;
			
			case EqualEqual:
			case BangEqual:
				return 6;
			
			case More:
			case MoreEqual:
			case Less:
			case LessEqual:
				return 6;
			
			case LessLess:
			case MoreMore:
			case MoreMoreMore:
				return 7;
			
			case BangLessMoreEqual:
			case BangLessMore:
			case LessMore:
			case LessMoreEqual:
			case BangMore:
			case BangMoreEqual:
			case BangLess:
			case BangLessEqual:
				return 7;
			
			case Plus:
			case Minus:
				return 8;
			
			case Slash:
			case Star:
			case Percent:
				return 9;
			
			case Tilde:
				return 10;
			
			default:
				return 0;
		}
	}
	
	void parseBinaryExpression(uint minPrecedence = 0) {
		auto currentPrecedence = getPrecedence();
		
		while (currentPrecedence > minPrecedence) {
			auto previousPrecedence = currentPrecedence;
			auto guard = spliceSpan();
			
			while (previousPrecedence == currentPrecedence) {
				scope(success) {
					currentPrecedence = getPrecedence();
					if (currentPrecedence > previousPrecedence) {
						parseBinaryExpression(previousPrecedence);
						currentPrecedence = getPrecedence();
					}
					
					assert(currentPrecedence <= previousPrecedence);
				}
				
				space();
				split();
				if (match(TokenType.Bang)) {
					nextToken();
				}
				nextToken();
				space();
				
				parseBaseExpression();
			}
		}
	}
	
	bool parseArgumentList() {
		return parseList!parseExpression();
	}
	
	void parseIsExpression() in {
		assert(match(TokenType.Is));
	} do {
		nextToken();
		if (!match(TokenType.OpenParen)) {
			return;
		}
		
		nextToken();
		if (match(TokenType.CloseParen)) {
			return;
		}
		
		auto modeGuard = changeMode(Mode.Parameter);
		auto spanGuard = span();
		split();
		
		parseType();
		if (match(TokenType.Identifier)) {
			space();
			nextToken();
		}
		
		static bool isTypeSpecialization(TokenType t) {
			return t == TokenType.Struct || t == TokenType.Union || t == TokenType.Class || t == TokenType.Interface
				|| t == TokenType.Enum || t == TokenType.__Vector || t == TokenType.Function || t == TokenType.Delegate
				|| t == TokenType.Super || t == TokenType.Return || t == TokenType.__Parameters
				|| t == TokenType.Module || t == TokenType.Package;
		}
		
		while (match(TokenType.EqualEqual) || match(TokenType.Colon)) {
			space();
			split();
			nextToken();
			space();
			
			if (isTypeSpecialization(token.type)) {
				nextToken();
			} else {
				parseType();
			}
		}
		
		if (match(TokenType.Comma)) {
			nextToken();
			space();
			split();
		}
		
		parseList!parseStructuralElement(TokenType.CloseParen);
	}
	
	/**
	 * Declarations
	 */
	void parseTypedDeclaration() in {
		assert(match(TokenType.Identifier));
	} do {
		bool isParameter = mode == Mode.Parameter;
		while (true) {
			auto guard = span!PrefixSpan();
			split();
			space();
			runOnType!(TokenType.Identifier, nextToken)();
			
			while (parseParameterList()) {}
			
			// Variable, template parameters, whatever.
			if (match(TokenType.Equal) || match(TokenType.Colon)) {
				auto valueGuard = span();
				
				space();
				nextToken();
				space();
				split();
				
				parseExpression();
			}
			
			if (isParameter || !match(TokenType.Comma)) {
				break;
			}
			
			nextToken();
		}
		
		parseFunctionBody();
	}
	
	void parseConstructor() in {
		assert(match(TokenType.This));
	} do {
		nextToken();
		
		while (parseParameterList()) {}
		
		parseFunctionBody();
	}
	
	void parseFunctionBody() {
		bool foundBody = false;
		while (!foundBody) {
			clearSplitType();
			space();
			
			parseStorageClasses(true);
			
			switch (token.type) with (TokenType) {
				case OpenBrace:
					// Function declaration.
					foundBody = true;
					break;
				
				case Body, Do:
					foundBody = true;
					nextToken();
					break;
				
				case In, Out:
					nextToken();
					parseParameterList();
					break;
				
				case If: {
					auto guard = span();
					split();
					nextToken();
					space();
					parseCondition();
					continue;
				}
				
				default:
					clearSplitType();
					return;
			}
			
			space();
			if (match(TokenType.OpenBrace)) {
				parseBlock(Mode.Statement);
			}
		}
	}
	
	void parseTemplate() in {
		assert(match(TokenType.Template));
	} do {
		nextToken();
		space();
		runOnType!(TokenType.Identifier, nextToken)();
		parseParameterList();
		space();
		parseBlock(Mode.Declaration);
	}
	
	void parseTemplateParameter() in {
		assert(token.type == TokenType.Identifier);
	} do {
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
	
	void parseImport() in {
		assert(match(TokenType.Import));
	} do {
		nextToken();
		
		auto guard = span!PrefixSpan();
		
		while (true) {
			space();
			split();
			parseIdentifier();
			
			if (!match(TokenType.Comma)) {
				break;
			}
			
			nextToken();
		}
		
		if (!match(TokenType.Colon)) {
			return;
		}
		
		space();
		nextToken();
		
		auto bindsGuard = spliceSpan();
		while (true) {
			space();
			split();
			
			auto bindGuard = span();
			
			parseIdentifier();
			
			if (match(TokenType.Equal)) {
				space();
				nextToken();
				space();
				split();
				
				parseIdentifier();
			}
			
			if (!match(TokenType.Comma)) {
				break;
			}
			
			nextToken();
		}
	}
	
	bool parseStorageClasses(bool isPostfix = false) {
		bool ret = false;
		while (true) {
			scope(success) {
				// This will be true after the first loop iterration.
				ret = true;
			}
			
			switch (token.type) with (TokenType) {
				case Const, Immutable, Inout, Shared, Scope:
					auto lookahead = trange.save.withComments(false);
					lookahead.popFront();
					if (lookahead.front.type == OpenParen) {
						return ret;
					}
					
					nextToken();
					break;
				
				case In, Out:
					// Make sure we deambiguate with contracts.
					if (isPostfix) {
						return ret;
					}
					
					nextToken();
					break;
				
				case Abstract, Alias, Auto, Deprecated, Enum, Final, Lazy, Nothrow:
				case Override, Pure, Ref, Return, Static, __Gshared:
					nextToken();
					break;
				
				case Align, Extern, Pragma, Synchronized:
					nextToken();
					parseArgumentList();
					break;
				
				case At:
					nextToken();
					parseIdentifier();
					break;
				
				default:
					return ret;
			}
			
			space();
		}
	}
	
	bool parseStorageClassDeclaration() {
		if (!parseStorageClasses()) {
			return false;
		}
		
		switch (token.type) with (TokenType) {
			case Colon:
				clearSplitType();
				parseColonBlock();
				break;
				
			case OpenBrace:
				parseBlock(mode);
				break;
			
			case Identifier:
				auto lookahead = trange.save.withComments(false);
				lookahead.popFront();
				
				auto t = lookahead.front.type;
				if (t == Equal || t == OpenParen) {
					parseTypedDeclaration();
					break;
				}
				
				goto default;
			
			default:
				parseStructuralElement();
				break;
		}
		
		return true;
	}
	 
	TokenType getStorageClassTokenType() {
		auto lookahead = trange.save.withComments(false);
		lookahead.popFront();
		
		if (lookahead.front.type == TokenType.Identifier) {
			lookahead.popFront();
		}
		
		if (lookahead.front.type == TokenType.OpenParen) {
			import d.parser.util;
			lookahead.popMatchingDelimiter!(TokenType.OpenParen)();
		}
		
		return lookahead.front.type;
	}
	
	void parseEnum() in {
		assert(match(TokenType.Enum));
	} do {
		auto t = getStorageClassTokenType();
		if (t != TokenType.Colon && t != TokenType.OpenBrace) {
			parseStorageClassDeclaration();
			return;
		}
		
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
			parseList!parseEnumEntry(TokenType.CloseBrace, true);
		}
	}
	
	void parseEnumEntry() {
		bool hasUDA = false;
		while(match(TokenType.At)) {
			hasUDA = true;
			nextToken();
			parseIdentifier();
			space();
		}
		
		if (hasUDA) {
			newline(1);
		}
		
		parseExpression();
	}
	
	void parseAlias() in {
		assert(match(TokenType.Alias));
	} do {
		auto t = getStorageClassTokenType();
		if (t != TokenType.This && t != TokenType.Identifier) {
			parseStorageClassDeclaration();
			return;
		}
		
		nextToken();
		space();
		
		parseIdentifier();
		
		if (match(TokenType.Identifier) || match(TokenType.This)) {
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
	
	void parseAggregate() in {
		assert(
			match(TokenType.Struct) ||
			match(TokenType.Union) ||
			match(TokenType.Class) ||
			match(TokenType.Interface));
	} do {
		nextToken();
		space();
		
		runOnType!(TokenType.Identifier, nextToken)();
		
		parseArgumentList();
		
		while (true) {
			space();
			
			switch (token.type) with(TokenType) {
				case Colon: {
					auto guard = span();
					split();
					nextToken();
					
					while (true) {
						space();
						parseIdentifier();
						
						if (!match(TokenType.Comma)) {
							break;
						}
						
						nextToken();
						split();
					}
					
					break;
				}
				
				case If: {
					auto guard = span();
					split();
					nextToken();
					space();
					parseCondition();
					break;
				}
				
				default:
					parseBlock(Mode.Declaration);
					return;
			}
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
		parseList!fun(closingTokenType);
		return true;
	}

	void parseList(alias fun)(TokenType closingTokenType, bool addNewLines = false) {
		if (match(closingTokenType)) {
			nextToken();
			return;
		}
		
		{
			auto guard = span!ListSpan();
			
			while (true) {
				if (addNewLines) {
					newline(1);
				} else {
					split();
				}
				
				fun();
				
				switch (token.type) with(TokenType) {
					case DotDot:
						auto rangeGuard = spliceSpan();
						space();
						split();
						
						nextToken();
						space();
						fun();
						break;
					
					case DotDotDot:
						nextToken();
						break;
					
					default:
						break;
				}
				
				if (!match(TokenType.Comma)) {
					break;
				}
				
				nextToken();
				space();
			}
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
	}
}
