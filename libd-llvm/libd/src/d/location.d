module d.location;

/**
 * Struct representing a location in a source file.
 */
struct Location {
	Source source;
	
	uint line = 1;
	uint index = 1;
	uint length = 0;
	
	string toString() const {
		return source.format(this);
	}
	
	void spanTo(ref const Location end) in {
		if(source !is end.source) {
			import std.stdio;
			writeln("source corrupted : ", cast(void*) source, " vs ", cast(void*) end.source);
			/*
			import sdc.terminal;
			outputCaretDiagnostics(this, "this");
			outputCaretDiagnostics(end, "end");
			*/
		}
		
		// FIXME: Source is often corrupted. This is likely a dmd bug :(
		// assert(source is end.source, "locations must have the same source !");
		
		assert(line <= end.line);
		assert(index + length <= end.index);
	} body {
		length = end.index - index;
	}
}

/*
final class LocationContext {
	Location[] locations;
	
	uint register(uint line, uint index, uint length) {
		Location loc;
		
		loc.line = line;
		loc.index = index;
		loc.length = length;
		
		return register(loc);
	}
	
	auto register(Location location) {
		uint ret = cast(uint) locations.length;
		locations ~= location;
		
		return ret;
	}
	
	auto retrieve(uint i) inout {
		return locations[i];
	}
}
*/

abstract class Source {
	string content;
	
	this(string content) {
		this.content = content;
	}
	
	string format(const Location location) const {
		return content[location.index .. location.index + location.length];
	}
	
	@property
	abstract string filename() const;
}

final class FileSource : Source {
	string _filename;
	
	this(string filename) {
		_filename = filename;
		
		import sdc.source;
		super((new Source(filename)).source ~ '\0');
	}
	
	@property
	override string filename() const {
		return _filename;
	}
}

final class MixinSource : Source {
	Location location;
	
	this(Location location, string content) {
		this.location = location;
		super(content);
	}
	
	override string format(const Location location) const {
		import std.conv;
		return to!string(location.line) ~ " " ~ to!string(location.index) ~ " " ~ to!string(location.length);
	}
	
	@property
	override string filename() const {
		return location.source.filename;
	}
}

