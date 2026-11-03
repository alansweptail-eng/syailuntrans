-- =====================================================================
-- SYAILUN TRANS — Skema database Supabase (Postgres)
-- Disusun dari model data prototipe. Jalankan di SQL Editor Supabase.
-- Belum dijalankan ke proyek mana pun; tinjau dulu sebelum produksi.
-- =====================================================================

create extension if not exists "pgcrypto";

-- Profil pengguna (terhubung ke auth.users) dan perannya
create type user_role as enum ('pelanggan', 'mitra', 'operasional', 'admin');
create type verif_status as enum ('belum', 'menunggu', 'terverifikasi', 'ditolak');

create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nama text not null default '',
  hp text,
  email text,
  role user_role not null default 'pelanggan',
  verifikasi verif_status not null default 'belum',
  verif_diajukan_at timestamptz,
  created_at timestamptz not null default now()
);

-- Mitra / usaha rental
create type partner_status as enum ('menunggu', 'aktif', 'ditolak', 'nonaktif');
create table partners (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references profiles(id),
  nama text not null,
  pemilik text,
  hp text,
  kota text,
  status partner_status not null default 'menunggu',
  komisi_persen numeric(5,2) not null default 10 check (komisi_persen between 0 and 50),
  is_platform_owner boolean not null default false,
  created_at timestamptz not null default now()
);

create table categories (
  id text primary key,               -- contoh: 'motor', 'mpv', 'suv'
  nama text not null,
  ikon text not null default 'car',
  tampil boolean not null default true,
  urutan int not null default 0
);

-- Kendaraan
create type vehicle_status as enum ('menunggu', 'disetujui', 'ditolak');
create table vehicles (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references partners(id) on delete cascade,
  category_id text not null references categories(id),
  nama text not null,
  harga_per_hari integer not null check (harga_per_hari >= 10000),
  transmisi text not null check (transmisi in ('Matic', 'Manual')),
  kapasitas int not null check (kapasitas > 0),
  bahan_bakar text not null default 'Bensin',
  paket_lepas boolean not null default true,
  paket_sopir boolean not null default false,
  paket_antar boolean not null default true,
  foto_path text,                    -- path di Supabase Storage, bucket 'vehicle-photos'
  status vehicle_status not null default 'menunggu',
  aktif boolean not null default true,
  unggulan boolean not null default false,
  created_at timestamptz not null default now(),
  check (paket_lepas or paket_sopir)
);

-- Pesanan
create type booking_status as enum ('menunggu-bayar', 'menunggu-penawaran', 'dikonfirmasi', 'berjalan', 'selesai', 'batal');
create type paket_sewa as enum ('lepas', 'sopir', 'khusus');
create table bookings (
  id text primary key,               -- kode pesanan, contoh: ST-3F9K2
  vehicle_id uuid not null references vehicles(id),
  customer_id uuid references profiles(id),
  nama_penyewa text not null,
  hp_penyewa text not null,
  email_penyewa text,
  ambil_tipe text not null default 'garasi' check (ambil_tipe in ('garasi', 'antar')),
  ambil_alamat text,
  kembali_tipe text not null default 'garasi' check (kembali_tipe in ('garasi', 'jemput')),
  kembali_alamat text,
  mulai date not null,
  jam_mulai time not null,
  selesai date not null,
  jam_selesai time not null,
  hari int not null check (hari > 0),
  paket paket_sewa not null,
  kebutuhan_khusus text,
  harga_khusus integer,
  perlindungan boolean not null default false,
  promo_kode text,
  catatan text,
  -- rincian harga disimpan saat pesanan dibuat agar tidak berubah jika tarif diubah
  harga_sewa integer not null,
  harga_sopir integer not null default 0,
  harga_antar integer not null default 0,
  harga_jemput integer not null default 0,
  harga_perlindungan integer not null default 0,
  diskon integer not null default 0,
  biaya_lebih_waktu integer not null default 0,
  jam_lebih int not null default 0,
  deposit integer not null default 0,
  total integer not null,
  status booking_status not null default 'menunggu-bayar',
  created_at timestamptz not null default now()
);
create index on bookings (vehicle_id, mulai);
create index on bookings (status);

-- Pembayaran (siap untuk QRIS, transfer, VA, dompet digital)
create type pay_method as enum ('qris', 'transfer', 'va', 'ewallet', 'tunai');
create type pay_status as enum ('belum', 'menunggu', 'lunas', 'gagal', 'dikembalikan');
create table payments (
  id uuid primary key default gen_random_uuid(),
  booking_id text not null references bookings(id) on delete cascade,
  metode pay_method,
  jumlah integer not null,
  status pay_status not null default 'belum',
  gateway_ref text,                  -- ID transaksi dari payment gateway
  paid_at timestamptz,
  created_at timestamptz not null default now()
);

-- Serah terima, pengembalian, kerusakan, deposit
create table handovers (
  booking_id text primary key references bookings(id) on delete cascade,
  serah_at timestamptz, km_awal int, bbm_awal text, checklist jsonb,
  kembali_at timestamptz, km_akhir int, bbm_akhir text,
  deposit_status text check (deposit_status in ('belum', 'ditahan', 'dikembalikan', 'dipotong')),
  deposit_potongan integer default 0,
  petugas_id uuid references profiles(id)
);
create table damage_reports (
  id uuid primary key default gen_random_uuid(),
  booking_id text not null references bookings(id) on delete cascade,
  keterangan text not null,
  biaya integer not null default 0,
  foto_path text,
  created_at timestamptz not null default now()
);

-- Tanggal ditutup (perawatan / sewa di luar aplikasi)
create table availability_blocks (
  id uuid primary key default gen_random_uuid(),
  vehicle_id uuid not null references vehicles(id) on delete cascade,
  dari date not null,
  sampai date not null,              -- eksklusif (tanggal kembali)
  jenis text not null default 'tutup' check (jenis in ('tutup', 'perawatan')),
  keterangan text,
  check (sampai > dari)
);

create table promos (
  kode text primary key,
  judul text not null,
  persen int not null check (persen between 1 and 90),
  min_hari int not null default 1,
  aktif boolean not null default true
);

create table reviews (
  id uuid primary key default gen_random_uuid(),
  booking_id text unique not null references bookings(id),
  vehicle_id uuid not null references vehicles(id),
  bintang int not null check (bintang between 1 and 5),
  teks text not null,
  nama_tampil text not null,
  created_at timestamptz not null default now()
);

create table support_tickets (
  id uuid primary key default gen_random_uuid(),
  nama text not null, hp text not null, topik text not null, pesan text not null,
  status text not null default 'baru' check (status in ('baru', 'diproses', 'selesai')),
  created_at timestamptz not null default now()
);

create table notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references profiles(id),
  target user_role,
  teks text not null,
  dibaca boolean not null default false,
  created_at timestamptz not null default now()
);

-- Pengaturan platform (satu baris)
create table settings (
  id int primary key default 1 check (id = 1),
  nama_usaha text not null default 'Syailun Trans',
  wa_admin text, alamat text, jam_operasional text,
  biaya_sopir int not null default 150000, biaya_antar int not null default 50000, biaya_jemput int not null default 50000,
  deposit_motor int not null default 300000, deposit_mobil int not null default 1000000,
  perlindungan_motor int not null default 15000, perlindungan_mobil int not null default 50000,
  lebih_jam_motor int not null default 10000, lebih_jam_mobil int not null default 50000,
  komisi_default numeric(5,2) not null default 10,
  syarat text[] not null default '{}', kebijakan_batal text
);
insert into settings (id) values (1) on conflict do nothing;

-- Cegah pesanan bentrok di tingkat database
create or replace function cek_bentrok() returns trigger language plpgsql as $$
begin
  if new.status in ('menunggu-bayar','menunggu-penawaran','dikonfirmasi','berjalan') and exists (
    select 1 from bookings b where b.vehicle_id = new.vehicle_id and b.id <> new.id
      and b.status in ('menunggu-bayar','menunggu-penawaran','dikonfirmasi','berjalan')
      and b.mulai < new.mulai + new.hari and new.mulai < b.mulai + b.hari
    union all
    select 1 from availability_blocks a where a.vehicle_id = new.vehicle_id
      and a.dari < new.mulai + new.hari and new.mulai < a.sampai
  ) then
    raise exception 'Tanggal sudah terisi untuk kendaraan ini';
  end if;
  return new;
end $$;
create trigger trg_cek_bentrok before insert or update of mulai, hari, status on bookings
  for each row execute function cek_bentrok();

-- ===== Row Level Security (dasar; sesuaikan sebelum produksi) =====
alter table profiles enable row level security;
alter table partners enable row level security;
alter table vehicles enable row level security;
alter table bookings enable row level security;
alter table payments enable row level security;
alter table reviews enable row level security;
alter table promos enable row level security;
alter table categories enable row level security;

create or replace function my_role() returns user_role language sql stable as $$ select role from profiles where id = auth.uid() $$;

create policy "profil sendiri" on profiles for all using (id = auth.uid() or my_role() in ('admin','operasional'));
create policy "kendaraan publik terbaca" on vehicles for select using (
  (status = 'disetujui' and aktif) or my_role() in ('admin','operasional')
  or partner_id in (select id from partners where owner_id = auth.uid()));
create policy "mitra kelola kendaraannya" on vehicles for all using (
  partner_id in (select id from partners where owner_id = auth.uid()) or my_role() = 'admin');
create policy "mitra aktif terbaca" on partners for select using (status = 'aktif' or owner_id = auth.uid() or my_role() = 'admin');
create policy "admin kelola mitra" on partners for all using (my_role() = 'admin' or owner_id = auth.uid());
create policy "pesanan milik sendiri" on bookings for select using (
  customer_id = auth.uid() or my_role() in ('admin','operasional')
  or vehicle_id in (select v.id from vehicles v join partners p on p.id = v.partner_id where p.owner_id = auth.uid()));
create policy "pelanggan membuat pesanan" on bookings for insert with check (customer_id = auth.uid());
create policy "operasional ubah pesanan" on bookings for update using (my_role() in ('admin','operasional'));
create policy "kategori terbaca" on categories for select using (true);
create policy "promo aktif terbaca" on promos for select using (aktif or my_role() = 'admin');
create policy "ulasan terbaca" on reviews for select using (true);

-- Storage: buat bucket 'vehicle-photos' (publik baca) dan 'customer-docs' (privat) lewat dashboard Supabase.
