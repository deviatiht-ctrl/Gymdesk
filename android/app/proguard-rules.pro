# ---------------------------------------------------------------------------
# GymDesk — règles R8 pour les builds release.
#
# AGP 9 active le « strict full mode » de R8 par défaut. Il supprime les
# composants ML Kit chargés par réflexion (ComponentRegistrar), ce qui fait
# que BarcodeScanning.getClient() lève un NullPointerException en release :
#   "Attempt to invoke virtual method 'zzh zzg.a(BarcodeScannerOptions)'
#    on a null object reference"
# Côté Flutter, cela remonte comme MobileScannerErrorCode.genericError et la
# caméra ne démarre jamais, même avec la permission accordée.
# ---------------------------------------------------------------------------

# ML Kit (barcode scanning, bundled model) + infrastructure commune
-keep class com.google.mlkit.** { *; }
-keep interface com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode_bundled.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }

# Découverte des composants Firebase/ML Kit par réflexion
-keep class * implements com.google.firebase.components.ComponentRegistrar { *; }
-keep class com.google.firebase.components.** { *; }
-keep class com.google.mlkit.common.internal.MlKitComponentDiscoveryService { *; }
-keep class com.google.mlkit.common.internal.MlKitInitProvider { *; }

# CameraX (utilisé par mobile_scanner)
-keep class androidx.camera.** { *; }

# Plugin mobile_scanner
-keep class dev.steenbakker.mobile_scanner.** { *; }

# Méthodes natives (JNI) du modèle ML Kit embarqué
-keepclasseswithmembernames class * {
    native <methods>;
}

-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.internal.mlkit_vision_barcode_bundled.**
