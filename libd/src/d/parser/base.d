module d.parser.base;

public import d.lexer;
public import d.location;

import d.parser.dmodule;

import d.base.name;

enum ParseMode {
	Greedy,
	Reluctant,
}

auto parse(R)(ref R trange, Name name, Name[] packages) if(isTokenRange!R) {
	return trange.parseModule(name, packages);
}

template isTokenRange(T) {
	import std.range;
	enum isTokenRange = isForwardRange!T && is(ElementType!T : const(Token!Location));
}

void match(R)(ref R trange, TokenType type) if(isTokenRange!R) {
	auto token = trange.front;
	
	if (token.type != type) {
		import d.exception;
		import std.conv, std.string;
		
		auto error = format("expected '%s', got '%s'.", to!string(type), to!string(token.type));
		
		throw new CompileException(token.location, error);
	}
	
	trange.popFront();
}

