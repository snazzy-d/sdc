//T error: global_tls_address_qualified.d:4:17:
//T error: Cannot use this address as a constant.
int tls;
const(int)* p = &tls;
