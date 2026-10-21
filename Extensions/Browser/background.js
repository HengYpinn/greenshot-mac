/*
 * Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
 * Copyright (C) 2026 Greenshot for Mac (Community) contributors
 * Based on Greenshot src/Greenshot.BrowserExtension/background.js,
 * Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Mac changes: the native host is io.github.greenshot_mac.host (greenshot-native-host in the app); IMPORT_CAPTURE and
 * TAB_CHANGED also send "browser" (upstream sends it only in HANDSHAKE), and IMPORT_CAPTURE the tab's width in CSS pixels
 * ("tab_width", so Greenshot knows the Retina scale). Turning the tab tracking off sends TAB_CHANGED with
 * "tracking": false, so Greenshot forgets the tab, and IMPORT_CAPTURE says "tracking" too (with it off, the captured
 * page doesn't become Greenshot's tab); Greenshot's event "report_tab" asks for the active tab again. A HANDSHAKE
 * that Greenshot refuses (the extension switched off in its settings) counts as offline, with Greenshot's reason, and
 * is tried again with the back-off; tab changes start no connection. The popup's status waits a moment for a
 * handshake under way. "Sent to Greenshot!" only when Greenshot answers IMPORT_CAPTURE with "ok" (upstream shows it
 * once the message is posted, also when Greenshot refused the capture).
 * manifest.json asks for no host permissions (upstream: <all_urls>): "activeTab" lets captureVisibleTab take the tab the
 * user clicked the button in (Firefox 126 and later), "tabs" gives the tab's address and title for the tab tracking.
 */

/**
 * Greenshot Companion Extension - Background Service Worker
 * Manages Native Messaging lifecycle with greenshot-native-host (in the Greenshot for Mac app),
 * handshake/configuration sync, retries, capture ingestion, and QA tab URL tracking.
 */

const NATIVE_HOST_NAME = "io.github.greenshot_mac.host";
const RETRY_BASE_DELAY_MS = 5000;
const RETRY_MAX_DELAY_MS = 60000;
// Mac: how long the popup's status waits for a handshake under way, and a capture for Greenshot's answer
const STATUS_WAIT_MS = 1500;
const CAPTURE_ANSWER_TIMEOUT_MS = 15000;

let nativePort = null;
let isConnected = false;
let retryCount = 0;
let retryTimerId = null;
// Mac: the handshake under way ({ promise, settle }), why Greenshot refused the last one, and the captures waiting for
// Greenshot's answer, oldest first (Greenshot answers a connection's requests in order)
let handshake = null;
let lastError = "";
let pendingCaptures = [];

let extensionConfig = {
  track_tab_urls: true,
  capture_format: "png"
};

// Initialize configuration from storage (Mac: a promise, so that nothing reports a tab before the user's choice to
// turn tab tracking off is known)
const configLoaded = new Promise((resolve) => {
  chrome.storage.local.get(["extensionConfig"], (res) => {
    if (res && res.extensionConfig) {
      extensionConfig = { ...extensionConfig, ...res.extensionConfig };
    }
    resolve();
  });
});

function getBrowserName() {
  if (navigator.userAgent.includes("Edg/")) return "edge";
  if (navigator.userAgent.includes("Firefox/")) return "firefox";
  return "chrome";
}

function updateBadge() {
  if (isConnected) {
    chrome.action.setBadgeText({ text: "ON" });
    chrome.action.setBadgeBackgroundColor({ color: "#2E7D32" }); // Green
  } else {
    chrome.action.setBadgeText({ text: "" });
  }
}

/**
 * Mac: a handshake under way is settled by Greenshot's first answer or by its port closing. The popup's status waits for
 * it: the service worker may just have woken and started it.
 */
function startHandshake() {
  let settle;
  const promise = new Promise((resolve) => {
    settle = resolve;
  });
  handshake = { promise, settle };
}

function settleHandshake() {
  if (handshake) {
    const { settle } = handshake;
    handshake = null;
    settle();
  }
}

function waitForHandshake(timeoutMs) {
  if (!handshake) {
    return Promise.resolve();
  }
  return Promise.race([handshake.promise, new Promise((resolve) => setTimeout(resolve, timeoutMs))]);
}

/**
 * Mac: Greenshot's reason as the popup shows it, without the log's tag.
 */
function readableReason(text, fallback) {
  const reason = typeof text === "string" ? text.replace(/^\[SECURITY\]\s*/, "").trim() : "";
  return reason || fallback;
}

/**
 * Mac: Greenshot's answer to the capture just sent ({ status, stderr }), or an error when none comes in time or the port
 * closes. A capture that timed out keeps its place, so that its late answer isn't taken for the next capture's.
 */
function captureAnswer() {
  const entry = { settled: false, resolve: null, timerId: null };
  const promise = new Promise((resolve) => {
    entry.resolve = resolve;
  });
  entry.timerId = setTimeout(() => {
    finishCapture(entry, { status: "error", stderr: "Greenshot didn't answer." });
  }, CAPTURE_ANSWER_TIMEOUT_MS);
  pendingCaptures.push(entry);
  return promise;
}

function finishCapture(entry, answer) {
  if (entry.settled) {
    return;
  }
  entry.settled = true;
  clearTimeout(entry.timerId);
  entry.resolve(answer);
}

function failPendingCaptures() {
  const entries = pendingCaptures;
  pendingCaptures = [];
  entries.forEach((entry) => finishCapture(entry, { status: "error", stderr: "Greenshot closed the connection." }));
}

/**
 * Drops the port (Mac: and with it the handshake under way and the captures waiting for an answer).
 */
function closePort() {
  const port = nativePort;
  nativePort = null;
  isConnected = false;
  if (port) {
    try {
      port.disconnect();
    } catch (e) {
      // Ignore disconnect errors on old port
    }
  }
  settleHandshake();
  failPendingCaptures();
}

/**
 * Connects to the native messaging host (greenshot-native-host).
 */
function connectNativeHost() {
  if (retryTimerId) {
    clearTimeout(retryTimerId);
    retryTimerId = null;
  }

  closePort();

  try {
    const port = chrome.runtime.connectNative(NATIVE_HOST_NAME);
    nativePort = port;

    // Mac: what a replaced port still says (or its end) is ignored
    port.onMessage.addListener((msg) => {
      if (port === nativePort) {
        onNativeMessage(msg);
      }
    });
    port.onDisconnect.addListener(() => onNativeDisconnect(port));

    // Send initial handshake request
    startHandshake();
    sendNativeMessage({
      source: "native_messaging",
      command: "HANDSHAKE",
      extension_version: chrome.runtime.getManifest().version,
      browser: getBrowserName()
    });
  } catch (err) {
    console.warn("Failed to connect to native messaging host:", err);
    settleHandshake();
    updateBadge();
    scheduleReconnect();
  }
}

function onNativeMessage(msg) {
  if (!msg) return;

  // Acknowledgement of an imported capture: "ok" (with width/height) or "error" with the reason in stderr
  if (msg.reply_to === "IMPORT_CAPTURE") {
    if (msg.status !== "ok") {
      console.warn("Greenshot rejected the capture:", msg.stderr);
    }
    const entry = pendingCaptures.shift();
    if (entry) {
      finishCapture(entry, msg);
    }
    return;
  }

  // Mac: Greenshot asks for the active tab again (the extension was switched back on in its settings, which forgot
  // the tab while this browser stayed connected)
  if (msg.event === "report_tab") {
    reportActiveTab();
    return;
  }

  if (msg.status === "unavailable" || msg.greenshot_running === false) {
    // Greenshot is offline
    isConnected = false;
    lastError = "";
    settleHandshake();
    updateBadge();
    scheduleReconnect();
    return;
  }

  if (msg.status === "ready" && msg.greenshot_running === true) {
    // Successful handshake
    isConnected = true;
    retryCount = 0;
    lastError = "";
    settleHandshake();
    updateBadge();

    if (msg.config) {
      // Mac: after the stored options were read, or saving would overwrite them with the defaults
      configLoaded.then(() => {
        extensionConfig = { ...extensionConfig, ...msg.config };
        chrome.storage.local.set({ extensionConfig });
      });
    }

    // Mac: Greenshot may have restarted and knows no tab; the same tab is reported again
    reportActiveTab();
    return;
  }

  // Mac: any other answer to the handshake is a refusal (the extension is switched off in Greenshot's settings, or
  // isn't allowed): offline with Greenshot's reason, and tried again later, as the setting may change
  if (handshake) {
    lastError = readableReason(msg.stderr, "Greenshot refused the connection.");
    closePort();
    updateBadge();
    scheduleReconnect();
  }
}

function onNativeDisconnect(port) {
  const lastErr = chrome.runtime.lastError;
  if (port !== nativePort) {
    // A port that was replaced (Mac: its end must not drop the new one)
    return;
  }

  isConnected = false;
  nativePort = null;
  settleHandshake();
  failPendingCaptures();
  updateBadge();

  if (lastErr) {
    console.info("Native messaging port disconnected:", lastErr.message);
  }

  scheduleReconnect();
}

function scheduleReconnect() {
  if (retryTimerId) return;

  // Bounded exponential backoff: 5s, 7.5s, 11s, ..., up to 60s
  const delay = Math.min(
    RETRY_MAX_DELAY_MS,
    Math.round(RETRY_BASE_DELAY_MS * Math.pow(1.5, retryCount++))
  );

  retryTimerId = setTimeout(() => {
    retryTimerId = null;
    connectNativeHost();
  }, delay);
}

/**
 * Sends a message to Greenshot; Mac: false when it couldn't be sent. Without a port the next try keeps to the back-off
 * (upstream connects at once, so while Greenshot is offline or refuses the extension every tab change started a new
 * native host).
 */
function sendNativeMessage(payload) {
  if (!nativePort) {
    scheduleReconnect();
    return false;
  }

  try {
    nativePort.postMessage(payload);
    return true;
  } catch (err) {
    console.warn("Failed to send message over native port:", err);
    closePort();
    updateBadge();
    scheduleReconnect();
    return false;
  }
}

/**
 * Captures the current visible tab and imports it into Greenshot.
 */
async function captureCurrentTab() {
  await configLoaded;
  const [activeTab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!activeTab || !activeTab.id) {
    throw new Error("No active tab found.");
  }

  // Mac: a handshake under way is waited for (the worker may just have woken)
  await waitForHandshake(STATUS_WAIT_MS);

  // Ensure native messaging is connected
  if (!isConnected || !nativePort) {
    connectNativeHost();
    throw new Error(lastError || "Greenshot is offline. Please start Greenshot.");
  }

  // Capture visible area
  const dataUrl = await chrome.tabs.captureVisibleTab(activeTab.windowId, {
    format: extensionConfig.capture_format === "jpeg" ? "jpeg" : "png"
  });

  const commaIdx = dataUrl.indexOf(",");
  const base64Payload = commaIdx >= 0 ? dataUrl.slice(commaIdx + 1) : dataUrl;

  const payload = {
    source: "native_messaging",
    command: "IMPORT_CAPTURE",
    browser: getBrowserName(),
    // Mac: with tab tracking off, Greenshot doesn't keep this page as the tab
    tracking: extensionConfig.track_tab_urls !== false,
    metadata: {
      title: activeTab.title || "Untitled Tab",
      url: activeTab.url || "",
      timestamp: Math.floor(Date.now() / 1000),
      tab_width: activeTab.width || 0
    },
    data: {
      mime_type: extensionConfig.capture_format === "jpeg" ? "image/jpeg" : "image/png",
      encoding: "base64",
      payload: base64Payload
    }
  };

  // Mac: sent only when Greenshot says it took it (it refuses it e.g. when the extension is switched off in its
  // settings, or a picture it can't read)
  if (!sendNativeMessage(payload)) {
    throw new Error("Greenshot is offline. Please start Greenshot.");
  }
  const answer = await captureAnswer();
  if (answer.status !== "ok") {
    throw new Error(readableReason(answer.stderr, "Greenshot refused the capture."));
  }
  return { success: true, title: activeTab.title };
}

/**
 * QA Tab URL Tracking
 * Reports active tab URL / title changes to Greenshot to assist QA file routing.
 */
let lastReportedUrl = "";
let lastReportedTitle = "";

function reportTabChange(url, title) {
  // Mac: only to a Greenshot that accepted the extension; the handshake reports the active tab (reportActiveTab)
  if (!extensionConfig.track_tab_urls || !url || !isConnected) {
    return;
  }

  // Ignore browser internal schemes
  if (url.startsWith("chrome://") || url.startsWith("edge://") || url.startsWith("about:") || url.startsWith("chrome-extension://") || url.startsWith("moz-extension://")) {
    return;
  }

  title = title || "";

  if (url === lastReportedUrl && title === lastReportedTitle) {
    return;
  }

  lastReportedUrl = url;
  lastReportedTitle = title;

  sendNativeMessage({
    source: "native_messaging",
    command: "TAB_CHANGED",
    browser: getBrowserName(),
    url: url,
    title: title
  });
}

/**
 * Mac: reports the active tab also when it didn't change: after a (re)connect, Greenshot may have restarted and knows
 * no tab, and after tab tracking was turned on.
 */
async function reportActiveTab() {
  await configLoaded;
  lastReportedUrl = "";
  lastReportedTitle = "";
  if (!isConnected || !extensionConfig.track_tab_urls) {
    return;
  }
  try {
    const [tab] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
    if (tab && tab.url) {
      reportTabChange(tab.url, tab.title);
    }
  } catch (e) {
    // No browser window
  }
}

/**
 * Mac: tab tracking was turned off, so Greenshot forgets the tab this browser reported (it would keep naming captures
 * after a page the user no longer shares).
 */
function forgetTab() {
  lastReportedUrl = "";
  lastReportedTitle = "";
  if (!isConnected) {
    return;
  }
  sendNativeMessage({
    source: "native_messaging",
    command: "TAB_CHANGED",
    browser: getBrowserName(),
    url: "",
    title: "",
    tracking: false
  });
}

chrome.tabs.onUpdated.addListener(async (tabId, changeInfo, tab) => {
  if (!tab.active) {
    return;
  }
  await configLoaded;

  // 1. Navigation started: URL changed.
  // During initial navigation / loading, tab.title may still be the previous document's title.
  // Send the new URL immediately with an empty title to clear stale context in Greenshot.
  if (changeInfo.url) {
    reportTabChange(changeInfo.url, "");
  }

  // 2. Title resolved or changed dynamically (e.g. SPAs, client-side routing, document.title set)
  if (changeInfo.title) {
    reportTabChange(tab.url, changeInfo.title);
  }

  // 3. Page load completed: ensure final URL and title are recorded
  if (changeInfo.status === "complete" && tab.url) {
    reportTabChange(tab.url, tab.title);
  }
});

chrome.tabs.onActivated.addListener(async (activeInfo) => {
  try {
    await configLoaded;
    const tab = await chrome.tabs.get(activeInfo.tabId);
    if (tab && tab.url) {
      reportTabChange(tab.url, tab.title);
    }
  } catch (e) {
    // Tab might have closed
  }
});

// Handle messages from Popup or Options UI
chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request.action === "GET_STATUS") {
    // Mac: Greenshot may have started since the last try, or the worker just woke and is connecting: the answer waits
    // a moment for the handshake, so the popup doesn't show Greenshot offline while it gets ready
    if (!isConnected && !handshake) {
      connectNativeHost();
    }
    Promise.all([configLoaded, waitForHandshake(STATUS_WAIT_MS)]).then(() => {
      sendResponse({
        isConnected,
        config: extensionConfig,
        error: isConnected ? "" : lastError
      });
    });
    return true;
  }

  if (request.action === "CAPTURE_VISIBLE") {
    captureCurrentTab()
      .then((res) => sendResponse(res))
      .catch((err) => sendResponse({ success: false, error: err.message }));
    return true;
  }

  if (request.action === "RECONNECT") {
    retryCount = 0;
    connectNativeHost();
    sendResponse({ status: "connecting" });
    return true;
  }

  if (request.action === "UPDATE_CONFIG") {
    const wasTracking = extensionConfig.track_tab_urls;
    extensionConfig = { ...extensionConfig, ...request.config };
    chrome.storage.local.set({ extensionConfig });
    if (wasTracking && !extensionConfig.track_tab_urls) {
      forgetTab();
    } else if (!wasTracking && extensionConfig.track_tab_urls) {
      reportActiveTab();
    }
    sendResponse({ success: true, config: extensionConfig });
    return true;
  }
});

// Connect on worker startup
connectNativeHost();
