//T error: tls_address_constant.d:6:15:
//T error: Cannot use this address as a constant.

int tls;

enum int* p = &tls;
