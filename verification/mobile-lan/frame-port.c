/* Exchange one Ethernet frame per length-prefixed record with the bridge. */
#include <errno.h>
#include <fcntl.h>
#include <net/if.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>
#ifdef __APPLE__
#include <net/bpf.h>
#include <sys/ioctl.h>
#else
#include <arpa/inet.h>
#include <linux/if_ether.h>
#include <linux/if_packet.h>
#endif

#define FRAME_MAX 1514
#ifdef __APPLE__
static unsigned int bpf_buffer_length;
#endif

static void die(const char *what) {
    perror(what);
    exit(1);
}

static int transfer(int fd, void *buffer, size_t size, int output) {
    unsigned char *cursor = buffer;
    while (size) {
        ssize_t count = output ? write(fd, cursor, size) : read(fd, cursor, size);
        if (count < 0 && errno == EINTR) continue;
        if (count < 0) die(output ? "write" : "read");
        if (count == 0) return 0;
        cursor += count;
        size -= (size_t)count;
    }
    return 1;
}

static void emit(const unsigned char *frame, size_t size) {
    if (size < 14 || size > FRAME_MAX) return;
    unsigned char header[2] = {size >> 8, size & 255};
    transfer(STDOUT_FILENO, header, sizeof(header), 1);
    transfer(STDOUT_FILENO, (void *)frame, size, 1);
}

static int open_port(const char *name) {
#ifdef __APPLE__
    int fd = -1;
    for (int i = 0; i < 256; i++) {
        char path[32];
        snprintf(path, sizeof(path), "/dev/bpf%d", i);
        fd = open(path, O_RDWR);
        if (fd != -1) break;
        if (errno != EBUSY) die("open BPF");
    }
    if (fd == -1) die("open BPF");
    struct ifreq iface = {0};
    if (strlen(name) >= sizeof(iface.ifr_name)) exit(2);
    strcpy(iface.ifr_name, name);
    unsigned int size = 16384;
    unsigned int one = 1;
    unsigned int zero = 0;
    if (ioctl(fd, BIOCSBLEN, &size) == -1 || ioctl(fd, BIOCSETIF, &iface) == -1 ||
        ioctl(fd, BIOCIMMEDIATE, &one) == -1 || ioctl(fd, BIOCSHDRCMPLT, &one) == -1 ||
        ioctl(fd, BIOCSSEESENT, &zero) == -1 || ioctl(fd, BIOCPROMISC, NULL) == -1)
        die("configure BPF");
    if (ioctl(fd, BIOCGBLEN, &size) == -1 || size > 65536) die("get BPF buffer length");
    bpf_buffer_length = size;
#else
    int fd = socket(AF_PACKET, SOCK_RAW, htons(ETH_P_ALL));
    if (fd == -1) die("open AF_PACKET");
    struct sockaddr_ll address = {0};
    address.sll_family = AF_PACKET;
    address.sll_protocol = htons(ETH_P_ALL);
    address.sll_ifindex = if_nametoindex(name);
    if (!address.sll_ifindex || bind(fd, (struct sockaddr *)&address, sizeof(address)) == -1)
        die("bind AF_PACKET");
    struct packet_mreq membership = {0};
    membership.mr_ifindex = address.sll_ifindex;
    membership.mr_type = PACKET_MR_PROMISC;
    if (setsockopt(fd, SOL_PACKET, PACKET_ADD_MEMBERSHIP, &membership, sizeof(membership)) == -1)
        die("enable TAP capture");
#endif
    return fd;
}

static void capture(int fd) {
#ifdef __APPLE__
    unsigned char bytes[65536];
    /* Darwin requires the read size to equal BIOCGBLEN, including immediate mode. */
    ssize_t count = read(fd, bytes, bpf_buffer_length);
    if (count < 0) die("read BPF");
    for (size_t i = 0; i + sizeof(struct bpf_hdr) <= (size_t)count;) {
        struct bpf_hdr header;
        memcpy(&header, bytes + i, sizeof(header));
        size_t used = (size_t)header.bh_hdrlen + header.bh_caplen;
        if (header.bh_hdrlen < 18 || used > (size_t)count - i) break;
        if (header.bh_caplen == header.bh_datalen)
            emit(bytes + i + header.bh_hdrlen, header.bh_caplen);
        i += BPF_WORDALIGN(used);
    }
#else
    unsigned char bytes[FRAME_MAX + 1];
    struct sockaddr_ll source = {0};
    socklen_t size = sizeof(source);
    ssize_t count = recvfrom(fd, bytes, sizeof(bytes), 0, (struct sockaddr *)&source, &size);
    if (count < 0) die("read AF_PACKET");
    if (source.sll_pkttype != PACKET_OUTGOING) emit(bytes, (size_t)count);
#endif
}

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    struct pollfd ports[] = {{STDIN_FILENO, POLLIN, 0}, {open_port(argv[1]), POLLIN, 0}};
    unsigned char ready[2] = {0, 0};
    if (!transfer(STDOUT_FILENO, ready, sizeof(ready), 1)) return 1;
    while (1) {
        int ready = poll(ports, 2, -1);
        if (ready < 0 && errno == EINTR) continue;
        if (ready < 0) die("poll");
        if (ports[0].revents & (POLLHUP | POLLERR)) return 0;
        if (ports[0].revents & POLLIN) {
            unsigned char size[2], frame[FRAME_MAX];
            if (!transfer(STDIN_FILENO, size, sizeof(size), 0)) return 0;
            size_t length = ((size_t)size[0] << 8) | size[1];
            if (length < 14 || length > FRAME_MAX) return 2;
            if (!transfer(STDIN_FILENO, frame, length, 0)) return 2;
            if (write(ports[1].fd, frame, length) != (ssize_t)length) die("inject frame");
        }
        if (ports[1].revents & (POLLHUP | POLLERR | POLLNVAL)) return 1;
        if (ports[1].revents & POLLIN) capture(ports[1].fd);
    }
}
