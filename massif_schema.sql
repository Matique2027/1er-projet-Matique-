-- Massif : à coller dans Supabase > SQL Editor > Run
-- Script rejouable (create if not exists + drop policy/trigger if exists).
-- Note : si une table existe déjà, ses contraintes ne sont PAS modifiées
-- (ex. age between 18 and 100). Sur une base vide, tout est appliqué.

-- ============ Fonction utilitaire : updated_at ============
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ============ Tables ============
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  sex text not null check (sex in ('homme','femme')),
  age int not null check (age between 18 and 100),
  height_cm int not null check (height_cm between 120 and 230),
  weight_kg numeric(5,1) not null check (weight_kg between 35 and 200),
  activity text not null check (activity in ('sedentaire','modere','actif')),
  train_days int not null check (train_days in (3,4,5)),
  location text not null check (location in ('salle','maison_halteres','maison_sans')),
  excluded text[] not null default '{}',
  weekly_budget_eur int not null check (weekly_budget_eur between 10 and 200),
  kcal_bonus int not null default 0, -- non modifiable par le client (voir GRANT plus bas)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Écrit uniquement par le webhook Stripe (clé service_role)
create table if not exists public.subscriptions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  stripe_customer_id text unique,
  stripe_subscription_id text unique,
  status text not null default 'none' check (status in (
    'none','trialing','active','past_due','canceled',
    'unpaid','incomplete','incomplete_expired','paused'
  )),
  trial_end timestamptz,
  current_period_end timestamptz,
  updated_at timestamptz not null default now()
);

-- Données communes, lecture seule pour les connectés
create table if not exists public.recipes (
  id text primary key, name text not null, slot text[] not null,
  ingredients jsonb not null, steps text[] not null, minutes int not null,
  cost_eur numeric(4,2) not null, kcal int not null, protein_g int not null,
  carbs_g int not null, fat_g int not null,
  tags text[] not null default '{}' -- 'viande','poisson','lactose','gluten' = présents
);
create table if not exists public.exercises (
  id text primary key, name text not null, muscles text[] not null,
  version text not null check (version in ('salle','maison_halteres','maison_sans')),
  cue text not null
);
-- ATTENTION mapping côté app : programs.version = 'salle' | 'maison'
-- alors que exercises.version / profiles.location = 'salle' | 'maison_halteres' | 'maison_sans'
create table if not exists public.programs (
  id text primary key, days int not null check (days in (3,4,5)),
  version text not null check (version in ('salle','maison')),
  sessions jsonb not null -- [{name, exercises:[{exercise_id, sets, rep_min, rep_max}]}]
);

-- Données de l'utilisateur
create table if not exists public.meal_plan (
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null,
  slot text not null check (slot in ('petit_dej','dejeuner','collation','diner')),
  recipe_id text not null references public.recipes(id),
  done boolean not null default false,
  primary key (user_id, day, slot)
);
create table if not exists public.workout_sets (
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null,
  exercise_id text not null references public.exercises(id),
  set_no int not null,
  reps int, load_kg numeric(5,1), done boolean not null default false,
  primary key (user_id, day, exercise_id, set_no)
);
create table if not exists public.weight_logs (
  user_id uuid not null references auth.users(id) on delete cascade,
  week_start date not null,
  weight_kg numeric(5,1) not null,
  primary key (user_id, week_start)
);
create table if not exists public.shopping_checks (
  user_id uuid not null references auth.users(id) on delete cascade,
  week_start date not null,
  item text not null,
  checked boolean not null default false, -- était true : insérer une ligne cochait l'article
  primary key (user_id, week_start, item)
);

-- Pas d'index supplémentaires : les clés primaires (user_id, day/week_start, ...)
-- couvrent déjà les requêtes par utilisateur et par date.

-- ============ Triggers updated_at ============
drop trigger if exists trg_profiles_updated_at on public.profiles;
create trigger trg_profiles_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

drop trigger if exists trg_subscriptions_updated_at on public.subscriptions;
create trigger trg_subscriptions_updated_at
  before update on public.subscriptions
  for each row execute function public.set_updated_at();

-- ============ RLS ============
alter table public.profiles        enable row level security;
alter table public.subscriptions   enable row level security;
alter table public.recipes         enable row level security;
alter table public.exercises       enable row level security;
alter table public.programs        enable row level security;
alter table public.meal_plan       enable row level security;
alter table public.workout_sets    enable row level security;
alter table public.weight_logs     enable row level security;
alter table public.shopping_checks enable row level security;

drop policy if exists "profil: soi-même" on public.profiles;
create policy "profil: soi-même" on public.profiles for all to authenticated
  using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

drop policy if exists "abonnement: lecture seule" on public.subscriptions;
create policy "abonnement: lecture seule" on public.subscriptions for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "recettes: lecture" on public.recipes;
create policy "recettes: lecture" on public.recipes for select to authenticated using (true);

drop policy if exists "exercices: lecture" on public.exercises;
create policy "exercices: lecture" on public.exercises for select to authenticated using (true);

drop policy if exists "programmes: lecture" on public.programs;
create policy "programmes: lecture" on public.programs for select to authenticated using (true);

drop policy if exists "repas: soi-même" on public.meal_plan;
create policy "repas: soi-même" on public.meal_plan for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

drop policy if exists "séries: soi-même" on public.workout_sets;
create policy "séries: soi-même" on public.workout_sets for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

drop policy if exists "poids: soi-même" on public.weight_logs;
create policy "poids: soi-même" on public.weight_logs for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

drop policy if exists "courses: soi-même" on public.shopping_checks;
create policy "courses: soi-même" on public.shopping_checks for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

-- ============ Droits par colonne : kcal_bonus réservé au serveur ============
-- Le client ne peut ni insérer ni modifier kcal_bonus, created_at, updated_at.
-- Le service_role (serveur, webhooks) n'est pas concerné.
revoke insert, update on public.profiles from authenticated;
grant insert (id, sex, age, height_cm, weight_kg, activity, train_days, location, excluded, weekly_budget_eur)
  on public.profiles to authenticated;
grant update (sex, age, height_cm, weight_kg, activity, train_days, location, excluded, weekly_budget_eur)
  on public.profiles to authenticated;
