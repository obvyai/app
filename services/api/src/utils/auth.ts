import { APIGatewayProxyEvent } from 'aws-lambda';
import { UnauthorizedError } from '../types/api';
import { logger } from './logger';

export interface UserContext {
  userId: string;
  email?: string;
  username?: string;
  isAdmin: boolean;
}

export function extractUserContext(event: APIGatewayProxyEvent): UserContext {
  try {
    // Extract user information from Cognito JWT claims
    const claims = event.requestContext.authorizer?.jwt?.claims;
    
    if (!claims) {
      throw new UnauthorizedError('No authentication claims found');
    }
    
    const userId = claims.sub || claims['cognito:username'];
    if (!userId) {
      throw new UnauthorizedError('No user ID found in claims');
    }
    
    const email = claims.email;
    const username = claims['cognito:username'] || claims.preferred_username;
    
    // Check if user is admin (you can customize this logic)
    const groups = claims['cognito:groups'] || [];
    const isAdmin = Array.isArray(groups) && groups.includes('admin');
    
    logger.debug({ userId, email, username, isAdmin }, 'Extracted user context');
    
    return {
      userId,
      email,
      username,
      isAdmin
    };
    
  } catch (error) {
    logger.error({ error: error.message }, 'Failed to extract user context');
    throw new UnauthorizedError('Invalid authentication');
  }
}

export function validateResourceAccess(userContext: UserContext, resourceUserId: string): void {
  if (userContext.isAdmin) {
    return; // Admins can access any resource
  }
  
  if (userContext.userId !== resourceUserId) {
    throw new UnauthorizedError('Access denied to this resource');
  }
}