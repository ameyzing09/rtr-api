-- Fix is_owner field for migrated users
UPDATE public.user_profiles SET is_owner = TRUE WHERE id IN (
  '00000000-0000-0000-0000-000000000001',
  '08428c58-6103-44f9-9e6c-183bf13e4e60',
  '895d2d2a-632f-4052-a7f8-619f1b82c8a7'
);
