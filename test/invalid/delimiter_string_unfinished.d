//T error: delimiter_string_unfinished.d:4:9:
//T error: Expected `FOO"` to end string literal, not the end of the file.

enum s = q"FOO
FOO
";
