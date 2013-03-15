module d.llvm.util;

import std.file;
import std.random;

/**
 * Generate a filename in a temporary directory that doesn't exist.
 *
 * Params:
 *   extension = a string to be appended to the filename. Defaults to an empty string.
 *
 * Returns: an absolute path to a unique (as far as we can tell) filename. 
 */
string temporaryFilename(string extension = "") {
	version(Windows) {
		import std.process;
		string prefix = getenv("TEMP") ~ '/';
	} else {
		string prefix = "/tmp/";
	}
	
	string filename;
	do {
		filename = randomString(32);
		filename = prefix ~ filename ~ extension;
	} while (exists(filename));
	
	return filename;
}

/// Generate a random string `length` characters long.
string randomString(size_t length) {
	auto str = new char[length];
	foreach (i; 0 .. length) {
		char c;
		switch (uniform(0, 3)) {
			case 0:
				c = uniform!("[]", char, char)('0', '9');
				break;
			
			case 1:
				c = uniform!("[]", char, char)('a', 'z');
				break;
			
			case 2:
				c = uniform!("[]", char, char)('A', 'Z');
				break;
			
			default:
				assert(false);
		}
		
		str[i] = c;
	}
	
	return str.idup;	
}

