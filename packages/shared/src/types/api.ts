import { z } from 'zod';

// Job status enum
export const JobStatus = {
  PENDING: 'PENDING',
  RUNNING: 'RUNNING',
  SUCCEEDED: 'SUCCEEDED',
  FAILED: 'FAILED'
} as const;

export type JobStatusType = typeof JobStatus[keyof typeof JobStatus];

// Quality levels
export const QualityLevel = {
  LOW: 'low',
  MEDIUM: 'medium',
  HIGH: 'high'
} as const;

export type QualityLevelType = typeof QualityLevel[keyof typeof QualityLevel];

// Inference modes
export const InferenceMode = {
  ASYNC: 'async',
  SYNC: 'sync'
} as const;

export type InferenceModeType = typeof InferenceMode[keyof typeof InferenceMode];

// Request validation schemas
export const SubmitJobRequestSchema = z.object({
  prompt: z.string()
    .min(1, 'Prompt cannot be empty')
    .max(1000, 'Prompt too long (max 1000 characters)'),
  modelId: z.string().optional().default('stable-diffusion-xl'),
  steps: z.number()
    .int()
    .min(1, 'Steps must be at least 1')
    .max(50, 'Steps cannot exceed 50')
    .optional()
    .default(20),
  guidanceScale: z.number()
    .min(1.0, 'Guidance scale must be at least 1.0')
    .max(20.0, 'Guidance scale cannot exceed 20.0')
    .optional()
    .default(7.5),
  width: z.number()
    .int()
    .min(256, 'Width must be at least 256')
    .max(1024, 'Width cannot exceed 1024')
    .refine(val => val % 64 === 0, 'Width must be divisible by 64')
    .optional()
    .default(1024),
  height: z.number()
    .int()
    .min(256, 'Height must be at least 256')
    .max(1024, 'Height cannot exceed 1024')
    .refine(val => val % 64 === 0, 'Height must be divisible by 64')
    .optional()
    .default(1024),
  seed: z.number()
    .int()
    .min(0)
    .max(2147483647)
    .optional(),
  quality: z.enum(['low', 'medium', 'high']).optional().default('medium'),
  mode: z.enum(['async', 'sync']).optional().default('async'),
  negativePrompt: z.string().max(500).optional()
});

export type SubmitJobRequest = z.infer<typeof SubmitJobRequestSchema>;

// Response types
export interface SubmitJobResponse {
  jobId: string;
  status: JobStatusType;
  message?: string;
  estimatedWaitTime?: string;
  result?: any; // For sync mode
}

export interface GetJobResponse {
  jobId: string;
  status: JobStatusType;
  createdAt: string;
  updatedAt: string;
  inputParams: SubmitJobRequest;
  imageUrl?: string;
  metadata?: Record<string, any>;
  timings?: Record<string, number>;
  error?: string;
  estimatedCompletion?: string;
}

export interface ModelInfo {
  modelId: string;
  name: string;
  description: string;
  category: string;
  version: string;
  maxResolution: number;
  defaultSteps: number;
  maxSteps: number;
  supportedQualities: QualityLevelType[];
  estimatedTime: Record<QualityLevelType, string>;
  pricing: Record<QualityLevelType, number>;
  features: string[];
  limitations: string[];
  available: boolean;
  reason?: string;
}

export interface ListModelsResponse {
  models: ModelInfo[];
  categories: string[];
  totalCount: number;
  recommendations?: Record<string, string>;
  qualityGuide?: Record<QualityLevelType, string>;
}

// Error types
export class ValidationError extends Error {
  constructor(message: string, public details?: any) {
    super(message);
    this.name = 'ValidationError';
  }
}

export class NotFoundError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'NotFoundError';
  }
}

export class UnauthorizedError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'UnauthorizedError';
  }
}

export class InternalError extends Error {
  constructor(message: string, public cause?: Error) {
    super(message);
    this.name = 'InternalError';
  }
}