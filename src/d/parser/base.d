// XXX: This whole file needs to go away.
module d.parser.base;

public import source.dlexer;
public import source.location;

import source.name;

enum ParseMode {
	Greedy,
	Reluctant,
}

void match(ref TokenRange trange, TokenType type) {
	auto token = trange.front;
	
	if (token.type == type) {
		trange.popFront();
		return;
	}
	
	import std.conv, std.string;
	auto error = token.type == TokenType.Invalid
		? token.name.toString(trange.context)
		: format!"expected '%s', got '%s'."(to!string(type), to!string(token.type));
	
	import source.exception;
	throw new CompileException(token.location, error);
}
