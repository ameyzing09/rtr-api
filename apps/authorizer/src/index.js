/**
 * Lambda Authorizer for API Gateway
 * Validates JWT tokens from Cognito
 *
 * PLACEHOLDER IMPLEMENTATION
 * TODO: Replace with full Cognito JWT validation
 */

exports.handler = async (event) => {
  console.log('Authorizer invoked:', JSON.stringify(event, null, 2));

  try {
    // Get the authorization token
    const token = event.authorizationToken || event.headers?.Authorization || event.headers?.authorization;

    if (!token) {
      console.log('No authorization token provided');
      return generatePolicy('user', 'Deny', event.methodArn);
    }

    // Remove 'Bearer ' prefix if present
    const jwtToken = token.replace(/^Bearer\s+/i, '');

    // Basic JWT format validation (3 parts separated by dots)
    const parts = jwtToken.split('.');
    if (parts.length !== 3) {
      console.log('Invalid JWT format');
      return generatePolicy('user', 'Deny', event.methodArn);
    }

    // Decode the payload (base64)
    let payload;
    try {
      const payloadBase64 = parts[1];
      const payloadJson = Buffer.from(payloadBase64, 'base64').toString('utf-8');
      payload = JSON.parse(payloadJson);
    } catch (err) {
      console.log('Failed to decode JWT payload:', err);
      return generatePolicy('user', 'Deny', event.methodArn);
    }

    // Extract user info from payload
    const userId = payload.sub || payload.username || 'unknown';
    const tenantId = payload['custom:tenantId'] || payload.tenantId || 'default-tenant';

    console.log(`Authorizing user: ${userId}, tenant: ${tenantId}`);

    // TODO: Add Cognito JWT signature verification
    // TODO: Check token expiration
    // TODO: Verify issuer matches Cognito user pool

    // For now, allow all requests with valid JWT format
    return generatePolicy(userId, 'Allow', event.methodArn, {
      userId,
      tenantId,
      email: payload.email || 'unknown@example.com'
    });

  } catch (error) {
    console.error('Authorization error:', error);
    return generatePolicy('user', 'Deny', event.methodArn);
  }
};

/**
 * Generate IAM policy for API Gateway
 */
function generatePolicy(principalId, effect, resource, context = {}) {
  const authResponse = {
    principalId
  };

  if (effect && resource) {
    authResponse.policyDocument = {
      Version: '2012-10-17',
      Statement: [
        {
          Action: 'execute-api:Invoke',
          Effect: effect,
          Resource: resource
        }
      ]
    };
  }

  // Add context to pass to downstream Lambda functions
  if (Object.keys(context).length > 0) {
    authResponse.context = {};
    for (const [key, value] of Object.entries(context)) {
      // Context values must be strings
      authResponse.context[key] = String(value);
    }
  }

  console.log('Generated policy:', JSON.stringify(authResponse, null, 2));
  return authResponse;
}
