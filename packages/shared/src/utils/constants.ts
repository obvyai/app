// API Configuration
export const API_CONFIG = {
  BASE_URL: process.env.NEXT_PUBLIC_API_BASE_URL || 'http://localhost:3001/v1',
  TIMEOUT: 30000, // 30 seconds
  RETRY_ATTEMPTS: 3,
  RETRY_DELAY: 1000, // 1 second
} as const;

// Image Generation Limits
export const IMAGE_LIMITS = {
  MIN_WIDTH: 256,
  MAX_WIDTH: 1024,
  MIN_HEIGHT: 256,
  MAX_HEIGHT: 1024,
  DIMENSION_STEP: 64,
  MIN_STEPS: 1,
  MAX_STEPS: 50,
  MIN_GUIDANCE_SCALE: 1.0,
  MAX_GUIDANCE_SCALE: 20.0,
  MAX_PROMPT_LENGTH: 1000,
  MAX_NEGATIVE_PROMPT_LENGTH: 500,
  MAX_SEED: 2147483647,
} as const;

// Default Values
export const DEFAULTS = {
  MODEL_ID: 'stable-diffusion-xl',
  STEPS: 20,
  GUIDANCE_SCALE: 7.5,
  WIDTH: 1024,
  HEIGHT: 1024,
  QUALITY: 'medium' as const,
  MODE: 'async' as const,
} as const;

// Status Messages
export const STATUS_MESSAGES = {
  PENDING: 'Your image is queued for generation',
  RUNNING: 'Generating your image...',
  SUCCEEDED: 'Image generated successfully!',
  FAILED: 'Image generation failed',
} as const;

// Polling Configuration
export const POLLING_CONFIG = {
  INTERVAL: 2000, // 2 seconds
  MAX_ATTEMPTS: 150, // 5 minutes total
  BACKOFF_MULTIPLIER: 1.1,
  MAX_INTERVAL: 10000, // 10 seconds
} as const;

// File Upload Limits
export const UPLOAD_LIMITS = {
  MAX_FILE_SIZE: 10 * 1024 * 1024, // 10MB
  ALLOWED_TYPES: ['image/jpeg', 'image/png', 'image/webp'],
  MAX_FILES: 1,
} as const;

// Cache Configuration
export const CACHE_CONFIG = {
  MODELS_TTL: 5 * 60 * 1000, // 5 minutes
  JOB_STATUS_TTL: 30 * 1000, // 30 seconds
  USER_JOBS_TTL: 60 * 1000, // 1 minute
} as const;

// Error Messages
export const ERROR_MESSAGES = {
  NETWORK_ERROR: 'Network error. Please check your connection and try again.',
  TIMEOUT_ERROR: 'Request timed out. Please try again.',
  VALIDATION_ERROR: 'Please check your input and try again.',
  UNAUTHORIZED_ERROR: 'You are not authorized to perform this action.',
  NOT_FOUND_ERROR: 'The requested resource was not found.',
  INTERNAL_ERROR: 'An unexpected error occurred. Please try again later.',
  RATE_LIMIT_ERROR: 'Too many requests. Please wait a moment and try again.',
} as const;

// Feature Flags
export const FEATURES = {
  ENABLE_SYNC_MODE: true,
  ENABLE_BATCH_GENERATION: false,
  ENABLE_IMAGE_UPLOAD: false,
  ENABLE_CUSTOM_MODELS: false,
  ENABLE_GALLERY: true,
  ENABLE_SHARING: true,
} as const;