const { DynamoDBClient, PutItemCommand } = require('@aws-sdk/client-dynamodb');
const { SageMakerRuntimeClient, InvokeEndpointAsyncCommand, InvokeEndpointCommand } = require('@aws-sdk/client-sagemaker-runtime');
const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');
const { marshall } = require('@aws-sdk/util-dynamodb');

const dynamodb = new DynamoDBClient({ region: '${region}' });
const sagemaker = new SageMakerRuntimeClient({ region: '${region}' });
const s3 = new S3Client({ region: '${region}' });

const JOBS_TABLE_NAME = process.env.JOBS_TABLE_NAME;
const SAGEMAKER_ENDPOINT_NAME = process.env.SAGEMAKER_ENDPOINT_NAME;
const INFERENCE_INPUT_BUCKET = process.env.INFERENCE_INPUT_BUCKET;

// Generate ULID for job IDs
function generateULID() {
  const timestamp = Date.now();
  const randomness = Math.random().toString(36).substring(2, 15);
  return timestamp.toString(36).toUpperCase() + randomness.toUpperCase();
}

// Validate input parameters
function validateInput(body) {
  const errors = [];
  
  if (!body.prompt || typeof body.prompt !== 'string' || body.prompt.trim().length === 0) {
    errors.push('prompt is required and must be a non-empty string');
  }
  
  if (body.prompt && body.prompt.length > 1000) {
    errors.push('prompt must be less than 1000 characters');
  }
  
  if (body.steps && (typeof body.steps !== 'number' || body.steps < 1 || body.steps > 50)) {
    errors.push('steps must be a number between 1 and 50');
  }
  
  if (body.guidanceScale && (typeof body.guidanceScale !== 'number' || body.guidanceScale < 1 || body.guidanceScale > 20)) {
    errors.push('guidanceScale must be a number between 1 and 20');
  }
  
  if (body.width && (typeof body.width !== 'number' || body.width < 256 || body.width > 1024 || body.width % 64 !== 0)) {
    errors.push('width must be a number between 256 and 1024, divisible by 64');
  }
  
  if (body.height && (typeof body.height !== 'number' || body.height < 256 || body.height > 1024 || body.height % 64 !== 0)) {
    errors.push('height must be a number between 256 and 1024, divisible by 64');
  }
  
  if (body.seed && (typeof body.seed !== 'number' || body.seed < 0 || body.seed > 2147483647)) {
    errors.push('seed must be a number between 0 and 2147483647');
  }
  
  if (body.quality && !['low', 'medium', 'high'].includes(body.quality)) {
    errors.push('quality must be one of: low, medium, high');
  }
  
  if (body.mode && !['async', 'sync'].includes(body.mode)) {
    errors.push('mode must be one of: async, sync');
  }
  
  return errors;
}

// Get user ID from JWT token
function getUserId(event) {
  try {
    const claims = event.requestContext.authorizer.jwt.claims;
    return claims.sub || claims['cognito:username'] || 'anonymous';
  } catch (error) {
    console.warn('Could not extract user ID from token:', error);
    return 'anonymous';
  }
}

exports.handler = async (event) => {
  console.log('Event:', JSON.stringify(event, null, 2));
  
  try {
    // Parse request body
    let body;
    try {
      body = JSON.parse(event.body || '{}');
    } catch (error) {
      return {
        statusCode: 400,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
          'Access-Control-Allow-Methods': 'OPTIONS,POST'
        },
        body: JSON.stringify({
          error: 'Invalid JSON in request body'
        })
      };
    }
    
    // Validate input
    const validationErrors = validateInput(body);
    if (validationErrors.length > 0) {
      return {
        statusCode: 400,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
          'Access-Control-Allow-Methods': 'OPTIONS,POST'
        },
        body: JSON.stringify({
          error: 'Validation failed',
          details: validationErrors
        })
      };
    }
    
    // Generate job ID and get user ID
    const jobId = generateULID();
    const userId = getUserId(event);
    const timestamp = new Date().toISOString();
    
    // Prepare inference parameters
    const inferenceParams = {
      prompt: body.prompt.trim(),
      steps: body.steps || 20,
      guidance_scale: body.guidanceScale || 7.5,
      width: body.width || 512,
      height: body.height || 512,
      seed: body.seed || Math.floor(Math.random() * 2147483647),
      quality: body.quality || 'medium'
    };
    
    // Create input JSON for SageMaker
    const inputData = {
      inputs: inferenceParams.prompt,
      parameters: {
        num_inference_steps: inferenceParams.steps,
        guidance_scale: inferenceParams.guidance_scale,
        width: inferenceParams.width,
        height: inferenceParams.height,
        seed: inferenceParams.seed
      }
    };
    
    const mode = body.mode || 'async';
    
    // Store job in DynamoDB
    const jobItem = {
      jobId,
      userId,
      status: 'PENDING',
      createdAt: timestamp,
      updatedAt: timestamp,
      inputParams: inferenceParams,
      mode,
      ttl: Math.floor(Date.now() / 1000) + (7 * 24 * 60 * 60) // 7 days TTL
    };
    
    await dynamodb.send(new PutItemCommand({
      TableName: JOBS_TABLE_NAME,
      Item: marshall(jobItem)
    }));
    
    if (mode === 'async') {
      // Upload input to S3
      const inputKey = `jobs/${jobId}/input.json`;
      await s3.send(new PutObjectCommand({
        Bucket: INFERENCE_INPUT_BUCKET,
        Key: inputKey,
        Body: JSON.stringify(inputData),
        ContentType: 'application/json'
      }));
      
      // Invoke SageMaker async endpoint
      const invokeParams = {
        EndpointName: SAGEMAKER_ENDPOINT_NAME,
        InputLocation: `s3://${INFERENCE_INPUT_BUCKET}/${inputKey}`,
        InferenceId: jobId
      };
      
      const result = await sagemaker.send(new InvokeEndpointAsyncCommand(invokeParams));
      console.log('SageMaker async invocation result:', result);
      
      return {
        statusCode: 202,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
          'Access-Control-Allow-Methods': 'OPTIONS,POST'
        },
        body: JSON.stringify({
          jobId,
          status: 'PENDING',
          message: 'Job submitted successfully. First inference may take up to 60 seconds due to cold start.',
          estimatedWaitTime: '60-120 seconds'
        })
      };
    } else {
      // Synchronous mode - invoke endpoint directly
      const invokeParams = {
        EndpointName: SAGEMAKER_ENDPOINT_NAME,
        ContentType: 'application/json',
        Body: JSON.stringify(inputData)
      };
      
      try {
        const result = await sagemaker.send(new InvokeEndpointCommand(invokeParams));
        const responseBody = JSON.parse(new TextDecoder().decode(result.Body));
        
        // Update job status to completed
        await dynamodb.send(new PutItemCommand({
          TableName: JOBS_TABLE_NAME,
          Item: marshall({
            ...jobItem,
            status: 'SUCCEEDED',
            updatedAt: new Date().toISOString(),
            result: responseBody
          })
        }));
        
        return {
          statusCode: 200,
          headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
            'Access-Control-Allow-Methods': 'OPTIONS,POST'
          },
          body: JSON.stringify({
            jobId,
            status: 'SUCCEEDED',
            result: responseBody
          })
        };
      } catch (error) {
        console.error('Synchronous inference failed:', error);
        
        // Update job status to failed
        await dynamodb.send(new PutItemCommand({
          TableName: JOBS_TABLE_NAME,
          Item: marshall({
            ...jobItem,
            status: 'FAILED',
            updatedAt: new Date().toISOString(),
            error: error.message
          })
        }));
        
        return {
          statusCode: 500,
          headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
            'Access-Control-Allow-Methods': 'OPTIONS,POST'
          },
          body: JSON.stringify({
            error: 'Inference failed',
            details: error.message
          })
        };
      }
    }
    
  } catch (error) {
    console.error('Error:', error);
    
    return {
      statusCode: 500,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'OPTIONS,POST'
      },
      body: JSON.stringify({
        error: 'Internal server error',
        details: error.message
      })
    };
  }
};