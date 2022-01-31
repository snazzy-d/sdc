module format.parser;

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
	import source.dlexer;
	TokenRange trange;

	import format.chunk;
	Builder builder;

	bool needDoubleIndent = false;
	bool doubleIndentBlock = false;

	enum Mode {
		Declaration,
		Statement,
		Parameter,
		Attribute,
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
	 *  - inFlightComments: Comments which are on their own.
	 *  - nextComments: Comment attached to what comes next.
	 */
	Location[] inFlightComments;
	Location[] nextComments;

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
	import source.context;
	this(Position base, Context context) {
		this.trange =
			lex(base, context).withStringDecoding(false).withComments();
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
	void write(Location loc, string s) {
		if (skipFormatting()) {
			return;
		}

		if (newLineCount(loc) == 0) {
			builder.write(s);
			return;
		}

		// We have a multi line chunk.
		import std.array;
		foreach (i, l; s.split('\n')) {
			if (i > 0) {
				builder.split(true, true);
				builder.newline(1);
			}

			builder.write(l);
		}
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

	void clearSeparator() {
		if (skipFormatting()) {
			return;
		}

		builder.clearSeparator();
	}

	void split() {
		emitRawContent();
		builder.split(skipFormatting());
	}

	auto indent(uint level = 1) {
		return builder.indent(level);
	}

	auto unindent(uint level = 1) {
		return builder.unindent(level);
	}

	import format.span;
	auto span(S = Span, T...)(T args) {
		emitSkippedTokens();
		emitInFlightComments();

		return builder.span!S(args);
	}

	auto spliceSpan(S = Span, T...)(T args) {
		emitSkippedTokens();
		emitInFlightComments();

		return builder.spliceSpan!S(args);
	}

	auto block() {
		emitRawContent();
		return builder.block();
	}

	/**
	 * Miscellaneous and conveniences.
	 */
	@property
	auto context() {
		return trange.context;
	}

	/**
	 * Whitespace management.
	 */
	import source.location;
	uint getLineNumber(Position p) {
		return p.getFullPosition(context).getLineNumber();
	}

	int newLineCount(Position start, Position stop) {
		return getLineNumber(stop) - getLineNumber(start);
	}

	int newLineCount(Location location) {
		return newLineCount(location.start, location.stop);
	}

	int newLineCount(ref TokenRange r) {
		return newLineCount(r.previous, r.front.location.start);
	}

	int newLineCount() {
		return newLineCount(trange);
	}

	uint getSourceOffset(Position p) {
		return p.getFullPosition(context).getSourceOffset();
	}

	int whiteSpaceLength(Position start, Position stop) {
		return getSourceOffset(stop) - getSourceOffset(start);
	}

	int whiteSpaceLength() {
		return whiteSpaceLength(trange.previous, token.location.start);
	}

	void emitSourceBasedWhiteSpace(Position previous, Location current) {
		if (auto nl = newLineCount(previous, current.start)) {
			newline(nl);
			return;
		}

		if (whiteSpaceLength(previous, current.start) > 0) {
			space();
		}
	}

	void emitSourceBasedWhiteSpace() {
		emitSourceBasedWhiteSpace(trange.previous, token.location);
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
		write(token.location, token.toString(context));

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
			space();
			split();

			skipped = Location(trange.previous, token.location.stop);
		} else {
			skipped.spanTo(token.location);
		}

		if (match(TokenType.End)) {
			// We skipped until the end.
			return;
		}

		trange.popFront();

		// Skip over comments that look related too.
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

		import std.string;
		auto str = skipped.getFullLocation(context).getSlice().strip();
		write(skipped, str);
		skipped = Location.init;

		emitSourceBasedWhiteSpace();
		split();
	}

	/**
	 * Unformateed code management.
	 */
	void emitRawContent() {
		auto upTo = inFlightComments.length > 0
			? inFlightComments[0]
			: nextComments.length > 0 ? nextComments[0] : token.location;

		emitRawContent(upTo.start);
	}

	void emitRawContent(Position upTo) {
		if (!skipFormatting()) {
			return;
		}

		builder.write(
			Location(sdfmtOffStart, upTo).getFullLocation(context).getSlice());
		sdfmtOffStart = upTo;
	}

	/**
	 * Comments management
	 */
	void emitComment(Location loc, Position previous) {
		emitSourceBasedWhiteSpace(previous, loc);

		import std.string;
		auto comment = loc.getFullLocation(context).getSlice().strip();
		if (skipFormatting() && comment == "// sdfmt on") {
			emitRawContent(loc.start);
			sdfmtOffStart = Position();
		}

		write(loc, comment);

		if (comment == "// sdfmt off") {
			sdfmtOffStart = loc.stop;
			assert(skipFormatting(), "We should start skipping.");
		}

		// Make sure we have a line split after // style comments.
		if (!skipFormatting() && comment.startsWith("//")) {
			newline(1);
			split();
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

		emitSourceBasedWhiteSpace(previous, nextTokenLoc);
	}

	void emitInFlightComments() {
		auto nextTokenLoc =
			nextComments.length > 0 ? nextComments[0] : token.location;

		emitComments(inFlightComments, nextTokenLoc);
	}

	void flushComments() {
		emitInFlightComments();
		emitComments(nextComments, token.location);
	}

	void parseComments() in {
		assert(inFlightComments == []);
		assert(nextComments == []);
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

		nextComments = commentBlock;
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
		switch (token.type) with (TokenType) {
			case End:
				return;

			case Module:
				parseModuleDeclaration();
				break;

			/**
			 * Misc
			 */
			case DotDotDot:
				nextToken();
				return;

			/**
			 * Statements
			 */
			case OpenBrace:
				parseBlock(mode);

				// Blocks do not end with a semicolon.
				return;

			case Identifier:
				auto lookahead = trange.getLookahead();
				lookahead.popFront();
				auto t = lookahead.front.type;

				if (mode == Mode.Parameter
					    && (t == Colon || t == Equal || t == DotDotDot)) {
					parseTemplateParameter();
					break;
				}

				if (t != Colon) {
					// This is an expression or a declaration.
					goto default;
				}

				lookahead.popFront();
				if (newLineCount(lookahead) == 0) {
					nextToken();
					nextToken();
					space();
					goto Entry;
				}

				{
					auto guard = unindent();
					newline(2);
					nextToken();
				}

				parseColonBlock();
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

			case Return:
				// If this is a parameter, then return is a storage class.
				if (mode == Mode.Parameter) {
					goto default;
				}

				goto ReturnLike;

			case Throw:
				goto ReturnLike;

			ReturnLike:
				parseReturn();
				break;

			case Break, Continue:
				nextToken();

				if (match(Identifier)) {
					space();
					nextToken();
				}

				break;

			case With:
				parseWith();
				break;

			case Switch:
				parseSwitch();
				break;

			case Case:
				{
					auto guard = unindent();
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

			case Default:
				{
					auto guard = unindent();
					newline();
					nextToken();
				}

				parseColonBlock();
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
			 * Compile time constructs.
			 */
			case Static: {
				// There is nothing special to do in this case, just move on.
				if (!doubleIndentBlock) {
					goto default;
				}

				auto lookahead = trange.getLookahead();
				lookahead.popFront();
				auto t = lookahead.front.type;

				// This ia declaration.
				if (t != If && t != Foreach && t != ForeachReverse) {
					goto default;
				}

				// Request the next nested block to be double indented.
				auto oldNeedDoubleIndent = needDoubleIndent;
				scope(exit) {
					needDoubleIndent = oldNeedDoubleIndent;
				}

				needDoubleIndent = true;

				auto guard = unindent();
				split();

				nextToken();
				space();

				if (match(If)) {
					parseIf();
				} else {
					parseForeach();
				}

				break;
			}

			/**
			 * Declaration
			 */
			case This:
				// This template parameters.
				auto lookahead = trange.getLookahead();
				lookahead.popFront();

				if (lookahead.front.type == TokenType.Identifier) {
					nextToken();
					space();
					parseTypedDeclaration();
					break;
				}

				// FIXME: customized parsing depending if declaration or statement are prefered.
				// For now, assume ctor.
				parseConstructor();
				break;

			case Template:
				parseTemplate();
				break;

			case Import:
				auto lookahead = trange.getLookahead();
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
				auto lookahead = trange.getLookahead();

				// Pop all attributes.
				while (lookahead.front.type == At) {
					lookahead.popFront();

					if (lookahead.front.type == Identifier) {
						lookahead.popFront();
					}

					if (lookahead.front.type == OpenParen) {
						import source.parserutil;
						lookahead.popMatchingDelimiter!OpenParen();
					}
				}

				bool isColonBlock = lookahead.front.type == Colon;
				auto guard = unindent(isColonBlock);
				newline();

				parseAttributes();

				if (!match(Colon)) {
					newline(1);
					goto Entry;
				}

				clearSeparator();
				nextToken();
				newline();
				break;

			case Public, Private, Protected, Package, Export:
				auto lookahead = trange.getLookahead();
				lookahead.popFront();

				if (lookahead.front.type != Colon) {
					nextToken();
					space();
					goto Entry;
				}

				{
					auto guard = unindent();
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
						auto lookahead = trange.getLookahead();
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
		assert(match(TokenType.Module));
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
			switch (token.type) with (TokenType) {
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
		switch (token.type) with (TokenType) {
			case Identifier:
				nextToken();

				if (mode == Mode.Attribute) {
					break;
				}

				parseStorageClasses(true);
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
			case FloatLiteral:
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
				if (mode == Mode.Attribute) {
					parseArgumentList();
					break;
				}

				import source.parserutil;
				auto lookahead = trange.getLookahead();
				lookahead.popMatchingDelimiter!OpenParen();

				bool isLambda;
				switch (lookahead.front.type) {
					case OpenBrace,
					     EqualMore, At, Nothrow, Pure, Ref, Synchronized:
						isLambda = true;
						break;

					default:
						isLambda = false;
						break;
				}

				if (!isLambda) {
					// This isn't a lambda.
					parseArgumentList();
					break;
				}

				// We have a lambda.
				kind = IdentifierKind.Expression;
				parseParameterList();
				space();
				parseStorageClasses(true);

				switch (token.type) {
					case OpenBrace:
						goto Lambda;

					case EqualMore:
						nextToken();
						space();
						split();
						parseExpression();
						break;

					default:
						break;
				}

				break;

			case OpenBrace: {
				// Try to detect if it is a struct literal or a parameterless lambda.
				kind = IdentifierKind.Expression;

				import source.parserutil;
				auto lookahead = trange.getLookahead();

				lookahead.popFront();
				if (lookahead.front.type != Identifier) {
					goto Lambda;
				}

				lookahead.popFront();
				if (lookahead.front.type != Colon) {
					goto Lambda;
				}

				// We may still have a lambda starting with a labeled statement,
				// so we go on the hunt for a semicolon.
				lookahead.popFront();
				while (true) {
					switch (lookahead.front.type) {
						case CloseBrace:
							goto StructLiteral;

						case Semicolon:
							goto Lambda;

						case End:
							// This is malformed, assume literal.
							goto StructLiteral;

						case OpenParen:
							lookahead.popMatchingDelimiter!OpenParen();
							break;

						case OpenBrace:
							lookahead.popMatchingDelimiter!OpenBrace();
							break;

						case OpenBracket:
							lookahead.popMatchingDelimiter!OpenBracket();
							break;

						default:
							lookahead.popFront();
					}
				}
			}

			StructLiteral:
				kind = IdentifierKind.Expression;
				parseStructLiteral();
				break;

			case Function, Delegate:
				// Function and delegate literals.
				kind = IdentifierKind.Expression;

				nextToken();
				if (!match(OpenParen)) {
					// We have an explicit type.
					space();
					parseType();
				}

				if (match(OpenParen)) {
					parseParameterList();
				}

				space();
				parseStorageClasses(true);
				goto Lambda;

			Lambda:
				kind = IdentifierKind.Expression;
				parseBlock(Mode.Statement);
				clearSeparator();
				break;

			case OpenBracket:
				kind = IdentifierKind.Expression;
				parseArrayLiteral();
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

				auto lookahead = trange.getLookahead();
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
			switch (token.type) with (TokenType) {
				case Dot:
					split();
					nextToken();
					// Put another coin in the Pachinko!
					kind = parseBaseIdentifier();
					break;

				case Star:
					final switch (kind) with (IdentifierKind) {
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

					auto lookahead = trange.getLookahead();
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

				case OpenParen:
					parseArgumentList();
					break;

				case OpenBracket:
					// Technically, this is not an array literal,
					// but this should do for now.
					parseArrayLiteral();
					break;

				default:
					return;
			}
		}
	}

	/**
	 * Statements
	 */
	bool parseEmptyBlock() {
		if (!match(TokenType.CloseBrace) && !match(TokenType.End)) {
			return false;
		}

		{
			// Flush comments so that they have the proper indentation.
			auto guard = indent();
			flushComments();
		}

		nextToken();
		return true;
	}

	bool parseBlock(alias fun = parseBlockContent, T...)(T args) {
		if (!match(TokenType.OpenBrace)) {
			return false;
		}

		nextToken();
		if (parseEmptyBlock()) {
			newline(mode == Mode.Declaration ? 2 : 1);
			return true;
		}

		{
			// We have an actual block.
			clearSeparator();
			newline(1);

			auto blockGuard = block();
			fun(args);
		}

		if (match(TokenType.CloseBrace)) {
			nextToken();
			newline(2);
		}

		return true;
	}

	void parseBlockContent(Mode m) {
		auto indentGuard = indent(1 + needDoubleIndent);
		auto modeGuard = changeMode(m);

		auto oldNeedDoubleIndent = needDoubleIndent;
		auto oldDoubleIndentBlock = doubleIndentBlock;
		scope(exit) {
			needDoubleIndent = oldNeedDoubleIndent;
			doubleIndentBlock = oldDoubleIndentBlock;
		}

		doubleIndentBlock = needDoubleIndent;
		needDoubleIndent = false;

		split();

		while (!match(TokenType.CloseBrace) && !match(TokenType.End)) {
			parseStructuralElement();
		}

		// Flush comments so that they have the proper indentation.
		flushComments();
	}

	static isBasicBlockEntry(ref TokenRange r) {
		auto t = r.front.type;
		if (t == TokenType.Case || t == TokenType.Default) {
			return true;
		}

		if (t != TokenType.Identifier) {
			return false;
		}

		// Check for labeled statements.
		r.popFront();
		return r.front.type == TokenType.Colon;
	}

	static isBasicBlockTerminator(TokenType t) {
		return t == TokenType.CloseBrace || t == TokenType.Return
			|| t == TokenType.Break || t == TokenType.Continue
			|| t == TokenType.Goto || t == TokenType.Throw;
	}

	static isBasicBlockBoundary(ref TokenRange r) {
		return isBasicBlockTerminator(r.front.type) || isBasicBlockEntry(r);
	}

	void parseColonBlock() {
		runOnType!(TokenType.Colon, nextToken)();

		if (match(TokenType.CloseBrace)) {
			// Empty colon block.
			return;
		}

		if (!match(TokenType.OpenBrace)) {
			newline(1);
			parseStructuralElement();
			return;
		}

		import source.parserutil;
		auto lookahead = trange.getLookahead();
		lookahead.popMatchingDelimiter!(TokenType.OpenBrace)();
		if (!isBasicBlockBoundary(lookahead)) {
			newline(1);
			return;
		}

		auto guard = unindent();
		space();
		parseBlock(mode);
	}

	bool parseControlFlowBlock(bool forceNewLine = true) {
		if (parseBlock(mode)) {
			return true;
		}

		auto guard = span();

		if (forceNewLine) {
			newline(1);
		} else {
			space();
		}

		split();
		parseStructuralElement();
		return false;
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

			guard.registerFix(function(AlignedSpan s, size_t i) {
				s.alignOn(i);
			});

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
		clearSeparator();
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
			return t == TokenType.If || t == TokenType.Do
				|| t == TokenType.While || t == TokenType.For
				|| t == TokenType.Foreach || t == TokenType.ForeachReverse
				|| t == TokenType.Version || t == TokenType.Debug;
		}

		bool useControlFlowBlock = !isControlFlow(token.type);
		if (useControlFlowBlock && match(TokenType.Static)) {
			auto lookahead = trange.getLookahead();
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
				clearSeparator();
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

		// Request the next nested block to be double indented.
		auto oldNeedDoubleIndent = needDoubleIndent;
		scope(exit) {
			needDoubleIndent = oldNeedDoubleIndent;
		}

		needDoubleIndent = true;
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
		auto lookahead = trange.getLookahead();
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
			return t == TokenType.Equal || t == TokenType.PlusEqual
				|| t == TokenType.MinusEqual || t == TokenType.StarEqual
				|| t == TokenType.SlashEqual || t == TokenType.PercentEqual
				|| t == TokenType.AmpersandEqual || t == TokenType.PipeEqual
				|| t == TokenType.CaretEqual || t == TokenType.TildeEqual
				|| t == TokenType.LessLessEqual || t == TokenType.MoreMoreEqual
				|| t == TokenType.MoreMoreMoreEqual
				|| t == TokenType.CaretCaretEqual;
		}

		if (!isAssignExpression(token.type)) {
			return;
		}

		auto guard = spliceSpan();
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

		if (!match(TokenType.QuestionMark)) {
			return;
		}

		auto guard = spliceSpan!ConditionalSpan();

		space();
		split();

		guard.registerFix(function(ConditionalSpan s, size_t i) {
			s.setQuestionMarkIndex(i);
		});

		nextToken();
		space();

		parseExpression();

		space();
		split();

		runOnType!(TokenType.Comma, nextToken)();
		guard.registerFix(function(ConditionalSpan s, size_t i) {
			s.setColonIndex(i);
		});

		nextToken();
		space();

		parseBaseExpression();
		parseConditionalExpression();
	}

	bool isBangIsOrIn() in {
		assert(match(TokenType.Bang));
	} do {
		auto lookahead = trange.getLookahead();
		lookahead.popFront();
		auto t = lookahead.front.type;
		return t == TokenType.Is || t == TokenType.In;
	}

	uint getPrecedence() {
		switch (token.type) with (TokenType) {
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

	void parseArgumentList() {
		if (!match(TokenType.OpenParen)) {
			return;
		}

		nextToken();
		parseList!parseExpression(TokenType.CloseParen);
	}

	void parseArrayLiteral() {
		if (!match(TokenType.OpenBracket)) {
			return;
		}

		nextToken();
		parseList!parseArrayElement(TokenType.CloseBracket);
	}

	void parseArrayElement() {
		parseExpression();

		if (match(TokenType.Colon)) {
			space();
			nextToken();
			space();
			parseExpression();
		}
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
			return t == TokenType.Struct || t == TokenType.Union
				|| t == TokenType.Class || t == TokenType.Interface
				|| t == TokenType.Enum || t == TokenType.__Vector
				|| t == TokenType.Function || t == TokenType.Delegate
				|| t == TokenType.Super || t == TokenType.Return
				|| t == TokenType.__Parameters
				|| t == TokenType.Module || t == TokenType.Package;
		}

		while (match(TokenType.EqualEqual) || match(TokenType.Colon)) {
			auto specGuard = span();

			space();
			split();
			nextToken();
			space();

			if (isTypeSpecialization(token.type)) {
				nextToken();
			} else {
				parseType();
			}

			clearSeparator();
		}

		if (match(TokenType.Comma)) {
			nextToken();
			space();
			split();
		}

		parseList!parseStructuralElement(TokenType.CloseParen);
	}

	void parseStructLiteral() {
		parseBlock!parseStructLiteralContent();
		clearSeparator();
	}

	void parseStructLiteralContent() {
		auto indentGuard = indent();

		split();

		while (!match(TokenType.CloseBrace) && !match(TokenType.End)) {
			parseMapEntry();
			runOnType!(TokenType.Comma, nextToken)();
			newline(1);
		}

		// Flush comments so that they have the proper indentation.
		flushComments();
	}

	void parseMapEntry() {
		auto guard = span();
		runOnType!(TokenType.Identifier, nextToken)();
		runOnType!(TokenType.Colon, nextToken)();

		split();
		space();
		parseExpression();
	}

	/**
	 * Declarations
	 */
	void parseParameterPacks() {
		ListOptions options;
		options.closingTokenType = TokenType.CloseParen;

		auto guard = changeMode(Mode.Parameter);

		while (match(TokenType.OpenParen)) {
			nextToken();
			parseList!parseStructuralElement(options);
			options.splice = true;
		}
	}

	void parseTypedDeclaration() in {
		assert(match(TokenType.Identifier));
	} do {
		bool isParameter = mode == Mode.Parameter;
		while (true) {
			auto guard = span!PrefixSpan();
			split();
			space();
			runOnType!(TokenType.Identifier, nextToken)();

			parseParameterPacks();

			// Variable, template parameters, whatever.
			if (match(TokenType.Equal) || match(TokenType.Colon)) {
				auto valueGuard = spliceSpan();

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
		parseParameterPacks();
		parseFunctionBody();
	}

	void parseFunctionBody() {
		if (parseFunctionPostfix()) {
			space();
			parseBlock(Mode.Statement);
		}
	}

	bool parseFunctionPostfix() {
		auto guard = span!IndentSpan(2);

		while (true) {
			clearSeparator();
			space();

			switch (token.type) with (TokenType) {
				case OpenBrace:
					// Function declaration.
					return true;

				case Body, Do:
					nextToken();
					return true;

				case In:
					nextToken();
					if (!parseParameterList()) {
						space();
						parseBlock(Mode.Statement);
					}

					break;

				case Out:
					// FIXME: This doesn't looks like it is doing the right thing.
					nextToken();
					parseParameterList();
					space();
					parseBlock(Mode.Statement);
					break;

				case If:
					split();
					nextToken();
					space();
					parseCondition();
					break;

				default:
					if (!parseStorageClasses(true)) {
						clearSeparator();
						return false;
					}

					break;
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

		if (match(TokenType.If)) {
			auto guard = span!IndentSpan(2);
			split();
			nextToken();
			space();
			parseCondition();
			space();
		}

		parseBlock(Mode.Declaration);
	}

	void parseTemplateParameter() in {
		assert(token.type == TokenType.Identifier);
	} do {
		nextToken();

		if (match(TokenType.DotDotDot)) {
			nextToken();
		}

		while (match(TokenType.Colon) || match(TokenType.Equal)) {
			space();
			nextToken();
			space();
			parseType();
		}
	}

	bool parseParameterList() {
		if (!match(TokenType.OpenParen)) {
			return false;
		}

		auto guard = changeMode(Mode.Parameter);
		nextToken();
		parseList!parseStructuralElement(TokenType.CloseParen);
		return true;
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

	void parseAttributes() {
		auto guard = changeMode(Mode.Attribute);

		while (match(TokenType.At)) {
			nextToken();
			parseIdentifier();
			space();
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
					auto lookahead = trange.getLookahead();
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

				case Abstract, Alias, Auto, Enum, Final, Lazy,
				     Nothrow, Override, Pure, Ref, Return, Static, __Gshared:
					nextToken();
					break;

				case Align, Deprecated, Extern, Pragma, Synchronized:
					nextToken();
					parseArgumentList();
					break;

				case At:
					parseAttributes();
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
				clearSeparator();
				parseColonBlock();
				break;

			case OpenBrace:
				parseBlock(mode);
				break;

			case Identifier:
				auto lookahead = trange.getLookahead();
				lookahead.popFront();

				auto t = lookahead.front.type;
				if (t == Equal || t == OpenParen) {
					split();
					parseTypedDeclaration();
					break;
				}

				goto default;

			case Assert, Foreach, ForeachReverse, If:
				parseStructuralElement();
				break;

			default:
				split();
				parseStructuralElement();
				break;
		}

		return true;
	}

	TokenType getStorageClassTokenType() {
		auto lookahead = trange.getLookahead();
		lookahead.popFront();

		if (lookahead.front.type == TokenType.Identifier) {
			lookahead.popFront();
		}

		if (lookahead.front.type == TokenType.OpenParen) {
			import source.parserutil;
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
		while (match(TokenType.At)) {
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
		}
	}

	void parseAggregate() in {
		assert(match(TokenType.Struct) || match(TokenType.Union)
			|| match(TokenType.Class) || match(TokenType.Interface));
	} do {
		nextToken();
		space();

		runOnType!(TokenType.Identifier, nextToken)();

		parseParameterList();

		while (true) {
			space();

			switch (token.type) with (TokenType) {
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
					auto guard = span!IndentSpan(2);
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
	struct ListOptions {
		TokenType closingTokenType;
		bool addNewLines = false;
		bool splice = false;
	}

	void parseList(alias fun)(TokenType closingTokenType,
	                          bool addNewLines = false) {
		ListOptions options;
		options.closingTokenType = closingTokenType;
		options.addNewLines = addNewLines;

		return parseList!fun(options);
	}

	void parseList(alias fun)(ListOptions options) {
		auto guard = builder.virtualSpan();

		if (match(options.closingTokenType)) {
			nextToken();
			return;
		}

		parseInnerList!fun(options);

		if (match(options.closingTokenType)) {
			auto trailingGuard = span!TrainlingListSpan();
			if (options.addNewLines) {
				newline(1);
			}

			nextToken();
		}

		if (options.addNewLines) {
			newline(2);
		}
	}

	void parseInnerList(alias fun)(ListOptions options) {
		auto guard = options.splice ? spliceSpan!ListSpan() : span!ListSpan();

		while (!match(options.closingTokenType)) {
			if (options.addNewLines) {
				newline(1);
			}

			split();
			guard.registerFix(function(ListSpan s, size_t i) {
				s.registerElement(i);
			});

			fun();

			if (match(TokenType.DotDot)) {
				auto rangeGuard = spliceSpan();
				space();
				split();

				nextToken();
				space();
				fun();
			}

			if (!match(TokenType.Comma)) {
				break;
			}

			nextToken();
			space();
		}
	}
}
