module d.context;

final class Context {
package:
	import d.context.name;
	NameManager _nameManager;
	
	import d.context.source;
	SourceManager sourceManager;
	
	import d.context.config;
	Config _config;
	
public:
	this(Config config) {
		_nameManager = NameManager.get();
		sourceManager = SourceManager.get();
		
		_config = config;
	}
	
	alias nameManager this;
	@property
	ref nameManager() inout {
		return _nameManager;
	}
	
	@property
	ref config() const {
		return _config;
	}
	
	import d.context.location;
	Position registerFile(Location location, string filename, string directory) {
		import std.file, std.path;
		auto data = cast(const(ubyte)[]) read(buildPath(directory, filename));
		
		import util.utf8;
		auto content = convertToUTF8(data) ~ '\0';
		
		return sourceManager.registerFile(
			location,
			getName(filename),
			getName(directory),
			content,
		);
	}
	
	Position registerMixin(Location location, string content) {
		return sourceManager.registerMixin(location, content);
	}
}
