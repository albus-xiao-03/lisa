// Typed wrappers for libcurl's variadic option functions, and the connect-time address gate (SEC-02).

#include "CCurlShim.h"

#include <curl/curl.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <poll.h>
#include <string.h>
#include <sys/socket.h>

int lisa_curl_setopt_long(void *handle, int option, long value) {
    return (int)curl_easy_setopt((CURL *)handle, (CURLoption)option, value);
}

int lisa_curl_setopt_string(void *handle, int option, const char *value) {
    return (int)curl_easy_setopt((CURL *)handle, (CURLoption)option, value);
}

int lisa_curl_setopt_pointer(void *handle, int option, void *value) {
    return (int)curl_easy_setopt((CURL *)handle, (CURLoption)option, value);
}

int lisa_curl_setopt_offset(void *handle, int option, int64_t value) {
    return (int)curl_easy_setopt((CURL *)handle, (CURLoption)option, (curl_off_t)value);
}

int lisa_curl_set_write_callback(void *handle, lisa_curl_data_callback callback, void *userdata) {
    CURLcode result = curl_easy_setopt((CURL *)handle, CURLOPT_WRITEFUNCTION, (curl_write_callback)callback);
    if (result == CURLE_OK) result = curl_easy_setopt((CURL *)handle, CURLOPT_WRITEDATA, userdata);
    return (int)result;
}

int lisa_curl_set_header_callback(void *handle, lisa_curl_data_callback callback, void *userdata) {
    CURLcode result = curl_easy_setopt((CURL *)handle, CURLOPT_HEADERFUNCTION, (curl_write_callback)callback);
    if (result == CURLE_OK) result = curl_easy_setopt((CURL *)handle, CURLOPT_HEADERDATA, userdata);
    return (int)result;
}

int lisa_curl_set_read_callback(void *handle, lisa_curl_data_callback callback, void *userdata) {
    CURLcode result = curl_easy_setopt((CURL *)handle, CURLOPT_READFUNCTION, (curl_read_callback)callback);
    if (result == CURLE_OK) result = curl_easy_setopt((CURL *)handle, CURLOPT_READDATA, userdata);
    return (int)result;
}

static int lisa_progress(void *clientp, curl_off_t dltotal, curl_off_t dlnow, curl_off_t ultotal, curl_off_t ulnow) {
    (void)dltotal;
    (void)dlnow;
    (void)ultotal;
    (void)ulnow;
    lisa_curl_abort_binding *binding = (lisa_curl_abort_binding *)clientp;
    return (binding != NULL && binding->check != NULL && binding->check(binding->userdata) != 0) ? 1 : 0;
}

int lisa_curl_set_abort_check(void *handle, lisa_curl_abort_binding *binding) {
    if (binding == NULL || binding->check == NULL) return (int)CURLE_BAD_FUNCTION_ARGUMENT;
    CURLcode result = curl_easy_setopt((CURL *)handle, CURLOPT_XFERINFOFUNCTION, lisa_progress);
    if (result == CURLE_OK) result = curl_easy_setopt((CURL *)handle, CURLOPT_XFERINFODATA, (void *)binding);
    if (result == CURLE_OK) result = curl_easy_setopt((CURL *)handle, CURLOPT_NOPROGRESS, 0L);
    return (int)result;
}

static curl_socket_t lisa_open_socket(void *clientp, curlsocktype purpose, struct curl_sockaddr *address) {
    lisa_curl_address_gate *gate = (lisa_curl_address_gate *)clientp;
    if (gate == NULL || gate->check == NULL || address == NULL || purpose != CURLSOCKTYPE_IPCXN) return CURL_SOCKET_BAD;
    // libcurl passes storage large enough for any socket address (lib/cf-socket.h), as its documentation's cast relies on.
    if (address->family == AF_INET) {
        const struct sockaddr_in *v4 = (const struct sockaddr_in *)(const void *)&address->addr;
        if (!gate->check(gate->context, (const unsigned char *)&v4->sin_addr, 4)) return CURL_SOCKET_BAD;
    } else if (address->family == AF_INET6) {
        const struct sockaddr_in6 *v6 = (const struct sockaddr_in6 *)(const void *)&address->addr;
        if (!gate->check(gate->context, (const unsigned char *)&v6->sin6_addr, 16)) return CURL_SOCKET_BAD;
    } else {
        return CURL_SOCKET_BAD;
    }
#ifdef SOCK_CLOEXEC
    return socket(address->family, address->socktype | SOCK_CLOEXEC, address->protocol);
#else
    return socket(address->family, address->socktype, address->protocol);
#endif
}

static int lisa_prereq(void *clientp, char *primary_ip, char *local_ip, int primary_port, int local_port) {
    (void)local_ip;
    (void)primary_port;
    (void)local_port;
    lisa_curl_address_gate *gate = (lisa_curl_address_gate *)clientp;
    if (gate == NULL || gate->check == NULL || primary_ip == NULL) return CURL_PREREQFUNC_ABORT;
    unsigned char bytes[16];
    int allowed = 0;
    if (inet_pton(AF_INET, primary_ip, bytes) == 1) {
        allowed = gate->check(gate->context, bytes, 4);
    } else if (inet_pton(AF_INET6, primary_ip, bytes) == 1) {
        allowed = gate->check(gate->context, bytes, 16);
    }
    if (!allowed) return CURL_PREREQFUNC_ABORT;
    if (gate->max_requests > 0 && gate->request_count >= gate->max_requests) {
        gate->resend_refused = 1;
        return CURL_PREREQFUNC_ABORT;
    }
    gate->request_count += 1;
    gate->request_started = 1;
    return CURL_PREREQFUNC_OK;
}

int lisa_curl_install_address_gate(void *handle, lisa_curl_address_gate *gate) {
    if (gate == NULL || gate->check == NULL) return (int)CURLE_BAD_FUNCTION_ARGUMENT;
    CURLcode result = curl_easy_setopt((CURL *)handle, CURLOPT_OPENSOCKETFUNCTION, lisa_open_socket);
    if (result == CURLE_OK) result = curl_easy_setopt((CURL *)handle, CURLOPT_OPENSOCKETDATA, (void *)gate);
    if (result == CURLE_OK) result = curl_easy_setopt((CURL *)handle, CURLOPT_PREREQFUNCTION, lisa_prereq);
    if (result == CURLE_OK) result = curl_easy_setopt((CURL *)handle, CURLOPT_PREREQDATA, (void *)gate);
    return (int)result;
}

int lisa_curl_getinfo_long(void *handle, int info, long *value) {
    return (int)curl_easy_getinfo((CURL *)handle, (CURLINFO)info, value);
}

int lisa_curl_getinfo_string(void *handle, int info, const char **value) {
    char *result = NULL;
    CURLcode code = curl_easy_getinfo((CURL *)handle, (CURLINFO)info, &result);
    *value = result;
    return (int)code;
}

int lisa_curl_getinfo_socket(void *handle, int info, int *value) {
    curl_socket_t socket = CURL_SOCKET_BAD;
    CURLcode code = curl_easy_getinfo((CURL *)handle, (CURLINFO)info, &socket);
    *value = (int)socket;
    return (int)code;
}

int lisa_curl_wait_socket(int socket, int for_writing, long timeout_ms) {
    struct pollfd descriptor;
    memset(&descriptor, 0, sizeof(descriptor));
    descriptor.fd = socket;
    descriptor.events = for_writing ? POLLOUT : POLLIN;
    int ready = poll(&descriptor, 1, (int)(timeout_ms < 0 ? 0 : (timeout_ms > 2147483647L ? 2147483647L : timeout_ms)));
    if (ready < 0) return -1;
    if (ready == 0) return 0;
    if (descriptor.revents & (POLLERR | POLLNVAL)) return -1;
    return 1;
}
