import { APIGatewayProxyEvent, APIGatewayProxyResult } from 'aws-lambda';
import { ulid } from 'ulid';
import { SubmitJobRequestSchema, JobStatus, ValidationError, SubmitJobResponse, JobItem } from '../types/api';
import { successResponse, errorResponse, optionsResponse } from '../utils/response';
import { extractUserContext } from '../utils/auth';
import { DynamoDBService } from '../services/dynamodb';
import { SageMakerService } from '../services/sagemaker';
import { createChildLogger } from '../utils/logger';

const dynamoService = new DynamoDBService();
const sagemakerService = new SageMakerService();

export const handler = async (event: APIGatewayProxyEvent): Promise<APIGatewayProxyResult> => {
  const requestId = event.requestContext.requestId;
  const logger = createChildLogger({ requestId, handler: 'submit-job' });
  
  try {
    // Handle CORS preflight
    if (event.httpMethod === 'OPTIONS') {
      return optionsResponse();
    }
    
    logger.info({ method: event.httpMethod, path: event.path }, 'Processing submit job request');
    
    // Extract user context
    const userContext = extractUserContext(event);
    logger.info({ userId: userContext.userId }, 'User authenticated');
    
    // Parse and validate request body
    if (!event.body) {
      throw new ValidationError('Request body is required');
    }
    
    let requestBody;
    try {
      requestBody = JSON.parse(event.body);
    } catch (error) {
      throw new ValidationError('Invalid JSON in request body');
    }
    
    // Validate request against schema
    const validationResult = SubmitJobRequestSchema.safeParse(requestBody);
    if (!validationResult.success) {
      throw new ValidationError('Invalid request parameters', validationResult.error.issues);
    }
    
    const request = validationResult.data;
    logger.info({ 
      prompt: request.prompt.substring(0, 100) + (request.prompt.length > 100 ? '...' : ''),
      modelId: request.modelId,
      mode: request.mode,
      steps: request.steps,
      quality: request.quality
    }, 'Request validated');
    
    // Generate job ID and create job record
    const jobId = ulid();
    const timestamp = new Date().toISOString();
    
    const jobItem: JobItem = {
      jobId,
      userId: userContext.userId,
      status: JobStatus.PENDING,
      createdAt: timestamp,
      updatedAt: timestamp,
      inputParams: request,
      mode: request.mode,
      ttl: Math.floor(Date.now() / 1000) + (7 * 24 * 60 * 60) // 7 days TTL
    };
    
    // Save job to DynamoDB
    await dynamoService.createJob(jobItem);
    logger.info({ jobId }, 'Job created in database');
    
    if (request.mode === 'sync') {
      // Synchronous inference
      try {
        logger.info({ jobId }, 'Starting synchronous inference');
        
        const result = await sagemakerService.invokeSync(request);
        
        // Update job with result
        await dynamoService.updateJobStatus(jobId, JobStatus.SUCCEEDED, {
          metadata: JSON.stringify(result.metadata)
        });
        
        const response: SubmitJobResponse = {
          jobId,
          status: JobStatus.SUCCEEDED,
          result: {
            generated_image: result.generated_image,
            metadata: result.metadata
          }
        };
        
        logger.info({ jobId, generationTime: result.metadata.generation_time_seconds }, 'Sync inference completed');
        return successResponse(response, 200);
        
      } catch (error) {
        // Update job status to failed
        await dynamoService.updateJobStatus(jobId, JobStatus.FAILED, {
          error: error.message
        });
        
        logger.error({ jobId, error: error.message }, 'Sync inference failed');
        throw error;
      }
    } else {
      // Asynchronous inference
      try {
        logger.info({ jobId }, 'Starting asynchronous inference');
        
        const outputLocation = await sagemakerService.invokeAsync(jobId, request);
        
        // Update job status to running
        await dynamoService.updateJobStatus(jobId, JobStatus.RUNNING);
        
        const response: SubmitJobResponse = {
          jobId,
          status: JobStatus.PENDING,
          message: 'Job submitted successfully. First inference may take up to 60 seconds due to cold start.',
          estimatedWaitTime: '60-120 seconds'
        };
        
        logger.info({ jobId, outputLocation }, 'Async inference started');
        return successResponse(response, 202);
        
      } catch (error) {
        // Update job status to failed
        await dynamoService.updateJobStatus(jobId, JobStatus.FAILED, {
          error: error.message
        });
        
        logger.error({ jobId, error: error.message }, 'Async inference failed to start');
        throw error;
      }
    }
    
  } catch (error) {
    logger.error({ error: error.message, stack: error.stack }, 'Submit job handler error');
    return errorResponse(error, requestId);
  }
};