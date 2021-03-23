module sdc.format.writter;

import sdc.format.chunk;

struct Writter {
	import std.array;
	Appender!string buffer;
	
	string write(Chunk[] chunks) {
		import std.array;
		buffer = appender!string();
		
		uint cost = 0;
		size_t start = 0;
		foreach (i, c; chunks) {
			if (!c.isLineBreak()) {
				continue;
			}
			
			cost += LineWritter(&this, chunks[start .. i]).write();
			start = i;
		}
		
		// Make sure we write the last line too.
		cost += LineWritter(&this, chunks[start .. $]).write();
		
		return buffer.data;
	}
}

enum INDENTATION_SIZE = 4;
enum PAGE_WIDTH = 80;

struct SolveState {
	uint overflow = 0;
	uint cost = 0;
	
	this(Chunk[] line) {
		computeCost(line);
	}
	
	void computeCost(Chunk[] line) {
		if (line.length == 0) {
			return;
		}

		uint length = line[0].indentation * INDENTATION_SIZE;
		foreach (c; line) {
			if (c.splitType == SplitType.Space) {
				length++;
			}
			
			length += c.length;
		}
		
		if (length > PAGE_WIDTH) {
			overflow = length - PAGE_WIDTH;
		}
	}
}

struct LineWritter {
	Writter* writter;
	Chunk[] line;
	
	this(Writter* writter, Chunk[] line) {
		this.writter = writter;
		this.line = line;
	}
	
	uint write() {
		if (line.length == 0) {
			// This is empty.
			return 0;
		}
		
		auto state = SolveState(line);
		
		final switch (line[0].splitType) with (SplitType) {
			case None:
				// File starts.
				break;
			
			case Space:
				assert(0, "Expected line break");
			
			case NewLine:
				output('\n');
				indent(line[0].indentation);
				break;
			
			case TwoNewLines:
				output("\n\n");
				indent(line[0].indentation);
				break;
		}
		
		output(line[0].text);
		
		foreach (i, c; line[1 .. $]) {
			assert(!c.isLineBreak(), "Line splitting bug");
			if (c.splitType == SplitType.Space) {
				output(' ');
			}
			
			output(c.text);
		}
		
		return 0;
	}
	
	void output(char c) {
		writter.buffer ~= c;
	}
	
	void output(string s) {
		writter.buffer ~= s;
	}
	
	void indent(uint level) {
		foreach (_; 0 .. level) {
			output('\t');
		}
	}
}
