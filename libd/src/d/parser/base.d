module d.parser.base;

public import d.lexer;
public import d.context.location;

import d.parser.dmodule;

import d.context.name;

enum ParseMode {
	Greedy,
	Reluctant,
}

auto parse(ref TokenRange trange, Name name, Name[] packages) {
	return trange.parseModule(name, packages);
}

void match(ref TokenRange trange, TokenType type) {
	auto token = trange.front;
	
	if (token.type != type) {
		import d.exception;
		import std.conv, std.string;
		
		auto error = format("expected '%s', got '%s'.", to!string(type), to!string(token.type));
		
		throw new CompileException(token.location, error);
	}
	
	trange.popFront();
}
