package com.shinezeogame.sdrop

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.concurrent.thread

/**
 * Fonctions propres à Android, appelées depuis `lib/data/system_bridge.dart` :
 * nom du téléphone, réception des annonces en multidiffusion, et contenu reçu du menu
 * « Partager » des autres applications.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    // Partage qui a ouvert l'application : il est copié en arrière-plan, et remis à
    // l'interface quand elle le demande (tout de suite s'il est prêt, sinon dès qu'il l'est).
    private var initialShareReady = true
    private var initialShare: Map<String, Any?>? = null
    private var waitingForInitialShare: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) {
            // Nouveau lancement : les copies des partages précédents ne servent plus.
            File(cacheDir, SHARE_FOLDER).deleteRecursively()
            handleShare(intent, initial = true)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val created = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sdrop/systeme")
        channel = created
        created.setMethodCallHandler { call, result ->
            when (call.method) {
                "nomAppareil" -> result.success(deviceName())
                "verrouMultidiffusion" -> {
                    setMulticastLock(call.arguments as? Boolean ?: false)
                    result.success(null)
                }
                "dossierDeSecours" -> result.success(getExternalFilesDir(null)?.let { File(it, "sDrop").path })
                "partageInitial" -> {
                    if (initialShareReady) {
                        result.success(initialShare)
                        initialShare = null
                    } else {
                        waitingForInitialShare = result
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleShare(intent, initial = false)
    }

    override fun onDestroy() {
        setMulticastLock(false)
        super.onDestroy()
    }

    /** Nom donné au téléphone par son propriétaire, à défaut son modèle. */
    private fun deviceName(): String {
        val chosen = try {
            Settings.Global.getString(contentResolver, "device_name")
        } catch (e: Exception) {
            null
        }
        return if (chosen.isNullOrBlank()) Build.MODEL else chosen
    }

    private fun setMulticastLock(enabled: Boolean) {
        try {
            if (enabled) {
                if (multicastLock == null) {
                    val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                    multicastLock = wifi.createMulticastLock("sdrop").apply {
                        setReferenceCounted(false)
                        acquire()
                    }
                }
            } else {
                multicastLock?.release()
                multicastLock = null
            }
        } catch (e: Exception) {
            // Sans verrou, la diffusion classique reste disponible.
        }
    }

    /** Traite un « Partager → sDrop » : fichiers copiés dans le dossier temporaire, ou texte. */
    private fun handleShare(intent: Intent?, initial: Boolean) {
        val action = intent?.action
        if (intent == null || (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE)) return
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)
        val uris = sharedUris(intent, action)
        if (initial) initialShareReady = false
        // La copie peut être longue (vidéos) : elle se fait hors du fil de l'interface.
        thread {
            val files = uris.mapNotNull { copyToCache(it) }
            val share = mapOf<String, Any?>("fichiers" to files, "texte" to if (files.isEmpty()) text else null)
            runOnUiThread {
                if (!initial) {
                    channel?.invokeMethod("partage", share)
                } else {
                    initialShareReady = true
                    val waiting = waitingForInitialShare
                    if (waiting != null) {
                        waitingForInitialShare = null
                        waiting.success(share)
                    } else {
                        initialShare = share
                    }
                }
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun sharedUris(intent: Intent, action: String): List<Uri> {
        return try {
            if (action == Intent.ACTION_SEND) {
                val uri = if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM)
                }
                listOfNotNull(uri)
            } else {
                val uris = if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
                }
                uris?.filterNotNull() ?: emptyList()
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    /** Copie un contenu partagé dans le dossier temporaire ; renvoie son chemin. */
    private fun copyToCache(uri: Uri): String? {
        return try {
            val folder = File(cacheDir, "$SHARE_FOLDER/${System.nanoTime()}")
            folder.mkdirs()
            // Le nom vient d'une autre application : on n'en garde que le dernier élément.
            val name = File(displayName(uri) ?: "fichier").name.ifBlank { "fichier" }
            val target = File(folder, name)
            contentResolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            } ?: return null
            target.path
        } catch (e: Exception) {
            null
        }
    }

    private fun displayName(uri: Uri): String? {
        if (uri.scheme == "file") return uri.lastPathSegment
        return try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        } catch (e: Exception) {
            null
        } ?: uri.lastPathSegment
    }

    companion object {
        private const val SHARE_FOLDER = "partage"
    }
}
