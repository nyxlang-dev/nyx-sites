// assets/copy.js — copiar al portapapeles el comando de instalación.
//
// Sin dependencias y sin build: un solo listener delegado en document, así
// sirve para cualquier elemento con [data-copy] que aparezca en la página.
// Camino principal: navigator.clipboard (requiere contexto seguro). Fallback:
// un <textarea> fuera de pantalla + execCommand("copy"), que es lo único que
// funciona en http:// y en navegadores viejos.
//
// Las etiquetas del botón vienen del HTML (data-copy-label / data-copied-label)
// para que el JS no tenga texto traducible adentro.
(function () {
  "use strict";

  function fallbackCopy(text) {
    var ta = document.createElement("textarea");
    ta.value = text;
    ta.setAttribute("readonly", "");
    ta.style.position = "fixed";
    ta.style.top = "-1000px";
    ta.style.opacity = "0";
    document.body.appendChild(ta);
    ta.select();
    var ok = false;
    try { ok = document.execCommand("copy"); } catch (e) { ok = false; }
    document.body.removeChild(ta);
    return ok;
  }

  function flash(btn) {
    var idle = btn.getAttribute("data-copy-label") || btn.textContent;
    var done = btn.getAttribute("data-copied-label") || idle;
    btn.setAttribute("data-copy-label", idle);
    btn.textContent = done;
    btn.classList.add("is-copied");
    window.setTimeout(function () {
      btn.textContent = idle;
      btn.classList.remove("is-copied");
    }, 1600);
  }

  document.addEventListener("click", function (ev) {
    var target = ev.target;
    if (!target || !target.closest) { return; }
    var btn = target.closest("[data-copy]");
    if (!btn) { return; }
    var text = btn.getAttribute("data-copy") || "";
    if (!text) { return; }
    ev.preventDefault();
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(
        function () { flash(btn); },
        function () { if (fallbackCopy(text)) { flash(btn); } }
      );
    } else if (fallbackCopy(text)) {
      flash(btn);
    }
  });
})();
