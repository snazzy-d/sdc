// XXX: This whole file needs to go away.
module d.parser.base;

public import source.dlexer;
public import source.location;
public import source.parserutil;

enum ParseMode {
	Greedy,
	Reluctant,
}
