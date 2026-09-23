//T error: tls_address_constant.d:7:10:
//T error: Cannot use the address of a thread-local as a constant.

// Mutable module-scope variables are TLS in SDC, so their address
// is not a link-time constant and cannot initialize an enum.
int tls;
enum p = &tls;
