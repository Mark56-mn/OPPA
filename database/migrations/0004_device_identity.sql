create unique index if not exists oppa_devices_user_key_unique
  on public.oppa_devices(user_id, device_public_key);