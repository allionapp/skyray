# Keep the gomobile-generated bindings (reflection + JNI-registered natives).
-keep class go.** { *; }
-keep class raycore.** { *; }
-keep class libXray.** { *; }
-dontwarn go.**
-dontwarn raycore.**
-dontwarn libXray.**
