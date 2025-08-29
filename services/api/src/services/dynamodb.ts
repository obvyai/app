import { DynamoDBClient, GetItemCommand, PutItemCommand, UpdateItemCommand, QueryCommand } from '@aws-sdk/client-dynamodb';
import { marshall, unmarshall } from '@aws-sdk/util-dynamodb';
import { JobItem, JobStatusType, InternalError, NotFoundError } from '../types/api';
import { logger } from '../utils/logger';

export class DynamoDBService {
  private client: DynamoDBClient;
  private tableName: string;

  constructor() {
    this.client = new DynamoDBClient({ region: process.env.AWS_REGION });
    this.tableName = process.env.JOBS_TABLE_NAME!;
    
    if (!this.tableName) {
      throw new Error('JOBS_TABLE_NAME environment variable is required');
    }
  }

  async createJob(job: JobItem): Promise<void> {
    try {
      logger.info({ jobId: job.jobId, userId: job.userId }, 'Creating job in DynamoDB');
      
      await this.client.send(new PutItemCommand({
        TableName: this.tableName,
        Item: marshall(job, { removeUndefinedValues: true }),
        ConditionExpression: 'attribute_not_exists(jobId)' // Prevent overwrites
      }));
      
      logger.info({ jobId: job.jobId }, 'Job created successfully');
    } catch (error) {
      logger.error({ error: error.message, jobId: job.jobId }, 'Failed to create job');
      throw new InternalError('Failed to create job', error as Error);
    }
  }

  async getJob(jobId: string): Promise<JobItem | null> {
    try {
      logger.debug({ jobId }, 'Getting job from DynamoDB');
      
      const result = await this.client.send(new GetItemCommand({
        TableName: this.tableName,
        Key: marshall({ jobId })
      }));

      if (!result.Item) {
        return null;
      }

      const job = unmarshall(result.Item) as JobItem;
      logger.debug({ jobId, status: job.status }, 'Job retrieved successfully');
      
      return job;
    } catch (error) {
      logger.error({ error: error.message, jobId }, 'Failed to get job');
      throw new InternalError('Failed to retrieve job', error as Error);
    }
  }

  async updateJobStatus(
    jobId: string, 
    status: JobStatusType, 
    updates: Partial<JobItem> = {}
  ): Promise<void> {
    try {
      logger.info({ jobId, status, updates }, 'Updating job status');
      
      const updateExpression = ['SET #status = :status', '#updatedAt = :updatedAt'];
      const expressionAttributeNames: Record<string, string> = {
        '#status': 'status',
        '#updatedAt': 'updatedAt'
      };
      const expressionAttributeValues: Record<string, any> = {
        ':status': status,
        ':updatedAt': new Date().toISOString()
      };

      // Add completion timestamp for final states
      if (status === 'SUCCEEDED' || status === 'FAILED') {
        updateExpression.push('#completedAt = :completedAt');
        expressionAttributeNames['#completedAt'] = 'completedAt';
        expressionAttributeValues[':completedAt'] = new Date().toISOString();
      }

      // Add optional updates
      Object.entries(updates).forEach(([key, value]) => {
        if (value !== undefined && key !== 'jobId' && key !== 'status' && key !== 'updatedAt') {
          const attrName = `#${key}`;
          const attrValue = `:${key}`;
          updateExpression.push(`${attrName} = ${attrValue}`);
          expressionAttributeNames[attrName] = key;
          expressionAttributeValues[attrValue] = value;
        }
      });

      await this.client.send(new UpdateItemCommand({
        TableName: this.tableName,
        Key: marshall({ jobId }),
        UpdateExpression: updateExpression.join(', '),
        ExpressionAttributeNames: expressionAttributeNames,
        ExpressionAttributeValues: marshall(expressionAttributeValues, { removeUndefinedValues: true }),
        ConditionExpression: 'attribute_exists(jobId)' // Ensure job exists
      }));
      
      logger.info({ jobId, status }, 'Job status updated successfully');
    } catch (error) {
      if (error.name === 'ConditionalCheckFailedException') {
        throw new NotFoundError(`Job ${jobId} not found`);
      }
      logger.error({ error: error.message, jobId, status }, 'Failed to update job status');
      throw new InternalError('Failed to update job status', error as Error);
    }
  }

  async getUserJobs(userId: string, limit: number = 50): Promise<JobItem[]> {
    try {
      logger.debug({ userId, limit }, 'Getting user jobs from DynamoDB');
      
      const result = await this.client.send(new QueryCommand({
        TableName: this.tableName,
        IndexName: 'UserIndex',
        KeyConditionExpression: 'userId = :userId',
        ExpressionAttributeValues: marshall({
          ':userId': userId
        }),
        ScanIndexForward: false, // Sort by createdAt descending
        Limit: limit
      }));

      const jobs = result.Items?.map(item => unmarshall(item) as JobItem) || [];
      logger.debug({ userId, count: jobs.length }, 'User jobs retrieved successfully');
      
      return jobs;
    } catch (error) {
      logger.error({ error: error.message, userId }, 'Failed to get user jobs');
      throw new InternalError('Failed to retrieve user jobs', error as Error);
    }
  }

  async getJobsByStatus(status: JobStatusType, limit: number = 100): Promise<JobItem[]> {
    try {
      logger.debug({ status, limit }, 'Getting jobs by status from DynamoDB');
      
      const result = await this.client.send(new QueryCommand({
        TableName: this.tableName,
        IndexName: 'StatusIndex',
        KeyConditionExpression: '#status = :status',
        ExpressionAttributeNames: {
          '#status': 'status'
        },
        ExpressionAttributeValues: marshall({
          ':status': status
        }),
        ScanIndexForward: false, // Sort by createdAt descending
        Limit: limit
      }));

      const jobs = result.Items?.map(item => unmarshall(item) as JobItem) || [];
      logger.debug({ status, count: jobs.length }, 'Jobs by status retrieved successfully');
      
      return jobs;
    } catch (error) {
      logger.error({ error: error.message, status }, 'Failed to get jobs by status');
      throw new InternalError('Failed to retrieve jobs by status', error as Error);
    }
  }
}