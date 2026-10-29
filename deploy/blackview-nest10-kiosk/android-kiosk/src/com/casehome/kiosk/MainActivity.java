package com.casehome.kiosk;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Bitmap;
import android.net.Uri;
import android.net.wifi.WifiConfiguration;
import android.net.wifi.WifiManager;
import android.net.http.SslError;
import android.os.Bundle;
import android.util.Log;
import android.view.View;
import android.view.WindowManager;
import android.webkit.SslErrorHandler;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class MainActivity extends Activity {
    private static final String LOG_TAG = "CASEKiosk";
    private static final String DEFAULT_URL = "https://case.local/";
    private static final String PREFS = "case-kiosk";
    private static final String URL_KEY = "url";
    private static final long RETRY_DELAY_MS = 10000;
    private static final Pattern WIFI_VALUE = Pattern.compile(
        "(?m)^\\s*(ssid|psk)=\\\"((?:\\\\.|[^\\\"])*)\\\"\\s*$");
    private WebView webView;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        applyImmersiveMode();
        importWifiConfiguration();

        webView = new WebView(this);
        webView.setBackgroundColor(0xfff4f6f8);
        configureWebView(webView);
        setContentView(webView);
        loadConfiguredUrl(getIntent());
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        loadConfiguredUrl(intent);
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) applyImmersiveMode();
    }

    @Override
    public void onBackPressed() {
        if (webView.canGoBack()) webView.goBack();
    }

    private void configureWebView(WebView view) {
        WebSettings settings = view.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        settings.setMediaPlaybackRequiresUserGesture(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE);
        settings.setLoadWithOverviewMode(true);
        settings.setUseWideViewPort(true);
        settings.setBuiltInZoomControls(false);
        settings.setDisplayZoomControls(false);
        settings.setSupportZoom(false);

        view.setWebChromeClient(new WebChromeClient());
        view.setWebViewClient(new WebViewClient() {
            @Override
            public void onPageStarted(WebView webView, String url, Bitmap favicon) {
                webView.removeCallbacks(retryLoad);
            }

            @Override
            public void onPageFinished(WebView webView, String url) {
                webView.evaluateJavascript(
                    "(function(){return JSON.stringify({innerWidth:window.innerWidth,"
                        + "innerHeight:window.innerHeight,outerWidth:window.outerWidth,"
                        + "devicePixelRatio:window.devicePixelRatio,screenWidth:screen.width,"
                        + "mobileMedia:matchMedia('(max-width: 820px)').matches,"
                        + "tabletMedia:matchMedia('(max-width: 1024px)').matches});})()",
                    value -> Log.i(LOG_TAG, "Viewport " + value));
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView webView,
                                                    WebResourceRequest request) {
                return false;
            }

            @Override
            public void onReceivedSslError(WebView webView, SslErrorHandler handler,
                                           SslError error) {
                String host = Uri.parse(error.getUrl()).getHost();
                if (isTrustedLocalHost(host)) handler.proceed();
                else handler.cancel();
            }

            @Override
            public void onReceivedError(WebView webView, WebResourceRequest request,
                                        WebResourceError error) {
                if (request.isForMainFrame()) {
                    webView.removeCallbacks(retryLoad);
                    webView.postDelayed(retryLoad, RETRY_DELAY_MS);
                }
            }
        });
    }

    private void importWifiConfiguration() {
        File importFile = new File(getFilesDir(), "lanovo_wpa.conf");
        if (!importFile.isFile()) return;

        try {
            String source = readFile(importFile);
            String ssid = null;
            String psk = null;
            Matcher matcher = WIFI_VALUE.matcher(source);
            while (matcher.find()) {
                if ("ssid".equals(matcher.group(1))) ssid = unescape(matcher.group(2));
                if ("psk".equals(matcher.group(1))) psk = unescape(matcher.group(2));
            }
            if (ssid == null || psk == null) {
                Log.e(LOG_TAG, "Wi-Fi import file has no SSID or PSK");
                return;
            }

            WifiConfiguration config = new WifiConfiguration();
            config.SSID = quote(ssid);
            config.preSharedKey = psk.matches("[0-9a-fA-F]{64}") ? psk : quote(psk);
            config.allowedKeyManagement.set(WifiConfiguration.KeyMgmt.WPA_PSK);

            WifiManager wifi = (WifiManager) getApplicationContext()
                .getSystemService(WIFI_SERVICE);
            wifi.setWifiEnabled(true);
            int networkId = wifi.addNetwork(config);
            if (networkId >= 0) {
                wifi.disconnect();
                wifi.enableNetwork(networkId, true);
                wifi.reconnect();
                wifi.saveConfiguration();
                if (!importFile.delete()) {
                    Log.w(LOG_TAG, "Could not remove completed Wi-Fi import file");
                }
            } else {
                Log.e(LOG_TAG, "Android rejected imported Wi-Fi network");
            }
        } catch (IOException error) {
            Log.e(LOG_TAG, "Could not import Wi-Fi configuration", error);
        }
    }

    private static String readFile(File file) throws IOException {
        StringBuilder out = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(new FileReader(file))) {
            String line;
            while ((line = reader.readLine()) != null) out.append(line).append('\n');
        }
        return out.toString();
    }

    private static String unescape(String value) {
        return value.replace("\\\\\"", "\"").replace("\\\\\\\\", "\\\\");
    }

    private static String quote(String value) {
        return "\"" + value.replace("\\\\", "\\\\\\\\").replace("\"", "\\\\\"") + "\"";
    }

    private final Runnable retryLoad = new Runnable() {
        @Override
        public void run() {
            webView.reload();
        }
    };

    private void loadConfiguredUrl(Intent intent) {
        String requested = intent.getStringExtra(URL_KEY);
        if (requested != null && isAllowedUrl(requested)) {
            getSharedPreferences(PREFS, MODE_PRIVATE).edit().putString(URL_KEY, requested).apply();
        }
        String url = getSharedPreferences(PREFS, MODE_PRIVATE)
            .getString(URL_KEY, DEFAULT_URL);
        webView.loadUrl(url);
    }

    private static boolean isAllowedUrl(String value) {
        Uri uri = Uri.parse(value);
        String scheme = uri.getScheme();
        return uri.getHost() != null
            && ("https".equalsIgnoreCase(scheme) || "http".equalsIgnoreCase(scheme));
    }

    private static boolean isTrustedLocalHost(String host) {
        if (host == null) return false;
        return host.equalsIgnoreCase("case.local")
            || host.endsWith(".local")
            || host.matches("^(10\\.|192\\.168\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.).*");
    }

    private void applyImmersiveMode() {
        getWindow().getDecorView().setSystemUiVisibility(
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                | View.SYSTEM_UI_FLAG_FULLSCREEN
                | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                | View.SYSTEM_UI_FLAG_LAYOUT_STABLE);
    }
}
