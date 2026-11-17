// Typed, non-variadic entry points for libcurl's variadic curl_easy_setopt and curl_easy_getinfo, and the C callbacks
// that check every resolved address before a socket is opened (SEC-02). The interface uses only plain C types, so
// libcurl's declarations come from the CCurl module alone.

#ifndef LISA_CCURL_SHIM_H
#define LISA_CCURL_SHIM_H

#include <stddef.h>
#include <stdint.h>

/// A libcurl data callback: write, header and read functions all share this shape.
typedef size_t (*lisa_curl_data_callback)(char *buffer, size_t size, size_t count, void *userdata);

/// Returns nonzero to abort the transfer; called from libcurl's progress callback about once a second or more.
typedef int (*lisa_curl_abort_check)(void *userdata);

/// Returns nonzero when a connection to `address` (4 or 16 bytes, network order) is allowed.
typedef int (*lisa_curl_address_check)(void *context, const unsigned char *address, size_t length);

/// The abort check installed on a handle. It must stay valid until the transfer ends.
typedef struct lisa_curl_abort_binding {
    lisa_curl_abort_check check;
    void *userdata;
} lisa_curl_abort_binding;

/// The address check installed on a handle. It must stay valid until curl_easy_cleanup returns.
typedef struct lisa_curl_address_gate {
    lisa_curl_address_check check;
    void *context;
    /// Set to 1 once the pre-request check has passed: from then on, request bytes may reach the server.
    int request_started;
    /// How many times the request may be sent; 0 means no limit. libcurl resends a request on a new connection when
    /// a reused one died without a response, so a non-idempotent request is limited to 1.
    int max_requests;
    /// How many times the pre-request check passed.
    int request_count;
    /// Set to 1 when a further send was refused because `max_requests` was reached.
    int resend_refused;
} lisa_curl_address_gate;

int lisa_curl_setopt_long(void *handle, int option, long value);
int lisa_curl_setopt_string(void *handle, int option, const char *value);
int lisa_curl_setopt_pointer(void *handle, int option, void *value);
int lisa_curl_setopt_offset(void *handle, int option, int64_t value);

/// Sets CURLOPT_WRITEFUNCTION and CURLOPT_WRITEDATA.
int lisa_curl_set_write_callback(void *handle, lisa_curl_data_callback callback, void *userdata);
/// Sets CURLOPT_HEADERFUNCTION and CURLOPT_HEADERDATA.
int lisa_curl_set_header_callback(void *handle, lisa_curl_data_callback callback, void *userdata);
/// Sets CURLOPT_READFUNCTION and CURLOPT_READDATA.
int lisa_curl_set_read_callback(void *handle, lisa_curl_data_callback callback, void *userdata);
/// Sets CURLOPT_XFERINFOFUNCTION with `binding` as its data, and CURLOPT_NOPROGRESS = 0.
int lisa_curl_set_abort_check(void *handle, lisa_curl_abort_binding *binding);
/// Sets CURLOPT_OPENSOCKETFUNCTION (checked before connect) and CURLOPT_PREREQFUNCTION (checked again before request
/// bytes are sent, including on a reused connection) with `gate` as their data.
int lisa_curl_install_address_gate(void *handle, lisa_curl_address_gate *gate);

int lisa_curl_getinfo_long(void *handle, int info, long *value);
int lisa_curl_getinfo_string(void *handle, int info, const char **value);
int lisa_curl_getinfo_socket(void *handle, int info, int *value);

/// Waits until `socket` is readable (`for_writing` 0) or writable (1), at most `timeout_ms`. Returns 1 when ready,
/// 0 on timeout and -1 on error.
int lisa_curl_wait_socket(int socket, int for_writing, long timeout_ms);

#endif
