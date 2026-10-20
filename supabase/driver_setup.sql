-- ============================================================
-- NOCHY E-AT : Setup role Driver
--  - Profil driver (nama, no HP) bisa diedit dari app
--  - Driver melihat orderan siap antar, mengambil, dan menyelesaikan
--  - Posisi driver ditulis ke tabel driver_locations (realtime)
--  - Pembeli menilai driver; rating tampil sebagai rata-rata semua
--    penilaian pembeli (sama seperti rating toko)
--  - Stok produk otomatis berkurang saat CHECKOUT, dan dikembalikan
--    otomatis saat pesanan dibatalkan (bagian 12-16)
--  - Voucher toko/seller hanya boleh dipakai 1 kali per user, dan
--    hangus begitu pembayarannya berhasil (bagian 17)
--  - Kategori menu (rekomendasi / makanan / minuman / snack; satu
--    menu boleh masuk beberapa kategori sekaligus) dan tipe pesanan
--    antar vs ambil sendiri (bagian 18-20). Kategori Flash Sale tidak
--    dipilih manual: menu otomatis masuk ke sana kalau harganya
--    sedang didiskon (products.discount_price).
--  - Memperbaiki constraint status pesanan dan kolom rating yang
--    NOT NULL (lihat bagian 7-9 di bawah)
-- Cara pakai: Supabase Dashboard > SQL Editor > New query,
-- tempel seluruh file ini lalu klik RUN. Aman dijalankan
-- berulang kali (idempotent) dan tidak menghapus data.
-- ============================================================

-- ------------------------------------------------------------
-- 1) Rating driver pada profil
-- ------------------------------------------------------------
alter table public.profiles
  add column if not exists driver_rating numeric(3,2) not null default 0;

alter table public.profiles
  add column if not exists driver_rating_count integer not null default 0;

-- ------------------------------------------------------------
-- 2) Fungsi hitung ulang rating driver.
--    Nilai diambil dari tabel ratings (kolom driver_rating) yang
--    dihubungkan lewat orders.driver_id, sehingga tidak perlu
--    menambah kolom driver_id di tabel ratings.
-- ------------------------------------------------------------
create or replace function public.refresh_driver_rating(p_driver_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.profiles
     set driver_rating = coalesce(
           (select round(avg(r.driver_rating)::numeric, 2)
              from public.ratings r
              join public.orders o on o.id = r.order_id
             where o.driver_id = p_driver_id
               and r.driver_rating is not null), 0),
         driver_rating_count = (
           select count(*)
             from public.ratings r
             join public.orders o on o.id = r.order_id
            where o.driver_id = p_driver_id
              and r.driver_rating is not null)
   where id = p_driver_id;
$$;

-- ------------------------------------------------------------
-- 3) Posisi driver (dibaca pembeli, ditulis driver sendiri)
-- ------------------------------------------------------------
alter table public.driver_locations enable row level security;

drop policy if exists "driver locations readable" on public.driver_locations;
create policy "driver locations readable" on public.driver_locations
  for select
  using (true);

drop policy if exists "driver writes own location" on public.driver_locations;
create policy "driver writes own location" on public.driver_locations
  for all
  using (driver_id = auth.uid())
  with check (driver_id = auth.uid());

-- ------------------------------------------------------------
-- 4) Izin driver mengubah pesanan.
--    Driver hanya boleh mengambil pesanan berstatus ready_for_pickup
--    yang belum punya driver, dan mengubah pesanan yang sudah
--    menjadi miliknya.
-- ------------------------------------------------------------
drop policy if exists "driver update available or own orders" on public.orders;
create policy "driver update available or own orders" on public.orders
  for update
  using (
    driver_id = auth.uid()
    or (driver_id is null and status = 'ready_for_pickup')
  )
  with check (
    driver_id = auth.uid()
    or (driver_id is null and status = 'ready_for_pickup')
  );

-- ------------------------------------------------------------
-- 5) Publikasikan tabel ke Supabase Realtime.
--    Tanpa baris ini, subscribe di app tidak akan pernah menerima
--    perubahan posisi driver maupun status pesanan.
-- ------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'driver_locations'
  ) then
    alter publication supabase_realtime add table public.driver_locations;
  end if;

  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'orders'
  ) then
    alter publication supabase_realtime add table public.orders;
  end if;
end $$;

-- ------------------------------------------------------------
-- 6) Penyempurnaan RLS yang wajib ada agar tidak gagal diam-diam.
--    PostgREST tidak memberi error ketika policy menolak UPDATE;
--    ia hanya mengembalikan 0 baris terpengaruh. Akibatnya app
--    tetap menampilkan "tersimpan" padahal datanya tidak masuk.
--    Catatan: kedua policy ini TIDAK menyalakan RLS, jadi aman
--    dipasang walau ternyata RLS kedua tabel masih mati.
-- ------------------------------------------------------------

-- Pembeli boleh mengubah penilaian miliknya sendiri. Dipakai ketika
-- satu pesanan dinilai dua kali: tokonya dulu, drivernya belakangan.
drop policy if exists "customer update own rating" on public.ratings;
create policy "customer update own rating" on public.ratings
  for update
  using (customer_id = auth.uid())
  with check (customer_id = auth.uid());

-- Pemilik profil boleh mengubah datanya sendiri (nama, no HP, alamat).
drop policy if exists "profile owner update own profile" on public.profiles;
create policy "profile owner update own profile" on public.profiles
  for update
  using (id = auth.uid())
  with check (id = auth.uid());

-- ------------------------------------------------------------
-- 7) Longgarkan kolom rating di tabel ratings.
--    Kedua kolom ini NOT NULL, padahal pembeli boleh menilai toko
--    dan driver pada waktu yang berbeda. Akibatnya:
--      - menilai toko tanpa driver  -> error 23502 (driver_rating)
--      - menilai driver tanpa toko  -> error 23502 (store_rating)
--    PostgREST hanya mengembalikan 0 baris terpengaruh, jadi di app
--    pesanannya terlihat "terkirim" padahal datanya tidak tersimpan.
--    Dengan ini satu pesanan boleh punya satu kolom saja terisi.
-- ------------------------------------------------------------
alter table public.ratings
  alter column store_rating drop not null;

alter table public.ratings
  alter column driver_rating drop not null;

-- ------------------------------------------------------------
-- 8) Buka daftar status pesanan untuk alur driver.
--    Constraint lama orders_status_check hanya mengenal:
--      pending, accepted, cooking, ready_for_pickup,
--      delivering, completed, cancelled
--    sehingga "on_delivery" dan "arrived" ditolak Postgres dengan
--    error 23514: "new row for relation orders violates check
--    constraint orders_status_check".
--    Nilai lama tetap dipertahankan agar baris data lama tidak rusak.
--    WAJIB dijalankan sebelum bagian 9, kalau tidak update di
--    bagian 9 ikut kena error yang sama.
-- ------------------------------------------------------------
alter table public.orders
  drop constraint if exists orders_status_check;

alter table public.orders
  add constraint orders_status_check
  check (
    status in (
      'pending',
      'accepted',
      'cooking',
      'ready_for_pickup',
      'delivering',
      'on_delivery',
      'arrived',
      'completed',
      'cancelled'
    )
  );

-- ------------------------------------------------------------
-- 9) Penyesuaian data lama: status "delivering" dipakai simulator bot.
--    Diseragamkan ke "on_delivery" supaya satu alur saja.
-- ------------------------------------------------------------
update public.orders
   set status = 'on_delivery'
 where status = 'delivering';

-- ------------------------------------------------------------
-- 10) Penanda pesanan: orders.stock_deducted.
--
--     Kolom ini berarti "pesanan ini sudah memotong stok produk".
--     Menjadi tumpuan keputusan apakah stok perlu dikembalikan
--     saat pesanan dibatalkan, dan membuat backfill idempoten.
--
--     ATURAN AWALNYA stok dipotong saat pesanan completed. Perintah
--     pembuat trigger-nya sudah dihapus karena aturannya diganti
--     di bagian 12-15: stok dipotong saat CHECKOUT, karena makanan
--     tidak bisa dikembalikan begitu dipesan.
--     Bagian 12 tetap membuang trigger lama sebagai jaring pengaman
--     untuk file versi sebelumnya yang mungkin sudah terlanjur jalan.
-- ------------------------------------------------------------
alter table public.orders
  add column if not exists stock_deducted boolean not null default false;

-- ------------------------------------------------------------
-- 11) Backfill pesanan yang sudah completed sebelum trigger ada.
--
--     SUDAH DIGANTIKAN BAGIAN 15, jadi tidak ada perintah yang
--     dieksekusi di sini. Perintah aslinya memakai:
--         update public.products p
--            set stock = greatest(p.stock - oi.quantity, 0)
--           from public.order_items oi
--           join done_orders d on d.id = oi.order_id
--     tanpa group by. Klausa inilah sumber bug yang diperbaiki di
--     bagian 16: dua order yang menunjuk ke produk sama cuma
--     menghasilkan satu update, jadi kuantitas salah satunya hilang.
--
--     Bagian 15 sekarang menandai semua pesanan non-cancelled
--     (termasuk yang completed), sehingga cakupannya mencakup
--     bagian ini sepenuhnya dan lebih aman.
-- ------------------------------------------------------------

-- ============================================================
-- ATURAN BARU (bagian 12 dst)
-- Diputuskan: stok dipotong saat CHECKOUT, bukan saat pesanan
-- selesai. Alasannya makanan tidak bisa dikembalikan begitu
-- dipesan, dan potongan di akhir bikin stok ludes karena pesanan
-- menumpuk sebelum sempat diproses.
--
-- Bagian 10-11 di atas tinggal catatan sejarah: bagian 10 hanya
-- membuat penanda orders.stock_deducted (yang tetap dipakai),
-- dan bagian 11 sengaja dikosongkan karena sudah digantikan
-- bagian 15. Penanda tersebut berarti "pesanan ini sudah
-- memotong stok".
-- ============================================================

-- ------------------------------------------------------------
-- 12) Buang aturan lama (potong saat status jadi completed).
--     Aman dijalankan ulang: trigger dan fungsi memang sudah ada.
-- ------------------------------------------------------------
drop trigger if exists trg_decrement_stock_on_completion on public.orders;
drop function if exists public.decrement_stock_on_completion();

-- ------------------------------------------------------------
-- 13) Potong stok saat item pesanan masuk (checkout).
--
--     Dipasang di order_items, bukan di orders, karena saat baris
--     orders dibuat order_items belum ada — query-nya pasti kosong.
--
--     Pemrosesan per baris (for each row) juga otomatis bebas dari
--     bug GROUP BY di bagian 11: satu produk yang muncul di dua
--     baris item justru dihitung dua kali, memang sesuai harapan.
--
--     security definer supaya pembeli yang insert order_items tetap
--     bisa mengubah products walaupun RLS produk membatasi.
-- ------------------------------------------------------------
create or replace function public.deduct_stock_on_item_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.products p
     set stock = greatest(coalesce(p.stock, 0) - new.quantity, 0)
   where p.id = new.product_id;

  update public.orders o
     set stock_deducted = true
   where o.id = new.order_id
     and o.stock_deducted = false;

  return new;
end;
$$;

drop trigger if exists trg_deduct_stock on public.order_items;

create trigger trg_deduct_stock
  after insert on public.order_items
  for each row
  execute function public.deduct_stock_on_item_insert();

-- ------------------------------------------------------------
-- 14) Kembalikan stok kalau pesanan dibatalkan.
--     BEFORE trigger supaya penanda stock_deducted ikut tersimpan
--     ke baris pesanan; tanpa itu pesanan bisa dipulihkan dua kali.
-- ------------------------------------------------------------
create or replace function public.restore_stock_on_cancel()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'cancelled'
     and coalesce(old.status, '') <> 'cancelled'
     and new.stock_deducted
  then
    update public.products p
       set stock = coalesce(p.stock, 0) + x.total_qty
      from (
        select oi.product_id, sum(oi.quantity) as total_qty
          from public.order_items oi
         where oi.order_id = new.id
         group by oi.product_id
      ) x
     where x.product_id = p.id;

    new.stock_deducted := false;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_restore_stock_on_cancel on public.orders;

create trigger trg_restore_stock_on_cancel
  before update on public.orders
  for each row
  execute function public.restore_stock_on_cancel();

-- ------------------------------------------------------------
-- 15) Backfill aturan baru: pesanan yang masih aktif tapi belum
--     memotong stok. Kolom "group by" di sini wajib — tanpa itu
--     Postgres hanya meng-update satu baris produk sekali walau
--     beberapa item menunjuk padanya (lihat catatan bug di 16).
--
--     Pesanan cancelled sengaja dibiarkan: memang tidak ada stok
--     yang dipotong untuk pesanan yang batal.
-- ------------------------------------------------------------
with pending_orders as (
  update public.orders
     set stock_deducted = true
   where status <> 'cancelled'
     and stock_deducted = false
  returning id
)
update public.products p
   set stock = greatest(coalesce(p.stock, 0) - x.total_qty, 0)
  from (
    select oi.product_id, sum(oi.quantity) as total_qty
      from public.order_items oi
      join pending_orders d on d.id = oi.order_id
     group by oi.product_id
  ) x
 where x.product_id = p.id;

-- ------------------------------------------------------------
-- 16) PERBAIKAN SATU KALI akibat bug di bagian 11.
--
--     Backfill lama menulis "update products ... from order_items"
--     tanpa group by. Order NOCHY-1792384364970 dan
--     NOCHY-1792369143229 sama-sama memotong Nasi Tai, tapi karena
--     keduanya menyasar baris produk yang sama, Postgres hanya
--     menjalankan SATU update dengan kuantitas salah satu secara
--     acak. Yang terpotong x5, sedangkan x2 dari NOCHY-1792384364970
--     hilang diam-diam (Nasi Tai jadi 16, seharusnya 14).
--
--     stock_repaired dipakai sebagai penanda supaya perbaikan ini
--     cuma berjalan sekali walau file dijalankan berulang kali.
-- ------------------------------------------------------------
alter table public.orders
  add column if not exists stock_repaired boolean not null default false;

with repaired_orders as (
  update public.orders
     set stock_repaired = true
   where order_number = 'NOCHY-1792384364970'
     and stock_repaired = false
  returning id
)
update public.products p
   set stock = greatest(coalesce(p.stock, 0) - x.total_qty, 0)
  from (
    select oi.product_id, sum(oi.quantity) as total_qty
      from public.order_items oi
      join repaired_orders r on r.id = oi.order_id
     group by oi.product_id
  ) x
 where x.product_id = p.id;

-- ============================================================
-- VOUCHER TOKO : 1 user hanya boleh memakai satu voucher toko
-- satu kali. Setelah dipakai, voucher itu hangus untuk user
-- tersebut dan hilang dari daftarnya; user lain tetap bisa pakai.
--
-- Pencatatannya baru dibuat setelah pembayaran benar-benar
-- berhasil, jadi user yang batal bayar tidak kehilangan voucher.
-- ============================================================

-- ------------------------------------------------------------
-- 17) Tabel catatan pemakaian voucher toko.
--     unique (user_id, store_voucher_id) menjamin 1 user 1 kali
--     langsung di level database, bukan cuma di tampilan aplikasi.
-- ------------------------------------------------------------
create table if not exists public.store_voucher_usages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null
    references public.profiles (id) on delete cascade,
  store_voucher_id uuid not null
    references public.store_vouchers (id) on delete cascade,
  order_number text,
  created_at timestamptz not null default now(),
  constraint store_voucher_usages_unique_per_user
    unique (user_id, store_voucher_id)
);

create index if not exists store_voucher_usages_user_id_idx
  on public.store_voucher_usages (user_id);

alter table public.store_voucher_usages enable row level security;

drop policy if exists "user reads own voucher usages"
  on public.store_voucher_usages;
create policy "user reads own voucher usages"
  on public.store_voucher_usages
  for select using (auth.uid() = user_id);

drop policy if exists "user records own voucher usage"
  on public.store_voucher_usages;
create policy "user records own voucher usage"
  on public.store_voucher_usages
  for insert with check (auth.uid() = user_id);

-- ============================================================
-- KATEGORI MENU + PESANAN AMBIL SENDIRI (PICKUP)
-- ============================================================

-- ------------------------------------------------------------
-- 18) Kategori menu, dipilih seller saat menulis atau mengubah
--     menu. Kolom ini yang dipakai sidebar kategori di halaman
--     detail toko untuk benar-benar menyaring; selama ini
--     sidebar hanya menyorot teks tanpa menyaring apa pun.
--
--     Bentuknya array supaya satu menu boleh dipajang di beberapa
--     kategori sekaligus, misal Makanan sekaligus Flash Sale.
--     'makanan' tetap jadi nilai awal supaya menu lama langsung
--     punya satu kategori dan tidak lenyap dari tampilan.
-- ------------------------------------------------------------
alter table public.products
  add column if not exists category text not null default 'makanan';

-- Constraint lama dibuang dulu, sebelum tipe kolom diubah: saat
-- ALTER COLUMN TYPE, Postgres mengurai ulang ekspresi constraint lama
-- (yang masih membandingkan text) dan itu gagal setelah kolomnya jadi
-- array. Constraint versi array dipasang lagi di bawah.
alter table public.products
  drop constraint if exists products_category_check;

-- Ubah text -> text[]. Dijaga cek tipe kolom dulu supaya file ini
-- tetap aman dijalankan berulang kali (lihat bagian 18 catatan atas).
do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'products'
      and column_name = 'category'
      and data_type = 'text'
  ) then
    -- Default lama bertipe text juga harus dilepas dulu: klausa USING
    -- hanya mengurus konversi datanya, sedangkan default akan dicoba
    -- di-cast otomatis dan gagal ("default ... cannot be cast
    -- automatically").
    alter table public.products
      alter column category drop default;
    alter table public.products
      alter column category type text[]
      using (case
        when category is null then '{makanan}'::text[]
        else array[category]
      end);
    alter table public.products
      alter column category set default '{makanan}'::text[];
  end if;
end $$;

alter table public.products
  add constraint products_category_check
  check (
    category <@ array['flash_sale', 'rekomendasi', 'makanan', 'minuman', 'snack']::text[]
  );

-- ------------------------------------------------------------
-- 19) Tipe pesanan:
--     'delivery' -> diantar driver, jadi muncul di daftar orderan
--                   driver;
--     'pickup'   -> diambil sendiri oleh customer, tidak pernah
--                   menyentuh driver sama sekali.
--
--     Baris lama otomatis menjadi 'delivery' lewat nilai default,
--     memang semuanya pesanan antar. CHECK sengaja dipasang supaya
--     ejaan salah tulis dari aplikasi langsung gagal keras, bukan
--     jadi data yang diam-diam salah.
-- ------------------------------------------------------------
alter table public.orders
  add column if not exists fulfillment_type text not null default 'delivery';

alter table public.orders
  drop constraint if exists orders_fulfillment_type_check;
alter table public.orders
  add constraint orders_fulfillment_type_check
  check (fulfillment_type in ('delivery', 'pickup'));

-- ------------------------------------------------------------
-- 20) Izin pembeli menutup pesanan ambil sendiri.
--     Pickup tidak pernah lewat driver, jadi satu-satunya yang bisa
--     menutup pesanan setelah statusnya ready_for_pickup adalah
--     pembelinya sendiri lewat tombol "Sudah Saya Ambil".
--     Ekspresi with check dipakai sama seperti using, sehingga
--     pembeli tetap tidak bisa menimpa pesanan milik orang lain.
--     Kalau RLS di tabel orders memang tidak aktif, kebijakan ini
--     tidak berpengaruh apa pun — ditulis supaya aman begitu RLS
--     diaktifkan kapan pun.
-- ------------------------------------------------------------
drop policy if exists "customer completes own pickup orders" on public.orders;
create policy "customer completes own pickup orders" on public.orders
  for update
  using (customer_id = auth.uid())
  with check (customer_id = auth.uid());
