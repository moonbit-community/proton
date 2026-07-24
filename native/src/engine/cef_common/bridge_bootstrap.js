(function installMoonBitBridge(nativeInvoke, rawConfig, pageInstance) {
  "use strict";

  if (typeof nativeInvoke !== "function") {
    throw new TypeError("Proton bridge requires a native invoke function");
  }

  const config = typeof rawConfig === "string" ? JSON.parse(rawConfig) : rawConfig;
  if (!config || typeof config !== "object") {
    throw new TypeError("Proton bridge config must be an object");
  }

  if (typeof pageInstance !== "string" || !pageInstance) {
    throw new TypeError("Proton bridge requires a native page instance");
  }

  const requestTimeoutMs = Number.isInteger(config.request_timeout_ms) &&
      config.request_timeout_ms > 0
    ? config.request_timeout_ms
    : 30000;
  const pending = new Map();
  const listeners = new Map();
  let nextRequestId = 1;
  let disposed = false;

  function listenersFor(name) {
    const key = String(name);
    let entries = listeners.get(key);
    if (!entries) {
      entries = [];
      listeners.set(key, entries);
    }
    return entries;
  }

  function emit(name, event) {
    for (const listener of listenersFor(name).slice()) {
      listener(event);
    }
    return event;
  }

  const events = {
    on(name, listener) {
      if (typeof listener !== "function") {
        throw new TypeError("MoonBit.events.on expects a listener function");
      }
      const key = String(name);
      listenersFor(key).push(listener);
      return function unsubscribe() {
        const current = listenersFor(key);
        listeners.set(key, current.filter((candidate) => candidate !== listener));
      };
    },
    emit(name, event) {
      return emit(String(name), event);
    },
  };

  function invokeOp(name, payload) {
    if (disposed) {
      return Promise.reject(new Error("Proton bridge context has been disposed"));
    }
    return new Promise((resolve, reject) => {
      const id = nextRequestId++;
      if (nextRequestId > 2147483640) {
        nextRequestId = 1;
      }
      const timer = setTimeout(() => {
        if (!pending.delete(id)) {
          return;
        }
        reject(new Error("bridge request timed out"));
      }, requestTimeoutMs);
      pending.set(id, { resolve, reject, timer });

      let payloadJson;
      try {
        payloadJson = JSON.stringify(payload === undefined ? null : payload);
      } catch (error) {
        clearTimeout(timer);
        pending.delete(id);
        reject(error);
        return;
      }

      try {
        nativeInvoke(id, String(name), payloadJson, pageInstance);
      } catch (error) {
        clearTimeout(timer);
        pending.delete(id);
        reject(error);
      }
    });
  }

  const root = {
    core: { invokeOp },
    events,
  };
  const extensions = Array.isArray(config.extensions) ? config.extensions : [];
  for (const extension of extensions) {
    const namespace = String(extension && extension.namespace || "");
    if (!namespace || namespace === "core" || namespace === "events") {
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
      if (ok) {
        try {
          entry.resolve(JSON.parse(payloadJson));
        } catch (error) {
          entry.reject(error);
        }
      } else {
        entry.reject(new Error(errorMessage || "bridge request failed"));
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
        return true;
      }
      const name = String(event.name || "");
      if (!name) {
        return false;
      }
      emit(name, {
        name,
        payload: event.payload === undefined ? null : event.payload,
      });
      return true;
    },
    dispose(reason) {
      if (disposed) {
        return;
      }
      disposed = true;
      const error = new Error(reason || "Proton bridge context was released");
      for (const entry of pending.values()) {
        clearTimeout(entry.timer);
        entry.reject(error);
      }
      pending.clear();
      listeners.clear();
    },
  };
})
