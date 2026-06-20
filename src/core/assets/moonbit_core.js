(function() {
  const moonbitName = __MOONBIT_NAME_JS__;
  const bindingName = __BINDING_NAME_JS__;
  const existing = window[moonbitName];
  const root = existing && typeof existing === 'object' ? existing : Object.create(null);
  const state = root['@@state'] && typeof root['@@state'] === 'object' ? root['@@state'] : (root['@@state'] = Object.create(null));
  const opNames = state.opNames && typeof state.opNames === 'object' ? state.opNames : (state.opNames = Object.create(null));
  const exactListeners = state.exactListeners && typeof state.exactListeners === 'object' ? state.exactListeners : (state.exactListeners = Object.create(null));
  function getBinding() {
    const binding = window[bindingName];
    return typeof binding === 'function' ? binding : null;
  }
  function waitForBinding(deadline) {
    const binding = getBinding();
    if (binding) {
      return Promise.resolve(binding);
    }
    if (Date.now() >= deadline) {
      return Promise.reject(new Error('MoonBit op runtime is not available'));
    }
    return new Promise(function(resolve) {
      window.setTimeout(resolve, 10);
    }).then(function() {
      return waitForBinding(deadline);
    });
  }
  function startBindingPoll() {
    const pollName = bindingName + '_poll';
    const poll = window[pollName];
    if (typeof poll !== 'function') {
      return;
    }
    const tick = function() {
      poll()
        .then(function(hasPending) {
          if (hasPending) {
            window.setTimeout(tick, 10);
          }
        })
        .catch(function() {});
    };
    window.setTimeout(tick, 0);
  }
  function invokeWithBinding(binding, name, payload) {
    const result = binding({ name: name, payload: payload === undefined ? null : payload });
    startBindingPoll();
    return result;
  }
  const core = root.core && typeof root.core === 'object' ? root.core : (root.core = Object.create(null));
  core.registerOp = function(name) {
    opNames[name] = true;
    return true;
  };
  core.hasOp = function(name) {
    return !!opNames[name];
  };
  core.invokeOp = function(name, payload) {
    const binding = getBinding();
    if (binding) {
      return invokeWithBinding(binding, name, payload);
    }
    return waitForBinding(Date.now() + 1000).then(function(binding) {
      return invokeWithBinding(binding, name, payload);
    });
  };
  core.ops = core.ops && typeof core.ops === 'object' ? core.ops : new Proxy(Object.create(null), {
    get(target, property) {
      if (typeof property !== 'string' || property === 'then') {
        return undefined;
      }
      if (!Object.prototype.hasOwnProperty.call(target, property)) {
        target[property] = function(payload) {
          return core.invokeOp(property, payload);
        };
      }
      return target[property];
    }
  });
  function invokeExtension(extensionName, apiName, payload) {
    const opName = 'ext:' + extensionName + '/' + apiName;
    if (core.hasOp(opName)) {
      return core.invokeOp(opName, payload);
    }
    return Promise.reject(new Error('MoonBit op is not available: ' + extensionName + '.' + apiName));
  }
  const events = root.events && typeof root.events === 'object' ? root.events : (root.events = Object.create(null));
  function ensureExactListeners(name) {
    if (!Array.isArray(exactListeners[name])) {
      exactListeners[name] = [];
    }
    return exactListeners[name];
  }
  function emitExact(name, event) {
    const listeners = ensureExactListeners(name).slice();
    for (const listener of listeners) {
      listener(event);
    }
    return event;
  }
  events.emit = function(name, event) {
    return emitExact(name, event);
  };
  events['@@emitExtensionEvent'] = function(extensionName, eventName, payload) {
    const event = {
      extension: extensionName,
      name: eventName,
      payload: payload === undefined ? null : payload
    };
    emitExact(extensionName + '.' + eventName, event);
    return event;
  };
  events.on = function(name, listener) {
    if (typeof listener !== 'function') {
      throw new TypeError('MoonBit.events.on expects a listener function');
    }
    const listeners = ensureExactListeners(name);
    listeners.push(listener);
    return function() {
      exactListeners[name] = ensureExactListeners(name).filter(function(candidate) {
        return candidate !== listener;
      });
    };
  };
  root['@@extensions'] = root['@@extensions'] && typeof root['@@extensions'] === 'object' ? root['@@extensions'] : Object.create(null);
  root['@@ensureExtension'] = function(extensionName) {
    const existingExtension = root['@@extensions'][extensionName];
    if (existingExtension && typeof existingExtension === 'object') {
      return existingExtension;
    }
    const target = Object.create(null);
    const proxy = new Proxy(target, {
      get(_, property) {
        if (property === 'invoke') {
          return function(apiName, payload) {
            return invokeExtension(extensionName, apiName, payload);
          };
        }
        if (property === 'on') {
          return function(eventName, listener) {
            return events.on(extensionName + '.' + eventName, listener);
          };
        }
        if (property === 'name') {
          return extensionName;
        }
        if (typeof property !== 'string' || property === 'then') {
          return undefined;
        }
        if (!Object.prototype.hasOwnProperty.call(target, property)) {
          target[property] = function(payload) {
            return invokeExtension(extensionName, property, payload);
          };
        }
        return target[property];
      }
    });
    root['@@extensions'][extensionName] = proxy;
    root[extensionName] = proxy;
    return proxy;
  };
  window[moonbitName] = root;
})();
