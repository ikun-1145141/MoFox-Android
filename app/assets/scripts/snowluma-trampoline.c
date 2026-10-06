/*
 * snowluma-trampoline.c (v2, fork-safe)
 *
 * 在 QQ 进程内补调 SnowLuma hook 组件的引擎启动导出
 * snowluma_linux_hook_start_dynamic（官方 ptrace 注入器的最后一步）。
 *
 * v1 教训：构造函数里 pthread_create + 线程立刻做 stdio/malloc，
 * 会在 Chromium fork zygote 的窗口期把 malloc/mmap 锁带进子进程，
 * 导致 GPU 子进程启动失败（error_code=1002）→ "GPU process isn't usable"。
 *
 * v2 fork-safe 设计：
 *   1. 构造函数内先用裸 syscall 读 cmdline，含 "--type=" 的 Electron
 *      子进程直接不创建线程；
 *   2. 线程先纯 nanosleep 3s——期间零用户态锁活动，完全避开
 *      Chromium 早期的 zygote/GPU fork 窗口；
 *   3. dlsym 之前只用 open/read/close/nanomsleep/memmem（无 malloc）；
 *   4. wrapper.node 出现（Electron 就绪）后再等 5s 才调用导出。
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <pthread.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define TRAMPOLINE_LOG "/tmp/snowluma-trampoline.log"

/* 纯 syscall 追加一行日志（无 stdio/malloc，任何阶段都安全） */
static void log_raw(const char *s) {
    int fd = open(TRAMPOLINE_LOG, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) return;
    size_t len = 0;
    while (s[len] && len < 512) len++;
    ssize_t rc = write(fd, "[trampoline] ", 13);
    rc = write(fd, s, len);
    rc = write(fd, "\n", 1);
    (void)rc;
    close(fd);
}

static void msleep_raw(int ms) {
    struct timespec ts;
    ts.tv_sec = ms / 1000;
    ts.tv_nsec = (long)(ms % 1000) * 1000000L;
    nanosleep(&ts, NULL);
}

/* 裸读小文件到栈缓冲（cmdline），返回长度 */
static int read_small_raw(const char *path, char *buf, int cap) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) return -1;
    int total = 0;
    while (total < cap - 1) {
        ssize_t n = read(fd, buf + total, cap - 1 - total);
        if (n <= 0) break;
        total += (int)n;
    }
    close(fd);
    buf[total] = 0;
    return total;
}

/* maps 裸扫描：分块读 + 跨块重叠拼接，无 malloc */
static int maps_contain_raw(const char *needle) {
    char buf[8192];
    char carry[64];
    char tmp[8320];
    size_t carry_len = 0;
    int fd = open("/proc/self/maps", O_RDONLY);
    if (fd < 0) return 0;
    size_t nlen = strlen(needle);
    ssize_t n;
    int found = 0;
    while ((n = read(fd, buf, sizeof buf)) > 0) {
        if ((size_t)n > sizeof buf) break;
        memcpy(tmp, carry, carry_len);
        memcpy(tmp + carry_len, buf, (size_t)n);
        size_t total = carry_len + (size_t)n;
        if (total >= nlen && memmem(tmp, total, needle, nlen)) {
            found = 1;
            break;
        }
        carry_len = total > sizeof carry ? sizeof carry : total;
        memcpy(carry, tmp + total - carry_len, carry_len);
    }
    close(fd);
    return found;
}

static void *trampoline_thread(void *arg) {
    (void)arg;

    /* 关键窗口：Chromium 在 main 后 ~1s 内 fork zygote / 拉 GPU 子进程。
     * 此期间保持零用户态锁活动。 */
    msleep_raw(3000);

    /* 必须是映射了 SnowLuma 组件的进程（QQ 主进程）；10s 内没有就退出 */
    int i;
    for (i = 0; i < 20; i++) {
        if (maps_contain_raw("snowluma-linux-arm64.so")) break;
        msleep_raw(500);
    }
    if (i >= 20) return NULL;

    /* 等 Electron 模块就绪（最多 120s） */
    for (i = 0; i < 240; i++) {
        if (maps_contain_raw("wrapper.node")) break;
        msleep_raw(500);
    }
    if (i >= 240) {
        log_raw("timeout: wrapper.node not found in maps");
        return NULL;
    }
    msleep_raw(5000);

    void *fn_stop = dlsym(RTLD_DEFAULT, "snowluma_linux_hook_stop_dynamic");
    void *fn = dlsym(RTLD_DEFAULT, "snowluma_linux_hook_start_dynamic");
    if (!fn) {
        log_raw("dlsym: snowluma_linux_hook_start_dynamic not found");
        return NULL;
    }

    /* stub 线程在 QQ 进程极早期已把引擎按当时的模块状态启动过一次
     * （目标解析时机错误，之后不再重解析）。这里先停再启，强制引擎
     * 在 QQ 完全就绪后完整重启一次，让目标解析与钩子安装落在正确
     * 时刻，并让登录后的 MSF 连接从头被观测。 */
    if (fn_stop) {
        int rc_stop = ((int (*)(long))fn_stop)(0);
        log_raw("stop_dynamic called");
        if (rc_stop != 1) {
            char m[32] = "stop rc=";
            int v = rc_stop, neg = v < 0;
            char *q = m + 8;
            if (neg) { *q++ = '-'; v = -v; }
            if (v == 0) *q++ = '0';
            else { char d[12]; int k = 0; while (v) { d[k++] = (char)('0' + v % 10); v /= 10; } while (k) *q++ = d[--k]; }
            *q = 0;
            log_raw(m);
        }
        msleep_raw(2000);
    }

    log_raw("calling snowluma_linux_hook_start_dynamic(0)");
    int rc = ((int (*)(long))fn)(0);
    char buf[64];
    const char *p = "start_dynamic rc=";
    memcpy(buf, p, strlen(p));
    int v = rc;
    int neg = 0;
    char *q = buf + strlen(p);
    if (v < 0) { neg = 1; v = -v; }
    if (v == 0) *q++ = '0';
    else {
        char digits[12];
        int d = 0;
        while (v > 0) { digits[d++] = (char)('0' + v % 10); v /= 10; }
        while (d > 0) *q++ = digits[--d];
    }
    if (neg) {
        memmove(buf + strlen(p) + 1, buf + strlen(p), q - (buf + strlen(p)));
        *q = '-';
        q++;
    }
    *q = 0;
    log_raw(buf);
    return NULL;
}

__attribute__((constructor))
static void trampoline_ctor(void) {
    /* Electron 子进程（--type=...）绝不创建线程：裸读判断，无任何分配 */
    char buf[4096];
    if (read_small_raw("/proc/self/cmdline", buf, sizeof buf) < 0) return;
    if (strstr(buf, "--type=") != NULL) return;

    pthread_t t;
    if (pthread_create(&t, NULL, trampoline_thread, NULL) == 0)
        pthread_detach(t);
}
