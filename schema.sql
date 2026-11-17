-- Massif : à coller dans Supabase > SQL Editor > Run
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  sex text not null check (sex in ('homme','femme')),
  age int not null check (age >= 18),
  height_cm int not null check (height_cm between 120 and 230),
  weight_kg numeric(5,1) not null check (weight_kg between 35 and 200),
  activity text not null check (activity in ('sedentaire','modere','actif')),
  train_days int not null check (train_days in (3,4,5)),
  location text not null check (location in ('salle','maison_halteres','maison_sans')),
  excluded text[] not null default '{}',
  weekly_budget_eur int not null check (weekly_budget_eur between 10 and 200),
  kcal_bonus int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Écrit uniquement par le webhook Stripe (clé service_role)
create table public.subscriptions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  stripe_customer_id text unique,
  stripe_subscription_id text unique,
  status text not null default 'none', -- trialing, active, past_due, canceled...
  trial_end timestamptz,
  current_period_end timestamptz,
  updated_at timestamptz not null default now()
);

-- Données communes, lecture seule pour les connectés
create table public.recipes (
  id text primary key, name text not null, slot text[] not null,
  ingredients jsonb not null, steps text[] not null, minutes int not null,
  cost_eur numeric(4,2) not null, kcal int not null, protein_g int not null,
  carbs_g int not null, fat_g int not null,
  tags text[] not null default '{}' -- 'viande','poisson','lactose','gluten' = présents
);
create table public.exercises (
  id text primary key, name text not null, muscles text[] not null,
  version text not null check (version in ('salle','maison_halteres','maison_sans')),
  cue text not null
);
create table public.programs (
  id text primary key, days int not null check (days in (3,4,5)),
  version text not null check (version in ('salle','maison')),
  sessions jsonb not null -- [{name, exercises:[{exercise_id, sets, rep_min, rep_max}]}]
);

-- Données de l'utilisateur
create table public.meal_plan (
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null, slot text not null check (slot in ('petit_dej','dejeuner','collation','diner')),
  recipe_id text not null references public.recipes(id), done boolean not null default false,
  primary key (user_id, day, slot)
);
create table public.workout_sets (
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null, exercise_id text not null, set_no int not null,
  reps int, load_kg numeric(5,1), done boolean not null default false,
  primary key (user_id, day, exercise_id, set_no)
);
create table public.weight_logs (
  user_id uuid not null references auth.users(id) on delete cascade,
  week_start date not null, weight_kg numeric(5,1) not null,
  primary key (user_id, week_start)
);
create table public.shopping_checks (
  user_id uuid not null references auth.users(id) on delete cascade,
  week_start date not null, item text not null, checked boolean not null default true,
  primary key (user_id, week_start, item)
);
create index on public.meal_plan (user_id, day);
create index on public.workout_sets (user_id, day);
create index on public.weight_logs (user_id, week_start desc);

-- RLS
alter table public.profiles enable row level security;
alter table public.subscriptions enable row level security;
alter table public.recipes enable row level security;
alter table public.exercises enable row level security;
alter table public.programs enable row level security;
alter table public.meal_plan enable row level security;
alter table public.workout_sets enable row level security;
alter table public.weight_logs enable row level security;
alter table public.shopping_checks enable row level security;

create policy "profil: soi-même" on public.profiles for all
  using (auth.uid() = id) with check (auth.uid() = id);
create policy "abonnement: lecture seule" on public.subscriptions for select
  using (auth.uid() = user_id);
create policy "recettes: lecture" on public.recipes for select to authenticated using (true);
create policy "exercices: lecture" on public.exercises for select to authenticated using (true);
create policy "programmes: lecture" on public.programs for select to authenticated using (true);
create policy "repas: soi-même" on public.meal_plan for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "séries: soi-même" on public.workout_sets for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "poids: soi-même" on public.weight_logs for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "courses: soi-même" on public.shopping_checks for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
