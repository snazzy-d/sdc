//T error: global_tls_address_qualified.d:4:16:
//T error: Thread local tls has no address at compile time.
int tls;
const(int)* p = &tls;
