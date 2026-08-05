package com.mofox.android.runtime

import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadFactory
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/** Dedicated bounded executor for interactive rootfs file requests. */
internal class RuntimeFileExecutor(
    workerCount: Int = 2,
    queueCapacity: Int = 32,
) {
    private val threadNumber = AtomicInteger()
    private val executor = ThreadPoolExecutor(
        workerCount,
        workerCount,
        0L,
        TimeUnit.MILLISECONDS,
        ArrayBlockingQueue(queueCapacity),
        ThreadFactory { runnable ->
            Thread(runnable, "mofox-file-io-${threadNumber.incrementAndGet()}").apply {
                isDaemon = true
            }
        },
        ThreadPoolExecutor.AbortPolicy(),
    )

    fun execute(block: () -> Unit) {
        try {
            executor.execute(block)
        } catch (error: RejectedExecutionException) {
            throw RuntimeFileException(
                code = RuntimeFileErrorCode.BUSY,
                operation = "fileRequest",
                message = "The file service is busy",
                retryable = true,
                cause = error,
            )
        }
    }

    fun shutdown() {
        executor.shutdownNow()
    }
}
