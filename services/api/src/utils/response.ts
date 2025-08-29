import { APIGatewayProxyResult } from 'aws-lambda';
import { ValidationError, NotFoundError, UnauthorizedError, InternalError } from '../types/api';
import { logger } from './logger';

const CORS_HEADERS = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
  'Access-Control-Allow-Methods': 'OPTIONS,GET,POST,PUT,DELETE'
};

export function successResponse(data: any, statusCode: number = 200): APIGatewayProxyResult {
  return {
    statusCode,
    headers: CORS_HEADERS,
    body: JSON.stringify(data)
  };
}

export function errorResponse(error: Error, requestId?: string): APIGatewayProxyResult {
  const errorId = requestId || 'unknown';
  
  if (error instanceof ValidationError) {
    logger.warn({ error: error.message, details: error.details, requestId: errorId }, 'Validation error');
    return {
      statusCode: 400,
      headers: CORS_HEADERS,
      body: JSON.stringify({
        error: 'Validation failed',
        message: error.message,
        details: error.details
      })
    };
  }
  
  if (error instanceof UnauthorizedError) {
    logger.warn({ error: error.message, requestId: errorId }, 'Unauthorized error');
    return {
      statusCode: 403,
      headers: CORS_HEADERS,
      body: JSON.stringify({
        error: 'Access denied',
        message: error.message
      })
    };
  }
  
  if (error instanceof NotFoundError) {
    logger.warn({ error: error.message, requestId: errorId }, 'Not found error');
    return {
      statusCode: 404,
      headers: CORS_HEADERS,
      body: JSON.stringify({
        error: 'Not found',
        message: error.message
      })
    };
  }
  
  // Internal server error
  logger.error({ 
    error: error.message, 
    stack: error.stack, 
    cause: error instanceof InternalError ? error.cause : undefined,
    requestId: errorId 
  }, 'Internal server error');
  
  return {
    statusCode: 500,
    headers: CORS_HEADERS,
    body: JSON.stringify({
      error: 'Internal server error',
      message: process.env.NODE_ENV === 'development' ? error.message : 'An unexpected error occurred'
    })
  };
}

export function optionsResponse(): APIGatewayProxyResult {
  return {
    statusCode: 200,
    headers: {
      ...CORS_HEADERS,
      'Access-Control-Max-Age': '86400'
    },
    body: ''
  };
}