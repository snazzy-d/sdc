//T error: cast_address_global_tls.d:4:16:
//T error: Cannot use this address as a constant.
int g;
const(int)* p = &cast(const(int)) g;
