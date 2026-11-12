//T error: tls_address_constant.d:6:14:
//T error: Thread local tls has no address at compile time.

int tls;

enum int* p = &tls;
