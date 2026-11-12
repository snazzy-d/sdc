//T error: global_tls_address.d:6:9:
//T error: Thread local tls has no address at compile time.

int tls;

int* p = &tls;
