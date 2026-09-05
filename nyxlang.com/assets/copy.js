// assets/copy.js — copiar al portapapeles el comando de instalación.
// T1 deja el enganche mínimo (todo elemento con data-copy); la T2 le pone la
// interacción y el feedback visual definitivos.
document.addEventListener("click", function (ev) {
  var el = ev.target.closest("[data-copy]");
  if (!el) return;
  navigator.clipboard.writeText(el.getAttribute("data-copy"));
});
