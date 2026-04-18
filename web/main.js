"use strict";

(function () {
  const STATUS_EL = document.getElementById("status");
  const META_EL = document.getElementById("meta");
  const TERM_EL = document.getElementById("terminal");
  const RESET_BTN = document.getElementById("reset");
  const HALT_BTN = document.getElementById("halt");

  const IMAGES = {
    bios: "images/seabios.bin",
    vgaBios: "images/vgabios.bin",
    kernel: "images/bzImage",
  };

  const KERNEL_CMDLINE =
    "console=ttyS0 earlyprintk=serial,ttyS0,115200 ignore_loglevel tsc=reliable clocksource=pit";

  const term = new Terminal({
    fontFamily:
      '"JetBrains Mono", "Fira Code", Menlo, Consolas, monospace',
    fontSize: 14,
    cursorBlink: true,
    convertEol: true,
    theme: {
      background: "#000000",
      foreground: "#b8e0a0",
      cursor: "#7cff7c",
      selectionBackground: "#1e3a1e",
      black: "#0b0f0a",
      red: "#ff6b6b",
      green: "#7cff7c",
      yellow: "#ffb86b",
      blue: "#7cc7ff",
      magenta: "#ff7cf0",
      cyan: "#7cf0ff",
      white: "#b8e0a0",
    },
  });

  const FitAddon =
    window.FitAddon && window.FitAddon.FitAddon
      ? window.FitAddon.FitAddon
      : null;

  const fitAddon = FitAddon ? new FitAddon() : null;
  if (fitAddon) term.loadAddon(fitAddon);

  term.open(TERM_EL);
  if (fitAddon) fitAddon.fit();

  const setStatus = (label, cls) => {
    STATUS_EL.textContent = label;
    STATUS_EL.classList.remove("booting", "running", "halted");
    STATUS_EL.classList.add(cls);
  };

  const setMeta = (text) => {
    META_EL.textContent = text;
  };

  if (typeof V86 === "undefined" && typeof V86Starter === "undefined") {
    term.write(
      "\x1b[31mfatal\x1b[0m: libv86 not loaded. check vendor/libv86.js\r\n",
    );
    setStatus("error", "halted");
    return;
  }

  const V86Ctor = typeof V86 !== "undefined" ? V86 : V86Starter;

  const emulator = new V86Ctor({
    wasm_path: "vendor/v86.wasm",
    memory_size: 64 * 1024 * 1024,
    vga_memory_size: 2 * 1024 * 1024,
    screen_container: null,
    bios: { url: IMAGES.bios },
    vga_bios: { url: IMAGES.vgaBios },
    bzimage: { url: IMAGES.kernel },
    cmdline: KERNEL_CMDLINE,
    autostart: true,
    disable_mouse: true,
    disable_keyboard: true,
    uart1: false,
  });

  setStatus("booting", "booting");
  term.writeln("\x1b[32m[webOS]\x1b[0m loading kernel…");

  let booted = false;
  const bootStart = performance.now();

  emulator.add_listener("emulator-ready", () => {
    term.writeln("\x1b[32m[webOS]\x1b[0m emulator ready, starting CPU…");
  });

  emulator.add_listener("emulator-started", () => {
    term.writeln("\x1b[32m[webOS]\x1b[0m CPU running");
  });

  emulator.add_listener("serial0-output-byte", (byte) => {
    if (!booted) {
      booted = true;
      const ms = Math.round(performance.now() - bootStart);
      setStatus("running", "running");
      setMeta(`boot: ${ms} ms`);
    }
    term.write(String.fromCharCode(byte));
  });

  term.onData((data) => {
    for (let i = 0; i < data.length; i++) {
      emulator.serial0_send(data[i]);
    }
  });

  window.addEventListener("resize", () => {
    if (fitAddon) fitAddon.fit();
  });

  RESET_BTN.addEventListener("click", () => {
    term.reset();
    booted = false;
    emulator.restart();
    setStatus("booting", "booting");
    setMeta("");
    term.writeln("\x1b[33m[webOS]\x1b[0m reset");
  });

  HALT_BTN.addEventListener("click", () => {
    emulator.stop();
    setStatus("halted", "halted");
    term.writeln("\r\n\x1b[31m[webOS]\x1b[0m halted");
  });

  term.focus();
  window.__webos = { emulator, term };
})();
