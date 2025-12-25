/**
 * Job App Lambda
 * Handles job management endpoints: CRUD operations
 *
 * PLACEHOLDER IMPLEMENTATION
 * TODO: Replace with actual database integration
 */

exports.handler = async (event) => {
  console.log('Job handler invoked:', JSON.stringify(event, null, 2));

  try {
    const path = event.path || event.rawPath;
    const method = event.httpMethod || event.requestContext?.http?.method;

    // Extract tenantId from authorizer context
    const tenantId = event.requestContext?.authorizer?.tenantId || 'default-tenant';
    const userId = event.requestContext?.authorizer?.userId || 'unknown-user';

    console.log(`Request from tenant: ${tenantId}, user: ${userId}`);

    // Route to appropriate handler
    if (path === '/jobs' && method === 'GET') {
      return await listJobs(tenantId);
    } else if (path === '/jobs' && method === 'POST') {
      return await createJob(event, tenantId, userId);
    } else if (path.match(/\/jobs\/[^/]+$/) && method === 'GET') {
      const jobId = path.split('/').pop();
      return await getJob(jobId, tenantId);
    } else if (path.match(/\/jobs\/[^/]+$/) && method === 'PUT') {
      const jobId = path.split('/').pop();
      return await updateJob(jobId, event, tenantId, userId);
    } else if (path.match(/\/jobs\/[^/]+$/) && method === 'DELETE') {
      const jobId = path.split('/').pop();
      return await deleteJob(jobId, tenantId, userId);
    } else {
      return createResponse(404, { error: 'Not Found' });
    }
  } catch (error) {
    console.error('Error:', error);
    return createResponse(500, { error: 'Internal Server Error', message: error.message });
  }
};

/**
 * List all jobs for tenant
 * TODO: Query from PostgreSQL database with tenantId filter
 */
async function listJobs(tenantId) {
  console.log(`Listing jobs for tenant: ${tenantId}`);

  // TODO: SELECT * FROM jobs WHERE tenantId = $1

  // Placeholder data
  const jobs = [
    {
      id: 'job-1',
      tenantId,
      title: 'Software Engineer',
      description: 'Build amazing things',
      status: 'open',
      createdAt: new Date().toISOString()
    },
    {
      id: 'job-2',
      tenantId,
      title: 'Product Manager',
      description: 'Lead product strategy',
      status: 'open',
      createdAt: new Date().toISOString()
    }
  ];

  return createResponse(200, {
    jobs,
    count: jobs.length
  });
}

/**
 * Create new job
 * TODO: INSERT into PostgreSQL database
 */
async function createJob(event, tenantId, userId) {
  const body = JSON.parse(event.body || '{}');
  const { title, description, status = 'open' } = body;

  console.log(`Creating job for tenant: ${tenantId}`);

  // TODO: INSERT INTO jobs (tenantId, title, description, status, createdBy) VALUES ($1, $2, $3, $4, $5)

  // Placeholder response
  const job = {
    id: 'job-' + Date.now(),
    tenantId,
    title,
    description,
    status,
    createdBy: userId,
    createdAt: new Date().toISOString()
  };

  return createResponse(201, {
    message: 'Job created (placeholder)',
    job
  });
}

/**
 * Get job by ID
 * TODO: SELECT from PostgreSQL database with tenantId check
 */
async function getJob(jobId, tenantId) {
  console.log(`Getting job ${jobId} for tenant: ${tenantId}`);

  // TODO: SELECT * FROM jobs WHERE id = $1 AND tenantId = $2

  // Placeholder response
  const job = {
    id: jobId,
    tenantId,
    title: 'Sample Job',
    description: 'This is a placeholder job',
    status: 'open',
    createdAt: new Date().toISOString()
  };

  return createResponse(200, { job });
}

/**
 * Update job
 * TODO: UPDATE in PostgreSQL database with tenantId check
 */
async function updateJob(jobId, event, tenantId, userId) {
  const body = JSON.parse(event.body || '{}');
  const { title, description, status } = body;

  console.log(`Updating job ${jobId} for tenant: ${tenantId}`);

  // TODO: UPDATE jobs SET title = $1, description = $2, status = $3, updatedAt = NOW(), updatedBy = $4
  //       WHERE id = $5 AND tenantId = $6

  // Placeholder response
  const job = {
    id: jobId,
    tenantId,
    title: title || 'Updated Job',
    description: description || 'Updated description',
    status: status || 'open',
    updatedBy: userId,
    updatedAt: new Date().toISOString()
  };

  return createResponse(200, {
    message: 'Job updated (placeholder)',
    job
  });
}

/**
 * Delete job
 * TODO: DELETE from PostgreSQL database with tenantId check
 */
async function deleteJob(jobId, tenantId, userId) {
  console.log(`Deleting job ${jobId} for tenant: ${tenantId}`);

  // TODO: DELETE FROM jobs WHERE id = $1 AND tenantId = $2

  return createResponse(200, {
    message: 'Job deleted (placeholder)',
    jobId
  });
}

/**
 * Create HTTP response
 */
function createResponse(statusCode, body) {
  return {
    statusCode,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Credentials': true
    },
    body: JSON.stringify(body)
  };
}
