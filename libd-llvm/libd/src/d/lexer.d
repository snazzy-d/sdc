module d.lexer;

import std.array;
import std.ascii;
import std.range;
import std.uni;
import std.utf;

alias isAlpha = std.ascii.isAlpha;
alias isUniAlpha = std.uni.isAlpha;
alias isWhite = std.ascii.isWhite;

enum TokenType {
	Invalid = 0,
	
	Begin,
	End,
	
	// Literals
	Identifier,
	StringLiteral,
	CharacterLiteral,
	IntegerLiteral,
	FloatLiteral,
	
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
	SlashAssign,		// /=
	Dot,				// .
	DoubleDot,			// ..
	TripleDot,			// ...
	Ampersand,			// &
	AmpersandAssign,	// &=
	DoubleAmpersand,	// &&
	Pipe,				// |
	PipeAssign,			// |=
	DoublePipe,			// ||
	Minus,				// -
	MinusAssign,		// -=
	DoubleMinus,		// --
	Plus,				// +
	PlusAssign,			// +=
	DoublePlus,			// ++
	Less,				// <
	LessAssign,			// <=
	DoubleLess,			// <<
	DoubleLessAssign,	// <<=
	LessMore,			// <>
	LessMoreAssign,		// <>=
	More,				// >
	MoreAssign,			// >=
	DoubleMoreAssign,	// >>=
	TripleMoreAssign,	// >>>=
	DoubleMore,			// >>
	TripleMore,			// >>>
	Bang,				// !
	BangAssign,			// !=
	BangLessMore,		// !<>
	BangLessMoreAssign,	// !<>=
	BangLess,			// !<
	BangLessAssign,		// !<=
	BangMore,			// !>
	BangMoreAssign,		// !>=
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
	Assign,				// =
	DoubleAssign,		// ==
	Star,				// *
	StarAssign,			// *=
	Percent,			// %
	PercentAssign,		// %=
	Caret,				// ^
	CaretAssign,		// ^=
	DoubleCaret,		// ^^
	DoubleCaretAssign,	// ^^=
	Tilde,				// ~
	TildeAssign,		// ~=
	At,					// @
	AssignMore,			// =>
	Hash,				// #
	/*
	version(KIRBY) {
		KirbyRape,		// (>^(>O_O)>
	}
	*/
}

import d.context;

struct Token(Location) {
	Location location;
	TokenType type;
	Name name;
}

auto lex(alias locationProvider, R)(R r, Context context) if(isForwardRange!R) {
	alias Location = typeof(locationProvider(0, 0, 0));
	alias Token = .Token!Location;
	
	struct Lexer {
		static assert(isForwardRange!Lexer);
		
		Token t;
		R r;
		
		Context context;
		
		uint line = 1;
		uint index;
		
		/*
		@disable
		this(this);
		*/
		
		@property
		auto front() inout {
			return t;
		}
		
		void popFront() {
			t = getNextToken();
			
			/+
			import sdc.terminal;
			import std.conv;
			outputCaretDiagnostics(t.location, to!string(t.type));
			+/
		}
		
		@property
		auto save() inout {
			// XXX: dmd bug, context pointer isn't copied properly
			// Seems fixed in 2.063
			version(DigitalMars) {
				// XXX: doing it manualy using black magic.
				// Context pointer is the last element of the struct. Here in position 9.
				auto ret = inout(Lexer)(t, r.save, context, line, index);
				(cast(void**) &ret)[9] = (cast(void**) &this)[9];
				
				return ret;
			} else {
				return inout(Lexer)(t, r.save, line, index);
			}
		}
		
		@property
		bool empty() const {
			return t.type == TokenType.End;
		}
		
	private :
		auto getNextToken() {
			while(1) {
				// pragma(msg, lexerMixin());
				mixin(lexerMixin());
			}
		}
		
		void popChar() {
			r.popFront();
			index++;
		}
		
		auto lexWhiteSpace(string s)() {
			static if(s == "\n" || s == "\r" || s == "\r\n") {
				line++;
			}
		}
		
		auto lexComment(string s)() {
			auto c = r.front;
			
			static if(s == "//") {
				// TODO: check for unicode line break.
				while(c != '\n' && c != '\r') {
					popChar();
					c = r.front;
				}
				
				popChar();
				if(c == '\r') {
					if(r.front == '\n') popChar();
				}
				
				line++;
			} else static if(s == "/*") {
				Pump: while(1) {
					// TODO: check for unicode line break.
					while(c != '*' && c != '\r' && c != '\n') {
						popChar();
						c = r.front;
					}
					
					auto match = c;
					popChar();
					c = r.front;
					
					switch(match) {
						case '*' :
							if(c == '/') {
								popChar();
								break Pump;
							}
							
							break;
						
						case '\r' :
							// \r\n is a special case.
							if(c == '\n') {
								popChar();
								c = r.front;
							}
							
							line++;
							break;
						
						case '\n' :
							line++;
							break;
						
						default :
							assert(0, "Unrecheable.");
					}
				}
			} else static if(s == "/+") {
				uint stack = 0;
				Pump: while(1) {
					// TODO: check for unicode line break.
					while(c != '+' && c != '/' && c != '\r' && c != '\n') {
						popChar();
						c = r.front;
					}
					
					auto match = c;
					popChar();
					c = r.front;
					
					switch(match) {
						case '+' :
							if(c == '/') {
								popChar();
								if(!stack) break Pump;
								
								c = r.front;
								stack--;
							}
							
							break;
						
						case '/' :
							if(c == '+') {
								popChar();
								c = r.front;
								
								stack++;
							}
							
							break;
						
						case '\r' :
							// \r\n is a special case.
							if(c == '\n') {
								popChar();
								c = r.front;
							}
							
							line++;
							break;
						
						case '\n' :
							line++;
							break;
						
						default :
							assert(0, "Unrecheable.");
					}
				}
			} else {
				static assert(0, s ~ " isn't a known type of comment.");
			}
		}
		
		auto lexIdentifier(string s)() {
			static if(s == "") {
				auto c = r.front;
				
				if(isIdChar(c)) {
					return lexIdentifier(s);
				} else if(c & 0x80) {
					size_t l;
					auto save = r.save;
					auto u = save.decodeFront(l);
					
					if(isUniAlpha(u)) {
						char[4] encoded;
						for(uint i = 0; i < l; i++) {
							encoded[i] = r.front;
							popChar();
						}
						
						return lexIdentifier(cast(string) encoded[0 .. l]);
					} else {
						assert(0, "bazinga !");
					}
				}
				
				// TODO: check for unicode whitespaces.
				assert(0, "bazinga !");
			} else {
				return lexIdentifier(s);
			}
		}
		
		// XXX: dmd don't support overlaod of template and non templates.
		auto lexIdentifier()(string prefix) in {
			assert(index >= prefix.length);
		} body {
			Token t;
			t.type = TokenType.Identifier;
			uint l = line, begin = cast(uint) (index - prefix.length);
			
			mixin CharPumper;
			
			putString(prefix);
			pumpChars!isIdChar(r);
			
			t.location = locationProvider(l, begin, index - begin);
			t.name = getValue();
			
			return t;
		}
		
		auto lexEscapeSequence() in {
			assert(r.front == '\\', r.front ~ " is not a valid escape sequence.");
		} body {
			popChar();
			scope(success) popChar();
			
			switch(r.front) {
				case '\'' :
					return '\'';
				
				case '"' :
					return '"';
				
				case '?' :
					assert(0, "WTF is \\?");
				
				case '\\' :
					return '\\';
				
				case '0' :
					return '\0';
				
				case 'a' :
					return '\a';
				
				case 'b' :
					return '\b';
				
				case 'f' :
					return '\f';
				
				case 'r' :
					return '\r';
				
				case 'n' :
					return '\n';
				
				case 't' :
					return '\t';
				
				case 'v' :
					return '\v';
				
				default :
					assert(0, "Don't know about it.");
			}
		}
		
		auto lexEscapeChar() {
			auto c = r.front;
			switch(c) {
				case '\0' :
					assert(0, "unexpected end :(");
				
				case '\\' :
					return lexEscapeSequence();
				
				case '\'' :
					assert(0, "Empty character litteral is bad, very very bad !");
				
				default :
					if(c & 0x80) {
						assert(0, "Unicode not supported here");
					} else {
						popChar();
						return c;
					}
			}
		}
		
		Token lexString(string s)() in {
			assert(index >= s.length);
		} body {
			Token t;
			t.type = TokenType.StringLiteral;
			uint l = line, begin = cast(uint) (index - s.length);
			
			auto c = r.front;
			
			static if(s == "\"") {
				mixin CharPumper!false;
				
				Pump: while(1) {
					// TODO: check for unicode line break.
					while(c != '\"' && c != '\r' && c != '\n') {
						putChar(lexEscapeChar());
						c = r.front;
					}
					
					popChar();
					switch(c) {
						case '\"' :
							// End of string.
							break Pump;
						
						case '\r' :
							c = r.front;
							
							// \r\n is a special case.
							if(c == '\n') {
								popChar();
								c = r.front;
							}
							
							line++;
							break;
						
						case '\n' :
							line++;
							break;
						
						default :
							assert(0, "Unrecheable.");
					}
				}
				
				t.location = locationProvider(l, begin, index - begin);
				t.name = getValue();
				
				return t;
			} else {
				assert(0, "string literal using " ~ s ~ "not supported");
			}
		}
		
		auto lexChar(string s)() if(s == "'") {
			Token t;
			t.type = TokenType.CharacterLiteral;
			uint l = line, begin = index - 1;
			
			t.name = context.getName([lexEscapeChar()]);
			
			if(r.front != '\'') {
				assert(0, "booya !");
			}
			
			popChar();
			
			t.location = locationProvider(l, begin, index - begin);
			return t;
		}
		
		auto lexNumeric(string s)() if(s.length == 1 && isDigit(s[0])) {
			return lexNumeric(s[0]);
		}
		
		Token lexNumeric(string s)() if(s.length == 2 && s[0] == '0') {
			Token t;
			t.type = TokenType.IntegerLiteral;
			uint l = line, begin = index - 1;
			
			mixin CharPumper!false;
			
			putString(s);
			
			auto c = r.front;
			switch(s[1]) {
				case 'B', 'b' :
					assert(c == '0' || c == '1', "invalid integer literal");
					while(1) {
						while(c == '0' || c == '1') {
							putChar(c);
							popChar();
							c = r.front;
						}
						
						if(c == '_') {
							popChar();
							c = r.front;
							continue;
						}
						
						break;
					}
					
					break;
				
				case 'X', 'x' :
					assert((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'), "invalid integer literal");
					while(1) {
						while((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')) {
							putChar(c);
							popChar();
							c = r.front;
						}
						
						if(c == '_') {
							popChar();
							c = r.front;
							continue;
						}
						
						break;
					}
					
					break;
				
				default :
					assert(0, s ~ " is not a valid prefix.");
			}
			
			switch(c) {
				case 'U', 'u' :
					putChar(c);
					popChar();
					
					c = r.front;
					if(c == 'L' || c == 'l') {
						putChar(c);
						popChar();
					}
					
					break;
				
				case 'L', 'l' :
					putChar(c);
					popChar();
					
					c = r.front;
					if(c == 'U' || c == 'u') {
						putChar(c);
						popChar();
					}
					
					break;
				
				default:
					break;
			}
			
			t.location = locationProvider(l, begin, index - begin);
			t.name = getValue();
			
			return t;
		}
		
		auto lexNumeric()(char c) {
			Token t;
			t.type = TokenType.IntegerLiteral;
			uint l = line, begin = index - 1;
			
			mixin CharPumper!false;
			
			assert(c >= '0' && c <= '9', "invalid integer literal");
			putChar(c);
			c = r.front;
			while(1) {
				while(c >= '0' && c <= '9') {
					putChar(c);
					popChar();
					c = r.front;
				}
				
				if(c == '_') {
					popChar();
					c = r.front;
					continue;
				}
				
				break;
			}
			
			switch(c) {
				case '.' :
					auto lookAhead = r.save;
					lookAhead.popFront();
					
					if(lookAhead.front.isDigit()) {
						popChar();
						putChar('.');
						
						t.type = TokenType.FloatLiteral;
						
						pumpChars!isDigit(r);
					}
					
					break;
				
				case 'U', 'u' :
					putChar(c);
					popChar();
					
					c = r.front;
					if(c == 'L' || c == 'l') {
						putChar(c);
						popChar();
					}
					
					break;
				
				case 'L', 'l' :
					putChar(c);
					popChar();
					
					c = r.front;
					if(c == 'U' || c == 'u') {
						putChar(c);
						popChar();
					}
					
					break;
				
				default:
					break;
			}
			
			t.location = locationProvider(l, begin, index - begin);
			t.name = getValue();
			
			return t;
		}
		
		auto lexKeyword(string s)() {
			auto c = r.front;
			if(isIdChar(c)) {
				return lexIdentifier!s();
			} else if(c & 0x80) {
				size_t l;
				auto save = r.save;
				auto u = save.decodeFront(l);
				
				if(isUniAlpha(u)) {
					// Double decoding here, but shouldn't be a problem as it should be rare enough.
					return lexIdentifier!s();
				}
			}
			
			enum type = getKeywordsMap()[s];
			
			uint l = s.length;
			
			Token t;
			t.type = type;
			t.location = locationProvider(line, index - l, l);
			t.name = BuiltinName!s;
			
			return t;
		}
		
		auto lexOperator(string s)() {
			enum type = getOperatorsMap()[s];
			
			uint l = s.length;
			
			Token t;
			t.type = type;
			t.location = locationProvider(line, index - l, l);
			t.name = BuiltinName!s;
			
			return t;
		}
	}
	
	auto lexer = Lexer();
	
	lexer.r = r.save;
	lexer.t.type = TokenType.Begin;
	lexer.t.location = locationProvider(0, 0, 0);
	
	lexer.context = context;
	
	// Pop #!
	auto c = lexer.r.front;
	if(c == '#') {
		do {
			lexer.popChar();
			c = lexer.r.front;
		} while(c != '\n' && c != '\r');
		
		lexer.popChar();
		if(c == '\r') {
			if(lexer.r.front == '\n') lexer.popChar();
		}
		
		lexer.line++;
	}
	
	return lexer;
}

private:

@property
char front(string s) {
	return s[0];
}

void popFront(ref string s) {
	s = s[1 .. $];
}

auto isIdChar(C)(C c) {
	static if(is(C == char)) {
		return c == '_' || isAlphaNum(c);
	} else static if(is(C == wchar) || is(C == dchar)) {
		return isUniAlpha(c);
	} else {
		static assert(0, "This function is only for chatacter types.");
	}
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
		if(i < BufferSize) {
			do {
				c = r.front;
				
				if(condition(c)) {
					buffer[i++] = c;
					popChar();
					
					continue;
				} else static if(decode) {
					// Check if if have an unicode character.
					if(c & 0x80) {
						size_t l;
						auto save = r.save;
						auto u = save.decodeFront(l);
						
						if(condition(u)) {
							while(l--) {
								putChar(r.front);
								popChar();
							}
							
							goto Begin;
						}
					}
				}
				
				return;
			} while(i < BufferSize);
			
			// Buffer is full, we need to work on heap;
			heapBuffer = buffer.idup;
		}
		
		while(1) {
			 c = r.front;
			 
			 if(condition(c)) {
				heapBuffer ~= c;
				popChar();
				
				continue;
			 } else static if(decode) {
				// Check if if have an unicode character.
				if(c & 0x80) {
					size_t l;
					auto save = r.save;
					auto u = save.decodeFront(l);
					
					if(condition(u)) {
						heapBuffer.reserve(l);
						
						while(l--) {
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
		if(i < BufferSize) {
			buffer[i++] = c;
			
			if(i == BufferSize) {
				// Buffer is full, we need to work on heap;
				heapBuffer = buffer.idup;
			}
		} else {
			heapBuffer ~= c;
		}
	}
	
	void putString(string s) {
		auto finalSize = i + s.length;
		if(finalSize < BufferSize) {
			buffer[i .. finalSize][] = s[];
			i = finalSize;
		} else if(i < BufferSize) {
			heapBuffer.reserve(finalSize);
			heapBuffer ~= buffer[0 .. i];
			heapBuffer ~= s;
			
			i = BufferSize;
		} else {
			heapBuffer ~= s;
		}
	}
	
	Name getValue() {
		return context.getName(
			(i < BufferSize)
				? buffer[0 .. i].idup
				: heapBuffer
		);
	}
}

public:
auto getOperatorsMap() {
	return [
		"/"		: TokenType.Slash,
		"/="	: TokenType.SlashAssign,
		"."		: TokenType.Dot,
		".."	: TokenType.DoubleDot,
		"..."	: TokenType.TripleDot,
		"&"		: TokenType.Ampersand,
		"&="	: TokenType.AmpersandAssign,
		"&&"	: TokenType.DoubleAmpersand,
		"|"		: TokenType.Pipe,
		"|="	: TokenType.PipeAssign,
		"||"	: TokenType.DoublePipe,
		"-"		: TokenType.Minus,
		"-="	: TokenType.MinusAssign,
		"--"	: TokenType.DoubleMinus,
		"+"		: TokenType.Plus,
		"+="	: TokenType.PlusAssign,
		"++"	: TokenType.DoublePlus,
		"<"		: TokenType.Less,
		"<="	: TokenType.LessAssign,
		"<<"	: TokenType.DoubleLess,
		"<<="	: TokenType.DoubleLessAssign,
		"<>"	: TokenType.LessMore,
		"<>="	: TokenType.LessMoreAssign,
		">"		: TokenType.More,
		">="	: TokenType.MoreAssign,
		">>="	: TokenType.DoubleMoreAssign,
		">>>="	: TokenType.TripleMoreAssign,
		">>"	: TokenType.DoubleMore,
		">>>"	: TokenType.TripleMore,
		"!"		: TokenType.Bang,
		"!="	: TokenType.BangAssign,
		"!<>"	: TokenType.BangLessMore,
		"!<>="	: TokenType.BangLessMoreAssign,
		"!<"	: TokenType.BangLess,
		"!<="	: TokenType.BangLessAssign,
		"!>"	: TokenType.BangMore,
		"!>="	: TokenType.BangMoreAssign,
		"("		: TokenType.OpenParen,
		")"		: TokenType.CloseParen,
		"["		: TokenType.OpenBracket,
		"]"		: TokenType.CloseBracket,
		"{"		: TokenType.OpenBrace,
		"}"		: TokenType.CloseBrace,
		"?"		: TokenType.QuestionMark,
		","		: TokenType.Comma,
		";"		: TokenType.Semicolon,
		":"		: TokenType.Colon,
		"$"		: TokenType.Dollar,
		"="		: TokenType.Assign,
		"=="	: TokenType.DoubleAssign,
		"*"		: TokenType.Star,
		"*="	: TokenType.StarAssign,
		"%"		: TokenType.Percent,
		"%="	: TokenType.PercentAssign,
		"^"		: TokenType.Caret,
		"^="	: TokenType.CaretAssign,
		"^^"	: TokenType.DoubleCaret,
		"^^="	: TokenType.DoubleCaretAssign,
		"~"		: TokenType.Tilde,
		"~="	: TokenType.TildeAssign,
		"@"		: TokenType.At,
		"=>"	: TokenType.AssignMore,
		"#"		: TokenType.Hash,
		/*
		version(KIRBY) {
			"(>^(>O_O)>"	: KirbyRape,
		}
		*/
		"\0"	: TokenType.End,
	];
}

auto getKeywordsMap() {
	return [
		"abstract"			: TokenType.Abstract,
		"alias"				: TokenType.Alias,
		"align"				: TokenType.Align,
		"asm"				: TokenType.Asm,
		"assert"			: TokenType.Assert,
		"auto"				: TokenType.Auto,
		"body"				: TokenType.Body,
		"bool"				: TokenType.Bool,
		"break"				: TokenType.Break,
		"byte"				: TokenType.Byte,
		"case"				: TokenType.Case,
		"cast"				: TokenType.Cast,
		"catch"				: TokenType.Catch,
		"cent"				: TokenType.Cent,
		"char"				: TokenType.Char,
		"class"				: TokenType.Class,
		"const"				: TokenType.Const,
		"continue"			: TokenType.Continue,
		"dchar"				: TokenType.Dchar,
		"debug"				: TokenType.Debug,
		"default"			: TokenType.Default,
		"delegate"			: TokenType.Delegate,
		"deprecated"		: TokenType.Deprecated,
		"do"				: TokenType.Do,
		"double"			: TokenType.Double,
		"else"				: TokenType.Else,
		"enum"				: TokenType.Enum,
		"export"			: TokenType.Export,
		"extern"			: TokenType.Extern,
		"false"				: TokenType.False,
		"final"				: TokenType.Final,
		"finally"			: TokenType.Finally,
		"float"				: TokenType.Float,
		"for"				: TokenType.For,
		"foreach"			: TokenType.Foreach,
		"foreach_reverse"	: TokenType.ForeachReverse,
		"function"			: TokenType.Function,
		"goto"				: TokenType.Goto,
		"if"				: TokenType.If,
		"immutable"			: TokenType.Immutable,
		"import"			: TokenType.Import,
		"in"				: TokenType.In,
		"inout"				: TokenType.Inout,
		"int"				: TokenType.Int,
		"interface"			: TokenType.Interface,
		"invariant"			: TokenType.Invariant,
		"is"				: TokenType.Is,
		"lazy"				: TokenType.Lazy,
		"long"				: TokenType.Long,
		"macro"				: TokenType.Macro,
		"mixin"				: TokenType.Mixin,
		"module"			: TokenType.Module,
		"new"				: TokenType.New,
		"nothrow"			: TokenType.Nothrow,
		"null"				: TokenType.Null,
		"out"				: TokenType.Out,
		"override"			: TokenType.Override,
		"package"			: TokenType.Package,
		"pragma"			: TokenType.Pragma,
		"private"			: TokenType.Private,
		"protected"			: TokenType.Protected,
		"public"			: TokenType.Public,
		"pure"				: TokenType.Pure,
		"real"				: TokenType.Real,
		"ref"				: TokenType.Ref,
		"return"			: TokenType.Return,
		"scope"				: TokenType.Scope,
		"shared"			: TokenType.Shared,
		"short"				: TokenType.Short,
		"static"			: TokenType.Static,
		"struct"			: TokenType.Struct,
		"super"				: TokenType.Super,
		"switch"			: TokenType.Switch,
		"synchronized"		: TokenType.Synchronized,
		"template"			: TokenType.Template,
		"this"				: TokenType.This,
		"throw"				: TokenType.Throw,
		"true"				: TokenType.True,
		"try"				: TokenType.Try,
		"typeid"			: TokenType.Typeid,
		"typeof"			: TokenType.Typeof,
		"ubyte"				: TokenType.Ubyte,
		"ucent"				: TokenType.Ucent,
		"uint"				: TokenType.Uint,
		"ulong"				: TokenType.Ulong,
		"union"				: TokenType.Union,
		"unittest"			: TokenType.Unittest,
		"ushort"			: TokenType.Ushort,
		"version"			: TokenType.Version,
		"void"				: TokenType.Void,
		"volatile"			: TokenType.Volatile,
		"wchar"				: TokenType.Wchar,
		"while"				: TokenType.While,
		"with"				: TokenType.With,
		"__FILE__"			: TokenType.__File__,
		"__LINE__"			: TokenType.__Line__,
		"__gshared"			: TokenType.__Gshared,
		"__traits"			: TokenType.__Traits,
		"__vector"			: TokenType.__Vector,
		"__parameters"		: TokenType.__Parameters,
	];
}

private:
auto getLexerMap() {
	auto ret = [
		// WhiteSpaces
		" "					: "?lexWhiteSpace",
		"\t"				: "?lexWhiteSpace",
		"\v"				: "?lexWhiteSpace",
		"\f"				: "?lexWhiteSpace",
		"\n"				: "?lexWhiteSpace",
		"\r"				: "?lexWhiteSpace",
		"\r\n"				: "?lexWhiteSpace",
		
		// Comments
		"//"				: "?lexComment",
		"/*"				: "?lexComment",
		"/+"				: "?lexComment",
		
		// Integer literals.
		"0b"				: "lexNumeric",
		"0B"				: "lexNumeric",
		"0x"				: "lexNumeric",
		"0X"				: "lexNumeric",
		
		// String literals.
		`r"`				: "lexString",
		"`"					: "lexString",
		`"`					: "lexString",
		`x"`				: "lexString",
		`q"`				: "lexString",
		"q{"				: "lexString",
		
		// Character literals.
		"'"					: "lexChar",
	];
	
	foreach(op, _; getOperatorsMap()) {
		ret[op] = "lexOperator";
	}
	
	foreach(kw, _; getKeywordsMap()) {
		ret[kw] = "lexKeyword";
	}
	
	foreach(i; 0 .. 10) {
		import std.conv;
		ret[to!string(i)] = "lexNumeric";
	}
	
	return ret;
}

auto stringify(string s) {
	return "`" ~ s.replace("`", "`\"`\"`").replace("\0", "`\"\\0\"`") ~ "`";
}

auto getReturnOrBreak(string fun, string base) {
	auto cmd = "!" ~ stringify(base) ~ "()";
	
	if(fun[0] == '?') {
		cmd = fun[1 .. $] ~ cmd;
		return "
				static if(is(typeof(" ~ cmd ~ ") == void)) {
					" ~ cmd ~ ";
					continue;
				} else {
					return " ~ cmd ~ ";
				}";
	} else {
		cmd = fun ~ cmd;
		return "
				return " ~ cmd ~ ";";
	}
}

string lexerMixin(string base = "", string def = "lexIdentifier", string[string] ids = getLexerMap()) {
	auto defaultFun = def;
	string[string][char] nextLevel;
	foreach(id, fun; ids) {
		if(id == "") {
			defaultFun = fun;
		} else {
			nextLevel[id[0]][id[1 .. $]] = fun;
		}
	}
	
	auto ret = "
		switch(r.front) {";
	
	foreach(c, ids; nextLevel) {
		// TODO: have a real function to handle that.
		string charLit;
		switch(c) {
			case '\0' :
				charLit = "\\0";
				break;
			
			case '\'' :
				charLit = "\\'";
				break;
			
			case '\n' :
				charLit = "\\n";
				break;
			
			case '\r' :
				charLit = "\\r";
				break;
			
			default:
				charLit = [c];
		}
		
		ret ~= "
			case '" ~ charLit ~ "' :
				popChar();";
		
		auto newBase = base ~ c;
		if(ids.length == 1) {
			if(auto cdef = "" in ids) {
				ret ~= getReturnOrBreak(*cdef, newBase);
				continue;
			}
		}
		
		ret ~= lexerMixin(newBase, def, nextLevel[c]);
	}
	
	ret ~= "
			default :" ~ getReturnOrBreak(defaultFun, base) ~ "
		}
		";
	
	return ret;
}

