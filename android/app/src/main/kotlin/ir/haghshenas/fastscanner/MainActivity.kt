package ir.haghshenas.fastscanner

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "fastscanner/intent"

        const val ACTION_SCAN =
            "ir.haghshenas.fastscanner.action.SCAN"

        const val EXTRA_RECORD_ID =
            "record_id"

        const val EXTRA_RETURN_PACKAGE =
            "return_package"

        const val EXTRA_RETURN_ACTION =
            "return_action"
    }

    private var currentIntent: Intent? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        currentIntent = intent
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)

        setIntent(intent)
        currentIntent = intent
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->

            when (call.method) {

                "getScanRequest" -> {

                    val intent = currentIntent ?: intent

                    val recordId =
                        intent.getStringExtra(EXTRA_RECORD_ID)

                    val returnPackage =
                        intent.getStringExtra(EXTRA_RETURN_PACKAGE)

                    val returnAction =
                        intent.getStringExtra(EXTRA_RETURN_ACTION)

                    result.success(
                        mapOf(
                            "record_id" to recordId,
                            "return_package" to returnPackage,
                            "return_action" to returnAction,
                            "is_external_scan" to (
                                recordId != null &&
                                returnPackage != null
                            )
                        )
                    )
                }

                "completeScan" -> {

                    val outputPath =
                        call.argument<String>("output_path")

                    val mimeType =
                        call.argument<String>("mime_type")
                            ?: "application/pdf"

                    val recordId =
                        call.argument<String>("record_id")

                    if (outputPath.isNullOrEmpty()) {
                        result.error(
                            "INVALID_PATH",
                            "output_path is empty",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    val intent = currentIntent ?: intent

                    val returnPackage =
                        intent.getStringExtra(EXTRA_RETURN_PACKAGE)

                    val returnAction =
                        intent.getStringExtra(EXTRA_RETURN_ACTION)

                    if (
                        returnPackage.isNullOrEmpty() ||
                        returnAction.isNullOrEmpty()
                    ) {
                        result.success(
                            mapOf(
                                "returned" to false,
                                "reason" to "normal_mode"
                            )
                        )
                        return@setMethodCallHandler
                    }

                    val returnIntent = Intent(returnAction).apply {

                        setPackage(returnPackage)

                        putExtra(
                            "record_id",
                            recordId
                        )

                        putExtra(
                            "file_path",
                            outputPath
                        )

                        putExtra(
                            "mime_type",
                            mimeType
                        )

                        putExtra(
                            "success",
                            true
                        )

                        addFlags(
                            Intent.FLAG_INCLUDE_STOPPED_PACKAGES
                        )
                    }

                    sendBroadcast(returnIntent)

                    result.success(
                        mapOf(
                            "returned" to true
                        )
                    )

                    finish()
                }

                "cancelScan" -> {

                    val intent = currentIntent ?: intent

                    val returnPackage =
                        intent.getStringExtra(EXTRA_RETURN_PACKAGE)

                    val returnAction =
                        intent.getStringExtra(EXTRA_RETURN_ACTION)

                    if (
                        !returnPackage.isNullOrEmpty() &&
                        !returnAction.isNullOrEmpty()
                    ) {

                        val returnIntent =
                            Intent(returnAction).apply {

                                setPackage(returnPackage)

                                putExtra(
                                    "success",
                                    false
                                )

                                putExtra(
                                    "cancelled",
                                    true
                                )

                                addFlags(
                                    Intent.FLAG_INCLUDE_STOPPED_PACKAGES
                                )
                            }

                        sendBroadcast(returnIntent)
                    }

                    result.success(true)

                    finish()
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}