import { APIGatewayProxyEvent, APIGatewayProxyResult } from 'aws-lambda';
import { GetJobResponse, NotFoundError, ValidationError } from '../types/api';
import { successResponse, errorResponse, optionsResponse } from '../utils/response';
import { extractUserContext, validateResourceAccess } from '../utils/auth';
import { DynamoDBService } from '../services/dynamodb';
import { S3Client, GetObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { createChildLogger } from '../utils/logger';

const dynamoService = new DynamoDBService();
const s3Client = new S3Client({ region: process.env.AWS_REGION });

export const handler = async (event: APIGatewayProxyEvent): Promise<APIGatewayProxyResult> => {
  const requestId = event.requestContext.requestId;
  const logger = createChildLogger({ requestId, handler: 'get-job' });
  
  try {
    // Handle CORS preflight
    if (event.httpMethod === 'OPTIONS') {
      return optionsResponse();
    }
    
    logger.info({ method: event.httpMethod, path: event.path }, 'Processing get job request');
    
    // Extract job ID from path parameters
    const jobId = event.pathParameters?.id;
    if (!jobId) {
      throw new ValidationError('Job ID is required');
    }
    
    logger.info({ jobId }, 'Getting job details');
    
    // Extract user context
    const userContext = extractUserContext(event);
    
    // Retrieve job from database
    const job = await dynamoService.getJob(jobId);
    if (!job) {
      throw new NotFoundError('Job not found');
    }
    
    // Check if user has access to this job
    validateResourceAccess(userContext, job.userId);
    
    logger.info({ 
      jobId, 
      status: job.status, 
      userId: job.userId 
    }, 'Job retrieved successfully');
    
    // Prepare response
    const response: GetJobResponse = {
      jobId: job.jobId,
      status: job.status,
      createdAt: job.createdAt,
      updatedAt: job.updatedAt,
      inputParams: job.inputParams
    };
    
    // Add result data if job is completed successfully
    if (job.status === 'SUCCEEDED') {
      if (job.imageUrl) {
        // Direct image URL (from callback processing)
        response.imageUrl = job.imageUrl;
      } else if (job.outputKey) {
        // Generate presigned URL for the image
        try {
          const imagesBucket = process.env.IMAGES_BUCKET!;
          const presignedUrl = await getSignedUrl(
            s3Client,
            new GetObjectCommand({
              Bucket: imagesBucket,
              Key: job.outputKey
            }),
            { expiresIn: 3600 } // 1 hour
          );
          response.imageUrl = presignedUrl;
          logger.debug({ jobId, outputKey: job.outputKey }, 'Generated presigned URL');
        } catch (error) {
          logger.warn({ 
            jobId, 
            outputKey: job.outputKey, 
            error: error.message 
          }, 'Failed to generate presigned URL');
        }
      }
      
      // Add metadata if available
      if (job.metadata) {
        try {
          response.metadata = JSON.parse(job.metadata);
        } catch (error) {
          logger.warn({ jobId, error: error.message }, 'Failed to parse job metadata');
        }
      }
      
      // Add timing information if available
      if (job.timings) {
        try {
          response.timings = JSON.parse(job.timings);
        } catch (error) {
          logger.warn({ jobId, error: error.message }, 'Failed to parse job timings');
        }
      }
    } else if (job.status === 'FAILED') {
      // Add error information
      if (job.error) {
        response.error = job.error;
      }
    } else if (job.status === 'PENDING' || job.status === 'RUNNING') {
      // Add estimated completion time
      const createdTime = new Date(job.createdAt).getTime();
      const currentTime = Date.now();
      const elapsedMinutes = Math.floor((currentTime - createdTime) / 60000);
      
      if (elapsedMinutes < 2) {
        response.estimatedCompletion = 'Processing... First inference may take up to 60 seconds due to cold start.';
      } else if (elapsedMinutes < 5) {
        response.estimatedCompletion = 'Processing... Should complete within the next few minutes.';
      } else {
        response.estimatedCompletion = 'Processing is taking longer than expected. Please check back in a few minutes.';
      }
    }
    
    return successResponse(response);
    
  } catch (error) {
    logger.error({ error: error.message, stack: error.stack }, 'Get job handler error');
    return errorResponse(error, requestId);
  }
};