// Role to Permissions mapping (from Go service)
export const ROLE_PERMISSIONS: Record<string, string[]> = {
  SUPERADMIN: [
    'tenant:list',
    'tenant:create',
    'tenant:read',
    'tenant:update',
    'tenant:impersonate',
    'tenant:status',
    'sys:user:list',
    'sys:health:read',
    'analytics:read',
    'settings:global',
    'settings:security',
    'settings:db',
  ],
  ADMIN: [
    'job:*',
    'application:*',
    'pipeline:*',
    'member:*',
    'interview:*',
    'settings:*',
    'billing:*',
    'integrations:*',
    'feedback:*',
    'evaluation:*',
    'analytics:read',
  ],
  HR: [
    'job:*',
    'application:*',
    'pipeline:*',
    'member:*',
    'interview:*',
    'feedback:*',
    'evaluation:*',
  ],
  INTERVIEWER: [
    'interview:*',
    'feedback:*',
    'evaluation:*',
    'application:read',
    'interview:list',
    'application:list',
  ],
  VIEWER: [],
  CANDIDATE: [
    'analytics:read',
    'application:read',
    'application:list',
  ],
};

// Permission checking with wildcard support
export function hasPermission(userPermissions: string[], required: string): boolean {
  const [namespace] = required.split(':');
  return userPermissions.some((p) => {
    if (p === required) return true;
    if (p === `${namespace}:*`) return true;
    return false;
  });
}

// Get permissions for a role
export function getPermissions(role: string): string[] {
  return ROLE_PERMISSIONS[role] || [];
}
