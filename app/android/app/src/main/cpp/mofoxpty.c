#include <errno.h>
#include <fcntl.h>
#include <jni.h>
#include <pty.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

static char **copy_string_array(JNIEnv *env, jobjectArray values) {
    if (values == NULL) return NULL;
    jsize count = (*env)->GetArrayLength(env, values);
    char **result = calloc((size_t)count + 1, sizeof(char *));
    if (result == NULL) return NULL;
    for (jsize index = 0; index < count; index++) {
        jstring item = (jstring)(*env)->GetObjectArrayElement(env, values, index);
        const char *chars = (*env)->GetStringUTFChars(env, item, NULL);
        if (chars == NULL) {
            (*env)->DeleteLocalRef(env, item);
            continue;
        }
        result[index] = strdup(chars);
        (*env)->ReleaseStringUTFChars(env, item, chars);
        (*env)->DeleteLocalRef(env, item);
    }
    result[count] = NULL;
    return result;
}

static void free_string_array(char **values) {
    if (values == NULL) return;
    for (size_t index = 0; values[index] != NULL; index++) {
        free(values[index]);
    }
    free(values);
}

JNIEXPORT jlongArray JNICALL
Java_com_mofox_android_runtime_NativePty_nativeStart(
    JNIEnv *env,
    jobject thiz,
    jobjectArray command,
    jobjectArray environment,
    jstring cwd,
    jint cols,
    jint rows
) {
    (void)thiz;
    char **argv = copy_string_array(env, command);
    char **envp = copy_string_array(env, environment);
    const char *cwd_chars = cwd == NULL ? NULL : (*env)->GetStringUTFChars(env, cwd, NULL);
    if (argv == NULL || argv[0] == NULL || envp == NULL) {
        free_string_array(argv);
        free_string_array(envp);
        if (cwd_chars != NULL) (*env)->ReleaseStringUTFChars(env, cwd, cwd_chars);
        return NULL;
    }

    struct winsize size;
    memset(&size, 0, sizeof(size));
    size.ws_col = (unsigned short)(cols > 0 ? cols : 80);
    size.ws_row = (unsigned short)(rows > 0 ? rows : 24);

    int master_fd = -1;
    pid_t pid = forkpty(&master_fd, NULL, NULL, &size);
    if (pid == 0) {
        if (cwd_chars != NULL) chdir(cwd_chars);
        execve(argv[0], argv, envp);
        _exit(127);
    }

    free_string_array(argv);
    free_string_array(envp);
    if (cwd_chars != NULL) (*env)->ReleaseStringUTFChars(env, cwd, cwd_chars);

    if (pid < 0) return NULL;

    int flags = fcntl(master_fd, F_GETFD);
    if (flags >= 0) fcntl(master_fd, F_SETFD, flags | FD_CLOEXEC);

    jlong values[2] = {(jlong)pid, (jlong)master_fd};
    jlongArray result = (*env)->NewLongArray(env, 2);
    if (result == NULL) {
        close(master_fd);
        kill(pid, SIGTERM);
        return NULL;
    }
    (*env)->SetLongArrayRegion(env, result, 0, 2, values);
    return result;
}

JNIEXPORT jint JNICALL
Java_com_mofox_android_runtime_NativePty_nativeRead(
    JNIEnv *env,
    jobject thiz,
    jint fd,
    jbyteArray buffer,
    jint offset,
    jint length
) {
    (void)thiz;
    jbyte *bytes = (*env)->GetByteArrayElements(env, buffer, NULL);
    if (bytes == NULL) return -1;
    ssize_t count = read(fd, bytes + offset, (size_t)length);
    (*env)->ReleaseByteArrayElements(env, buffer, bytes, 0);
    if (count < 0) {
        if (errno == EIO) return 0;
        return -errno;
    }
    return (jint)count;
}

JNIEXPORT jint JNICALL
Java_com_mofox_android_runtime_NativePty_nativeWrite(
    JNIEnv *env,
    jobject thiz,
    jint fd,
    jbyteArray data,
    jint offset,
    jint length
) {
    (void)thiz;
    jbyte *bytes = (*env)->GetByteArrayElements(env, data, NULL);
    if (bytes == NULL) return -1;
    ssize_t count = write(fd, bytes + offset, (size_t)length);
    (*env)->ReleaseByteArrayElements(env, data, bytes, JNI_ABORT);
    if (count < 0) return -errno;
    return (jint)count;
}

JNIEXPORT void JNICALL
Java_com_mofox_android_runtime_NativePty_nativeResize(
    JNIEnv *env,
    jobject thiz,
    jint fd,
    jint cols,
    jint rows
) {
    (void)env;
    (void)thiz;
    struct winsize size;
    memset(&size, 0, sizeof(size));
    size.ws_col = (unsigned short)(cols > 0 ? cols : 80);
    size.ws_row = (unsigned short)(rows > 0 ? rows : 24);
    ioctl(fd, TIOCSWINSZ, &size);
}

JNIEXPORT void JNICALL
Java_com_mofox_android_runtime_NativePty_nativeClose(JNIEnv *env, jobject thiz, jint fd) {
    (void)env;
    (void)thiz;
    close(fd);
}

JNIEXPORT void JNICALL
Java_com_mofox_android_runtime_NativePty_nativeKill(JNIEnv *env, jobject thiz, jint pid) {
    (void)env;
    (void)thiz;
    kill((pid_t)pid, SIGTERM);
}

JNIEXPORT jint JNICALL
Java_com_mofox_android_runtime_NativePty_nativeWait(JNIEnv *env, jobject thiz, jint pid) {
    (void)env;
    (void)thiz;
    int status = 0;
    if (waitpid((pid_t)pid, &status, 0) < 0) return -errno;
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
    return status;
}