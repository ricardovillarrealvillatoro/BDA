/* MedAssist AI · validación en el navegador y comportamiento de la interfaz.
 * La validación de aquí es solo una ayuda: el servidor (funciones validar_* de app/) y la base de datos
 * vuelven a validar todo. Ningún dato se guarda si el servidor lo rechaza. */
(function () {
  "use strict";

  const hoy = () => {
    const d = new Date();
    d.setMinutes(d.getMinutes() - d.getTimezoneOffset());
    return d.toISOString().slice(0, 10);
  };

  /* ---------- Mensajes de error junto a cada campo ---------- */
  function contenedor(el) {
    return el.closest(".field") || el.parentElement;
  }

  function marcarError(el, mensaje) {
    const caja = contenedor(el);
    let span = caja.querySelector(":scope > .field-error[data-js]");
    if (!span) {
      span = document.createElement("span");
      span.className = "field-error";
      span.dataset.js = "";
      if (el.closest(".field")) caja.appendChild(span);
      else el.insertAdjacentElement("afterend", span);
    }
    span.textContent = mensaje;
    if (caja.classList.contains("field")) caja.classList.add("con-error");
    el.setAttribute("aria-invalid", "true");
  }

  function limpiarError(el) {
    const caja = contenedor(el);
    const span = caja.querySelector(":scope > .field-error[data-js]") ||
      (el.nextElementSibling && el.nextElementSibling.matches(".field-error[data-js]") ? el.nextElementSibling : null);
    if (span) span.remove();
    caja.classList.remove("con-error");
    el.removeAttribute("aria-invalid");
  }

  /* Reglas propias que el navegador no trae */
  function reglasPropias(el, form) {
    const v = (el.value || "").trim();
    if (el.dataset.igualA) {
      const otro = form.querySelector(`[name="${el.dataset.igualA}"]`);
      if (otro && v !== otro.value.trim()) return el.dataset.mensaje || "Los valores no coinciden.";
    }
    if (el.dataset.requeridoSi) {
      const otro = form.querySelector(`[name="${el.dataset.requeridoSi}"]`);
      if (otro && otro.value && !v) return el.dataset.mensaje || "Este campo es obligatorio.";
    }
    if (el.dataset.noAntesDe && v) {
      const otro = form.querySelector(`[name="${el.dataset.noAntesDe}"]`);
      if (otro && otro.value && v < otro.value) return el.dataset.mensaje || "La fecha es anterior a la inicial.";
    }
    if (el.type === "password" && el.minLength >= 10 && v && !(/[A-Za-z]/.test(v) && /\d/.test(v))) {
      return el.dataset.mensaje || "Use letras y números.";
    }
    return null;
  }

  /* Mensajes en español sin depender del idioma del navegador */
  function mensajeEspanol(el) {
    const v = el.validity;
    if (v.valueMissing) return el.tagName === "SELECT" ? "Seleccione una opción." : "Este campo es obligatorio.";
    if (v.typeMismatch) return el.type === "email" ? "Escriba un correo válido." : "Formato no válido.";
    if (v.tooShort) return `Escriba al menos ${el.minLength} caracteres.`;
    if (v.tooLong) return `Máximo ${el.maxLength} caracteres.`;
    if (v.patternMismatch) return "El formato no es válido.";
    if (v.rangeUnderflow) return `El valor mínimo es ${el.min}.`;
    if (v.rangeOverflow) return `El valor máximo es ${el.max}.`;
    if (v.stepMismatch || v.badInput) return "Escriba un número válido.";
    return el.validationMessage;
  }

  function validarCampo(el, form) {
    if (el.disabled || el.type === "hidden" || el.hidden) {
      limpiarError(el);
      return true;
    }
    if (el.tagName !== "SELECT" && el.type !== "checkbox" && el.type !== "radio" && typeof el.value === "string") {
      // Quitar espacios a los lados antes de validar (el servidor hace lo mismo)
      if (el.value !== el.value.trim() && el.type !== "password") el.value = el.value.trim();
    }
    let mensaje = null;
    if (!el.checkValidity()) mensaje = el.dataset.mensaje || mensajeEspanol(el);
    else mensaje = reglasPropias(el, form);
    if (mensaje) {
      marcarError(el, mensaje);
      return false;
    }
    limpiarError(el);
    return true;
  }

  function validarFormulario(form) {
    let ok = true;
    let primero = null;
    const campos = form.querySelectorAll("input:not([type=radio]):not([type=checkbox]), select, textarea");
    campos.forEach((el) => {
      if (!validarCampo(el, form)) {
        ok = false;
        primero = primero || el;
      }
    });

    // Grupos de radio obligatorios
    const grupos = new Set();
    form.querySelectorAll("input[type=radio][required]").forEach((r) => grupos.add(r.name));
    grupos.forEach((nombre) => {
      const marcado = form.querySelector(`input[type=radio][name="${nombre}"]:checked`);
      const grupo = form.querySelector(`input[type=radio][name="${nombre}"]`).closest("[role=radiogroup]");
      grupo.querySelectorAll(".field-error[data-js]").forEach((s) => s.remove());
      if (!marcado) {
        const span = document.createElement("span");
        span.className = "field-error";
        span.dataset.js = "";
        span.textContent = "Elija una opción.";
        grupo.appendChild(span);
        ok = false;
        primero = primero || grupo.querySelector("input");
      }
    });

    // Al menos N casillas marcadas
    form.querySelectorAll("[data-min-checks]").forEach((fs) => {
      const min = parseInt(fs.dataset.minChecks, 10) || 1;
      const n = fs.querySelectorAll("input[type=checkbox]:checked").length;
      fs.querySelectorAll(":scope > .field-error[data-js]").forEach((s) => s.remove());
      fs.classList.toggle("con-error", n < min);
      if (n < min) {
        const span = document.createElement("span");
        span.className = "field-error";
        span.dataset.js = "";
        span.textContent = fs.dataset.mensaje || `Seleccione al menos ${min}.`;
        fs.appendChild(span);
        ok = false;
        primero = primero || fs.querySelector("input");
      }
    });

    // Uno de varios campos (p. ej. valor numérico o texto del resultado)
    if (form.dataset.unoDe) {
      const nombres = form.dataset.unoDe.split(",");
      const lleno = nombres.some((n) => {
        const el = form.querySelector(`[name="${n}"]`);
        return el && el.value.trim() !== "";
      });
      const primerCampo = form.querySelector(`[name="${nombres[0]}"]`);
      if (!lleno && primerCampo) {
        marcarError(primerCampo, form.dataset.mensaje || "Capture al menos un valor.");
        ok = false;
        primero = primero || primerCampo;
      }
    }

    if (primero) primero.focus();
    return ok;
  }

  /* ---------- Envío de formularios: validación y confirmación ---------- */
  document.addEventListener("submit", (ev) => {
    const form = ev.target;
    if (form.hasAttribute("data-validar") && !validarFormulario(form)) {
      ev.preventDefault();
      return;
    }
    if (form.dataset.confirm && !window.confirm(form.dataset.confirm)) {
      ev.preventDefault();
      return;
    }
    // Evitar doble envío (doble clic en "Guardar")
    const boton = form.querySelector("button[type=submit]");
    if (boton && form.method.toLowerCase() === "post") {
      setTimeout(() => { boton.disabled = true; }, 0);
    }
  });

  // Revalidar un campo con error en cuanto el usuario lo corrige
  document.addEventListener("input", (ev) => {
    const el = ev.target;
    if (el.hasAttribute("data-mayusculas")) {
      const pos = el.selectionStart;
      el.value = el.value.toUpperCase();
      try { el.setSelectionRange(pos, pos); } catch (e) { /* tipo sin selección */ }
    }
    if (el.getAttribute("aria-invalid") === "true" && el.form) validarCampo(el, el.form);
  });

  /* ---------- Formulario de decisión sobre una recomendación ---------- */
  function prepararDecision(form) {
    const accion = form.querySelector("[name=accion_final]");
    const actualizar = () => {
      const tipo = form.querySelector("input[name=tipo]:checked");
      const modificar = tipo && tipo.value === "modificada";
      accion.hidden = !modificar;
      accion.required = modificar;
      if (!modificar) limpiarError(accion);
      form.querySelectorAll("[role=radiogroup] > .field-error[data-js]").forEach((s) => s.remove());
    };
    form.addEventListener("change", (ev) => { if (ev.target.name === "tipo") actualizar(); });
    actualizar();
  }

  /* ---------- Inicio ---------- */
  document.addEventListener("DOMContentLoaded", () => {
    document.querySelectorAll("input[type=date][data-no-futura]").forEach((el) => { el.max = hoy(); });
    document.querySelectorAll("form[data-decision]").forEach(prepararDecision);
    document.querySelectorAll("[data-imprimir]").forEach((b) => b.addEventListener("click", () => window.print()));

    // Mensajes flash: cerrar a mano y ocultar solos los de éxito
    document.querySelectorAll(".flash").forEach((f) => {
      const cerrar = () => {
        f.classList.add("saliendo");
        setTimeout(() => f.remove(), 250);
      };
      const b = f.querySelector("[data-cerrar]");
      if (b) b.addEventListener("click", cerrar);
      if (f.classList.contains("success")) setTimeout(cerrar, 6000);
    });
  });
})();
