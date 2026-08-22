# Migración de FinanzasPersonales a la web (GitHub Pages + Supabase)

## Qué te armé

```
finanzas-web/
├── index.html              ← Login (Google + email) y menú principal
├── cuentas.html             ← Módulo de ejemplo, 100% funcional
├── supabase-schema.sql      ← Estructura de base de datos + permisos
├── assets/
│   ├── supabase-client.js   ← Conexión y autenticación (lo usan todas las páginas)
│   └── shared.css           ← Estilos comunes (tu paleta original)
└── MIGRACION.md              ← Este archivo
```

**Cada módulo (Movimientos, Reportes, Inversiones, etc.) es un archivo `.html`
independiente**, así podés tocar uno sin arriesgar romper los demás. `index.html`
ya no hace nada más que loguear y mostrar el menú.

Los datos ya **no se guardan en `localStorage`**: se guardan en una base de
datos Postgres en Supabase, así están disponibles desde cualquier dispositivo.

## Permisos

- **`hcanteros@gmail.com`** → administrador: puede crear, editar y borrar en
  cualquier módulo.
- **Cualquier otra persona** que se registre (con Google o con email) →
  **solo lectura**: puede ver todo pero no puede crear nada. Esto está
  garantizado a nivel de base de datos (Row Level Security), no solo
  ocultando botones en la pantalla — aunque alguien manipule el HTML o
  llame a la API directamente, Supabase le va a rechazar cualquier
  escritura si no es el admin.

## Paso 1 — Crear el proyecto en Supabase

1. Andá a [supabase.com](https://supabase.com) → **New project**.
2. Elegí un nombre, una contraseña de base de datos (guardala) y la región
   más cercana (ej. South America).
3. Cuando termine de crearse, andá a **SQL Editor → New query**, pegá el
   contenido completo de `supabase-schema.sql` y ejecutá (**Run**). Esto
   crea todas las tablas, los permisos y la lógica de "quién es admin".
4. Andá a **Project Settings → API** y copiá:
   - **Project URL**
   - **anon public key**
5. Abrí `assets/supabase-client.js` y reemplazá:
   ```js
   const SUPABASE_URL = 'https://TU-PROYECTO.supabase.co';
   const SUPABASE_ANON_KEY = 'TU_ANON_KEY_PUBLICA';
   ```
   con los valores reales. (La `anon key` es pública a propósito — Supabase
   está diseñado para que esta clave viaje en el frontend; la seguridad la
   da el sistema de permisos (RLS) que ya quedó configurado en el paso 3.)

## Paso 2 — Habilitar login con Google

1. En Supabase: **Authentication → Providers → Google** → activarlo.
2. Necesitás un **Client ID** y **Client Secret** de Google. Se generan en
   [Google Cloud Console](https://console.cloud.google.com/apis/credentials):
   - Crear un proyecto (o usar uno existente).
   - **Credentials → Create Credentials → OAuth client ID → Web application**.
   - En **Authorized redirect URIs** pegá la URL que te muestra Supabase en
     la pantalla de configuración del provider Google (termina en
     `.../auth/v1/callback`).
   - Copiá el Client ID y Client Secret generados y pegalos en Supabase.
3. En **Authentication → URL Configuration**, agregá la URL donde vas a
   publicar el sitio (ver Paso 3) tanto en **Site URL** como en
   **Redirect URLs**, por ejemplo:
   `https://tu-usuario.github.io/finanzas-web/index.html`

## Paso 3 — Publicar en GitHub Pages

1. Creá un repositorio nuevo en GitHub (puede ser privado o público).
2. Subí el contenido de la carpeta `finanzas-web/` a la raíz del repo.
3. En el repo: **Settings → Pages → Source** → elegí la rama `main` y
   carpeta `/ (root)`.
4. GitHub te da una URL tipo
   `https://tu-usuario.github.io/nombre-repo/`. Esa es la URL final de tu
   app — usala en el paso anterior para las Redirect URLs de Supabase.

## Paso 4 — Marcarte como administrador

El script SQL ya deja preparado que **cualquier cuenta que se registre con
el email `hcanteros@gmail.com`** (por Google o por email/contraseña) queda
automáticamente como administrador. Solo tenés que:

1. Entrar a tu `index.html` publicado.
2. Registrarte (o entrar con Google) usando exactamente ese email.
3. Ya vas a tener todos los permisos.

Si en el futuro querés sumar otro admin, corré en el SQL Editor:
```sql
update public.profiles set is_admin = true where email = 'otro@correo.com';
```

## Paso 5 — Replicar el patrón en los módulos que faltan

`cuentas.html` es la plantilla de referencia. Cada módulo nuevo sigue
siempre la misma receta:

1. Copiá `cuentas.html` como punto de partida.
2. Cambiá el `<title>`, el encabezado y el nombre de la tabla en las
   consultas (`supabase.from('movimientos')`, `supabase.from('pasivos')`,
   etc. — los nombres de tabla ya existen en `supabase-schema.sql`).
3. Ajustá los campos del formulario a las columnas de esa tabla.
4. Import siempre lo mismo al principio:
   ```js
   import { supabase, requireAuth, renderUserBadge, applyReadOnlyMode } from './assets/supabase-client.js';
   ```
5. Al final del script, llamá `requireAuth()` para exigir login, pintar el
   badge de usuario y aplicar el modo solo-lectura si corresponde.

Los módulos pendientes de migrar (el menú de `index.html` ya tiene los
links armados, solo falta crear cada archivo):

- `dashboard.html`
- `movimientos.html`
- `reportes.html`
- `estado-resultados.html`
- `presupuesto.html`
- `pasivos.html`
- `inversiones.html`
- `balance.html`
- `activos.html`
- `exportar.html`
- `usuarios.html` (admin-only)
- `configuracion.html` (admin-only)

Las tablas correspondientes a cada uno ya están creadas por el script SQL
(`movimientos`, `presupuestos`, `pasivos`, `activos`, `brokers`,
`instrumentos`, `mov_inversiones`, `bal_snapshots`, `otros_activos`,
`categorias`, `config`), así que cada módulo nuevo es básicamente repetir
el patrón de `cuentas.html` apuntando a su tabla.

## Notas importantes

- **Chart.js y xlsx.js**: en la versión original estaban incrustados en el
  mismo archivo para que funcione offline. En la web ya no hace falta:
  podés cargarlos desde CDN (`cdn.jsdelivr.net`) solo en las páginas que
  los necesiten (Reportes, Exportar Excel), así cada módulo pesa lo mínimo.
- **IDs**: mantuve el mismo esquema de IDs de texto generados en el
  navegador (`uid()`) que usaba la app original, para que sea sencillo
  migrar datos existentes desde tu `localStorage` si querés importarlos.
- **Migrar datos viejos**: si querés pasar lo que ya tenés cargado en
  `localStorage` a Supabase, decime y armamos un script de importación que
  lea el backup/export de tu app actual y haga `insert` en cada tabla.
