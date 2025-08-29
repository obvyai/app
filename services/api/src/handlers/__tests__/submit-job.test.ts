import { APIGatewayProxyEvent, Context } from 'aws-lambda';
import { handler } from '../submit-job';
import { DynamoDBService } from '../../services/dynamodb';
import { SageMakerService } from '../../services/sagemaker';

// Mock the services
jest.mock('../../services/dynamodb');
jest.mock('../../services/sagemaker');

const mockDynamoService = jest.mocked(DynamoDBService);
const mockSageMakerService = jest.mocked(SageMakerService);

describe('Submit Job Handler', () => {
  let mockEvent: APIGatewayProxyEvent;
  let mockContext: Context;

  beforeEach(() => {
    jest.clearAllMocks();
    
    mockEvent = {
      httpMethod: 'POST',
      path: '/v1/jobs',
      headers: {},
      multiValueHeaders: {},
      queryStringParameters: null,
      multiValueQueryStringParameters: null,
      pathParameters: null,
      stageVariables: null,
      requestContext: {
        requestId: 'test-request-id',
        stage: 'test',
        requestTime: '2024-01-01T00:00:00Z',
        requestTimeEpoch: 1704067200000,
        identity: {
          sourceIp: '127.0.0.1',
          userAgent: 'test-agent',
        },
        authorizer: {
          jwt: {
            claims: {
              sub: 'test-user-id',
              email: 'test@example.com',
            },
          },
        },
      } as any,
      body: null,
      isBase64Encoded: false,
      resource: '',
      accountId: '',
      apiId: '',
    };

    mockContext = {
      callbackWaitsForEmptyEventLoop: false,
      functionName: 'test-function',
      functionVersion: '1',
      invokedFunctionArn: 'arn:aws:lambda:us-east-1:123456789012:function:test',
      memoryLimitInMB: '512',
      awsRequestId: 'test-aws-request-id',
      logGroupName: '/aws/lambda/test',
      logStreamName: '2024/01/01/[$LATEST]test',
      getRemainingTimeInMillis: () => 30000,
      done: jest.fn(),
      fail: jest.fn(),
      succeed: jest.fn(),
    };

    // Setup default mocks
    mockDynamoService.prototype.createJob = jest.fn().mockResolvedValue(undefined);
    mockDynamoService.prototype.updateJobStatus = jest.fn().mockResolvedValue(undefined);
    mockSageMakerService.prototype.invokeAsync = jest.fn().mockResolvedValue('s3://output/location');
    mockSageMakerService.prototype.invokeSync = jest.fn().mockResolvedValue({
      generated_image: 'base64-encoded-image',
      metadata: {
        prompt: 'test prompt',
        generation_time_seconds: 15.5,
        model_id: 'stable-diffusion-xl',
        device: 'cuda',
        timestamp: 1704067200,
        parameters: {},
      },
    });
  });

  describe('Input Validation', () => {
    it('should return 400 for missing request body', async () => {
      const result = await handler(mockEvent, mockContext);

      expect(result.statusCode).toBe(400);
      expect(JSON.parse(result.body)).toMatchObject({
        error: 'Validation failed',
        message: 'Request body is required',
      });
    });

    it('should return 400 for invalid JSON', async () => {
      mockEvent.body = 'invalid json';

      const result = await handler(mockEvent, mockContext);

      expect(result.statusCode).toBe(400);
      expect(JSON.parse(result.body)).toMatchObject({
        error: 'Validation failed',
        message: 'Invalid JSON in request body',
      });
    });

    it('should return 400 for missing prompt', async () => {
      mockEvent.body = JSON.stringify({
        steps: 20,
      });

      const result = await handler(mockEvent, mockContext);

      expect(result.statusCode).toBe(400);
      expect(JSON.parse(result.body)).toMatchObject({
        error: 'Validation failed',
        details: expect.arrayContaining([
          expect.objectContaining({
            message: 'Prompt cannot be empty',
          }),
        ]),
      });
    });

    it('should return 400 for invalid steps', async () => {
      mockEvent.body = JSON.stringify({
        prompt: 'test prompt',
        steps: 100, // exceeds max
      });

      const result = await handler(mockEvent, mockContext);

      expect(result.statusCode).toBe(400);
      expect(JSON.parse(result.body)).toMatchObject({
        error: 'Validation failed',
        details: expect.arrayContaining([
          expect.objectContaining({
            message: 'Steps cannot exceed 50',
          }),
        ]),
      });
    });

    it('should return 400 for invalid dimensions', async () => {
      mockEvent.body = JSON.stringify({
        prompt: 'test prompt',
        width: 500, // not divisible by 64
        height: 500,
      });

      const result = await handler(mockEvent, mockContext);

      expect(result.statusCode).toBe(400);
      expect(JSON.parse(result.body)).toMatchObject({
        error: 'Validation failed',
        details: expect.arrayContaining([
          expect.objectContaining({
            message: 'Width must be divisible by 64',
          }),
          expect.objectContaining({
            message: 'Height must be divisible by 64',
          }),
        ]),
      });
    });
  });

  describe('Async Mode', () => {
    it('should successfully submit async job', async () => {
      mockEvent.body = JSON.stringify({
        prompt: 'a beautiful sunset',
        mode: 'async',
        steps: 20,
        width: 1024,
        height: 1024,
      });

      const result = await handler(mockEvent, mockContext);

      expect(result.statusCode).toBe(202);
      
      const responseBody = JSON.parse(result.body);
      expect(responseBody).toMatchObject({
        jobId: expect.any(String),
        status: 'PENDING',
        message: expect.stringContaining('Job submitted successfully'),
        estimatedWaitTime: '60-120 seconds',
      });

      expect(mockDynamoService.prototype.createJob).toHaveBeenCalledWith(
        expect.objectContaining({
          jobId: expect.any(String),
          userId: 'test-user-id',
          status: 'PENDING',
          mode: 'async',
          inputParams: expect.objectContaining({
            prompt: 'a beautiful sunset',
            steps: 20,
            width: 1024,
            height: 1024,
          }),
        })
      );

      expect(mockSageMakerService.prototype.invokeAsync).toHaveBeenCalledWith(
        expect.any(String),
        expect.objectContaining({
          prompt: 'a beautiful sunset',
          steps: 20,
          width: 1024,
          height: 1024,
        })
      );
    });

    it('should handle SageMaker async failure', async () => {
      mockEvent.body = JSON.stringify({
        prompt: 'test prompt',
        mode: 'async',
      });

      mockSageMakerService.prototype.invokeAsync = jest.fn().mockRejectedValue(
        new Error('SageMaker service unavailable')
      );

      const result = await handler(mockEvent, mockContext);

      expect(result.statusCode).toBe(500);
      expect(mockDynamoService.prototype.updateJobStatus).toHaveBeenCalledWith(
        expect.any(String),
        'FAILED',
        expect.objectContaining({
          error: 'SageMaker service unavailable',
        })
      );
    });
  });

  describe('Sync Mode', () => {
    it('should successfully complete sync job', async () => {
      mockEvent.body = JSON.stringify({
        prompt: 'a beautiful sunset',
        mode: 'sync',
        steps: 10,
      });

      const result = await handler(mockEvent, mockContext);

      expect(result.statusCode).toBe(200);
      
      const responseBody = JSON.parse(result.body);
      expect(responseBody).toMatchObject({
        jobId: expect.any(String),
        status: 'SUCCEEDED',
        result: {
          generated_image: 'base64-encoded-image',
          metadata: expect.objectContaining({
            prompt: 'test prompt',
            generation_time_seconds: 15.5,
          }),
        },
      });

      expect(mockSageMakerService.prototype.invokeSync).toHaveBeenCalledWith(
        expect.objectContaining({
          prompt: 'a beautiful sunset',
          steps: 10,
        })
      );

      expect(mockDynamoService.prototype.updateJobStatus).toHaveBeenCalledWith(
        expect.any(String),
        'SUCCEEDED',
        expect.objectContaining({
          metadata: expect.any(String),
        })
      );
    });

    it('should handle SageMaker sync failure', async () => {
      mockEvent.body = JSON.stringify({
        prompt: 'test prompt',
        mode: 'sync',
      });

      mockSageMakerService.prototype.invokeSync = jest.fn().mockRejectedValue(
        new Error('Model inference failed')
      );

      const result = await handler(mockEvent, mockContext);

      expect(result.statusCode).toBe(500);
      expect(mockDynamoService.prototype.updateJobStatus).toHaveBeenCalledWith(
        expect.any(String),
        'FAILED',
        expect.objectContaining({
          error: 'Model inference failed',
        })
      );
    });
  });

  describe('CORS Handling', () => {
    it('should handle OPTIONS request', async () => {
      mockEvent.httpMethod = 'OPTIONS';

      const result = await handler(mockEvent, mockContext);

      expect(result.statusCode).toBe(200);
      expect(result.headers).toMatchObject({
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': expect.stringContaining('OPTIONS'),
        'Access-Control-Max-Age': '86400',
      });
    });

    it('should include CORS headers in all responses', async () => {
      mockEvent.body = JSON.stringify({
        prompt: 'test prompt',
      });

      const result = await handler(mockEvent, mockContext);

      expect(result.headers).toMatchObject({
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': expect.stringContaining('Authorization'),
      });
    });
  });

  describe('Authentication', () => {
    it('should extract user context from JWT claims', async () => {
      mockEvent.body = JSON.stringify({
        prompt: 'test prompt',
        mode: 'async',
      });

      await handler(mockEvent, mockContext);

      expect(mockDynamoService.prototype.createJob).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'test-user-id',
        })
      );
    });

    it('should handle missing authentication', async () => {
      mockEvent.requestContext.authorizer = undefined;
      mockEvent.body = JSON.stringify({
        prompt: 'test prompt',
      });

      const result = await handler(mockEvent, mockContext);

      expect(result.statusCode).toBe(403);
      expect(JSON.parse(result.body)).toMatchObject({
        error: 'Access denied',
      });
    });
  });

  describe('Default Values', () => {
    it('should apply default values for optional parameters', async () => {
      mockEvent.body = JSON.stringify({
        prompt: 'test prompt',
      });

      await handler(mockEvent, mockContext);

      expect(mockDynamoService.prototype.createJob).toHaveBeenCalledWith(
        expect.objectContaining({
          inputParams: expect.objectContaining({
            steps: 20, // default
            guidanceScale: 7.5, // default
            width: 1024, // default
            height: 1024, // default
            quality: 'medium', // default
            mode: 'async', // default
          }),
        })
      );
    });
  });
});