/* Offline CA directory filter for shell-less containers. No network or TLS code.
 * ca-filter-roots.h contains exact DER base64 from the incident's roots.json.
 */
#define _POSIX_C_SOURCE 200809L
#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include "ca-filter-roots.h"

static void fail(const char *message) { perror(message); exit(EXIT_FAILURE); }

static int blocked(const char *begin, const char *end) {
    size_t length = (size_t)(end - begin), count = 0;
    char *canonical = malloc(length + 1);
    if (!canonical) fail("allocate certificate");
    for (const char *p = begin; p < end; p++)
        if (!isspace((unsigned char)*p)) canonical[count++] = *p;
    canonical[count] = '\0';
    int result = 0;
    for (size_t i = 0; i < sizeof(blocked_roots) / sizeof(blocked_roots[0]); i++)
        if (strcmp(canonical, blocked_roots[i]) == 0) result = 1;
    free(canonical);
    return result;
}

static void copy_filtered(const char *source, const char *destination, int bundle) {
    FILE *input = fopen(source, "rb");
    if (!input) fail(source);
    struct stat info;
    if (fstat(fileno(input), &info) || !S_ISREG(info.st_mode) ||
        info.st_size < 0 || info.st_size > 8 * 1024 * 1024) {
        fprintf(stderr, "Unexpected CA file: %s\n", source); exit(EXIT_FAILURE);
    }
    size_t size = (size_t)info.st_size;
    char *data = malloc(size + 1), *filtered = malloc(size + 1);
    if (!data || !filtered) fail("allocate CA file");
    if (fread(data, 1, size, input) != size || fclose(input)) fail("read CA file");
    data[size] = '\0';
    if (memchr(data, '\0', size)) {
        fprintf(stderr, "Unexpected binary CA file: %s\n", source); exit(EXIT_FAILURE);
    }
    static const char start[] = "-----BEGIN CERTIFICATE-----";
    static const char finish[] = "-----END CERTIFICATE-----";
    const char *cursor = data;
    size_t output_size = 0, total = 0, kept = 0;
    for (;;) {
        const char *begin = strstr(cursor, start);
        if (!begin) {
            size_t length = strlen(cursor);
            memcpy(filtered + output_size, cursor, length); output_size += length;
            break;
        }
        size_t prefix = (size_t)(begin - cursor);
        memcpy(filtered + output_size, cursor, prefix); output_size += prefix;
        const char *body = begin + strlen(start), *end = strstr(body, finish);
        if (!end || (strstr(body, start) && strstr(body, start) < end)) {
            fprintf(stderr, "Malformed certificate: %s\n", source); exit(EXIT_FAILURE);
        }
        total++;
        const char *after = end + strlen(finish);
        if (!blocked(body, end)) {
            size_t length = (size_t)(after - begin);
            memcpy(filtered + output_size, begin, length); output_size += length; kept++;
        }
        cursor = after;
    }
    if (bundle && !kept) {
        fprintf(stderr, "No trusted certificates retained: %s\n", source); exit(EXIT_FAILURE);
    }
    if (total && !kept) {
        if (unlink(destination) && errno != ENOENT) fail(destination);
    } else {
        FILE *output = fopen(destination, "wb");
        if (!output) fail(destination);
        if (fwrite(filtered, 1, output_size, output) != output_size || fclose(output))
            fail("write filtered CA file");
        if (chmod(destination, 0644)) fail(destination);
    }
    free(data); free(filtered);
}

int main(int argc, char **argv) {
    if (argc != 3) { fprintf(stderr, "Usage: ca-filter SOURCE_DIRECTORY OUTPUT_DIRECTORY\n"); return 2; }
    if (mkdir(argv[2], 0755) && errno != EEXIST) fail(argv[2]);
    DIR *directory = opendir(argv[1]);
    if (!directory) fail(argv[1]);
    struct dirent *entry;
    size_t files = 0;
    int found_bundle = 0;
    for (;;) {
        errno = 0;
        entry = readdir(directory);
        if (!entry) {
            if (errno) fail("read CA directory");
            break;
        }
        if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
        size_t input_size = strlen(argv[1]) + strlen(entry->d_name) + 2;
        size_t output_size = strlen(argv[2]) + strlen(entry->d_name) + 2;
        char *source = malloc(input_size), *destination = malloc(output_size);
        if (!source || !destination) fail("allocate CA path");
        snprintf(source, input_size, "%s/%s", argv[1], entry->d_name);
        snprintf(destination, output_size, "%s/%s", argv[2], entry->d_name);
        int bundle = !strcmp(entry->d_name, "ca-certificates.crt");
        copy_filtered(source, destination, bundle);
        found_bundle |= bundle; files++;
        free(source); free(destination);
    }
    if (closedir(directory)) fail("close CA directory");
    if (!found_bundle) { fprintf(stderr, "Missing system CA bundle\n"); return 1; }
    printf("Filtered %zu CA directory entries; preserved unrelated certificates\n", files);
    return 0;
}
