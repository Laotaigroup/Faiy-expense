-- =========================================================
--  ແອັບບັນທຶກລາຍຈ່າຍນ້ອງ — Supabase schema
--  ວາງທັງໝົດນີ້ໃນ Supabase > SQL Editor ແລ້ວກົດ Run ຄັ້ງດຽວ
-- =========================================================

-- 1) ລາຍຊື່ຄົນທີ່ມີສິດໃຊ້ແອັບ (ນ້ອງ + ອ້າຍ)
create table if not exists public.members (
  email        text primary key,
  display_name text not null,
  role         text not null check (role in ('student', 'family'))
);

-- ບໍ່ໃຊ້ອີເມວແທ້: ແອັບແປງຊື່ຜູ້ໃຊ້ "nong" ເປັນ "nong@nong-expense.app" ເອງ
-- ສ້າງ user ໃນ Authentication ດ້ວຍອີເມວແບບນີ້ (ຕິກ Auto Confirm)
insert into public.members (email, display_name, role) values
  ('nong@nong-expense.app', 'ນ້ອງ',  'student'),
  ('phi@nong-expense.app',  'ອ້າຍ', 'family')
on conflict (email) do update
  set display_name = excluded.display_name, role = excluded.role;

-- helper: ຜູ້ໃຊ້ທີ່ login ຢູ່ ເປັນສະມາຊິກບໍ
create or replace function public.is_member()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.members
    where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

-- 2) ຕາຕະລາງລາຍຈ່າຍ
create table if not exists public.expenses (
  id             uuid primary key default gen_random_uuid(),
  spent_on       date not null default (now() at time zone 'Asia/Shanghai')::date,
  amount         numeric(12,2) not null check (amount > 0),
  category       text not null default 'other'
                 check (category in ('food','transport','supplies','study','housing','phone','health','other')),
  note           text,
  is_claim       boolean not null default false,
  claim_status   text check (claim_status in ('pending','reimbursed')),
  reimbursed_at  timestamptz,
  receipt_path   text,
  created_by     uuid default auth.uid(),
  created_email  text default (auth.jwt() ->> 'email'),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  -- ຖ້າເປັນລາຍການຂໍຄືນ ຕ້ອງມີສະຖານະ
  constraint claim_status_consistent check (
    (is_claim and claim_status is not null) or (not is_claim and claim_status is null)
  )
);

create index if not exists expenses_spent_on_idx on public.expenses (spent_on desc);
create index if not exists expenses_claim_idx    on public.expenses (is_claim, claim_status);

-- ອັບເດດ updated_at ອັດຕະໂນມັດ
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists expenses_touch on public.expenses;
create trigger expenses_touch before update on public.expenses
  for each row execute function public.touch_updated_at();

-- 3) Row Level Security: ສະເພາະສະມາຊິກເທົ່ານັ້ນທີ່ເຫັນ/ແກ້ໄຂໄດ້
alter table public.members  enable row level security;
alter table public.expenses enable row level security;

drop policy if exists "members read"   on public.members;
create policy "members read" on public.members
  for select to authenticated using (public.is_member());

drop policy if exists "expenses select" on public.expenses;
drop policy if exists "expenses insert" on public.expenses;
drop policy if exists "expenses update" on public.expenses;
drop policy if exists "expenses delete" on public.expenses;

create policy "expenses select" on public.expenses
  for select to authenticated using (public.is_member());
create policy "expenses insert" on public.expenses
  for insert to authenticated with check (public.is_member());
create policy "expenses update" on public.expenses
  for update to authenticated using (public.is_member()) with check (public.is_member());
create policy "expenses delete" on public.expenses
  for delete to authenticated using (public.is_member());

-- 4) ບ່ອນເກັບຮູບໃບບິນ (private bucket)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('receipts', 'receipts', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

drop policy if exists "receipts select" on storage.objects;
drop policy if exists "receipts insert" on storage.objects;
drop policy if exists "receipts update" on storage.objects;
drop policy if exists "receipts delete" on storage.objects;

create policy "receipts select" on storage.objects
  for select to authenticated using (bucket_id = 'receipts' and public.is_member());
create policy "receipts insert" on storage.objects
  for insert to authenticated with check (bucket_id = 'receipts' and public.is_member());
create policy "receipts update" on storage.objects
  for update to authenticated using (bucket_id = 'receipts' and public.is_member());
create policy "receipts delete" on storage.objects
  for delete to authenticated using (bucket_id = 'receipts' and public.is_member());
