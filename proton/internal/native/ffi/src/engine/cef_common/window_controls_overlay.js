(function installWindowControlsOverlay(visible, x, y, width, height, zoomPercent) {
  "use strict";

  const cssProperties = [
    "--proton-titlebar-area-x",
    "--proton-titlebar-area-y",
    "--proton-titlebar-area-width",
    "--proton-titlebar-area-height",
  ];
  let rawGeometry = { visible, x, y, width, height, zoomPercent };
  let geometry = scaleGeometry(rawGeometry);
  let disposed = false;
  let domReadyListener = null;

  function scaleGeometry(value) {
    const zoom = Number(value.zoomPercent) > 0
      ? Number(value.zoomPercent) / 100
      : 1;
    const rect = {
      x: Number(value.x) / zoom,
      y: Number(value.y) / zoom,
      width: Number(value.width) / zoom,
      height: Number(value.height) / zoom,
    };
    return {
      visible: Boolean(value.visible) && rect.width > 0 && rect.height > 0,
      rect,
    };
  }

  function sameGeometry(left, right) {
    return left.visible === right.visible &&
      left.rect.x === right.rect.x &&
      left.rect.y === right.rect.y &&
      left.rect.width === right.rect.width &&
      left.rect.height === right.rect.height;
  }

  function makeRect(rect) {
    return new DOMRect(rect.x, rect.y, rect.width, rect.height);
  }

  function applyCssGeometry() {
    const style = document.documentElement?.style;
    if (!style) {
      return false;
    }
    if (!geometry.visible) {
      for (const property of cssProperties) {
        style.removeProperty(property);
      }
      return true;
    }
    style.setProperty(cssProperties[0], `${geometry.rect.x}px`);
    style.setProperty(cssProperties[1], `${geometry.rect.y}px`);
    style.setProperty(cssProperties[2], `${geometry.rect.width}px`);
    style.setProperty(cssProperties[3], `${geometry.rect.height}px`);
    return true;
  }

  function ensureCssGeometry() {
    if (applyCssGeometry() || domReadyListener) {
      return;
    }
    domReadyListener = () => {
      domReadyListener = null;
      applyCssGeometry();
    };
    document.addEventListener("DOMContentLoaded", domReadyListener, {
      once: true,
    });
  }

  const overlay = navigator.windowControlsOverlay instanceof EventTarget
    ? navigator.windowControlsOverlay
    : new EventTarget();
  let geometryChangeHandler = null;
  Object.defineProperties(overlay, {
    visible: {
      configurable: true,
      enumerable: true,
      get() {
        return geometry.visible;
      },
    },
    getTitlebarAreaRect: {
      configurable: true,
      value() {
        return makeRect(geometry.rect);
      },
    },
    ongeometrychange: {
      configurable: true,
      enumerable: true,
      get() {
        return geometryChangeHandler;
      },
      set(value) {
        if (geometryChangeHandler) {
          overlay.removeEventListener("geometrychange", geometryChangeHandler);
        }
        geometryChangeHandler = typeof value === "function" ? value : null;
        if (geometryChangeHandler) {
          overlay.addEventListener("geometrychange", geometryChangeHandler);
        }
      },
    },
  });
  Object.defineProperty(navigator, "windowControlsOverlay", {
    configurable: true,
    enumerable: true,
    value: overlay,
  });
  ensureCssGeometry();

  return {
    update(nextVisible, nextX, nextY, nextWidth, nextHeight, nextZoomPercent) {
      if (disposed) {
        return false;
      }
      rawGeometry = {
        visible: nextVisible,
        x: nextX,
        y: nextY,
        width: nextWidth,
        height: nextHeight,
        zoomPercent: nextZoomPercent,
      };
      const next = scaleGeometry(rawGeometry);
      if (sameGeometry(geometry, next)) {
        return false;
      }
      geometry = next;
      ensureCssGeometry();
      const event = new Event("geometrychange");
      Object.defineProperties(event, {
        titlebarAreaRect: {
          enumerable: true,
          value: makeRect(geometry.rect),
        },
        visible: { enumerable: true, value: geometry.visible },
      });
      overlay.dispatchEvent(event);
      return true;
    },

    dispose() {
      if (disposed) {
        return;
      }
      disposed = true;
      if (domReadyListener) {
        document.removeEventListener("DOMContentLoaded", domReadyListener);
        domReadyListener = null;
      }
      geometry = {
        visible: false,
        rect: { x: 0, y: 0, width: 0, height: 0 },
      };
      applyCssGeometry();
      delete navigator.windowControlsOverlay;
    },
  };
})
