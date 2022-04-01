//T has-passed:yes
//T compiles:yes
//T retval:0

int main() {
	string msg = q{tagada {tsoin} {{tsoin}}};

	assert(msg.length == 24);
	assert(msg[0] == 't');
	assert(msg[12] == 'n');
	assert(msg[23] == '}');

	msg = q"<xml></xml>";

	assert(msg.length == 9);
	assert(msg[0] == 'x');
	assert(msg[5] == '/');
	assert(msg[8] == 'l');

	msg = q"EOF
"""python comment!"""
EOF";

	assert(msg.length == 22);
	assert(msg[0] == '"');
	assert(msg[15] == 'n');
	assert(msg[21] == '\n');

	return 0;
}
