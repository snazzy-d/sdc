//T error: array_size_expression.d:5:12:
//T error: Can't cast immutable(char[]) to ulong.

alias I = int;
alias A = I["a"];

A a;
