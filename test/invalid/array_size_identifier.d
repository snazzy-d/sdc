//T error: array_size_identifier.d:6:12:
//T error: Can't cast immutable(char[]) to ulong.

alias I = int;
enum size = "a";
alias A = I[size];

A a;
