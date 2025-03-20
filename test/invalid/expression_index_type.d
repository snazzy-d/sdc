//T error: expression_index_type.d:7:10:
//T error: Cannot index expression 42 using type T.

alias T = uint;
alias N = 42;

alias A = N[T];
A a;
