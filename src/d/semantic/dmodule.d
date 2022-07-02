/**
 * This module crawl the AST to resolve identifiers and process types.
 */
module d.semantic.dmodule;

import d.semantic.scheduler;
import d.semantic.semantic;

import d.ast.declaration;

import d.ir.symbol;

import source.name;

alias AstModule = d.ast.declaration.Module;
alias Module = d.ir.symbol.Module;

alias PackageNames = Name[];

struct ModuleVisitorData {
private:
	Module[string] cachedModules;
}

struct ModuleVisitor {
private:
	SemanticPass pass;
	alias pass this;

	@property
	ref Module[string] cachedModules() {
		return pass.moduleVisitorData.cachedModules;
	}

public:
	this(SemanticPass pass) {
		this.pass = pass;
	}

	Module importModule(PackageNames packages) {
		import std.algorithm, std.range;
		auto name = packages.map!(p => p.toString(pass.context)).join(".");

		if (auto pMod = name in cachedModules) {
			return *pMod;
		}

		import std.algorithm, std.array, std.path;
		auto filename =
			packages.map!(p => p.toString(pass.context)).buildPath() ~ ".d";
		return parseAndScheduleModule(filename,
		                              getIncludeDir(filename, includePaths));
	}

	Module add(string filename) in(filename[$ - 2 .. $] == ".d") {
		import std.conv, std.path;
		filename =
			expandTilde(filename).asAbsolutePath.asNormalizedPath.to!string();

		// Try to find the module in include path.
		string dir;
		foreach (path; includePaths) {
			if (path.length < dir.length) {
				continue;
			}

			import std.algorithm;
			if (filename.startsWith(path)) {
				dir = path;
			}
		}

		return parseAndScheduleModule(relativePath(filename, dir), dir);
	}

	private Module parseAndScheduleModule(string filename, string dir) {
		auto astm = parse(filename, dir);
		auto mod = modulize(astm);
		auto name = getModuleName(mod);
		cachedModules[name] = mod;

		scheduler.schedule(astm, mod);
		return mod;
	}

	AstModule parse(string filename, string directory)
			in(filename[$ - 2 .. $] == ".d") {
		import source.location;
		auto base = context.registerFile(Location.init, filename, directory);

		import source.dlexer;
		auto l = lex(base, context);

		import d.parser.dmodule;
		auto m = l.parseModule();

		import std.algorithm, std.array, std.path;
		auto packages =
			filename[0 .. $ - 2].pathSplitter()
			                    .map!(p => pass.context.getName(p)).array();

		auto name = packages[$ - 1];
		packages = packages[0 .. $ - 1];

		// If we have no module declaration, we infer it from the file.
		if (m.name == BuiltinName!"") {
			m.name = name;
			m.packages = packages;
		} else {
			// XXX: Do proper error checking. Consider doing fixup.
			assert(m.name == name, "Wrong module name");
			assert(m.packages == packages, "Wrong module package");
		}

		return m;
	}

	Module modulize(AstModule astm) {
		auto loc = astm.location;

		auto m = new Module(loc, astm.name, null);
		m.addSymbol(m);

		Package p;
		foreach (n; astm.packages) {
			p = new Package(loc, n, p);
		}

		m.parent = p;
		p = m;
		while (p.parent !is null) {
			p.parent.addSymbol(p);
			p = p.parent;
		}

		return m;
	}

	private auto getModuleName(Module m) {
		auto name = m.name.toString(context);

		auto p = m.parent;
		while (p !is null) {
			name = p.name.toString(context) ~ "." ~ name;
			p = p.parent;
		}

		return name;
	}
}

private:
string getIncludeDir(string filename, const string[] includePaths) {
	foreach (path; includePaths) {
		import std.path;
		auto fullpath = buildPath(path, filename);

		import std.file;
		if (exists(fullpath)) {
			return path;
		}
	}

	// XXX: handle properly ? Now it will fail down the road.
	return "";
}
