# jniLibs：proot / busybox / sudo / bash

Android 把 `app/android/app/src/main/jniLibs/<abi>/*.so` 解压到 `applicationInfo.nativeLibraryDir`（典型路径
`/data/app/~~xxx==/com.mofox.android-yyy==/lib/<abi>/`），该目录由系统打 `exec` 标且不受 SELinux W^X
对 `app_data_file` 域的限制 —— 这是**唯一**能在不依赖 Termux 包名的前提下让 proot 在 Android 14/15
（targetSdk 35）下跑起来的合法路径。

## 文件清单（所有 6 个都必须以 `lib*.so` 命名才会被 PackageInstaller 解压保留）

| 文件 | 来源 | 作用 |
|------|------|------|
| `libash.so` | busybox 软链接 | proot 内 sh / bash 入口 |
| `libbash.so` | bash 静态构建 | 主交互 shell |
| `libbusybox.so` | busybox-android 静态构建 | tar / mkdir / chmod 等基础工具 |
| `libproot.so` | termux/proot 静态构建 | 用户态 chroot |
| `libsudo.so` | proot-distro/sudo 静态构建 | 进 rootfs 后的 sudo |
| `libloader.so` | proot 内置 loader.elf | proot 启动用的 ELF loader (`PROOT_LOADER`) |
| `liblibtalloc.so.2.so` | talloc 共享库 | proot 运行时依赖（`LD_LIBRARY_PATH=$nativeLibraryDir`） |

## 来源

直接复用 [AstrBot-Android-App](../../../../../AstrBot-Android-App/) 的产物，或从 termux/proot-distro 上游手动构建。

`tools/build.py --fetch-jnilibs <abi>` 会从 MoFox-Studio releases 拉对应的 zip 并解到这里。

> 不入仓。每次 release 由 CI 重新拉取。

## 目录布局（运行时）

```
src/main/jniLibs/
├── arm64-v8a/
│   ├── libash.so
│   ├── libbash.so
│   ├── libbusybox.so
│   ├── libproot.so
│   ├── libsudo.so
│   ├── libloader.so
│   └── liblibtalloc.so.2.so
├── armeabi-v7a/   # 同上
└── x86_64/        # 同上
```

## 关键 build.gradle.kts 配置

```kotlin
sourceSets {
    getByName("main") {
        jniLibs.srcDirs("src/main/jniLibs")
    }
}

packaging {
    jniLibs {
        useLegacyPackaging = true       // 关键：配合 AndroidManifest 的 extractNativeLibs="true"
        keepDebugSymbols += listOf(
            "**/libbash.so",
            "**/libbusybox.so",
            "**/libproot.so",
            "**/libsudo.so",
            "**/libloader.so",
            "**/liblibtalloc.so.2.so",
        )
    }
}
```

`AndroidManifest.xml`：

```xml
<application
    android:extractNativeLibs="true"
    ... />
```
