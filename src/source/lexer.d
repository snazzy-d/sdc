module source.lexer;

import std.array;
import std.range;
import std.utf;

enum TokenType {
	Invalid = 0,
	
	Begin,
	End,
	
	// Comments
	Comment,
	
	// Literals
	StringLiteral,
	CharacterLiteral,
	IntegerLiteral,
	FloatLiteral,
	
	// Identifier
	Identifier,
	
	// Keywords
	Abstract, Alias, Align, Asm, Assert, Auto,
	Body, Bool, Break, Byte,
	Case, Cast, Catch, Cdouble, Cent, Cfloat, Char,
	Class, Const, Continue, Creal,
	Dchar, Debug, Default, Delegate, Delete,
	Deprecated, Do, Double,
	Else, Enum, Export, Extern,
	False, Final, Finally, Float, For, Foreach,
	ForeachReverse, Function,
	Goto,
	Idouble, If, Ifloat, Immutable, Import, In,
	Inout, Int, Interface, Invariant, Ireal, Is,
	Lazy, Long,
	Macro, Mixin, Module,
	New, Nothrow, Null,
	Out, Override,
	Package, Pragma, Private, Protected, Public, Pure,
	Real, Ref, Return,
	Scope, Shared, Short, Static, Struct, Super,
	Switch, Synchronized,
	Template, This, Throw, True, Try, Typedef,
	Typeid, Typeof,
	Ubyte, Ucent, Uint, Ulong, Union, Unittest, Ushort,
	Version, Void, Volatile,
	Wchar, While, With,
	__File__, __Line__, __Gshared, __Traits, __Vector, __Parameters,
	
	/// Operators.
	Slash,				// /
	SlashEqual,			// /=
	Dot,				// .
	DotDot,				// ..
	DotDotDot,			// ...
	Ampersand,			// &
	AmpersandEqual,		// &=
	AmpersandAmpersand,	// &&
	Pipe,				// |
	PipeEqual,			// |=
	PipePipe,			// ||
	Minus,				// -
	MinusEqual,			// -=
	MinusMinus,			// --
	Plus,				// +
	PlusEqual,			// +=
	PlusPlus,			// ++
	Less,				// <
	LessEqual,			// <=
	LessLess,			// <<
	LessLessEqual,		// <<=
	LessMore,			// <>
	LessMoreEqual,		// <>=
	More,				// >
	MoreEqual,			// >=
	MoreMoreEqual,		// >>=
	MoreMoreMoreEqual,	// >>>=
	MoreMore,			// >>
	MoreMoreMore,		// >>>
	Bang,				// !
	BangEqual,			// !=
	BangLessMore,		// !<>
	BangLessMoreEqual,	// !<>=
	BangLess,			// !<
	BangLessEqual,		// !<=
	BangMore,			// !>
	BangMoreEqual,		// !>=
	OpenParen,			// (
	CloseParen,			// )
	OpenBracket,		// [
	CloseBracket,		// ]
	OpenBrace,			// {
	CloseBrace,			// }
	QuestionMark,		// ?
	Comma,				// ,
	Semicolon,			// ;
	Colon,				// :
	Dollar,				// $
	Equal,				// =
	EqualEqual,			// ==
	Star,				// *
	StarEqual,			// *=
	Percent,			// %
	PercentEqual,		// %=
	Caret,				// ^
	CaretEqual,			// ^=
	CaretCaret,			// ^^
	CaretCaretEqual,	// ^^=
	Tilde,				// ~
	TildeEqual,			// ~=
	At,					// @
	EqualMore,			// =>
	Hash,				// #
}

import source.context;
import source.location;

struct Token {
	Location location;
	TokenType type;
	
	import source.name;
	Name name;
	
	string toString(Context context) {
		return (type >= TokenType.Identifier)
			? name.toString(context)
			: location.getFullLocation(context).getSlice();
	}
}

auto lex(Position base, Context context) {
	auto lexer = TokenRange();
	
	lexer.content = base.getFullPosition(context).getSource().getContent();
	lexer.t.type = TokenType.Begin;
	
	lexer.context = context;
	lexer.base = base;
	lexer.previous = base;
	
	// Pop #!
	auto c = lexer.frontChar;
	if (c == '#') {
		do {
			lexer.popChar();
			c = lexer.frontChar;
		} while (c != '\n' && c != '\r');
		
		lexer.popChar();
		if (c == '\r') {
			if (lexer.frontChar == '\n') {
				lexer.popChar();
			}
		}
	}
	
	lexer.t.location =  Location(base, base.getWithOffset(lexer.index));
	return lexer;
}

struct TokenRange {
// TODO: We shouldn't let consumer play with the internal state of the lexer.
// Instead, we should provide accessor to useful members.
// private:
	static assert(isForwardRange!TokenRange);
	
	Token t;
	Position previous;
	
	Position base;
	uint index;
	
	Context context;
	string content;
	
	// Skip comments by default.
	bool tokenizeComments = false;
	
public:
	TokenRange withComments(bool wc = true) {
		TokenRange r = this.save;
		r.tokenizeComments = wc;
		return r;
	}
	
	// We don't want the lexer to be copyable. Use save.
	@disable this(this);
	
	@property
	auto front() inout {
		return t;
	}
	
	void popFront() {
		previous = t.location.stop;
		t = getNextToken();
		
		/+ Exprerience the token deluge !
		if (t.type != TokenType.End) {
			import util.terminal, std.conv;
			outputCaretDiagnostics(
				t.location.getFullLocation(context),
				to!string(t.type),
			);
		}
		// +/
	}
	
	void moveTo(ref TokenRange fr) in {
		assert(base is fr.base);
		assert(context is fr.context);
		assert(content is fr.content);
		assert(index < fr.index);
	} do {
		index = fr.index;
		t = fr.t;
	}
	
	@property
	auto save() inout {
		return inout(TokenRange)(t, previous, base, index, context, content);
	}
	
	@property
	bool empty() const {
		return t.type == TokenType.End;
	}
	
private:
	auto getNextToken() {
		while (true) {
			// pragma(msg, lexerMixin());
			mixin(lexerMixin());
		}
	}
	
	void popChar() {
		index++;
	}
	
	@property
	char frontChar() const {
		return content[index];
	}
	
	auto lexWhiteSpace(string s)() {
		// Just skip over whitespace.
	}
	
	uint popComment(string s)() {
		auto c = frontChar;
		
		static if (s == "//") {
			// TODO: check for unicode line break.
			while (c != '\n' && c != '\r') {
				if (c == 0) {
					return index;
				}
				
				popChar();
				c = frontChar;
			}
			
			uint ret = index;
			
			popChar();
			if (c == '\r') {
				if (frontChar == '\n') {
					popChar();
				}
			}
			
			return ret;
		} else static if (s == "/*") {
			while (true) {
				while (c != '*') {
					popChar();
					c = frontChar;
				}
				
				auto match = c;
				popChar();
				c = frontChar;
				
				if (c == '/') {
					popChar();
					return index;
				}
			}
		} else static if (s == "/+") {
			uint stack = 0;
			while (true) {
				while (c != '+' && c != '/') {
					popChar();
					c = frontChar;
				}
				
				auto match = c;
				popChar();
				c = frontChar;
				
				switch (match) {
					case '+' :
						if (c == '/') {
							popChar();
							if (!stack) {
								return index;
							}
							
							c = frontChar;
							stack--;
						}
						
						break;
					
					case '/' :
						if (c == '+') {
							popChar();
							c = frontChar;
							
							stack++;
						}
						
						break;
					
					default :
						assert(0, "Unreachable.");
				}
			}
		} else {
			static assert(0, s ~ " isn't a known type of comment.");
		}
	}
	
	auto lexComment(string s)() {
		Token t;
		t.type = TokenType.Comment;
		uint prefixLength = s.length;
		auto ibegin = index - prefixLength;
		auto begin = base.getWithOffset(ibegin);
		
		uint iend = popComment!s();
		
		t.location = Location(begin, base.getWithOffset(iend));
		t.name = context.getName(content[ibegin .. iend]);
		
		return t;
	}
	
	auto lexIdentifier(string s)() {
		static if (s == "") {
			if (isIdChar(frontChar)) {
				popChar();
				return lexIdentifier(1);
			}
			
			// XXX: proper error reporting.
			assert(frontChar & 0x80, "lex error");
			
			// XXX: Dafuq does this need to be a size_t ?
			size_t i = index;
			
			import std.uni;
			auto u = content.decode(i);
			assert(isAlpha(u), "lex error");
			
			auto l = cast(ubyte) (i - index);
			index += l;
			return lexIdentifier(l);
		} else {
			return lexIdentifier(s.length);
		}
	}
	
	auto lexIdentifier(uint prefixLength) in {
		assert(prefixLength > 0);
		assert(index >= prefixLength);
	} do {
		Token t;
		t.type = TokenType.Identifier;
		auto ibegin = index - prefixLength;
		auto begin = base.getWithOffset(ibegin);
		
		while (true) {
			while (isIdChar(frontChar)) {
				popChar();
			}
			
			if (!(frontChar | 0x80)) {
				break;
			}
			
			// XXX: Dafuq does this need to be a size_t ?
			size_t i = index;
			
			import std.uni;
			auto u = content.decode(i);
			if (!isAlpha(u)) {
				break;
			}
			
			index = cast(uint) i;
		}
		
		t.location = Location(begin, base.getWithOffset(index));
		t.name = context.getName(content[ibegin .. index]);
		
		return t;
	}
	
	Token lexString(string s)() in {
		assert(index >= s.length);
	} do {
		Token t;
		auto begin = base.getWithOffset(index - cast(uint) s.length);
		t.type = (s != "\'")
			? TokenType.StringLiteral
			: TokenType.CharacterLiteral;
		
		enum Delimiter = s[0];
		enum DoesEscape = Delimiter != '`';
		
		auto c = frontChar;
		while (c != Delimiter && c != '\0') {
			if (DoesEscape && c == '\\') {
				popChar();
				c = frontChar;
			}
			
			popChar();
			c = frontChar;
		}
		
		if (c == Delimiter) {
			popChar();
		}
		
		t.location = Location(begin, base.getWithOffset(index));
		return t;
	}
	
	auto lexNumeric(string s)() if (s.length == 1 && isDigit(s[0])) {
		return lexNumeric(s[0]);
	}
	
	Token lexNumeric(string s)() if (s.length == 2 && s[0] == '0') {
		Token t;
		t.type = TokenType.IntegerLiteral;
		auto ibegin = index - 2;
		auto begin = base.getWithOffset(ibegin);
		
		auto c = frontChar;
		switch(s[1] | 0x20) {
			case 'b':
				assert(c == '0' || c == '1', "invalid integer literal");
				while (true) {
					while (c == '0' || c == '1') {
						popChar();
						c = frontChar;
					}
					
					if (c == '_') {
						popChar();
						c = frontChar;
						continue;
					}
					
					break;
				}
				
				break;
			
			case 'x':
				auto hc = c | 0x20;
				assert((c >= '0' && c <= '9') || (hc >= 'a' && hc <= 'f'), "invalid integer literal");
				while (true) {
					hc = c | 0x20;
					while ((c >= '0' && c <= '9') || (hc >= 'a' && hc <= 'f')) {
						popChar();
						c = frontChar;
						hc = c | 0x20;
					}
					
					if (c == '_') {
						popChar();
						c = frontChar;
						continue;
					}
					
					break;
				}
				
				break;
			
			default :
				assert(0, s ~ " is not a valid prefix.");
		}
		
		switch(c | 0x20) {
			case 'u':
				popChar();
				
				c = frontChar;
				if (c == 'L' || c == 'l') {
					popChar();
				}
				
				break;
			
			case 'l':
				popChar();
				
				c = frontChar;
				if (c == 'U' || c == 'u') {
					popChar();
				}
				
				break;
			
			default:
				break;
		}
		
		t.location = Location(begin, base.getWithOffset(index));
		return t;
	}
	
	auto lexNumeric(char c) {
		Token t;
		t.type = TokenType.IntegerLiteral;
		auto ibegin = index - 1;
		auto begin = base.getWithOffset(ibegin);
		
		assert(c >= '0' && c <= '9', "invalid integer literal");
		
		c = frontChar;
		while (true) {
			while (c >= '0' && c <= '9') {
				popChar();
				c = frontChar;
			}
			
			if (c == '_') {
				popChar();
				c = frontChar;
				continue;
			}
			
			break;
		}
		
		switch (c) {
			case '.':
				auto lookAhead = content;
				lookAhead.popFront();
				
				if (lookAhead.front.isDigit()) {
					popChar();
					
					t.type = TokenType.FloatLiteral;
					
					assert(0, "No floating point ATM");
					// pumpChars!isDigit(content);
				}
				
				break;
			
			case 'U', 'u':
				popChar();
				
				c = frontChar;
				if (c == 'L' || c == 'l') {
					popChar();
				}
				
				break;
			
			case 'L', 'l':
				popChar();
				
				c = frontChar;
				if (c == 'U' || c == 'u') {
					popChar();
				}
				
				break;
			
			default:
				break;
		}
		
		t.location = Location(begin, base.getWithOffset(index));
		return t;
	}
	
	auto lexKeyword(string s)() {
		auto c = frontChar;
		if (isIdChar(c)) {
			popChar();
			return lexIdentifier(s.length + 1);
		}
		
		if (c & 0x80) {
			size_t i = index;
			
			import std.uni;
			auto u = content.decode(i);
			if (isAlpha(u)) {
				auto l = cast(ubyte) (i - index);
				index += l;
				return lexIdentifier(s.length + l);
			}
		}
		
		enum type = getKeywordsMap()[s];
		
		uint l = s.length;
		
		Token t;
		t.type = type;
		t.location = Location(base.getWithOffset(index - l), base.getWithOffset(index));

		import source.name;
		t.name = BuiltinName!s;
		
		return t;
	}
	
	auto lexOperator(string s)() {
		enum type = getOperatorsMap()[s];
		
		uint l = s.length;
		
		Token t;
		t.type = type;
		t.location = Location(base.getWithOffset(index - l), base.getWithOffset(index));

		import source.name;
		t.name = BuiltinName!s;
		
		return t;
	}
}

private:

@property
char front(string s) {
	return s[0];
}

void popFront(ref string s) {
	s = s[1 .. $];
}

auto isIdChar(char c) {
	import std.ascii;
	return c == '_' || isAlphaNum(c);
}

auto isDigit(char c) {
	import std.ascii;
	return std.ascii.isDigit(c);
}

mixin template CharPumper(bool decode = true) {
	// Nothing that we lex should be bigger than this (except very rare cases).
	enum BufferSize = 128;
	char[BufferSize] buffer = void;
	string heapBuffer;
	size_t i;
	
	void pumpChars(alias condition, R)(ref R r) {
		char c;
		
		Begin:
		if (i < BufferSize) {
			do {
				c = r.front;
				
				if (condition(c)) {
					buffer[i++] = c;
					popChar();
					
					continue;
				} else static if (decode) {
					// Check if if have an unicode character.
					if (c & 0x80) {
						size_t i = index;
						auto u = content.decode(i);
						
						if (condition(u)) {
							auto l = cast(ubyte) (i - index);
							while (l--) {
								putChar(r.front);
								popChar();
							}
							
							goto Begin;
						}
					}
				}
				
				return;
			} while (i < BufferSize);
			
			// Buffer is full, we need to work on heap;
			heapBuffer = buffer.idup;
		}
		
		while (true) {
			 c = r.front;
			 
			 if (condition(c)) {
				heapBuffer ~= c;
				popChar();
				
				continue;
			 } else static if (decode) {
				// Check if if have an unicode character.
				if (c & 0x80) {
					size_t i = index;
					auto u = content.decode(i);
					
					if (condition(u)) {
						auto l = cast(ubyte) (i - index);
						heapBuffer.reserve(l);
						
						while (l--) {
							heapBuffer ~= r.front;
							popChar();
						}
					}
				}
			}
			
			return;
		}
	}
	
	void putChar(char c) {
		if (i < BufferSize) {
			buffer[i++] = c;
			
			if (i == BufferSize) {
				// Buffer is full, we need to work on heap;
				heapBuffer = buffer.idup;
			}
		} else {
			heapBuffer ~= c;
		}
	}
	
	void putString(string s) {
		auto finalSize = i + s.length;
		if (finalSize < BufferSize) {
			buffer[i .. finalSize][] = s[];
			i = finalSize;
		} else if (i < BufferSize) {
			heapBuffer.reserve(finalSize);
			heapBuffer ~= buffer[0 .. i];
			heapBuffer ~= s;
			
			i = BufferSize;
		} else {
			heapBuffer ~= s;
		}
	}
	
	auto getValue() {
		return context.getName(
			(i < BufferSize)
				? buffer[0 .. i].idup
				: heapBuffer
		);
	}
}

public:
auto getOperatorsMap() {
	//with(TokenType): currently isn't working https://issues.dlang.org/show_bug.cgi?id=14332
	with(TokenType)
	return [
		"/"		: Slash,
		"/="	: SlashEqual,
		"."		: Dot,
		".."	: DotDot,
		"..."	: DotDotDot,
		"&"		: Ampersand,
		"&="	: AmpersandEqual,
		"&&"	: AmpersandAmpersand,
		"|"		: Pipe,
		"|="	: PipeEqual,
		"||"	: PipePipe,
		"-"		: Minus,
		"-="	: MinusEqual,
		"--"	: MinusMinus,
		"+"		: Plus,
		"+="	: PlusEqual,
		"++"	: PlusPlus,
		"<"		: Less,
		"<="	: LessEqual,
		"<<"	: LessLess,
		"<<="	: LessLessEqual,
		"<>"	: LessMore,
		"<>="	: LessMoreEqual,
		">"		: More,
		">="	: MoreEqual,
		">>="	: MoreMoreEqual,
		">>>="	: MoreMoreMoreEqual,
		">>"	: MoreMore,
		">>>"	: MoreMoreMore,
		"!"		: Bang,
		"!="	: BangEqual,
		"!<>"	: BangLessMore,
		"!<>="	: BangLessMoreEqual,
		"!<"	: BangLess,
		"!<="	: BangLessEqual,
		"!>"	: BangMore,
		"!>="	: BangMoreEqual,
		"("		: OpenParen,
		")"		: CloseParen,
		"["		: OpenBracket,
		"]"		: CloseBracket,
		"{"		: OpenBrace,
		"}"		: CloseBrace,
		"?"		: QuestionMark,
		","		: Comma,
		";"		: Semicolon,
		":"		: Colon,
		"$"		: Dollar,
		"="		: Equal,
		"=="	: EqualEqual,
		"*"		: Star,
		"*="	: StarEqual,
		"%"		: Percent,
		"%="	: PercentEqual,
		"^"		: Caret,
		"^="	: CaretEqual,
		"^^"	: CaretCaret,
		"^^="	: CaretCaretEqual,
		"~"		: Tilde,
		"~="	: TildeEqual,
		"@"		: At,
		"=>"	: EqualMore,
		"#"		: Hash,
		"\0"	: End,
	];
}

auto getKeywordsMap() {
	//with(TokenType): currently isn't working https://issues.dlang.org/show_bug.cgi?id=14332
	with(TokenType)
	return [
		"abstract"			: Abstract,
		"alias"				: Alias,
		"align"				: Align,
		"asm"				: Asm,
		"assert"			: Assert,
		"auto"				: Auto,
		"body"				: Body,
		"bool"				: Bool,
		"break"				: Break,
		"byte"				: Byte,
		"case"				: Case,
		"cast"				: Cast,
		"catch"				: Catch,
		"cent"				: Cent,
		"char"				: Char,
		"class"				: Class,
		"const"				: Const,
		"continue"			: Continue,
		"dchar"				: Dchar,
		"debug"				: Debug,
		"default"			: Default,
		"delegate"			: Delegate,
		"deprecated"		: Deprecated,
		"do"				: Do,
		"double"			: Double,
		"else"				: Else,
		"enum"				: Enum,
		"export"			: Export,
		"extern"			: Extern,
		"false"				: False,
		"final"				: Final,
		"finally"			: Finally,
		"float"				: Float,
		"for"				: For,
		"foreach"			: Foreach,
		"foreach_reverse"	: ForeachReverse,
		"function"			: Function,
		"goto"				: Goto,
		"if"				: If,
		"immutable"			: Immutable,
		"import"			: Import,
		"in"				: In,
		"inout"				: Inout,
		"int"				: Int,
		"interface"			: Interface,
		"invariant"			: Invariant,
		"is"				: Is,
		"lazy"				: Lazy,
		"long"				: Long,
		"macro"				: Macro,
		"mixin"				: Mixin,
		"module"			: Module,
		"new"				: New,
		"nothrow"			: Nothrow,
		"null"				: Null,
		"out"				: Out,
		"override"			: Override,
		"package"			: Package,
		"pragma"			: Pragma,
		"private"			: Private,
		"protected"			: Protected,
		"public"			: Public,
		"pure"				: Pure,
		"real"				: Real,
		"ref"				: Ref,
		"return"			: Return,
		"scope"				: Scope,
		"shared"			: Shared,
		"short"				: Short,
		"static"			: Static,
		"struct"			: Struct,
		"super"				: Super,
		"switch"			: Switch,
		"synchronized"		: Synchronized,
		"template"			: Template,
		"this"				: This,
		"throw"				: Throw,
		"true"				: True,
		"try"				: Try,
		"typeid"			: Typeid,
		"typeof"			: Typeof,
		"ubyte"				: Ubyte,
		"ucent"				: Ucent,
		"uint"				: Uint,
		"ulong"				: Ulong,
		"union"				: Union,
		"unittest"			: Unittest,
		"ushort"			: Ushort,
		"version"			: Version,
		"void"				: Void,
		"volatile"			: Volatile,
		"wchar"				: Wchar,
		"while"				: While,
		"with"				: With,
		"__FILE__"			: __File__,
		"__LINE__"			: __Line__,
		"__gshared"			: __Gshared,
		"__traits"			: __Traits,
		"__vector"			: __Vector,
		"__parameters"		: __Parameters,
	];
}

private:
auto getLexerMap() {
	auto ret = [
		// WhiteSpaces
		" "					: "-lexWhiteSpace",
		"\t"				: "-lexWhiteSpace",
		"\v"				: "-lexWhiteSpace",
		"\f"				: "-lexWhiteSpace",
		"\n"				: "-lexWhiteSpace",
		"\r"				: "-lexWhiteSpace",
		"\r\n"				: "-lexWhiteSpace",
		
		// Comments
		"//"				: "!tokenizeComments?lexComment:popComment",
		"/*"				: "!tokenizeComments?lexComment:popComment",
		"/+"				: "!tokenizeComments?lexComment:popComment",
		
		// Integer literals.
		"0b"				: "lexNumeric",
		"0B"				: "lexNumeric",
		"0x"				: "lexNumeric",
		"0X"				: "lexNumeric",
		
		// String literals.
		"`"					: "lexString",
		`"`					: "lexString",
		`x"`				: "lexString",
		`q"`				: "lexString",
		"q{"				: "lexString",
		`r"`				: "lexString",
		
		// Character literals.
		"'"					: "lexString",
	];
	
	foreach (op, _; getOperatorsMap()) {
		ret[op] = "lexOperator";
	}
	
	foreach (kw, _; getKeywordsMap()) {
		ret[kw] = "lexKeyword";
	}
	
	foreach (i; 0 .. 10) {
		import std.conv;
		ret[to!string(i)] = "lexNumeric";
	}
	
	return ret;
}

auto stringify(string s) {
	return "`" ~ s.replace("`", "` ~ \"`\" ~ `").replace("\0", "` ~ \"\\0\" ~ `") ~ "`";
}

auto getLexingCode(string fun, string base) {
	auto args = "!(" ~ stringify(base) ~ ")()";
	
	switch (fun[0]) {
		case '-':
			return "
				" ~ fun[1 .. $] ~ args ~ ";
				continue;";
			
		case '!':
			size_t i = 1;
			while (fun[i] != '?') {
				i++;
			}
			
			size_t endcond = i;
			while (fun[i] != ':') {
				i++;
			}
			
			auto cond = fun[1 .. endcond];
			auto lexCmd = fun[endcond + 1 .. i];
			auto skipCmd = fun[i + 1 .. $];
			
			return "
				if (" ~ cond ~ ") {
					return " ~ lexCmd ~ args ~ ";
				} else {
					" ~ skipCmd ~ args ~ ";
					continue;
				}";
			
		default:
			return "
				return " ~ fun ~ args ~ ";";
	}
}

string lexerMixin(string base = "", string def = "lexIdentifier", string[string] ids = getLexerMap()) {
	auto defaultFun = def;
	string[string][char] nextLevel;
	foreach (id, fun; ids) {
		if (id == "") {
			defaultFun = fun;
		} else {
			nextLevel[id[0]][id[1 .. $]] = fun;
		}
	}
	
	auto ret = "
		switch(frontChar) {";
	
	foreach (c, subids; nextLevel) {
		// TODO: have a real function to handle that.
		string charLit;
		switch(c) {
			case '\0':
				charLit = "\\0";
				break;
			
			case '\'':
				charLit = "\\'";
				break;
			
			case '\n':
				charLit = "\\n";
				break;
			
			case '\r':
				charLit = "\\r";
				break;
			
			default:
				charLit = [c];
		}
		
		ret ~= "
			case '" ~ charLit ~ "' :
				popChar();";
		
		auto newBase = base ~ c;
		if (subids.length == 1) {
			if (auto cdef = "" in subids) {
				ret ~= getLexingCode(*cdef, newBase);
				continue;
			}
		}
		
		ret ~= lexerMixin(newBase, def, nextLevel[c]);
	}
	
	ret ~= "
			default :" ~ getLexingCode(defaultFun, base) ~ "
		}
		";
	
	return ret;
}
