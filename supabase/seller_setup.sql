-- ============================================================
-- NOCHY E-AT : Setup role Seller / Resto
-- Cara pakai: Supabase Dashboard > SQL Editor > New query,
-- tempel seluruh file ini lalu klik RUN. Aman dijalankan
-- berulang kali (idempotent).
-- ============================================================

-- 1) Kolom gambar/logo toko
alter table public.stores
  add column if not exists image_url text;

-- 2) Kolom stok makanan (angka porsi)
alter table public.products
  add column if not exists stock integer not null default 0;

-- 3) Isi stok produk lama supaya tidak langsung dianggap "Habis"
update public.products
set stock = 50
where stock is null or stock = 0;

-- 4) OPSIONAL: policy agar pemilik toko boleh mengelola tokonya
--    sendiri dan menu-menunya.
--    - Kalau Row Level Security (RLS) belum aktif, bagian ini tidak
--      berpengaruh dan boleh dilewati.
--    - Kalau RLS aktif, bagian ini menambah izin untuk seller yang
--      sedang login (auth.uid()). Tidak mengurangi izin yang sudah ada.
drop policy if exists "seller manage own store" on public.stores;
create policy "seller manage own store" on public.stores
  for all
  using (merchant_id = auth.uid())
  with check (merchant_id = auth.uid());

drop policy if exists "seller manage own products" on public.products;
create policy "seller manage own products" on public.products
  for all
  using (store_id in (select id from public.stores where merchant_id = auth.uid()))
  with check (store_id in (select id from public.stores where merchant_id = auth.uid()));
