//T error: preprocessor_if.d:4:1:
//T error: C preprocessor directive `#if` is not supported, use `version` or `static if`.

#if 1
enum IF = 1;
#else
enum ELSE = 1;
#endif
