-- ============================================================
-- NOCHY E-AT : Update fitur lanjutan
--  - Toko Buka 24 Jam (seller bisa nyalakan/matikan)
--   - Voucher buatan seller (diskon toko sendiri)
--  - Rating toko oleh pembeli (rating = rata-rata semua pembeli)
-- Cara pakai: Supabase Dashboard > SQL Editor > New query,
-- tempel seluruh file ini lalu klik RUN. Aman dijalankan berulang
-- kali (idempotent) dan tidak menghapus data yang sudah ada.
-- ============================================================

-- ------------------------------------------------------------
-- 1) Opsi "Buka 24 Jam" pada toko
-- ============================================================
alter table public.stores
  add column if not exists is_24_hours boolean not null default false;

-- 2) Jumlah orang yang sudah menilai (untuk ditampilkan di pembeli)
alter table public.stores
  add column if not exists rating_count integer not null default 0;

-- ============================================================
-- 3) Voucher buatan Seller (muncul di toko & bisa dipakai pembeli)
--    discount_type: 'percent' | 'fixed' | 'free_delivery'
--    - percent       -> potong discount_value % dari subtotal,
--                       dibatasi max_discount (kalau diisi).
--    - fixed         -> potong Rp discount_value.
--    - free_delivery -> gratis ongkir sebesar discount_value.
-- ============================================================
create table if not exists public.store_vouchers (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  code text not null,
  title text not null,
  description text,
  discount_type text not null default 'fixed',
  discount_value numeric not null default 0,
  max_discount numeric,
  min_order numeric not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create index if not exists store_vouchers_store_id_idx on public.store_vouchers(store_id);

-- ============================================================
-- 4) Rating toko dari pembeli
--    Tabel `ratings` sudah ada. Kita tambah store_id supaya bisa
--    dihitung per toko, lalu isi dari data pesanan lama.
-- ============================================================
alter table public.ratings
  add column if not exists store_id uuid;

update public.ratings r
   set store_id = o.store_id
  from public.orders o
 where r.order_id = o.id
   and r.store_id is null;

create index if not exists ratings_store_id_idx on public.ratings(store_id);

-- Fungsi menghitung ulang rata-rata rating toko.
-- Dipakai aplikasi setelah pembeli mengirim rating.
create or replace function public.refresh_store_rating(p_store_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_avg numeric;
  v_count integer;
begin
  select coalesce(avg(store_rating), 0), count(store_rating)
    into v_avg, v_count
    from public.ratings
   where store_id = p_store_id;

  update public.stores
     set rating = round(v_avg, 1),
         rating_count = v_count
   where id = p_store_id;
end;
$$;

grant execute on function public.refresh_store_rating(uuid) to anon, authenticated;

-- ============================================================
-- 5) RLS policies (aman kalau RLS tidak aktif; berguna kalau aktif)
-- ============================================================
-- Voucher toko: semua orang boleh membaca, seller hanya mengelola
-- voucher tokonya sendiri.
drop policy if exists "public read store vouchers" on public.store_vouchers;
create policy "public read store vouchers" on public.store_vouchers
  for select using (true);

drop policy if exists "seller manage own vouchers" on public.store_vouchers;
create policy "seller manage own vouchers" on public.store_vouchers
  for all
  using (store_id in (select id from public.stores where merchant_id = auth.uid()))
  with check (store_id in (select id from public.stores where merchant_id = auth.uid()));

-- Rating: semua boleh membaca, pembeli hanya menulis rating miliknya.
drop policy if exists "public read ratings" on public.ratings;
create policy "public read ratings" on public.ratings
  for select using (true);

drop policy if exists "customer insert own rating" on public.ratings;
create policy "customer insert own rating" on public.ratings
  for insert with check (customer_id = auth.uid());
