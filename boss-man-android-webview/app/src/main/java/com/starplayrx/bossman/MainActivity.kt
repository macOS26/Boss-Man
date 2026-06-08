package com.starplayrx.bossman

import android.app.Activity
import android.os.Bundle
import android.view.View
import android.webkit.*
import androidx.webkit.WebViewAssetLoader

class MainActivity : Activity() {

    private lateinit var wv: WebView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        immersive()
        wv = WebView(this)
        setContentView(wv)
        wv.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            mediaPlaybackRequiresUserGesture = false
            allowFileAccess = true
        }
        val loader = WebViewAssetLoader.Builder()
            .setDomain("appassets.androidplatform.net")
            .addPathHandler("/play/", WebViewAssetLoader.AssetsPathHandler(this))
            .build()
        wv.webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(
                view: WebView,
                request: WebResourceRequest
            ): WebResourceResponse? = loader.shouldInterceptRequest(request.url)
            override fun onPageFinished(view: WebView, url: String) {
                view.evaluateJavascript(CHROMELESS_JS, null)
            }
        }
        wv.webChromeClient = object : WebChromeClient() {
            override fun onShowCustomView(view: View, callback: CustomViewCallback) {
                setContentView(view)
                immersive()
            }
            override fun onHideCustomView() {
                setContentView(wv)
                immersive()
            }
        }
        wv.loadUrl("https://appassets.androidplatform.net/play/server.html")
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) immersive()
    }

    @Suppress("DEPRECATION")
    private fun immersive() {
        window.decorView.systemUiVisibility = (
            View.SYSTEM_UI_FLAG_FULLSCREEN or
            View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
        )
    }
}

private const val CHROMELESS_JS = """(function(){
    var css="html,body{margin:0!important;padding:0!important;height:100%!important;overflow:hidden!important;background:#000!important;gap:0!important}" +
        "#game{width:100vw!important;height:100vh!important;max-width:none!important;max-height:none!important;border-radius:0!important;aspect-ratio:auto!important}" +
        "#footer{display:none!important}";
    var s=document.createElement('style');
    s.textContent=css;
    (document.head||document.documentElement).appendChild(s);
})();"""
