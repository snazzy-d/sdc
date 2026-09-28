module sdc.depfile;

/**
 * GNU make / Ninja depfile formatting.
 *
 *     target: \
 *       dep1 \
 *       dep2
 *
 * With phony=true, also emit an empty rule for every dependency (GCC -MP)
 * so `make` does not fail if a listed file is later removed:
 *
 *     dep1:
 *     dep2:
 *
 * We phony every prerequisite, not "all but the first". The first file
 * SourceManager sees is often a config file, not the user's source, so
 * a skip-first rule would drop the wrong path.
 */
void writeMakeDeps(string depFile, string target, string[] deps,
                   bool phony = false) {
	import std.stdio;
	auto f = File(depFile, "w");
	f.write(formatMakeDeps(target, deps, phony));
}

string defaultMakeDepsFile(string target) {
	return target ~ ".deps";
}

string formatMakeDeps(string target, string[] deps, bool phony = false) {
	import std.array;
	auto buf = appender!string();

	putEscapedMakePath(buf, target);
	buf.put(':');
	foreach (dep; deps) {
		buf.put(" \\\n  ");
		putEscapedMakePath(buf, dep);
	}

	buf.put('\n');

	if (phony) {
		foreach (dep; deps) {
			putEscapedMakePath(buf, dep);
			buf.put(":\n");
		}
	}

	return buf.data;
}

string escapedMakePath(string fname) {
	import std.array;
	auto buf = appender!string();
	putEscapedMakePath(buf, fname);
	return buf.data;
}

/**
 * Escape `fname` so GNU make treats it as a single path token.
 *
 * A space or tab preceded by 2N+1 backslashes is N backslashes followed
 * by a space. `$` is doubled. `#` and (on POSIX) `:` are backslash-escaped.
 */
void putEscapedMakePath(Sink)(auto ref Sink sink, string fname) {
	uint slashes;
	foreach (c; fname) {
		switch (c) {
			case '\\':
				slashes++;
				break;

			case '$':
				sink.put('$');
				goto default;

			case ' ':
			case '\t':
				foreach (i; 0 .. slashes) {
					sink.put('\\');
				}

				goto EscapedChar;

			case '#':
				goto EscapedChar;

			case ':':
				version(Windows) {
					goto default;
				} else {
					goto EscapedChar;
				}

			EscapedChar:
				sink.put('\\');
				goto default;

			default:
				slashes = 0;
				break;
		}

		sink.put(c);
	}
}

unittest {
	// Empty prerequisite list: target and colon only.
	assert(formatMakeDeps("a.out", []) == "a.out:\n");

	// One prerequisite per line, continued with ` \`.
	assert(formatMakeDeps("a.out", ["main.d", "foo.d"]) == `a.out: \
  main.d \
  foo.d
`);
}

unittest {
	// Empty rule for every prerequisite, including the first. Config
	// files are registered before the user's source, so "skip first"
	// would phony the config and leave the real input unprotected.
	assert(
		formatMakeDeps("foo.o", ["foo.d", "bar.d", "baz.d"], true) == `foo.o: \
  foo.d \
  bar.d \
  baz.d
foo.d:
bar.d:
baz.d:
`);

	assert(formatMakeDeps("foo.o", ["foo.d"], true)
		== "foo.o: \\\n  foo.d\nfoo.d:\n");
	assert(formatMakeDeps("foo.o", [], true) == "foo.o:\n");
}

unittest {
	// GNU make escaping, including the 2N+1 backslash rule for spaces.
	assert(escapedMakePath("plain.d") == "plain.d");
	assert(escapedMakePath("foo bar.d") == "foo\\ bar.d");
	assert(escapedMakePath("foo\tbar.d") == "foo\\\tbar.d");
	assert(escapedMakePath("hash#name.d") == "hash\\#name.d");
	assert(escapedMakePath("foo$bar.d") == "foo$$bar.d");
	assert(escapedMakePath("foo\\ bar.d") == "foo\\\\\\ bar.d");

	version(Windows) {
		assert(escapedMakePath("C:\\proj\\a.d") == "C:\\proj\\a.d");
	} else {
		assert(escapedMakePath("/tmp/a:b.d") == "/tmp/a\\:b.d");
	}

	// Phonies use the same escaping as the main rule.
	assert(formatMakeDeps("a.out", ["foo.d", "x#y.d"], true) == `a.out: \
  foo.d \
  x\#y.d
foo.d:
x\#y.d:
`);
}

unittest {
	// defaultMakeDepsFile uses the target and adds the .deps
	// extension (foo.o -> foo.o.deps, a.out -> a.out.deps).
	assert(defaultMakeDepsFile("foo.o") == "foo.o.deps");
	assert(defaultMakeDepsFile("a.out") == "a.out.deps");
	assert(defaultMakeDepsFile("dir/app") == "dir/app.deps");
}

unittest {
	import std.file, std.path;
	auto tmpl = (buildPath(tempDir(), "sdc-makedeps-XXXXXX") ~ '\0').dup;

	import std.exception, core.sys.posix.stdlib;
	errnoEnforce(mkdtemp(tmpl.ptr) !is null, "mkdtemp");

	import std.string;
	auto dir = fromStringz(tmpl.ptr).idup;
	scope(exit) {
		if (exists(dir)) {
			rmdirRecurse(dir);
		}
	}

	auto depFile = buildPath(dir, "app.o.deps");
	auto src0 = buildPath(dir, "app.d");
	auto src1 = buildPath(dir, "foo.d");
	auto src2 = buildPath(dir, "bar.d");

	auto esc0 = escapedMakePath(src0);
	auto esc1 = escapedMakePath(src1);
	auto esc2 = escapedMakePath(src2);

	writeMakeDeps(depFile, "app.o", [src0, src1, src2]);

	import std.format;
	assert(readText(depFile) == format!`app.o: \
  %s \
  %s \
  %s
`(esc0, esc1, esc2));

	writeMakeDeps(depFile, "app.o", [src0, src1, src2], true);
	assert(readText(depFile) == format!`app.o: \
  %s \
  %s \
  %s
%s:
%s:
%s:
`(esc0, esc1, esc2, esc0, esc1, esc2));
}
