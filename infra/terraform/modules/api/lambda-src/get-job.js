const { DynamoDBClient, GetItemCommand } = require('@aws-sdk/client-dynamodb');
const { S3Client, GetObjectCommand } = require('@aws-sdk/client-s3');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');
const { unmarshall } = require('@aws-sdk/util-dynamodb');

const dynamodb = new DynamoDBClient({ region: '${region}' });
const s3 = new S3Client({ region: '${region}' });

const JOBS_TABLE_NAME = process.env.JOBS_TABLE_NAME;
const IMAGES_BUCKET = process.env.IMAGES_BUCKET;

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

// Generate presigned URL for image access
async function generatePresignedUrl(bucket, key) {
  try {
    const command = new GetObjectCommand({
      Bucket: bucket,
      Key: key
    });
    
    const url = await getSignedUrl(s3, command, { expiresIn: 3600 }); // 1 hour
    return url;
  } catch (error) {
    console.error('Error generating presigned URL:', error);
    return null;
  }
}

exports.handler = async (event) => {
  console.log('Event:', JSON.stringify(event, null, 2));
  
  try {
    // Extract job ID from path parameters
    const jobId = event.pathParameters?.id;
    if (!jobId) {
      return {
        statusCode: 400,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
          'Access-Control-Allow-Methods': 'OPTIONS,GET'
        },
        body: JSON.stringify({
          error: 'Job ID is required'
        })
      };
    }
    
    // Get user ID for authorization
    const userId = getUserId(event);
    
    // Retrieve job from DynamoDB
    const result = await dynamodb.send(new GetItemCommand({
      TableName: JOBS_TABLE_NAME,
      Key: {
        jobId: { S: jobId }
      }
    }));
    
    if (!result.Item) {
      return {
        statusCode: 404,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
          'Access-Control-Allow-Methods': 'OPTIONS,GET'
        },
        body: JSON.stringify({
          error: 'Job not found'
        })
      };
    }
    
    const job = unmarshall(result.Item);
    
    // Check if user owns this job (basic authorization)
    if (job.userId !== userId && userId !== 'admin') {
      return {
        statusCode: 403,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
          'Access-Control-Allow-Methods': 'OPTIONS,GET'
        },
        body: JSON.stringify({
          error: 'Access denied'
        })
      };
    }
    
    // Prepare response
    const response = {
      jobId: job.jobId,
      status: job.status,
      createdAt: job.createdAt,
      updatedAt: job.updatedAt,
      inputParams: job.inputParams
    };
    
    // Add result data if job is completed
    if (job.status === 'SUCCEEDED') {
      if (job.imageUrl) {
        // If we have a direct image URL (from callback processing)
        response.imageUrl = job.imageUrl;
      } else if (job.outputKey) {
        // Generate presigned URL for the image
        const presignedUrl = await generatePresignedUrl(IMAGES_BUCKET, job.outputKey);
        if (presignedUrl) {
          response.imageUrl = presignedUrl;
        }
      }
      
      // Add metadata if available
      if (job.metadata) {
        response.metadata = job.metadata;
      }
      
      // Add timing information if available
      if (job.timings) {
        response.timings = job.timings;
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
      } else {
        response.estimatedCompletion = 'Processing... Should complete within the next few minutes.';
      }
    }
    
    return {
      statusCode: 200,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'OPTIONS,GET'
      },
      body: JSON.stringify(response)
    };
    
  } catch (error) {
    console.error('Error:', error);
    
    return {
      statusCode: 500,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'OPTIONS,GET'
      },
      body: JSON.stringify({
        error: 'Internal server error',
        details: error.message
      })
    };
  }
};