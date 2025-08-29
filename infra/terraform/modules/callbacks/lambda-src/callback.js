const { DynamoDBClient, GetItemCommand, UpdateItemCommand } = require('@aws-sdk/client-dynamodb');
const { S3Client, GetObjectCommand, CopyObjectCommand, PutObjectCommand } = require('@aws-sdk/client-s3');
const { marshall, unmarshall } = require('@aws-sdk/util-dynamodb');

const dynamodb = new DynamoDBClient({ region: '${region}' });
const s3 = new S3Client({ region: '${region}' });

const JOBS_TABLE_NAME = process.env.JOBS_TABLE_NAME;
const INFERENCE_OUTPUT_BUCKET = process.env.INFERENCE_OUTPUT_BUCKET;
const IMAGES_BUCKET = process.env.IMAGES_BUCKET;

// Parse S3 URI to extract bucket and key
function parseS3Uri(s3Uri) {
  const match = s3Uri.match(/^s3:\/\/([^\/]+)\/(.+)$/);
  if (!match) {
    throw new Error(`Invalid S3 URI: ${s3Uri}`);
  }
  return {
    bucket: match[1],
    key: match[2]
  };
}

// Generate a unique filename for the image
function generateImageFilename(jobId, originalFilename) {
  const timestamp = Date.now();
  const extension = originalFilename.split('.').pop() || 'png';
  return `generated/${jobId}/${timestamp}.${extension}`;
}

// Process successful inference result
async function processSuccess(jobId, outputLocation) {
  console.log(`Processing success for job ${jobId}, output: ${outputLocation}`);
  
  try {
    // Parse output location
    const { bucket, key } = parseS3Uri(outputLocation);
    
    // List objects in the output directory to find generated images
    const listParams = {
      Bucket: bucket,
      Prefix: key.endsWith('/') ? key : `${key}/`
    };
    
    // For simplicity, we'll assume the output contains a single image file
    // In a real implementation, you might need to handle multiple files or specific naming patterns
    
    // Try to get the output.json file first (if it exists)
    let metadata = {};
    try {
      const metadataResponse = await s3.send(new GetObjectCommand({
        Bucket: bucket,
        Key: `${key}/output.json`
      }));
      const metadataContent = await metadataResponse.Body.transformToString();
      metadata = JSON.parse(metadataContent);
    } catch (error) {
      console.log('No metadata file found, continuing without metadata');
    }
    
    // Try to find the generated image
    let imageKey = null;
    let imageUrl = null;
    
    // Common image file patterns from SageMaker output
    const possibleImageKeys = [
      `${key}/generated_image.png`,
      `${key}/output.png`,
      `${key}/image.png`,
      `${key}/result.png`,
      `${key.replace('.out', '')}.png`,
      `${key}/0.png` // Some models output numbered files
    ];
    
    for (const possibleKey of possibleImageKeys) {
      try {
        await s3.send(new GetObjectCommand({
          Bucket: bucket,
          Key: possibleKey
        }));
        imageKey = possibleKey;
        break;
      } catch (error) {
        // Continue trying other keys
        continue;
      }
    }
    
    if (imageKey) {
      // Copy the image to the public images bucket
      const publicImageKey = generateImageFilename(jobId, imageKey);
      
      await s3.send(new CopyObjectCommand({
        CopySource: `${bucket}/${imageKey}`,
        Bucket: IMAGES_BUCKET,
        Key: publicImageKey,
        MetadataDirective: 'REPLACE',
        Metadata: {
          'job-id': jobId,
          'created-at': new Date().toISOString(),
          'original-key': imageKey
        }
      }));
      
      // Generate the public URL (assuming CloudFront will be configured)
      imageUrl = `https://${IMAGES_BUCKET}.s3.amazonaws.com/${publicImageKey}`;
      
      console.log(`Image copied to public bucket: ${publicImageKey}`);
    } else {
      console.warn(`No image found in output location: ${outputLocation}`);
    }
    
    // Update job status in DynamoDB
    const updateParams = {
      TableName: JOBS_TABLE_NAME,
      Key: {
        jobId: { S: jobId }
      },
      UpdateExpression: 'SET #status = :status, #updatedAt = :updatedAt, #completedAt = :completedAt',
      ExpressionAttributeNames: {
        '#status': 'status',
        '#updatedAt': 'updatedAt',
        '#completedAt': 'completedAt'
      },
      ExpressionAttributeValues: {
        ':status': { S: 'SUCCEEDED' },
        ':updatedAt': { S: new Date().toISOString() },
        ':completedAt': { S: new Date().toISOString() }
      }
    };
    
    // Add image URL if found
    if (imageUrl) {
      updateParams.UpdateExpression += ', #imageUrl = :imageUrl, #outputKey = :outputKey';
      updateParams.ExpressionAttributeNames['#imageUrl'] = 'imageUrl';
      updateParams.ExpressionAttributeNames['#outputKey'] = 'outputKey';
      updateParams.ExpressionAttributeValues[':imageUrl'] = { S: imageUrl };
      updateParams.ExpressionAttributeValues[':outputKey'] = { S: publicImageKey };
    }
    
    // Add metadata if available
    if (Object.keys(metadata).length > 0) {
      updateParams.UpdateExpression += ', #metadata = :metadata';
      updateParams.ExpressionAttributeNames['#metadata'] = 'metadata';
      updateParams.ExpressionAttributeValues[':metadata'] = { S: JSON.stringify(metadata) };
    }
    
    await dynamodb.send(new UpdateItemCommand(updateParams));
    
    console.log(`Job ${jobId} marked as SUCCEEDED`);
    
  } catch (error) {
    console.error(`Error processing success for job ${jobId}:`, error);
    
    // Mark job as failed if we can't process the success
    await dynamodb.send(new UpdateItemCommand({
      TableName: JOBS_TABLE_NAME,
      Key: {
        jobId: { S: jobId }
      },
      UpdateExpression: 'SET #status = :status, #updatedAt = :updatedAt, #error = :error',
      ExpressionAttributeNames: {
        '#status': 'status',
        '#updatedAt': 'updatedAt',
        '#error': 'error'
      },
      ExpressionAttributeValues: {
        ':status': { S: 'FAILED' },
        ':updatedAt': { S: new Date().toISOString() },
        ':error': { S: `Failed to process inference result: ${error.message}` }
      }
    }));
  }
}

// Process failed inference result
async function processError(jobId, errorMessage) {
  console.log(`Processing error for job ${jobId}: ${errorMessage}`);
  
  try {
    await dynamodb.send(new UpdateItemCommand({
      TableName: JOBS_TABLE_NAME,
      Key: {
        jobId: { S: jobId }
      },
      UpdateExpression: 'SET #status = :status, #updatedAt = :updatedAt, #error = :error',
      ExpressionAttributeNames: {
        '#status': 'status',
        '#updatedAt': 'updatedAt',
        '#error': 'error'
      },
      ExpressionAttributeValues: {
        ':status': { S: 'FAILED' },
        ':updatedAt': { S: new Date().toISOString() },
        ':error': { S: errorMessage }
      }
    }));
    
    console.log(`Job ${jobId} marked as FAILED`);
    
  } catch (error) {
    console.error(`Error updating job ${jobId} status to FAILED:`, error);
  }
}

exports.handler = async (event) => {
  console.log('Event:', JSON.stringify(event, null, 2));
  
  try {
    // Process each SNS record
    for (const record of event.Records) {
      if (record.EventSource !== 'aws:sns') {
        console.log('Skipping non-SNS record');
        continue;
      }
      
      const message = JSON.parse(record.Sns.Message);
      console.log('SNS Message:', JSON.stringify(message, null, 2));
      
      // Extract job ID from inference ID or message
      const jobId = message.inferenceId || message.InferenceId;
      if (!jobId) {
        console.error('No job ID found in SNS message');
        continue;
      }
      
      // Determine if this is a success or error notification
      const topicArn = record.Sns.TopicArn;
      const isSuccess = topicArn.includes('success');
      const isError = topicArn.includes('error');
      
      if (isSuccess) {
        // Process successful inference
        const outputLocation = message.outputLocation || message.OutputLocation;
        if (outputLocation) {
          await processSuccess(jobId, outputLocation);
        } else {
          console.error('No output location found in success message');
          await processError(jobId, 'No output location provided in success notification');
        }
      } else if (isError) {
        // Process failed inference
        const errorMessage = message.errorMessage || message.ErrorMessage || 'Inference failed';
        await processError(jobId, errorMessage);
      } else {
        console.error('Unknown SNS topic type:', topicArn);
      }
    }
    
    return {
      statusCode: 200,
      body: JSON.stringify({
        message: 'Callback processed successfully'
      })
    };
    
  } catch (error) {
    console.error('Error processing callback:', error);
    
    return {
      statusCode: 500,
      body: JSON.stringify({
        error: 'Failed to process callback',
        details: error.message
      })
    };
  }
};