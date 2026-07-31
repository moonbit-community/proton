(function installMoonBitBridge(nativeInvoke, rawConfig, pageInstance) {
  "use strict";

  if (typeof nativeInvoke !== "function") {
    throw new TypeError("Proton bridge requires a native invoke function");
  }

  const rootConfig = typeof rawConfig === "string" ? JSON.parse(rawConfig) : rawConfig;
  if (!rootConfig || typeof rootConfig !== "object") {
    throw new TypeError("Proton bridge config must be an object");
  }
  const sourceOrigin = globalThis.location.protocol === "proton:" &&
      globalThis.location.hostname === "app"
    ? "app"
    : globalThis.location.origin;
  const grant = Array.isArray(rootConfig.grants)
    ? rootConfig.grants.find((candidate) =>
        candidate && candidate.source_origin === sourceOrigin)
    : undefined;
  if (!grant) {
    throw new TypeError("Proton bridge has no grant for this page source");
  }
  const config = { ...rootConfig, ...grant };

  if (typeof pageInstance !== "string" || !pageInstance) {
    throw new TypeError("Proton bridge requires a native page instance");
  }

  const requestTimeoutMs = Number.isInteger(config.request_timeout_ms) &&
      config.request_timeout_ms > 0
    ? config.request_timeout_ms
    : 30000;
  const pending = new Map();
  const listeners = new Map();
  const jsonListeners = new Map();
  let nextRequestId = 1;
  let disposed = false;

  class ProtonBridgeError extends Error {
    constructor(code, message, detail) {
      super(message);
      this.name = "ProtonBridgeError";
      this.code = String(code || "bridge_failed");
      if (detail !== undefined) {
        this.detail = detail;
      }
    }
  }

  function listenersFor(table, name) {
    const key = String(name);
    let entries = table.get(key);
    if (!entries) {
      entries = [];
      table.set(key, entries);
    }
    return entries;
  }

  function emit(name, event) {
    for (const listener of listenersFor(listeners, name).slice()) {
      listener(event);
    }
    return event;
  }

  function emitJson(route, payloadJson) {
    for (const listener of listenersFor(jsonListeners, route).slice()) {
      listener(payloadJson);
    }
  }

  function addListener(table, name, listener, label) {
    if (typeof listener !== "function") {
      throw new TypeError(`${label} expects a listener function`);
    }
    const key = String(name);
    listenersFor(table, key).push(listener);
    return function unsubscribe() {
      const current = listenersFor(table, key);
      table.set(key, current.filter((candidate) => candidate !== listener));
    };
  }

  const events = {
    on(name, listener) {
      return addListener(listeners, name, listener, "MoonBit.events.on");
    },
    onJson(route, listener) {
      return addListener(
        jsonListeners,
        route,
        listener,
        "MoonBit.events.onJson",
      );
    },
    emit(name, event) {
      return emit(String(name), event);
    },
  };

  function bridgeError(error, fallbackCode, fallbackMessage) {
    if (error instanceof ProtonBridgeError) {
      return error;
    }
    const message = error && error.message
      ? String(error.message)
      : String(error || fallbackMessage);
    return new ProtonBridgeError(
      error && error.code ? error.code : fallbackCode,
      message || fallbackMessage,
      error && error.detail,
    );
  }

  function cancelNativeRequest(id) {
    try {
      nativeInvoke("cancel", id, "", "", pageInstance);
    } catch (_) {
      // The renderer context may already be detached.
    }
  }

  function invokeJson(route, requestJson, options) {
    if (disposed) {
      return Promise.reject(new ProtonBridgeError(
        "bridge_disposed",
        "Proton bridge context has been disposed",
      ));
    }
    if (typeof requestJson !== "string") {
      return Promise.reject(new ProtonBridgeError(
        "invalid_request_json",
        "Proton bridge request must be JSON text",
      ));
    }
    return new Promise((resolve, reject) => {
      const id = nextRequestId++;
      if (nextRequestId > 2147483640) {
        nextRequestId = 1;
      }
      const signal = options && options.signal;
      let abortListener;
      const finish = () => {
        if (abortListener && signal) {
          signal.removeEventListener("abort", abortListener);
        }
      };
      const timer = setTimeout(() => {
        const entry = pending.get(id);
        if (!entry) {
          return;
        }
        cancelNativeRequest(id);
        pending.delete(id);
        finish();
        reject(new ProtonBridgeError(
          "request_timeout",
          "Proton bridge request timed out",
        ));
      }, requestTimeoutMs);
      pending.set(id, { resolve, reject, timer, finish });

      if (signal) {
        abortListener = () => {
          const entry = pending.get(id);
          if (!entry) {
            return;
          }
          cancelNativeRequest(id);
          pending.delete(id);
          clearTimeout(timer);
          finish();
          reject(new ProtonBridgeError(
            "request_cancelled",
            "Proton bridge request was cancelled",
          ));
        };
        if (signal.aborted) {
          abortListener();
          return;
        }
        signal.addEventListener("abort", abortListener, { once: true });
      }

      try {
        nativeInvoke(
          "request",
          id,
          String(route),
          requestJson,
          pageInstance,
        );
      } catch (error) {
        clearTimeout(timer);
        pending.delete(id);
        finish();
        reject(bridgeError(
          error,
          "native_invoke_failed",
          "Proton native invocation failed",
        ));
      }
    });
  }

  function invokeOp(name, payload) {
    let payloadJson;
    try {
      payloadJson = JSON.stringify(payload === undefined ? null : payload);
    } catch (error) {
      return Promise.reject(bridgeError(
        error,
        "request_encode_failed",
        "Proton bridge request could not be encoded",
      ));
    }
    return invokeJson(name, payloadJson).then((responseJson) => {
      try {
        return JSON.parse(responseJson);
      } catch (error) {
        throw bridgeError(
          error,
          "response_decode_failed",
          "Proton bridge response was not valid JSON",
        );
      }
    });
  }

  // Application commands are granted as "app:<name>" transport routes. Exposing
  // a proxy per granted command keeps plain-JavaScript pages from assembling
  // that transport name by hand, the same way extension APIs are exposed under
  // their namespace.
  const appPrefix = "app:";
  const app = {
    name: "app",
    invoke(commandName, payload) {
      return invokeOp(`${appPrefix}${String(commandName)}`, payload);
    },
    on(eventName, listener) {
      if (typeof listener !== "function") {
        throw new TypeError("MoonBit.app.on expects a listener function");
      }
      const name = String(eventName);
      return addListener(
        jsonListeners,
        `${appPrefix}${name}`,
        (payloadJson) => listener({ name, payload: JSON.parse(payloadJson) }),
        "MoonBit.app.on",
      );
    },
  };
  const ops = Array.isArray(config.ops) ? config.ops : [];
  for (const op of ops) {
    const route = String(op && op.name || "");
    if (!route.startsWith(appPrefix)) {
      continue;
    }
    const commandName = route.slice(appPrefix.length);
    if (
      !commandName || commandName === "then" ||
      Object.prototype.hasOwnProperty.call(app, commandName)
    ) {
      continue;
    }
    Object.defineProperty(app, commandName, {
      value: function invokeAppCommand(payload) {
        return invokeOp(route, payload);
      },
      writable: true,
      enumerable: true,
      configurable: true,
    });
  }

  const root = {
    core: { invokeJson, invokeOp },
    events,
    app,
  };
  const extensions = Array.isArray(config.extensions) ? config.extensions : [];
  for (const extension of extensions) {
    const namespace = String(extension && extension.namespace || "");
    if (
      !namespace || namespace === "core" || namespace === "events" ||
      namespace === "app"
    ) {
      continue;
    }
    const target = {
      name: namespace,
      invoke(apiName, payload) {
        return invokeOp(`ext:${namespace}/${String(apiName)}`, payload);
      },
      on(eventName, listener) {
        return events.on(`${namespace}.${String(eventName)}`, listener);
      },
    };
    const apis = Array.isArray(extension.apis) ? extension.apis : [];
    for (const rawApiName of apis) {
      const apiName = String(rawApiName || "");
      if (!apiName || apiName === "then") {
        continue;
      }
      target[apiName] = function invokeExtension(payload) {
        return invokeOp(`ext:${namespace}/${apiName}`, payload);
      };
    }
    root[namespace] = target;
  }

  Object.defineProperty(globalThis, "__MoonBit__", {
    value: root,
    configurable: true,
    enumerable: false,
    writable: false,
  });

  return {
    pageInstance,
    dispatchResponse(id, ok, payloadJson, errorMessage) {
      const entry = pending.get(id);
      if (!entry) {
        return false;
      }
      pending.delete(id);
      clearTimeout(entry.timer);
      entry.finish();
      if (ok) {
        entry.resolve(payloadJson);
      } else {
        let error = null;
        try {
          const parsed = JSON.parse(errorMessage || "");
          if (parsed && typeof parsed === "object") {
            error = new ProtonBridgeError(
              parsed.code || "remote_failure",
              parsed.message || "Proton bridge request failed",
              parsed.detail,
            );
          }
        } catch (_) {
          // The native ABI historically returned plain error text.
        }
        entry.reject(error || new ProtonBridgeError(
          "remote_failure",
          errorMessage || "Proton bridge request failed",
        ));
      }
      return true;
    },
    dispatchEvent(eventJson) {
      const event = typeof eventJson === "string" ? JSON.parse(eventJson) : eventJson;
      if (!event || typeof event !== "object") {
        return false;
      }
      if (event.page_instance != null &&
          String(event.page_instance) !== pageInstance) {
        return false;
      }
      if (event.kind === "extension") {
        const extension = String(event.extension || "");
        const name = String(event.name || "");
        if (!extension || !name) {
          return false;
        }
        emit(`${extension}.${name}`, {
          extension,
          name,
          payload: event.payload === undefined ? null : event.payload,
        });
        emitJson(
          `ext:${extension}/${name}`,
          JSON.stringify(event.payload === undefined ? null : event.payload),
        );
        return true;
      }
      const name = String(event.name || "");
      if (!name) {
        return false;
      }
      // Application events are keyed by their route alone. Publishing them to
      // the shared friendly-name table as well would let an application event
      // named "add.finished" reach listeners registered for extension "add"'s
      // "finished" event, which carries a different payload shape.
      emitJson(
        `${appPrefix}${name}`,
        JSON.stringify(event.payload === undefined ? null : event.payload),
      );
      return true;
    },
    dispose(reason) {
      if (disposed) {
        return;
      }
      disposed = true;
      const error = new Error(reason || "Proton bridge context was released");
      for (const [id, entry] of pending.entries()) {
        cancelNativeRequest(id);
        clearTimeout(entry.timer);
        entry.finish();
        entry.reject(new ProtonBridgeError("bridge_disposed", error.message));
      }
      pending.clear();
      listeners.clear();
      jsonListeners.clear();
    },
  };
})
