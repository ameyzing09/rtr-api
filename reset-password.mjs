import { createClient } from '@supabase/supabase-js';

const supabaseUrl = 'http://localhost:54321';
const serviceRoleKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { autoRefreshToken: false, persistSession: false }
});

const { data, error } = await supabase.auth.admin.updateUserById(
  '00000000-0000-0000-0000-000000000001',
  { password: 'password123' }
);

if (error) {
  console.error('Error:', error.message);
  process.exit(1);
}

console.log('Password reset successfully for superadmin@recrutr.in');
console.log('New password: password123');
