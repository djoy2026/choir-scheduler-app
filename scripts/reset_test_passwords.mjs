// Reset test user passwords through the Supabase Auth Admin API.
//
// Usage:
//   SUPABASE_URL="https://YOUR_PROJECT.supabase.co" \
//   SUPABASE_SERVICE_ROLE_KEY="YOUR_SERVICE_ROLE_KEY" \
//   node scripts/reset_test_passwords.mjs
//
// This script updates auth.users passwords only. It does not read or modify
// public.profiles.

const supabaseUrl = process.env.SUPABASE_URL;
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

const password = 'Password123';

const targetEmails = [
  'jide@whoisme.com',
  'myman@knuth.com',
  'tejus@knuth.com',
  'toogood@whoisme.com',
  'toogood2@whoisme.com',
];

const excludedEmails = new Set([
  'reviewer@whoisme.com',
  'andy@knuth.com',
]);

if (!supabaseUrl || !serviceRoleKey) {
  console.error(
    'Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY environment variable.',
  );
  process.exit(1);
}

const headers = {
  apikey: serviceRoleKey,
  Authorization: `Bearer ${serviceRoleKey}`,
  'Content-Type': 'application/json',
};

async function listAllUsers() {
  const users = [];
  let page = 1;
  const perPage = 1000;

  while (true) {
    const response = await fetch(
      `${supabaseUrl}/auth/v1/admin/users?page=${page}&per_page=${perPage}`,
      { headers },
    );

    if (!response.ok) {
      throw new Error(
        `Failed to list users: ${response.status} ${await response.text()}`,
      );
    }

    const body = await response.json();
    const pageUsers = body.users ?? [];

    users.push(...pageUsers);

    if (pageUsers.length < perPage) {
      return users;
    }

    page += 1;
  }
}

async function updatePassword(user) {
  const response = await fetch(`${supabaseUrl}/auth/v1/admin/users/${user.id}`, {
    method: 'PUT',
    headers,
    body: JSON.stringify({ password }),
  });

  if (!response.ok) {
    throw new Error(
      `Failed to update ${user.email}: ${response.status} ${await response.text()}`,
    );
  }
}

async function main() {
  const users = await listAllUsers();
  const usersByEmail = new Map(
    users.map((user) => [String(user.email).toLowerCase(), user]),
  );

  for (const email of targetEmails) {
    if (excludedEmails.has(email)) {
      console.log(`Skipped excluded user: ${email}`);
      continue;
    }

    const user = usersByEmail.get(email);

    if (!user) {
      console.log(`Missing user: ${email}`);
      continue;
    }

    await updatePassword(user);
    console.log(`Updated password for ${email}`);
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
