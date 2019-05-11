module sdc.format.writter;

struct Writter {
	import std.array;
	Appender!string buffer;
	
	import sdc.format.chunk;
	string write(Chunk[] chunks) {
		import std.array;
		buffer = appender!string();
		
		foreach (c; chunks) {
			final switch (c.splitType) with (SplitType) {
				case None:
					break;
				
				case Space:
					buffer ~= ' ';
					break;
				
				case NewLine:
					buffer ~= '\n';
					indent(c.indentation);
					break;
				
				case TwoNewLines:
					buffer ~= "\n\n";
					indent(c.indentation);
					break;
			}
			
			buffer ~= c.text;
		}
		
		return buffer.data;
	}
	
	void indent(uint level) {
		foreach(_; 0 .. level) {
			buffer ~= '\t';
		}
	}
}
