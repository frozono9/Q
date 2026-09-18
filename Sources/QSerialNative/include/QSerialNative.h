#ifndef Q_SERIAL_NATIVE_H
#define Q_SERIAL_NATIVE_H
#include <stddef.h>
#include <stdint.h>

typedef struct q_serial_port q_serial_port;
// Only native Espressif 303A:1001 serial candidates; callers must handshake.
// Returns byte count for newline-delimited paths, or -1 with an error.
int q_serial_candidates(char *output, size_t capacity, char *error, size_t error_size);
q_serial_port *q_serial_open(const char *path, char *error, size_t error_size);
int q_serial_read(q_serial_port *port, uint8_t *bytes, size_t capacity,
                  int timeout_ms, char *error, size_t error_size);
int q_serial_write(q_serial_port *port, const uint8_t *bytes, size_t count,
                   char *error, size_t error_size);
void q_serial_close(q_serial_port *port);
void q_install_interrupt_handler(void);
int q_interrupted(void);
// One blocking pipe read; returns available bytes, EOF (0), or error (-1).
int q_stdin_read(uint8_t *bytes, size_t capacity);
#endif
