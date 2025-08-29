import { 
  SageMakerRuntimeClient, 
  InvokeEndpointCommand, 
  InvokeEndpointAsyncCommand 
} from '@aws-sdk/client-sagemaker-runtime';
import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';
import { SubmitJobRequest, InternalError } from '../types/api';
import { logger } from '../utils/logger';

export interface SageMakerInferenceInput {
  inputs: string;
  parameters: {
    num_inference_steps: number;
    guidance_scale: number;
    width: number;
    height: number;
    seed?: number;
    negative_prompt?: string;
  };
}

export interface SageMakerSyncResponse {
  generated_image: string; // base64 encoded
  metadata: {
    prompt: string;
    parameters: any;
    generation_time_seconds: number;
    model_id: string;
    device: string;
    timestamp: number;
  };
}

export class SageMakerService {
  private client: SageMakerRuntimeClient;
  private s3Client: S3Client;
  private endpointName: string;
  private inputBucket: string;

  constructor() {
    this.client = new SageMakerRuntimeClient({ region: process.env.AWS_REGION });
    this.s3Client = new S3Client({ region: process.env.AWS_REGION });
    this.endpointName = process.env.SAGEMAKER_ENDPOINT_NAME!;
    this.inputBucket = process.env.INFERENCE_INPUT_BUCKET!;
    
    if (!this.endpointName) {
      throw new Error('SAGEMAKER_ENDPOINT_NAME environment variable is required');
    }
    if (!this.inputBucket) {
      throw new Error('INFERENCE_INPUT_BUCKET environment variable is required');
    }
  }

  private createInferenceInput(request: SubmitJobRequest): SageMakerInferenceInput {
    return {
      inputs: request.prompt,
      parameters: {
        num_inference_steps: request.steps,
        guidance_scale: request.guidanceScale,
        width: request.width,
        height: request.height,
        seed: request.seed,
        negative_prompt: request.negativePrompt
      }
    };
  }

  async invokeAsync(jobId: string, request: SubmitJobRequest): Promise<string> {
    try {
      logger.info({ jobId, endpointName: this.endpointName }, 'Starting async SageMaker inference');
      
      // Create inference input
      const inputData = this.createInferenceInput(request);
      
      // Upload input to S3
      const inputKey = `jobs/${jobId}/input.json`;
      await this.s3Client.send(new PutObjectCommand({
        Bucket: this.inputBucket,
        Key: inputKey,
        Body: JSON.stringify(inputData),
        ContentType: 'application/json',
        Metadata: {
          'job-id': jobId,
          'created-at': new Date().toISOString()
        }
      }));
      
      logger.debug({ jobId, inputKey }, 'Input uploaded to S3');
      
      // Invoke async endpoint
      const result = await this.client.send(new InvokeEndpointAsyncCommand({
        EndpointName: this.endpointName,
        InputLocation: `s3://${this.inputBucket}/${inputKey}`,
        InferenceId: jobId,
        RequestTTLSeconds: 3600 // 1 hour timeout
      }));
      
      const outputLocation = result.OutputLocation;
      if (!outputLocation) {
        throw new Error('No output location returned from SageMaker');
      }
      
      logger.info({ 
        jobId, 
        outputLocation, 
        inferenceId: result.InferenceId 
      }, 'Async inference started successfully');
      
      return outputLocation;
      
    } catch (error) {
      logger.error({ 
        error: error.message, 
        jobId, 
        endpointName: this.endpointName 
      }, 'Failed to invoke async SageMaker endpoint');
      throw new InternalError('Failed to start inference', error as Error);
    }
  }

  async invokeSync(request: SubmitJobRequest): Promise<SageMakerSyncResponse> {
    try {
      logger.info({ endpointName: this.endpointName }, 'Starting sync SageMaker inference');
      
      // Create inference input
      const inputData = this.createInferenceInput(request);
      
      // Invoke sync endpoint
      const result = await this.client.send(new InvokeEndpointCommand({
        EndpointName: this.endpointName,
        ContentType: 'application/json',
        Accept: 'application/json',
        Body: JSON.stringify(inputData)
      }));
      
      if (!result.Body) {
        throw new Error('No response body from SageMaker');
      }
      
      // Parse response
      const responseText = new TextDecoder().decode(result.Body);
      const response = JSON.parse(responseText) as SageMakerSyncResponse;
      
      logger.info({ 
        generationTime: response.metadata?.generation_time_seconds,
        modelId: response.metadata?.model_id 
      }, 'Sync inference completed successfully');
      
      return response;
      
    } catch (error) {
      logger.error({ 
        error: error.message, 
        endpointName: this.endpointName 
      }, 'Failed to invoke sync SageMaker endpoint');
      throw new InternalError('Failed to complete inference', error as Error);
    }
  }

  async checkEndpointHealth(): Promise<boolean> {
    try {
      // Simple health check with minimal inference
      const healthCheckInput = {
        inputs: "test",
        parameters: {
          num_inference_steps: 1,
          guidance_scale: 1.0,
          width: 512,
          height: 512
        }
      };
      
      await this.client.send(new InvokeEndpointCommand({
        EndpointName: this.endpointName,
        ContentType: 'application/json',
        Accept: 'application/json',
        Body: JSON.stringify(healthCheckInput)
      }));
      
      return true;
    } catch (error) {
      logger.warn({ 
        error: error.message, 
        endpointName: this.endpointName 
      }, 'Endpoint health check failed');
      return false;
    }
  }
}