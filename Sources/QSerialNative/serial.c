#include "QSerialNative.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

static int append_path(char *out, size_t capacity, const char *path) {
    size_t used = strlen(out), n = strlen(path);
    if (used + n + 2 > capacity) return -1;
    memcpy(out + used, path, n);
    out[used + n] = '\n';
    out[used + n + 1] = 0;
    return 0;
}

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <setupapi.h>

struct q_serial_port { HANDLE handle; };
static volatile LONG interrupted = 0;
static BOOL WINAPI on_interrupt(DWORD type) {
    if (type == CTRL_C_EVENT || type == CTRL_BREAK_EVENT || type == CTRL_CLOSE_EVENT) {
        InterlockedExchange(&interrupted, 1);
        return TRUE;
    }
    return FALSE;
}
void q_install_interrupt_handler(void) { SetConsoleCtrlHandler(on_interrupt, TRUE); }
int q_interrupted(void) { return InterlockedCompareExchange(&interrupted, 0, 0) != 0; }
int q_stdin_read(uint8_t *bytes, size_t capacity) {
    DWORD count = 0;
    if (!ReadFile(GetStdHandle(STD_INPUT_HANDLE), bytes, (DWORD)capacity, &count, NULL))
        return GetLastError() == ERROR_BROKEN_PIPE ? 0 : -1;
    return (int)count;
}
static int system_error(const char *action, char *error, size_t size) {
    DWORD code = GetLastError();
    char message[256] = {0};
    FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
                   NULL, code, 0, message, sizeof(message), NULL);
    snprintf(error, size, "%s (Windows %lu): %s", action, (unsigned long)code, message);
    return -1;
}

int q_serial_candidates(char *output, size_t capacity, char *error, size_t error_size) {
    static const GUID ports = {0x4d36e978, 0xe325, 0x11ce, {0xbf,0xc1,0x08,0x00,0x2b,0xe1,0x03,0x18}};
    if (!capacity) return -1;
    output[0] = 0;
    HDEVINFO devices = SetupDiGetClassDevsA(&ports, NULL, NULL, DIGCF_PRESENT);
    if (devices == INVALID_HANDLE_VALUE) return system_error("Enumerate serial ports", error, error_size);
    SP_DEVINFO_DATA info = {0};
    info.cbSize = sizeof(info);
    for (DWORD index = 0; SetupDiEnumDeviceInfo(devices, index, &info); ++index) {
        char hardware[4096] = {0};
        if (!SetupDiGetDeviceRegistryPropertyA(devices, &info, SPDRP_HARDWAREID,
                NULL, (BYTE *)hardware, sizeof(hardware) - 2, NULL)) continue;
        int matches = 0;
        for (char *id = hardware; *id; id += strlen(id) + 1) {
            for (char *p = id; *p; ++p) if (*p >= 'a' && *p <= 'z') *p -= 32;
            if (strstr(id, "VID_303A&PID_1001")) matches = 1;
        }
        if (!matches) continue;
        HKEY key = SetupDiOpenDevRegKey(devices, &info, DICS_FLAG_GLOBAL, 0, DIREG_DEV, KEY_READ);
        if (key == INVALID_HANDLE_VALUE) continue;
        char name[128] = {0};
        DWORD size = sizeof(name) - 1, type = 0;
        LONG result = RegQueryValueExA(key, "PortName", NULL, &type, (BYTE *)name, &size);
        RegCloseKey(key);
        if (result == ERROR_SUCCESS && type == REG_SZ && strncmp(name, "COM", 3) == 0) {
            if (append_path(output, capacity, name) < 0) {
                SetupDiDestroyDeviceInfoList(devices);
                snprintf(error, error_size, "Too many serial candidates");
                return -1;
            }
        }
    }
    SetupDiDestroyDeviceInfoList(devices);
    return (int)strlen(output);
}

q_serial_port *q_serial_open(const char *path, char *error, size_t error_size) {
    char device[256];
    // Only a COM device may be opened, never an arbitrary file or pipe.
    if (_strnicmp(path, "COM", 3) != 0 || !path[3] || strspn(path + 3, "0123456789") != strlen(path + 3)) {
        snprintf(error, error_size, "Expected a COM port, for example COM9"); return NULL;
    }
    snprintf(device, sizeof(device), "\\\\.\\%s", path);
    HANDLE handle = CreateFileA(device, GENERIC_READ | GENERIC_WRITE, 0, NULL,
                                OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (handle == INVALID_HANDLE_VALUE) { system_error("Open serial port (busy or unavailable)", error, error_size); return NULL; }
    DCB config = {0}; config.DCBlength = sizeof(config);
    if (!GetCommState(handle, &config)) goto failed;
    config.BaudRate = CBR_115200; config.ByteSize = 8; config.Parity = NOPARITY; config.StopBits = ONESTOPBIT;
    config.fBinary = TRUE; config.fParity = FALSE; config.fOutxCtsFlow = FALSE; config.fOutxDsrFlow = FALSE;
    config.fDtrControl = DTR_CONTROL_DISABLE; config.fRtsControl = RTS_CONTROL_DISABLE;
    config.fDsrSensitivity = FALSE; config.fOutX = FALSE; config.fInX = FALSE; config.fAbortOnError = FALSE;
    if (!SetCommState(handle, &config)) goto failed;
    COMMTIMEOUTS timeouts = {MAXDWORD, 0, 100, 0, 1000};
    if (!SetCommTimeouts(handle, &timeouts)) goto failed;
    q_serial_port *port = calloc(1, sizeof(*port));
    if (!port) { snprintf(error, error_size, "Out of memory"); CloseHandle(handle); return NULL; }
    port->handle = handle; return port;
failed:
    system_error("Configure serial port", error, error_size); CloseHandle(handle); return NULL;
}

int q_serial_read(q_serial_port *port, uint8_t *bytes, size_t capacity, int timeout_ms, char *error, size_t error_size) {
    COMMTIMEOUTS timeouts = {MAXDWORD, 0, (DWORD)(timeout_ms > 0 ? timeout_ms : 1), 0, 1000};
    if (!SetCommTimeouts(port->handle, &timeouts)) return system_error("Set serial timeout", error, error_size);
    DWORD count = 0;
    if (!ReadFile(port->handle, bytes, (DWORD)capacity, &count, NULL)) return system_error("Read serial port", error, error_size);
    return (int)count;
}
int q_serial_write(q_serial_port *port, const uint8_t *bytes, size_t count, char *error, size_t error_size) {
    DWORD written = 0;
    if (!WriteFile(port->handle, bytes, (DWORD)count, &written, NULL)) return system_error("Write serial port", error, error_size);
    if (written != count) { snprintf(error, error_size, "Serial write timed out"); return -1; }
    return (int)written;
}
void q_serial_close(q_serial_port *port) { if (port) { CloseHandle(port->handle); free(port); } }

#else
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <termios.h>
#include <sys/file.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <poll.h>
#include <dirent.h>
#include <signal.h>
#include <time.h>

struct q_serial_port { int fd; };
static volatile sig_atomic_t interrupted = 0;
static void on_interrupt(int signal_number) { (void)signal_number; interrupted = 1; }
void q_install_interrupt_handler(void) {
    struct sigaction action = {0}; action.sa_handler = on_interrupt;
    sigemptyset(&action.sa_mask); sigaction(SIGINT, &action, NULL); sigaction(SIGTERM, &action, NULL);
}
int q_interrupted(void) { return interrupted; }
static int system_error(const char *action, char *error, size_t size) {
    snprintf(error, size, "%s: %s", action, strerror(errno)); return -1;
}
static int usb_id(const char *directory, const char *name, unsigned expected) {
    char path[PATH_MAX]; snprintf(path, sizeof(path), "%s/%s", directory, name);
    FILE *file = fopen(path, "r"); if (!file) return 0;
    unsigned value = 0; int read = fscanf(file, "%x", &value); fclose(file);
    return read == 1 && value == expected;
}
int q_serial_candidates(char *output, size_t capacity, char *error, size_t error_size) {
    if (!capacity) return -1;
    output[0] = 0;
    DIR *directory = opendir("/sys/class/tty");
    if (!directory) return system_error("Enumerate serial ports", error, error_size);
    struct dirent *entry;
    while ((entry = readdir(directory))) {
        if (strncmp(entry->d_name, "ttyACM", 6) && strncmp(entry->d_name, "ttyUSB", 6)) continue;
        char link[PATH_MAX], parent[PATH_MAX];
        snprintf(link, sizeof(link), "/sys/class/tty/%s/device", entry->d_name);
        if (!realpath(link, parent)) continue;
        while (*parent) {
            if (usb_id(parent, "idVendor", 0x303a) && usb_id(parent, "idProduct", 0x1001)) {
                char path[512]; snprintf(path, sizeof(path), "/dev/%s", entry->d_name);
                if (append_path(output, capacity, path) < 0) {
                    closedir(directory); snprintf(error, error_size, "Too many serial candidates"); return -1;
                }
                break;
            }
            char *slash = strrchr(parent, '/'); if (!slash) break; *slash = 0;
        }
    }
    closedir(directory); return (int)strlen(output);
}
q_serial_port *q_serial_open(const char *path, char *error, size_t error_size) {
    int fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) { system_error("Open serial port (check device permissions)", error, error_size); return NULL; }
    if (!isatty(fd)) { snprintf(error, error_size, "Not a serial terminal"); close(fd); return NULL; }
    int exclusive = 0;
    if (flock(fd, LOCK_EX | LOCK_NB) < 0 || ioctl(fd, TIOCEXCL) < 0) goto failed;
    exclusive = 1;
    struct termios config;
    if (tcgetattr(fd, &config) < 0) goto failed;
    cfmakeraw(&config);
    config.c_cflag &= ~(CSIZE | PARENB | CSTOPB | CRTSCTS | HUPCL);
    config.c_cflag |= CS8 | CLOCAL | CREAD;
    config.c_cc[VMIN] = 0; config.c_cc[VTIME] = 0;
    if (cfsetispeed(&config, B115200) < 0 || cfsetospeed(&config, B115200) < 0 || tcsetattr(fd, TCSANOW, &config) < 0) goto failed;
    q_serial_port *port = calloc(1, sizeof(*port));
    if (!port) { snprintf(error, error_size, "Out of memory"); ioctl(fd, TIOCNXCL); close(fd); return NULL; }
    port->fd = fd; return port;
failed:
    system_error("Configure or lock serial port", error, error_size);
    if (exclusive) ioctl(fd, TIOCNXCL);
    close(fd); return NULL;
}
int q_serial_read(q_serial_port *port, uint8_t *bytes, size_t capacity, int timeout_ms, char *error, size_t error_size) {
    struct pollfd request = {port->fd, POLLIN, 0};
    int result = poll(&request, 1, timeout_ms);
    if (result < 0 && errno == EINTR) return 0;
    if (result < 0) return system_error("Poll serial port", error, error_size);
    if (!result) return 0;
    if (request.revents & (POLLHUP | POLLERR | POLLNVAL)) { snprintf(error, error_size, "Serial device disconnected"); return -1; }
    ssize_t count = read(port->fd, bytes, capacity);
    if (count < 0 && (errno == EAGAIN || errno == EINTR)) return 0;
    if (count < 0) return system_error("Read serial port", error, error_size);
    return (int)count;
}
static int64_t milliseconds(void) {
    struct timespec now; clock_gettime(CLOCK_MONOTONIC, &now);
    return (int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}
int q_serial_write(q_serial_port *port, const uint8_t *bytes, size_t count, char *error, size_t error_size) {
    size_t offset = 0; int64_t deadline = milliseconds() + 1000;
    while (offset < count) {
        int64_t remaining = deadline - milliseconds();
        if (remaining <= 0) { snprintf(error, error_size, "Serial write timed out"); return -1; }
        struct pollfd request = {port->fd, POLLOUT, 0};
        int ready = poll(&request, 1, (int)remaining);
        if (ready < 0 && errno == EINTR) continue;
        if (ready < 0) return system_error("Poll serial write", error, error_size);
        if (!ready) continue;
        if (request.revents & (POLLHUP | POLLERR | POLLNVAL)) { snprintf(error, error_size, "Serial device disconnected"); return -1; }
        ssize_t sent = write(port->fd, bytes + offset, count - offset);
        if (sent < 0 && (errno == EAGAIN || errno == EINTR)) continue;
        if (sent < 0) return system_error("Write serial port", error, error_size);
        offset += (size_t)sent;
    }
    return (int)offset;
}
void q_serial_close(q_serial_port *port) {
    if (port) { ioctl(port->fd, TIOCNXCL); close(port->fd); free(port); }
}
int q_stdin_read(uint8_t *bytes, size_t capacity) {
    ssize_t count;
    do { count = read(STDIN_FILENO, bytes, capacity); } while (count < 0 && errno == EINTR);
    return (int)count;
}
#endif
