module d.parser.base;

public import d.lexer;
public import d.location;

import d.parser.dmodule;

enum ParseMode {
	Greedy,
	Reluctant,
}

auto parse(TokenRange)(ref TokenRange trange, string name, string[] packages) if(isTokenRange!TokenRange) {
	return trange.parseModule(name, packages);
}

template isTokenRange(T) {
	import std.range;
	
	enum isTokenRange = isForwardRange!T && is(ElementType!T : const(Token!Location));
}

void match(R)(ref R trange, TokenType type) if(isTokenRange!R) {
	auto token = trange.front;
	
	if(token.type != type) {
		import sdc.compilererror;
		import std.conv, std.string;
		
		auto error = format("expected '%s', got %s (%s).", to!string(type), token.value, to!string(token.type));
		
		import sdc.terminal;
		outputCaretDiagnostics(token.location, error);
		
		throw new CompilerError(token.location, error);
	}
	
	trange.popFront();
}

