// =====================================================================
// supabase-client.js
// Módulo compartido: conexión a Supabase + autenticación (Google/email)
// Lo importan TODAS las páginas (index.html, cuentas.html, etc.)
// =====================================================================
import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

// -----------------------------------------------------------------
// 1) CONFIGURACIÓN — completá esto con los datos de TU proyecto Supabase
//    (Project Settings -> API). El "anon key" es pública, se puede
//    exponer en el frontend sin problema: la seguridad real la da RLS.
// -----------------------------------------------------------------
const SUPABASE_URL = 'https://vtwentiztmafllvlljgc.supabase.co';
   const SUPABASE_ANON_KEY = 'sb_publishable_DkfpX-l96XZJvUWAB1XOdg_Eqpol-js'; 
const ADMIN_EMAIL = 'hcanteros@gmail.com';

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// -----------------------------------------------------------------
// 2) SESIÓN / PERFIL
// -----------------------------------------------------------------
export async function getSession() {
  const { data } = await supabase.auth.getSession();
  return data.session;
}

export async function getProfile() {
  const session = await getSession();
  if (!session) return null;
  const { data, error } = await supabase
    .from('profiles')
    .select('*')
    .eq('id', session.user.id)
    .single();
  if (error) {
    // Puede pasar en el primer instante tras el registro, mientras
    // corre el trigger que crea el perfil. Devolvemos algo mínimo.
    return { id: session.user.id, email: session.user.email, is_admin: session.user.email === ADMIN_EMAIL };
  }
  return data;
}

export async function isCurrentUserAdmin() {
  const profile = await getProfile();
  return !!profile?.is_admin;
}

// -----------------------------------------------------------------
// 3) LOGIN / REGISTRO
// -----------------------------------------------------------------
export async function signInWithGoogle() {
  const { error } = await supabase.auth.signInWithOAuth({
    provider: 'google',
    options: { redirectTo: window.location.origin + window.location.pathname }
  });
  if (error) throw error;
}

export async function signUpWithEmail(email, password, fullName) {
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: { data: { full_name: fullName || '' } }
  });
  if (error) throw error;
  return data;
}

export async function signInWithEmail(email, password) {
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) throw error;
  return data;
}

export async function signOut() {
  await supabase.auth.signOut();
  window.location.href = 'index.html';
}

// -----------------------------------------------------------------
// 4) GUARDIA DE PÁGINA
// Llamar al principio de cada módulo (cuentas.html, movimientos.html…).
// Si no hay sesión, redirige al login. Devuelve { session, profile }.
// -----------------------------------------------------------------
export async function requireAuth() {
  const session = await getSession();
  if (!session) {
    window.location.href = 'index.html';
    return null;
  }
  const profile = await getProfile();
  return { session, profile };
}

// -----------------------------------------------------------------
// 5) UI: pinta el badge de usuario (nombre + rol) en la topbar
//    de cada módulo, y cablea el botón de logout.
// -----------------------------------------------------------------
export function renderUserBadge(el, profile) {
  if (!el) return;
  const rol = profile?.is_admin ? 'Administrador' : 'Solo lectura';
  el.innerHTML = `
    <div class="user-badge">
      <div>
        <div class="user-badge-name">${profile?.email || ''}</div>
        <div class="user-badge-role">${rol}</div>
      </div>
      <button class="btn btn-ghost btn-sm" id="btnLogout">Salir</button>
    </div>
  `;
  el.querySelector('#btnLogout')?.addEventListener('click', signOut);
}

// -----------------------------------------------------------------
// 6) Utilidad: aplica el modo solo-lectura a toda la página si el
//    usuario no es admin (oculta/deshabilita botones marcados con
//    la clase .admin-only)
// -----------------------------------------------------------------
export function applyReadOnlyMode(isAdmin) {
  if (isAdmin) return;
  document.querySelectorAll('.admin-only').forEach(node => {
    node.style.display = 'none';
  });
  document.querySelectorAll('[data-admin-disable]').forEach(node => {
    node.disabled = true;
    node.title = 'Solo el administrador puede modificar datos';
  });
}
