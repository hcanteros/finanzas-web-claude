-- =====================================================================
-- FinanzasPersonales — Esquema Supabase (Postgres + RLS)
-- =====================================================================
-- Cómo usarlo:
--   1. Crear un proyecto en https://supabase.com
--   2. Abrir "SQL Editor" -> "New query"
--   3. Pegar TODO este archivo y ejecutar (Run)
--   4. Repetir cada vez que agregues una tabla nueva (podés correr
--      este script varias veces, usa IF NOT EXISTS / OR REPLACE)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. EXTENSIONES
-- ---------------------------------------------------------------------
create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------
-- 1. PERFILES DE USUARIO
-- ---------------------------------------------------------------------
-- Se crea automáticamente un perfil cuando alguien se registra
-- (por email o por Google). El único admin del sistema es
-- hcanteros@gmail.com; todos los demás quedan como "solo lectura".

create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  email       text not null,
  full_name   text,
  is_admin    boolean not null default false,
  created_at  timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Cada usuario puede ver su propio perfil; el admin puede ver todos
drop policy if exists "profiles_select_own_or_admin" on public.profiles;
create policy "profiles_select_own_or_admin"
  on public.profiles for select
  using (auth.uid() = id or public.is_admin());

-- Nadie inserta/edita perfiles manualmente (lo hace el trigger de abajo)

-- Función que determina si el usuario actual es el administrador
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select is_admin from public.profiles where id = auth.uid()),
    false
  );
$$;

-- Trigger: al registrarse un usuario nuevo, se crea su perfil.
-- Solo hcanteros@gmail.com queda marcado como administrador.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name, is_admin)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', new.email),
    lower(new.email) = 'hcanteros@gmail.com'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ---------------------------------------------------------------------
-- 2. TABLAS DE DATOS DE LA APP
-- ---------------------------------------------------------------------
-- Nota de diseño: se usa una sola cuenta compartida de datos (no una
-- copia por usuario), porque la app es de uso familiar/comunitario con
-- un único administrador que carga todo. Si en el futuro cada usuario
-- necesita sus propios datos privados, se agrega una columna
-- owner_id uuid references auth.users(id) y se ajustan las policies.

create table if not exists public.cuentas (
  id             text primary key,
  nombre         text not null,
  tipo           text not null,
  moneda         text not null default 'ARS',
  saldo_inicial  numeric not null default 0,
  emoji          text,
  descripcion    text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create table if not exists public.movimientos (
  id                 text primary key,
  fecha              date not null,
  tipo               text not null,
  cuenta_id          text references public.cuentas(id) on delete cascade,
  cuenta_destino_id  text references public.cuentas(id) on delete set null,
  categoria          text,
  concepto           text,
  descripcion        text,
  monto              numeric not null,
  notas              text,
  comprobante        text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create table if not exists public.categorias (
  id          text primary key,
  tipo        text not null,          -- ingreso / gasto / transferencia / etc.
  nombre      text not null,
  updated_at  timestamptz not null default now()
);

create table if not exists public.config (
  clave       text primary key,
  valor       jsonb not null,
  updated_at  timestamptz not null default now()
);

create table if not exists public.presupuestos (
  id          text primary key,
  categoria   text not null,
  mes         text not null,           -- formato 'YYYY-MM'
  monto       numeric not null,
  updated_at  timestamptz not null default now()
);

create table if not exists public.pasivos (
  id            text primary key,
  nombre        text not null,
  tipo          text,
  monto_total   numeric not null default 0,
  saldo_actual  numeric not null default 0,
  moneda        text not null default 'ARS',
  vencimiento   date,
  notas         text,
  updated_at    timestamptz not null default now()
);

create table if not exists public.pagos_deuda (
  id          text primary key,
  pasivo_id   text references public.pasivos(id) on delete cascade,
  fecha       date not null,
  monto       numeric not null,
  notas       text,
  updated_at  timestamptz not null default now()
);

create table if not exists public.activos (
  id            text primary key,
  nombre        text not null,
  tipo          text,
  cantidad      numeric,
  valor_unit    numeric,
  moneda        text default 'ARS',
  broker_id     text,
  instrumento_id text,
  notas         text,
  updated_at    timestamptz not null default now()
);

create table if not exists public.brokers (
  id          text primary key,
  nombre      text not null,
  updated_at  timestamptz not null default now()
);

create table if not exists public.instrumentos (
  id          text primary key,
  ticker      text,
  nombre      text not null,
  tipo        text,
  updated_at  timestamptz not null default now()
);

create table if not exists public.mov_inversiones (
  id             text primary key,
  fecha          date not null,
  tipo           text not null,
  instrumento_id text,
  broker_id      text,
  cantidad       numeric,
  precio         numeric,
  monto          numeric,
  cuenta_id      text references public.cuentas(id) on delete set null,
  notas          text,
  updated_at     timestamptz not null default now()
);

create table if not exists public.bal_snapshots (
  id          text primary key,
  fecha       date not null,
  datos       jsonb not null,
  updated_at  timestamptz not null default now()
);

create table if not exists public.otros_activos (
  id          text primary key,
  nombre      text not null,
  tipo        text,
  valor       numeric,
  moneda      text default 'ARS',
  notas       text,
  updated_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 3. ROW LEVEL SECURITY: lectura para cualquier usuario logueado,
--    escritura (insert/update/delete) SOLO para el administrador.
-- ---------------------------------------------------------------------

do $$
declare
  t text;
  tablas text[] := array[
    'cuentas','movimientos','categorias','config','presupuestos',
    'pasivos','pagos_deuda','activos','brokers','instrumentos',
    'mov_inversiones','bal_snapshots','otros_activos'
  ];
begin
  foreach t in array tablas loop
    execute format('alter table public.%I enable row level security;', t);

    execute format('drop policy if exists "%1$s_select_auth" on public.%1$s;', t);
    execute format(
      'create policy "%1$s_select_auth" on public.%1$s for select using (auth.role() = ''authenticated'');',
      t
    );

    execute format('drop policy if exists "%1$s_write_admin" on public.%1$s;', t);
    execute format(
      'create policy "%1$s_write_admin" on public.%1$s for insert with check (public.is_admin());',
      t
    );

    execute format('drop policy if exists "%1$s_update_admin" on public.%1$s;', t);
    execute format(
      'create policy "%1$s_update_admin" on public.%1$s for update using (public.is_admin()) with check (public.is_admin());',
      t
    );

    execute format('drop policy if exists "%1$s_delete_admin" on public.%1$s;', t);
    execute format(
      'create policy "%1$s_delete_admin" on public.%1$s for delete using (public.is_admin());',
      t
    );
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 4. updated_at automático
-- ---------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

do $$
declare
  t text;
  tablas text[] := array[
    'cuentas','movimientos','categorias','config','presupuestos',
    'pasivos','pagos_deuda','activos','brokers','instrumentos',
    'mov_inversiones','bal_snapshots','otros_activos'
  ];
begin
  foreach t in array tablas loop
    execute format('drop trigger if exists set_updated_at on public.%I;', t);
    execute format(
      'create trigger set_updated_at before update on public.%I for each row execute procedure public.set_updated_at();',
      t
    );
  end loop;
end $$;

-- =====================================================================
-- Listo. Con esto:
--  - Cualquier persona puede registrarse (Google o email) y hacer login.
--  - Todos pueden VER los datos (select).
--  - Solo hcanteros@gmail.com puede crear, editar o borrar (insert/
--    update/delete) en cualquier tabla, en cualquier módulo.
--  - Si necesitás otro admin en el futuro, actualizá la condición
--    en handle_new_user() y corré:
--      update public.profiles set is_admin = true where email = 'otro@mail.com';
-- =====================================================================
